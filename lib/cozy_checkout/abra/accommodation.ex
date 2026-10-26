defmodule CozyCheckout.Abra.Accommodation do
  @moduledoc "Explicit, opt-in export of new accommodation advance requests."
  import Ecto.Query
  alias CozyCheckout.{Billing, Repo}
  alias CozyCheckout.Abra.{AccommodationExport, AdvanceBuilder, Client}
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Workers.AbraAccommodationWorker

  def config, do: Application.get_env(:cozy_checkout, :abra_accommodation, [])
  def enabled?, do: config()[:enabled] == true
  def get_export(document_id), do: Repo.get_by(AccommodationExport, document_id: document_id)

  def enqueue(document_id) do
    Repo.transaction(fn ->
      cfg = checked_config!()
      doc = Billing.get_document!(document_id)
      booking = Repo.one!(from b in Booking, where: b.id == ^doc.booking_id, lock: "FOR UPDATE")

      if doc.kind != "advance", do: Repo.rollback("Exportovat lze pouze zálohovou výzvu")

      if DateTime.compare(booking.inserted_at, cfg[:enabled_from]) == :lt,
        do: Repo.rollback("Starší pobyty jsou mimo novou integraci")

      export =
        case get_export(doc.id) do
          nil ->
            payload =
              case AdvanceBuilder.build(doc, cfg) do
                {:ok, payload} -> payload
                {:error, error} -> Repo.rollback(error)
              end

            [invoice] = payload["winstrom"]["faktura-vydana"]

            %AccommodationExport{}
            |> Ecto.Changeset.change(
              document_id: doc.id,
              base_url: cfg[:base_url],
              company_id: cfg[:company_id],
              external_id: invoice["id"],
              payload: payload
            )
            |> Repo.insert!()

          existing ->
            check_target!(existing, cfg)
            existing
        end

      if export.state == "synced" do
        export
      else
        {:ok, _job} = %{export_id: export.id} |> AbraAccommodationWorker.new() |> Oban.insert()
        export |> Ecto.Changeset.change(state: "queued", error: nil) |> Repo.update!()
      end
    end)
  end

  def sync(export_id, final_attempt? \\ false) do
    export = Repo.get!(AccommodationExport, export_id)
    cfg = config()

    cond do
      not enabled?() ->
        {:snooze, 60}

      export.state == "synced" ->
        :ok

      not same_target?(export, cfg) ->
        fail(export, "Cílová firma se změnila; export je pozastaven", true)

      cfg[:username] in [nil, ""] or cfg[:password] in [nil, ""] ->
        fail(export, "Chybí přístupové údaje do ABRA", final_attempt?)

      true ->
        export = export |> Ecto.Changeset.change(attempts: export.attempts + 1) |> Repo.update!()

        case deliver(export, cfg) do
          {:ok, id} ->
            export
            |> Ecto.Changeset.change(
              state: "synced",
              remote_id: id,
              error: nil,
              synced_at: DateTime.utc_now(:second)
            )
            |> Repo.update!()

            :ok

          {:error, reason} ->
            fail(export, reason, final_attempt?)
        end
    end
  end

  defp deliver(export, cfg) do
    case Client.find_invoice(export.external_id, cfg) do
      {:ok, remote} ->
        verify_remote(export, remote)

      :not_found ->
        with {:ok, _id} <- Client.create_invoice(export.payload, cfg),
             {:ok, remote} <- Client.find_invoice(export.external_id, cfg) do
          verify_remote(export, remote)
        else
          :not_found -> {:error, "ABRA po importu nevrátila doklad pod externím ID"}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_remote(export, remote) do
    [invoice] = export.payload["winstrom"]["faktura-vydana"]

    expected =
      invoice["polozkyFaktury"] |> Enum.map(&Decimal.new(&1["cenaMj"])) |> Billing.Money.sum()

    total = decimal(remote["sumCelkem"])

    if remote["kod"] == invoice["kod"] and remote["varSym"] == invoice["varSym"] and
         remote["mena"] == "code:CZK" and remote["typDokl"] == invoice["typDokl"] and
         remote["bankovniUcet"] == invoice["bankovniUcet"] and
         remote["ucetni"] in [false, "false"] and remote["clenDph"] == "code:000U" and
         remote["clenKonVykDph"] == "code:0.0." and
         is_struct(total, Decimal) and Decimal.equal?(total, expected) and valid_id?(remote["id"]) do
      {:ok, to_string(remote["id"])}
    else
      {:error,
       "Doklad v ABRA neodpovídá uloženému exportu (číslo, VS, částka nebo účetní nastavení); zkontrolujte jej ručně"}
    end
  end

  defp decimal(value) when is_binary(value) or is_integer(value) do
    case Decimal.parse(to_string(value)) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp decimal(_), do: nil
  defp valid_id?(id), do: (is_integer(id) and id > 0) or (is_binary(id) and id != "")

  defp fail(export, reason, final?) do
    export
    |> Ecto.Changeset.change(state: if(final?, do: "failed", else: "retrying"), error: reason)
    |> Repo.update!()

    if final?, do: {:cancel, reason}, else: {:error, reason}
  end

  defp checked_config! do
    cfg = config()

    required =
      ~w(base_url company_id username password advance_type_code bank_account_code)a

    if not enabled?() or not match?(%DateTime{}, cfg[:enabled_from]) or
         Enum.any?(required, &(cfg[&1] in [nil, ""])) do
      Repo.rollback("Export pobytů do ABRA není zapnutý nebo chybí konfigurace")
    end

    cfg
  end

  defp same_target?(export, cfg),
    do: export.base_url == cfg[:base_url] and export.company_id == cfg[:company_id]

  defp check_target!(export, cfg) do
    if not same_target?(export, cfg),
      do: Repo.rollback("Doklad již má export do jiné cílové firmy")
  end
end

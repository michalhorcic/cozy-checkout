defmodule CozyCheckout.Abra.Accommodation do
  @moduledoc "Persistent, retryable export of issued accommodation documents."
  import Ecto.Query
  alias CozyCheckout.{Billing, Repo}
  alias CozyCheckout.Abra.{AccommodationExport, AdvanceBuilder, Client, FinalInvoiceExport}
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Workers.AbraAccommodationWorker

  def config, do: Application.get_env(:cozy_checkout, :abra_accommodation, [])
  def enabled?, do: config()[:enabled] == true
  def get_export(document_id), do: Repo.get_by(AccommodationExport, document_id: document_id)

  def automatic?, do: config()[:auto_export_enabled] == true

  @doc "Persist an export intent in the document-issuance transaction. No HTTP or payload preparation."
  def enqueue_issued(doc) do
    cfg = config()
    booking = Repo.get!(Booking, doc.booking_id)

    if automatic?() and enabled?() and doc.kind in ["advance", "final"] and
         is_nil(booking.deleted_at) and match?(%DateTime{}, cfg[:enabled_from]) and
         DateTime.compare(booking.inserted_at, cfg[:enabled_from]) != :lt do
      if not Repo.in_transaction?(), do: raise("Export intent requires the issuance transaction")

      export =
        %AccommodationExport{}
        |> Ecto.Changeset.change(
          document_id: doc.id,
          base_url: cfg[:base_url],
          company_id: cfg[:company_id],
          external_id: "ext:cozy-checkout:accommodation:#{doc.id}",
          payload: %{},
          verification: %{"kind" => doc.kind, "automatic" => true}
        )
        |> Repo.insert!()

      {:ok, _} = %{export_id: export.id} |> AbraAccommodationWorker.new() |> Oban.insert()
    end

    :ok
  end

  def enqueue(document_id) do
    Repo.transaction(fn ->
      cfg = checked_config!()
      doc = Billing.get_document!(document_id)
      booking = Repo.one!(from b in Booking, where: b.id == ^doc.booking_id, lock: "FOR UPDATE")

      if doc.kind not in ["advance", "final"],
        do: Repo.rollback("Tento export podporuje pouze výzvu a vyúčtování")

      if doc.kind == "final" and not FinalInvoiceExport.enabled?(cfg),
        do: Repo.rollback("Export vyúčtování není zapnutý")

      if DateTime.compare(booking.inserted_at, cfg[:enabled_from]) == :lt,
        do: Repo.rollback("Starší pobyty jsou mimo novou integraci")

      export =
        case Repo.one(
               from e in AccommodationExport, where: e.document_id == ^doc.id, lock: "FOR UPDATE"
             ) do
          nil ->
            {payload, verification} =
              if doc.kind == "final" do
                case FinalInvoiceExport.prepare(doc, cfg) do
                  {:ok, payload, verification} -> {payload, verification}
                  {:error, error} -> Repo.rollback(error)
                  {:waiting, reason} -> Repo.rollback(reason)
                end
              else
                case AdvanceBuilder.build(doc, cfg) do
                  {:ok, payload} -> {payload, %{}}
                  {:error, error} -> Repo.rollback(error)
                end
              end

            [invoice] = payload["winstrom"]["faktura-vydana"]

            %AccommodationExport{}
            |> Ecto.Changeset.change(
              document_id: doc.id,
              base_url: cfg[:base_url],
              company_id: cfg[:company_id],
              external_id: invoice["id"],
              payload: payload,
              verification: verification
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

      export.verification["kind"] == "final" and not FinalInvoiceExport.enabled?(cfg) ->
        wait(export, "Export konečných faktur je vypnutý")

      true ->
        case prepare_pending(export, cfg) do
          {:ok, prepared} -> transfer(prepared, cfg, final_attempt?)
          {:error, {:waiting, reason}} -> wait(export, reason)
          {:error, reason} -> fail(export, reason, true)
        end
    end
  end

  defp prepare_pending(%{payload: payload} = export, cfg) when map_size(payload) > 0 do
    if same_target?(export, cfg),
      do: {:ok, export},
      else: {:error, "Cílová firma se změnila; export je pozastaven"}
  end

  defp prepare_pending(export, cfg) do
    Repo.transaction(fn ->
      doc = Billing.get_document!(export.document_id)
      Repo.one!(from b in Booking, where: b.id == ^doc.booking_id, lock: "FOR UPDATE")

      current =
        Repo.one!(from e in AccommodationExport, where: e.id == ^export.id, lock: "FOR UPDATE")

      cfg = checked_config!(cfg)
      check_target!(current, cfg)

      if current.payload != %{} do
        current
      else
        {payload, verification} =
          if doc.kind == "final" do
            case FinalInvoiceExport.prepare(doc, cfg) do
              {:ok, payload, verification} -> {payload, verification}
              {:waiting, reason} -> Repo.rollback({:waiting, reason})
              {:error, reason} -> Repo.rollback(reason)
            end
          else
            case AdvanceBuilder.build(doc, cfg) do
              {:ok, payload} -> {payload, %{}}
              {:error, reason} -> Repo.rollback(reason)
            end
          end

        current
        |> Ecto.Changeset.change(
          payload: payload,
          verification: Map.merge(current.verification, verification),
          base_url: cfg[:base_url],
          company_id: cfg[:company_id],
          state: "queued",
          error: nil
        )
        |> Repo.update!()
      end
    end)
  end

  defp transfer(%{state: "synced"}, _cfg, _final_attempt?), do: :ok

  defp transfer(export, cfg, final_attempt?) do
    if cfg[:username] in [nil, ""] or cfg[:password] in [nil, ""] do
      fail(export, "Chybí přístupové údaje do ABRA", final_attempt?)
    else
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

        {:waiting, reason} ->
          wait(export, reason)

        {:error, reason} ->
          fail(export, reason, final_attempt?)
      end
    end
  end

  defp wait(export, reason) do
    Repo.update_all(
      from(e in AccommodationExport, where: e.id == ^export.id and e.state != "synced"),
      set: [state: "waiting", error: reason, updated_at: DateTime.utc_now(:second)]
    )

    {:snooze, 60}
  end

  defp deliver(%{verification: %{"kind" => "final"}} = export, cfg),
    do: FinalInvoiceExport.deliver(export, cfg)

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

  @doc false
  def worker_failed(id, final_attempt?) do
    fail(
      Repo.get!(AccommodationExport, id),
      "Přenos přerušila neočekávaná chyba. Pokud se opakuje, předejte ji správci.",
      final_attempt?
    )
  end

  defp fail(export, reason, final?) do
    Repo.update_all(
      from(e in AccommodationExport, where: e.id == ^export.id and e.state != "synced"),
      set: [
        state: if(final?, do: "failed", else: "retrying"),
        error: reason,
        updated_at: DateTime.utc_now(:second)
      ]
    )

    if final?, do: {:cancel, reason}, else: {:error, reason}
  end

  defp checked_config!(cfg \\ config()) do
    required =
      ~w(base_url company_id username password advance_type_code bank_account_code)a

    if cfg[:enabled] != true or not match?(%DateTime{}, cfg[:enabled_from]) or
         Enum.any?(required, &(cfg[&1] in [nil, ""])) do
      Repo.rollback("Export pobytů do ABRA není zapnutý nebo chybí konfigurace")
    end

    cfg
  end

  defp same_target?(export, cfg),
    do: export.base_url == cfg[:base_url] and export.company_id == cfg[:company_id]

  defp check_target!(export, cfg) do
    pending_target? =
      export.payload == %{} and
        export.base_url in [nil, "", cfg[:base_url]] and
        export.company_id in [nil, "", cfg[:company_id]]

    if not same_target?(export, cfg) and not pending_target?,
      do: Repo.rollback("Doklad již má export do jiné cílové firmy")
  end
end

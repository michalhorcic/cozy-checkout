defmodule CozyCheckout.Abra.PaymentStatus do
  @moduledoc "Read-only ABRA balances. Does not import payments or issue tax documents."
  import Ecto.Query
  alias CozyCheckout.Repo
  alias CozyCheckout.Abra.{Accommodation, AccommodationExport, BankVerification, Client}
  alias CozyCheckout.Billing.{Account, Document}
  alias CozyCheckout.Bookings.{Booking, BookingInvoice}
  alias CozyCheckout.Workers.AbraPaymentStatusWorker

  def enqueue(booking_id) do
    if configured?(),
      do: %{booking_id: booking_id} |> AbraPaymentStatusWorker.new() |> Oban.insert(),
      else: {:error, "Ověřování úhrad ABRA není zapnuté nebo chybí připojení"}
  end

  def configured? do
    cfg = Accommodation.config()

    Accommodation.enabled?() and
      Enum.all?([:base_url, :company_id, :username, :password], &(cfg[&1] not in [nil, ""]))
  end

  def sync(booking_id \\ nil) do
    if configured?() do
      cfg = Accommodation.config()

      query =
        from e in target_exports(cfg),
          join: d in Document,
          on: d.id == e.document_id,
          join: b in Booking,
          on: b.id == d.booking_id,
          join: a in Account,
          on: a.id == d.billing_account_id,
          where:
            e.state == "synced" and not is_nil(e.remote_id) and
              d.kind in ["advance", "final"] and is_nil(d.deleted_at) and
              is_nil(b.deleted_at) and is_nil(a.deleted_at),
          order_by: e.id,
          select: %{id: e.id, remote_id: e.remote_id, number: d.number, vs: d.variable_symbol}

      query = if booking_id, do: where(query, [e, d], d.booking_id == ^booking_id), else: query

      # One remote GET for up to 50 documents; no per-document HTTP in LiveViews.
      results = query |> Repo.all() |> Enum.chunk_every(50) |> Enum.map(&sync_batch(&1, cfg))

      if Enum.any?(results, &match?({:error, _}, &1)),
        do: {:error, "Některé úhrady se nepodařilo ověřit; podrobnosti jsou u dokladů"},
        else: :ok
    else
      :ok
    end
  end

  defp sync_batch(exports, cfg) do
    started = DateTime.utc_now()
    ids = Enum.map(exports, & &1.remote_id)
    result = Client.invoice_payment_balances(ids, cfg)

    results =
      for export <- exports do
        checked =
          case result do
            {:ok, rows} ->
              case Enum.filter(rows, &(remote_id(&1) == export.remote_id)) do
                [invoice] -> validate(invoice, export)
                _ -> {:error, "Faktura v ABRA chybí nebo není jednoznačná"}
              end

            {:error, _} ->
              {:error, "ABRA není dostupná nebo nevrátila platný seznam faktur"}
          end

        changes =
          case checked do
            {:ok, total, remaining} ->
              [
                payment_total: total,
                payment_remaining: remaining,
                payment_checked_at: started,
                payment_attempted_at: started,
                payment_error: nil
              ]

            {:error, error} ->
              [payment_attempted_at: started, payment_error: error]
          end

        # HTTP is outside transactions. A late response cannot overwrite a newer check,
        # nor a document whose target or export state changed during the request.
        target_exports(cfg)
        |> where(
          [e],
          e.id == ^export.id and e.state == "synced" and
            e.remote_id == ^export.remote_id and
            (is_nil(e.payment_attempted_at) or e.payment_attempted_at < ^started)
        )
        |> Repo.update_all(set: changes)

        checked
      end

    if Enum.any?(results, &match?({:error, _}, &1)), do: {:error, :incomplete}, else: :ok
  end

  defp remote_id(%{"id" => id}) when is_integer(id), do: Integer.to_string(id)
  defp remote_id(%{"id" => id}) when is_binary(id), do: id
  defp remote_id(_), do: nil

  defp valid_amount?(nil), do: false

  defp valid_amount?(value),
    do:
      Decimal.equal?(value, Decimal.round(value, 2)) and
        Decimal.lte?(Decimal.abs(value), Decimal.new("99999999999999.99"))

  defp validate(invoice, export) do
    total = BankVerification.amount(invoice["sumCelkem"])
    remaining = BankVerification.amount(invoice["zbyvaUhradit"])

    cond do
      invoice["kod"] != export.number or invoice["varSym"] != export.vs ->
        {:error, "Identita faktury v ABRA neodpovídá vystavenému dokladu"}

      invoice["mena"] != "code:CZK" ->
        {:error, "Úhrada vyžaduje ověřenou měnu CZK"}

      invoice["storno"] not in [false, "false"] ->
        {:error, "Faktura v ABRA je stornovaná nebo má neznámý stav storna"}

      not valid_amount?(total) or not valid_amount?(remaining) ->
        {:error, "ABRA nevrátila platné částky úhrady"}

      Decimal.negative?(total) or Decimal.gt?(remaining, total) ->
        {:error, "Částky úhrady v ABRA vyžadují účetní kontrolu"}

      true ->
        {:ok, total, remaining}
    end
  end

  def for_documents(documents) do
    ids = Enum.map(documents, & &1.id)

    target_exports(Accommodation.config())
    |> where([e], e.document_id in ^ids and e.state == "synced")
    |> Repo.all()
    |> Map.new(&{&1.document_id, &1})
  end

  def state(%{payment_total: total, payment_remaining: remaining})
      when not is_nil(total) and not is_nil(remaining) do
    cond do
      Decimal.negative?(remaining) -> "overpaid"
      Decimal.equal?(remaining, 0) -> "paid"
      Decimal.lt?(remaining, total) -> "partial"
      true -> "unpaid"
    end
  end

  def state(_), do: nil

  def stale?(nil), do: true
  def stale?(%{checked_at: checked, error: error}), do: stale?(checked, error)
  def stale?(%{payment_checked_at: checked, payment_error: error}), do: stale?(checked, error)

  defp stale?(checked, error),
    do:
      not Accommodation.enabled?() or error not in [nil, false] or is_nil(checked) or
        DateTime.diff(DateTime.utc_now(), checked, :second) > 1800

  defp target_exports(cfg) do
    base = cfg[:base_url] || ""
    company = cfg[:company_id] || ""
    from e in AccommodationExport, where: e.base_url == ^base and e.company_id == ^company
  end

  @doc "Account read model; final invoice supersedes every advance, so deposits are never counted twice."
  def account_balances do
    exports = target_exports(Accommodation.config()) |> where([e], e.state == "synced")

    from a in Account,
      join: d in Document,
      on: d.billing_account_id == a.id and is_nil(d.deleted_at),
      left_join: f in Document,
      on: f.billing_account_id == a.id and f.kind == "final" and is_nil(f.deleted_at),
      left_join: i in BookingInvoice,
      on: i.billing_account_id == a.id,
      left_join: e in subquery(exports),
      on: e.document_id == d.id,
      where:
        is_nil(a.deleted_at) and
          (d.kind == "final" or (d.kind == "advance" and is_nil(f.id))),
      group_by: [a.id, f.id, f.total, i.total_price],
      having: count(d.id) == count(e.payment_checked_at),
      select: %{
        account_id: a.id,
        checked_at: min(e.payment_checked_at),
        error: fragment("bool_or(? IS NOT NULL)", e.payment_error),
        outstanding:
          fragment(
            "CASE WHEN ? IS NOT NULL THEN SUM(?) ELSE ? - SUM(? - ?) END",
            f.id,
            e.payment_remaining,
            i.total_price,
            e.payment_total,
            e.payment_remaining
          ),
        received:
          fragment(
            "CASE WHEN ? IS NOT NULL THEN ? - SUM(?) ELSE SUM(? - ?) END",
            f.id,
            f.total,
            e.payment_remaining,
            e.payment_total,
            e.payment_remaining
          )
      }
  end
end

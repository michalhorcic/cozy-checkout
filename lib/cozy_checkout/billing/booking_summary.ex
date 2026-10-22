defmodule CozyCheckout.Billing.BookingSummary do
  @moduledoc "Read-only booking billing states, shared by the list and its SQL filters."
  import Ecto.Query
  alias CozyCheckout.{Billing, Repo}
  alias CozyCheckout.Billing.{Document, Payment}
  alias CozyCheckout.Bookings.{Booking, BookingInvoice}

  def filter_options do
    [
      {"Všechny", ""},
      {"Soukromý pobyt", "personal"},
      {"Bez dokladu", "no_document"},
      {"Záloha vystavena", "advance_issued"},
      {"Záloha přijata", "advance_received"},
      {"Záloha vrácena", "advance_returned"},
      {"Konečná faktura", "final"},
      {"Neuhrazeno", "unpaid"},
      {"Částečně uhrazeno", "partial"},
      {"Uhrazeno", "paid"},
      {"Přeplatek", "overpaid"},
      {"Po splatnosti", "overdue"}
    ]
  end

  def label("personal"), do: "Soukromý pobyt"
  def label("no_document"), do: "Bez dokladu"
  def label("advance_issued"), do: "Záloha vystavena"
  def label("advance_received"), do: "Záloha přijata"
  def label("advance_returned"), do: "Záloha vrácena"
  def label("final"), do: "Faktura"
  def label("unpaid"), do: "Neuhrazeno"
  def label("partial"), do: "Částečně uhrazeno"
  def label("paid"), do: "Uhrazeno"
  def label("overpaid"), do: "Přeplatek"

  def for_bookings([]), do: %{}

  def for_bookings(ids) do
    query()
    |> where([s], s.booking_id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.booking_id, &1})
  end

  def apply_filter(query, state) when state in ["unpaid", "partial", "paid", "overpaid"] do
    where(query, [billing: s], s.payment_state == ^state)
  end

  def apply_filter(query, "overdue"), do: where(query, [billing: s], s.overdue)

  def apply_filter(query, state)
      when state in ~w(personal no_document advance_issued advance_received advance_returned final),
      do: where(query, [billing: s], s.state == ^state)

  def apply_filter(query, _), do: query

  def query do
    payments =
      from p in Payment,
        group_by: p.booking_id,
        select: %{
          booking_id: p.booking_id,
          received:
            sum(fragment("CASE WHEN ? = 'refund' THEN -? ELSE ? END", p.kind, p.amount, p.amount)),
          receipts: filter(count(p.id), p.kind == "receipt")
        }

    advances =
      from d in Document,
        where: d.kind == "advance",
        group_by: d.booking_id,
        select: %{booking_id: d.booking_id, count: count(d.id)}

    corrections =
      from d in Document,
        where: d.kind == "correction",
        group_by: d.parent_id,
        select: %{parent_id: d.parent_id, total: sum(d.total)}

    balances =
      from b in Booking,
        left_join: i in BookingInvoice,
        on: i.booking_id == b.id,
        left_join: f in Document,
        on: f.booking_id == b.id and f.kind == "final",
        left_join: c in subquery(corrections),
        on: c.parent_id == f.id,
        left_join: p in subquery(payments),
        on: p.booking_id == b.id,
        left_join: a in subquery(advances),
        on: a.booking_id == b.id,
        select: %{
          booking_id: b.id,
          personal: fragment("COALESCE(? = 'personal', false)", i.state),
          final_id: f.id,
          final_number: f.number,
          due_on: f.due_on,
          outstanding: f.total + coalesce(c.total, 0) - coalesce(p.received, 0),
          received: coalesce(p.received, 0),
          receipts: coalesce(p.receipts, 0),
          advances: coalesce(a.count, 0)
        }

    today = Billing.today()

    from s in subquery(balances),
      select: %{
        booking_id: s.booking_id,
        final_id: s.final_id,
        final_number: s.final_number,
        outstanding: s.outstanding,
        state:
          fragment(
            "CASE WHEN ? IS NOT NULL THEN 'final' WHEN ? THEN 'personal' WHEN ? > 0 THEN 'advance_received' WHEN ? > 0 THEN 'advance_returned' WHEN ? > 0 THEN 'advance_issued' ELSE 'no_document' END",
            s.final_id,
            s.personal,
            s.received,
            s.receipts,
            s.advances
          ),
        payment_state:
          fragment(
            "CASE WHEN ? IS NULL THEN NULL WHEN ? < 0 THEN 'overpaid' WHEN ? = 0 THEN 'paid' WHEN ? > 0 THEN 'partial' ELSE 'unpaid' END",
            s.final_id,
            s.outstanding,
            s.outstanding,
            s.received
          ),
        overdue: coalesce(s.outstanding > 0 and s.due_on < ^today, false)
      }
  end
end

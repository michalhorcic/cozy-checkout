defmodule CozyCheckout.Billing.BookingSummary do
  @moduledoc "Read-only booking billing states, shared by the list and its SQL filters."
  import Ecto.Query
  alias CozyCheckout.{Billing, Repo}
  alias CozyCheckout.Billing.{Account, Document, Payment}
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

  def label(nil), do: "Bez konečné faktury"
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

  def for_accounts(booking_id) do
    account_query()
    |> where([s], s.booking_id == ^booking_id)
    |> Repo.all()
    |> Map.new(&{&1.account_id, &1})
  end

  def for_bookings([]), do: %{}

  def for_bookings(ids) do
    query()
    |> where([b], b.id in ^ids)
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

  def account_query do
    payments =
      from p in Payment,
        group_by: p.billing_account_id,
        select: %{
          billing_account_id: p.billing_account_id,
          received:
            sum(fragment("CASE WHEN ? = 'refund' THEN -? ELSE ? END", p.kind, p.amount, p.amount)),
          receipts: filter(count(p.id), p.kind == "receipt")
        }

    advance_values =
      from d in Document,
        where: d.kind == "advance",
        select: %{
          billing_account_id: d.billing_account_id,
          percent:
            fragment(
              "COALESCE(NULLIF(?->'advance_calculation'->>'percent', '')::numeric, ? / NULLIF(NULLIF(?->'advance_calculation'->>'stay_total', '')::numeric, 0) * 100)",
              d.snapshot,
              d.total,
              d.snapshot
            )
        }

    advances =
      from a in subquery(advance_values),
        group_by: a.billing_account_id,
        select: %{
          billing_account_id: a.billing_account_id,
          count: count(a.billing_account_id),
          percent:
            fragment(
              "CASE WHEN COUNT(?) = COUNT(*) THEN SUM(?) END",
              a.percent,
              a.percent
            )
        }

    corrections =
      from d in Document,
        where: d.kind == "correction",
        group_by: d.parent_id,
        select: %{parent_id: d.parent_id, total: sum(d.total)}

    balances =
      from b in Account,
        where: is_nil(b.deleted_at),
        left_join: i in BookingInvoice,
        on: i.billing_account_id == b.id,
        left_join: f in Document,
        on: f.billing_account_id == b.id and f.kind == "final",
        left_join: c in subquery(corrections),
        on: c.parent_id == f.id,
        left_join: p in subquery(payments),
        on: p.billing_account_id == b.id,
        left_join: a in subquery(advances),
        on: a.billing_account_id == b.id,
        select: %{
          booking_id: b.booking_id,
          account_id: b.id,
          personal: fragment("COALESCE(? = 'personal', false)", i.state),
          final_id: f.id,
          final_number: f.number,
          due_on: f.due_on,
          outstanding: f.total + coalesce(c.total, 0) - coalesce(p.received, 0),
          received: coalesce(p.received, 0),
          receipts: coalesce(p.receipts, 0),
          advances: coalesce(a.count, 0),
          advance_percent: a.percent
        }

    today = Billing.today()

    from s in subquery(balances),
      select: %{
        booking_id: s.booking_id,
        account_id: s.account_id,
        personal: s.personal,
        received: s.received,
        advance_count: s.advances,
        advance_percent: s.advance_percent,
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

  def query do
    grouped =
      from s in subquery(account_query()),
        join: b in Booking,
        on: b.id == s.booking_id,
        group_by: [s.booking_id, b.allocation_completed_at],
        select: %{
          booking_id: s.booking_id,
          completed: not is_nil(b.allocation_completed_at),
          accounts: count(s.account_id),
          finals: filter(count(s.account_id), not is_nil(s.final_id)),
          paid: filter(count(s.account_id), s.payment_state == "paid"),
          overpaid: filter(count(s.account_id), s.payment_state == "overpaid"),
          partial: filter(count(s.account_id), s.payment_state == "partial"),
          unpaid: filter(count(s.account_id), s.payment_state == "unpaid"),
          personal: filter(count(s.account_id), s.personal),
          advance_received: filter(count(s.account_id), s.state == "advance_received"),
          advance_returned: filter(count(s.account_id), s.state == "advance_returned"),
          advance_issued: filter(count(s.account_id), s.state == "advance_issued"),
          overdue_count: filter(count(s.account_id), s.overdue),
          outstanding: sum(s.outstanding),
          final_id: fragment("MIN(?::text)", s.final_id),
          final_number: min(s.final_number)
        }

    from b in Booking,
      left_join: s in subquery(grouped),
      on: s.booking_id == b.id,
      select: %{
        booking_id: b.id,
        final_id: s.final_id,
        final_number: s.final_number,
        outstanding: s.outstanding,
        account_count: coalesce(s.accounts, 0),
        final_count: coalesce(s.finals, 0),
        paid_count: coalesce(s.paid, 0),
        state:
          fragment(
            "CASE WHEN ? > 0 AND ? = ? THEN 'personal' WHEN ? > 0 THEN 'final' WHEN ? > 0 THEN 'advance_received' WHEN ? > 0 THEN 'advance_returned' WHEN ? > 0 THEN 'advance_issued' ELSE 'no_document' END",
            s.accounts,
            s.personal,
            s.accounts,
            s.finals,
            s.advance_received,
            s.advance_returned,
            s.advance_issued
          ),
        payment_state:
          fragment(
            "CASE WHEN COALESCE(?, 0) = 0 THEN NULL WHEN ? > 0 THEN 'partial' WHEN ? > 0 THEN 'unpaid' WHEN ? > 0 THEN 'overpaid' WHEN ? AND ? > 0 AND ? = ? AND ? = ? THEN 'paid' ELSE 'unpaid' END",
            s.finals,
            s.partial,
            s.unpaid,
            s.overpaid,
            s.completed,
            s.accounts,
            s.finals,
            s.accounts,
            s.paid,
            s.accounts
          ),
        overdue: coalesce(s.overdue_count > 0, false)
      }
  end
end

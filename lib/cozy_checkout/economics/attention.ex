defmodule CozyCheckout.Economics.Attention do
  @moduledoc "Pure local overview of actionable debts, confirmed results and data quality."
  alias CozyCheckout.Economics.Reports
  @zero Decimal.new(0)

  def build(snapshots, confirmations, latest_run, today) do
    confirmed = MapSet.new(confirmations, &{to_string(&1.month), &1.fingerprint})
    confirmation_dates = MapSet.new(confirmations, &to_string(&1.month))

    months =
      for snapshot <- snapshots,
          month <- snapshot.payload["months"],
          do: %{data: month, period: snapshot.period_code, checked_at: snapshot.checked_at}

    months = Enum.sort_by(months, & &1.data["from"], :desc)
    completed = Enum.filter(months, &(&1.data["to"] < to_string(today)))
    last_confirmed = Enum.find(completed, &MapSet.member?(confirmed, key(&1.data)))

    changed =
      Enum.filter(
        completed,
        &(MapSet.member?(confirmation_dates, &1.data["from"]) and
            not MapSet.member?(confirmed, key(&1.data)))
      )

    bank =
      Enum.find_value(months, fn entry ->
        if entry.data["to"] <= to_string(today) do
          balances =
            Enum.filter(entry.data["balances"], &String.starts_with?(&1["account"], "221"))

          if balances != [],
            do: %{amount: sum(balances, "closing"), date: entry.data["to"], period: entry.period}
        end
      end)

    current =
      snapshots
      |> Enum.filter(&is_map(&1.payload["current_saldo"]))
      |> Enum.sort_by(
        &{&1.payload["current_saldo"]["date"], DateTime.to_unix(&1.checked_at)},
        :desc
      )
      |> List.first()

    saldo = if current, do: saldo(current.payload["current_saldo"], today)
    issues = []

    issues =
      if latest_run && latest_run.state == "failed",
        do: [%{kind: :import_failed} | issues],
        else: issues

    issues =
      if changed != [],
        do: [%{kind: :changed_months, count: length(changed)} | issues],
        else: issues

    issues =
      cond do
        is_nil(saldo) -> [%{kind: :missing_saldo} | issues]
        not saldo.fresh -> [%{kind: :stale_saldo, date: saldo.date} | issues]
        true -> issues
      end

    issues =
      if saldo && not saldo.supported, do: [%{kind: :unsupported_saldo} | issues], else: issues

    issues =
      if saldo && saldo.supported && saldo.receivables.count > 0,
        do: [
          %{
            kind: :overdue_receivables,
            count: saldo.receivables.count,
            amount: saldo.receivables.amount,
            date: saldo.date
          }
          | issues
        ],
        else: issues

    issues =
      if saldo && saldo.supported && saldo.payables.count > 0,
        do: [
          %{
            kind: :upcoming_payables,
            count: saldo.payables.count,
            amount: saldo.payables.amount,
            date: saldo.date
          }
          | issues
        ],
        else: issues

    issues =
      if saldo && saldo.supported && saldo.overdue_payables.count > 0,
        do: [
          %{
            kind: :overdue_payables,
            count: saldo.overdue_payables.count,
            amount: saldo.overdue_payables.amount,
            date: saldo.date
          }
          | issues
        ],
        else: issues

    issues =
      if saldo && saldo.unknown_due_count > 0,
        do: [%{kind: :unknown_due, count: saldo.unknown_due_count} | issues],
        else: issues

    %{
      result:
        if(last_confirmed,
          do: %{
            month: last_confirmed.data["from"],
            totals: last_confirmed.data["totals"],
            period: last_confirmed.period
          }
        ),
      bank: bank,
      saldo: saldo,
      issues: Enum.reverse(issues),
      latest_run: latest_run
    }
  end

  def saldo(nil, _today), do: nil

  def saldo(%{"date" => date, "items" => items}, today) do
    as_of = Date.from_iso8601!(date)
    last = Date.add(as_of, 14) |> to_string()
    supported = Enum.all?(items, &(not is_nil(&1["amount"])))

    positive =
      Enum.filter(
        items,
        &(not is_nil(&1["amount"]) and Decimal.positive?(Reports.number!(&1["amount"])))
      )

    receivables =
      Enum.filter(
        positive,
        &(&1["kind"] == "receivable" and not is_nil(&1["due"]) and &1["due"] < date)
      )

    payables =
      Enum.filter(
        positive,
        &(&1["kind"] == "payable" and not is_nil(&1["due"]) and &1["due"] >= date and
            &1["due"] <= last)
      )

    overdue_payables =
      Enum.filter(
        positive,
        &(&1["kind"] == "payable" and not is_nil(&1["due"]) and &1["due"] < date)
      )

    %{
      date: date,
      horizon: last,
      fresh: date == to_string(today),
      supported: supported,
      receivables: bucket(receivables, supported),
      payables: bucket(payables, supported),
      overdue_payables: bucket(overdue_payables, supported),
      unknown_due_count: Enum.count(positive, &is_nil(&1["due"])),
      items: items
    }
  end

  def filter_items(saldo, focus) do
    cond do
      is_nil(saldo) ->
        []

      focus == "receivables-overdue" ->
        Enum.filter(saldo.items, &positive_due?(&1, "receivable", fn d -> d < saldo.date end))

      focus == "payables-upcoming" ->
        Enum.filter(
          saldo.items,
          &positive_due?(&1, "payable", fn d -> d >= saldo.date and d <= saldo.horizon end)
        )

      focus == "payables-overdue" ->
        Enum.filter(saldo.items, &positive_due?(&1, "payable", fn d -> d < saldo.date end))

      true ->
        saldo.items
    end
    |> Enum.sort_by(&{&1["due"] || "9999", &1["module"], &1["document_id"]})
  end

  defp positive_due?(row, kind, predicate) do
    row["kind"] == kind and not is_nil(row["amount"]) and
      Decimal.positive?(Reports.number!(row["amount"])) and not is_nil(row["due"]) and
      predicate.(row["due"])
  end

  defp bucket(rows, true),
    do: %{
      count: length(rows),
      amount: sum(rows, "amount"),
      oldest_due: rows |> Enum.map(& &1["due"]) |> Enum.min(fn -> nil end)
    }

  defp bucket(_, false), do: %{count: nil, amount: nil, oldest_due: nil}

  defp sum(rows, field),
    do:
      Enum.reduce(rows, @zero, &Decimal.add(Reports.number!(&1[field]), &2))
      |> Decimal.to_string(:normal)

  defp key(month), do: {month["from"], Reports.month_fingerprint(month)}
end

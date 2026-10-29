defmodule CozyCheckout.Economics.AttentionTest do
  use ExUnit.Case, async: true
  import CozyCheckout.EconomicsFixtures
  alias CozyCheckout.Economics.{Attention, Reports}

  @today ~D[2026-10-29]
  defp item(id, kind, due, amount),
    do: %{
      "document_id" => id,
      "module" => if(kind == "receivable", do: "FAV", else: "FAP"),
      "kind" => kind,
      "due" => due,
      "amount" => amount
    }

  defp daily(items, date \\ "2026-10-29"), do: %{"date" => date, "items" => items}

  defp month do
    {:ok, month} =
      Reports.month(
        period(),
        ~D[2026-07-01],
        ~D[2026-07-31],
        catalog(),
        posted(),
        [],
        trial(),
        []
      )

    month
  end

  defp snapshot(months, current \\ nil, code \\ "FY-TEST") do
    %{
      period_code: code,
      checked_at: ~U[2026-10-29 04:00:00Z],
      payload: %{"months" => months, "current_saldo" => current}
    }
  end

  test "14-day boundaries, overdue date and credits remain distinct" do
    items = [
      item("old", "receivable", "2026-10-28", "100.25"),
      item("today", "receivable", "2026-10-29", "20"),
      item("credit", "receivable", "2026-10-28", "-100"),
      item("due-today", "payable", "2026-10-29", "10"),
      item("boundary", "payable", "2026-11-12", "30.10"),
      item("outside", "payable", "2026-11-13", "999"),
      item("past", "payable", "2026-10-28", "50"),
      item("unknown", "payable", nil, "12")
    ]

    saldo = Attention.saldo(daily(items), @today)
    assert saldo.fresh
    assert saldo.receivables == %{count: 1, amount: "100.25", oldest_due: "2026-10-28"}
    assert saldo.payables == %{count: 2, amount: "40.10", oldest_due: "2026-10-29"}
    assert saldo.overdue_payables.amount == "50"
    assert saldo.unknown_due_count == 1

    assert Enum.map(Attention.filter_items(saldo, "payables-upcoming"), & &1["document_id"]) == [
             "due-today",
             "boundary"
           ]

    assert Enum.map(Attention.filter_items(saldo, "receivables-overdue"), & &1["document_id"]) ==
             ["old"]
  end

  test "missing and unsupported data are distinct from an actual empty saldo" do
    assert Attention.saldo(nil, @today) == nil
    empty = Attention.saldo(daily([]), @today)
    assert empty.receivables.amount == "0" and empty.payables.count == 0

    unsupported =
      Attention.saldo(daily([item("changed", "receivable", "2026-10-01", nil)]), @today)

    refute unsupported.supported
    assert unsupported.receivables.amount == nil and unsupported.payables.amount == nil
  end

  test "a stale snapshot retains its actual date and deadline horizon" do
    saldo =
      Attention.saldo(daily([item("later", "payable", "2026-11-12", "20")], "2026-10-28"), @today)

    refute saldo.fresh
    assert saldo.horizon == "2026-11-11"
    assert saldo.payables.count == 0
    result = Attention.build([snapshot([month()], daily([], "2026-10-28"))], [], nil, @today)
    assert Enum.any?(result.issues, &(&1.kind == :stale_saldo))
    assert is_nil(result.result)
  end

  test "the result requires a matching confirmation; a later edit produces a task" do
    month = month()
    confirmation = %{month: ~D[2026-07-01], fingerprint: Reports.fingerprint(month)}
    data = Attention.build([snapshot([month], daily([]))], [confirmation], nil, @today)
    assert data.result.month == "2026-07-01"
    assert data.result.totals["result"] == "74.50"

    changed_daily =
      Attention.build(
        [snapshot([month], daily([item("new", "receivable", "2026-10-01", "25")]))],
        [confirmation],
        nil,
        @today
      )

    assert changed_daily.result.month == "2026-07-01"
    refute Enum.any?(changed_daily.issues, &(&1.kind == :changed_months))
    edited = Map.put(month, "warnings", ["unposted_documents"])
    data = Attention.build([snapshot([edited], daily([]))], [confirmation], nil, @today)
    assert is_nil(data.result)
    assert Enum.any?(data.issues, &(&1.kind == :changed_months and &1.count == 1))
  end

  test "months are selected by dates across fiscal codes, and future closing bank balances are excluded" do
    july = month()
    future = %{july | "from" => "2026-10-01", "to" => "2026-10-31"}
    confirmation = %{month: ~D[2026-07-01], fingerprint: Reports.fingerprint(july)}

    data =
      Attention.build(
        [snapshot([future], nil, "AAA"), snapshot([july], daily([]), "ZZZ")],
        [confirmation],
        nil,
        @today
      )

    assert data.result.period == "ZZZ"
    assert data.bank == %{amount: "174.50", date: "2026-07-31", period: "ZZZ"}
    data = Attention.build([snapshot([future], daily([]))], [], nil, @today)
    assert is_nil(data.bank)
  end

  test "failed imports preserve existing amounts and raise an actionable issue" do
    data =
      Attention.build(
        [snapshot([month()], daily([item("unpaid", "receivable", "2026-10-01", "100")]))],
        [],
        %{state: "failed"},
        @today
      )

    assert data.saldo.receivables.amount == "100"
    assert Enum.map(data.issues, & &1.kind) == [:import_failed, :overdue_receivables]
  end
end

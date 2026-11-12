defmodule CozyCheckout.Adventure.BarTest do
  use CozyCheckout.DataCase, async: false

  alias CozyCheckout.Adventure.Sources.Bar
  alias CozyCheckout.QueryRecorder
  alias CozyCheckout.Sales.{Order, Payment}

  @campaign %{starts_on: ~D[2026-10-01], ends_on: ~D[2026-10-10]}
  @as_of ~U[2026-10-10 12:00:00Z]

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    :ok
  end

  test "disabled Adventure returns before any source query" do
    Application.put_env(:cozy_checkout, :adventure_enabled, false)
    {result, queries} = QueryRecorder.record(fn -> Bar.evaluate(@campaign, as_of: @as_of) end)
    assert result == {:error, :disabled}
    assert queries == []
  end

  test "payment-date headline includes partial payments and paid tips, not service orders" do
    order =
      order(%{
        status: "partially_paid",
        total_amount: Decimal.new("1000"),
        discount_amount: Decimal.new("100"),
        tips_amount: Decimal.new("50"),
        inserted_at: ~U[2026-09-01 12:00:00Z]
      })

    payment(order, "200", ~D[2026-10-01])
    payment(order, "350", ~D[2026-10-10], %{payment_method: "qr_code"})
    payment(order, "500", ~D[2026-09-30])
    payment(order, "500", ~D[2026-10-11])
    payment(order, "999", ~D[2026-10-05], %{deleted_at: @as_of})
    payment(order(%{is_service_order: true}), "80", ~D[2026-10-03])
    payment(order(%{deleted_at: @as_of, status: "cancelled"}), "25", ~D[2026-10-04])

    {result, queries} = QueryRecorder.record(fn -> Bar.evaluate(@campaign, as_of: @as_of) end)

    assert length(queries) == 1
    assert_money(result, "received_amount", "575")
    assert_money(result, "service_received_amount", "80")
    assert_money(result, "total_received_amount", "655")
    assert_money(result, "cash_received_amount", "225")
    assert_money(result, "qr_received_amount", "350")
    assert_money(result, "service_cash_received_amount", "80")
    assert_money(result, "service_qr_received_amount", "0")
    assert result["metrics"]["payment_count"] == 3
    assert result["metrics"]["service_payment_count"] == 1
    assert result["evidence"]["headline_scope"] == "non_service_orders"
    assert result["quality"]["completeness"] == "complete"
    assert get_in(result, ["quality", "metrics", "received_amount", "completeness"]) == "complete"
    assert result["source"] == "bar"
    assert result["definition_version"] == 1
    assert result["as_of"] == DateTime.to_iso8601(@as_of)
    assert Jason.encode!(result)
    refute inspect(result) =~ "Private order"
    refute inspect(result) =~ "Private payment"
  end

  test "inclusive dates cap at Prague as_of day, independently of closure" do
    order = order()
    payment(order, "10", ~D[2026-10-05])
    payment(order, "20", ~D[2026-10-06])
    campaign = Map.put(@campaign, :closed_at, ~U[2026-10-02 12:00:00Z])

    before_midnight = Bar.evaluate(campaign, as_of: ~U[2026-10-05 21:59:59Z])
    after_midnight = Bar.evaluate(campaign, as_of: ~U[2026-10-05 22:00:00Z])

    assert_money(before_midnight, "received_amount", "10")
    assert_money(after_midnight, "received_amount", "30")
    assert after_midnight["evidence"]["as_of_on"] == "2026-10-06"

    future = Bar.evaluate(@campaign, as_of: ~U[2026-09-30 12:00:00Z])
    assert_money(future, "received_amount", "0")
    assert future["metrics"]["payment_count"] == 0
  end

  test "query count stays fixed as orders and payments grow" do
    {empty, empty_queries} =
      QueryRecorder.record(fn -> Bar.evaluate(@campaign, as_of: @as_of) end)

    assert_money(empty, "received_amount", "0")

    for _ <- 1..12 do
      order = order()
      payment(order, "1", ~D[2026-10-01])
      payment(order, "2", ~D[2026-10-10])
    end

    {result, queries} = QueryRecorder.record(fn -> Bar.evaluate(@campaign, as_of: @as_of) end)
    assert length(empty_queries) == 1
    assert length(queries) == 1
    assert result["metrics"]["payment_count"] == 24
    assert_money(result, "received_amount", "36")
  end

  defp order(attrs \\ %{}) do
    Repo.insert!(
      struct(
        Order,
        Map.merge(%{order_number: Ecto.UUID.generate(), name: "Private order"}, attrs)
      )
    )
  end

  defp payment(order, amount, date, attrs \\ %{}) do
    Repo.insert!(
      struct(
        Payment,
        Map.merge(
          %{
            order_id: order.id,
            amount: Decimal.new(amount),
            payment_date: date,
            payment_method: "cash",
            invoice_number: Ecto.UUID.generate(),
            notes: "Private payment"
          },
          attrs
        )
      )
    )
  end

  defp assert_money(result, key, expected) do
    assert is_binary(result["metrics"][key])
    assert Decimal.equal?(Decimal.new(result["metrics"][key]), Decimal.new(expected))
  end
end

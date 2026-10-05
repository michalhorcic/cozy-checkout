defmodule CozyCheckout.SalesConcurrencyTest do
  use ExUnit.Case, async: false
  @moduletag :financial
  import Ecto.Query
  import CozyCheckout.SalesFixtures
  alias CozyCheckout.{Repo, Sales}
  alias Ecto.Adapters.SQL.Sandbox

  @tag :known_bug
  test "two independent connections cannot pay the same remaining balance twice" do
    [order] = committed_orders(1)

    results =
      race([1, 2], fn index ->
        attrs =
          Map.put(
            payment_attrs(order, "100"),
            "invoice_number",
            "CONCURRENT-#{order.id}-#{index}"
          )

        Sales.create_payment(attrs)
      end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    payments = Sandbox.unboxed_run(Repo, fn -> Sales.list_payments_for_order(order.id) end)
    assert_amount(Enum.reduce(payments, Decimal.new(0), &Decimal.add(&2, &1.amount)), "100")
  end

  @tag :known_bug
  test "concurrent payments on different orders all receive distinct generated document numbers" do
    orders = committed_orders(6)
    results = race(orders, fn order -> Sales.create_payment(payment_attrs(order, "100")) end)
    assert Enum.all?(results, &match?({:ok, _}, &1)), "payment failures: #{inspect(results)}"
    numbers = Enum.map(results, fn {:ok, payment} -> payment.invoice_number end)
    assert length(Enum.uniq(numbers)) == length(orders)
  end

  defp committed_orders(count) do
    orders =
      Sandbox.unboxed_run(Repo, fn ->
        for _ <- 1..count do
          order = order_fixture()
          item_fixture(order)
          order
        end
      end)

    ids = Enum.map(orders, & &1.id)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        products =
          Repo.all(from i in Sales.OrderItem, where: i.order_id in ^ids, select: i.product_id)

        Repo.delete_all(from j in Oban.Job, where: fragment("?->>'order_id'", j.args) in ^ids)
        Repo.delete_all(from p in Sales.Payment, where: p.order_id in ^ids)
        Repo.delete_all(from i in Sales.OrderItem, where: i.order_id in ^ids)
        Repo.delete_all(from o in Sales.Order, where: o.id in ^ids)

        Repo.delete_all(
          from p in CozyCheckout.Catalog.Pricelist, where: p.product_id in ^products
        )

        Repo.delete_all(from p in CozyCheckout.Catalog.Product, where: p.id in ^products)
      end)
    end)

    orders
  end

  # Real separate database connections: a shared Sandbox transaction would serialize
  # these queries and cannot establish correctness of row locking.
  defp race(inputs, fun) do
    parent = self()

    tasks =
      Enum.map(inputs, fn input ->
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:ready, self()})

            receive do
              :go -> fun.(input)
            after
              5_000 -> raise "start barrier timed out"
            end
          end)
        end)
      end)

    for _ <- tasks do
      assert_receive {:ready, _pid}, 5_000
    end

    for task <- tasks, do: send(task.pid, :go)
    Task.await_many(tasks, 10_000)
  end
end

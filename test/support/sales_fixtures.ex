defmodule CozyCheckout.SalesFixtures do
  alias CozyCheckout.{Catalog, Repo, Sales}

  def order_fixture(attrs \\ %{}) do
    {:ok, order} =
      Sales.create_standalone_order(
        Map.merge(
          %{
            "name" => "Test account",
            "order_number" => "TEST-#{System.unique_integer([:positive])}"
          },
          attrs
        )
      )

    order
  end

  def product_fixture(price \\ "100", vat \\ "0") do
    {:ok, product} =
      Catalog.create_product(%{name: "Product #{System.unique_integer([:positive])}"})

    {:ok, pricelist} =
      Catalog.create_pricelist(%{
        product_id: product.id,
        price: price,
        vat_rate: vat,
        valid_from: Date.utc_today()
      })

    {product, pricelist}
  end

  def item_fixture(order, price \\ "100", vat \\ "0", quantity \\ 1) do
    {product, _} = product_fixture(price, vat)

    {:ok, item} =
      Sales.create_order_item(%{
        "order_id" => order.id,
        "product_id" => product.id,
        "quantity" => quantity
      })

    {:ok, _} = Sales.recalculate_order_total(order)
    Repo.preload(item, :product)
  end

  def payment_attrs(order, amount, method \\ "cash") do
    %{
      "order_id" => order.id,
      "amount" => amount,
      "payment_method" => method,
      "payment_date" => Date.utc_today()
    }
  end

  def assert_amount(actual, expected) do
    ExUnit.Assertions.assert(
      Decimal.equal?(actual, Decimal.new(expected)),
      "expected #{expected}, got #{actual}"
    )
  end

  # Accept either an explicit error result or a validation exception, without
  # prescribing how a future financial guard must expose the rejection.
  def assert_rejected(fun) do
    rejected =
      try do
        match?({:error, _}, fun.())
      rescue
        ArgumentError -> true
      end

    ExUnit.Assertions.assert(rejected, "expected inconsistent financial data to be rejected")
  end
end

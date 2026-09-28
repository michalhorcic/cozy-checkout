defmodule CozyCheckout.InventoryBarStockTest do
  use CozyCheckout.DataCase

  alias CozyCheckout.Catalog.Product
  alias CozyCheckout.Inventory
  alias CozyCheckout.Repo
  alias CozyCheckout.Sales
  alias CozyCheckout.Sales.{Order, OrderItem}

  test "bar stock is tracked independently from total stock and reconciled by count" do
    product = create_product("Draft beer", "ml")

    assert {:ok, _product} =
             Inventory.add_product_to_bar(product.id, %{
               "initial_quantity" => "10",
               "threshold" => "2"
             })

    assert Decimal.equal?(Inventory.get_bar_stock_level(product.id), Decimal.new("10000"))
    assert Decimal.equal?(Inventory.get_stock_level(product.id), Decimal.new("0"))

    assert {:ok, _movement} = Inventory.restock_bar_stock(product.id, "2.5")
    assert Decimal.equal?(Inventory.get_bar_stock_level(product.id), Decimal.new("12500"))

    assert {:ok, difference} = Inventory.count_bar_stock(product.id, "11")
    assert Decimal.equal?(difference, Decimal.new("-1500"))
    assert Decimal.equal?(Inventory.get_bar_stock_level(product.id), Decimal.new("11000"))

    assert [%{movement_type: "count_adjustment", notes: notes} | _] =
             Inventory.list_recent_bar_stock_movements()

    assert notes =~ "rozdíl -1.5"
  end

  test "POS quantity changes and item removal update bar stock" do
    product = create_product("Bottled beer", "pcs")

    assert {:ok, _product} =
             Inventory.add_product_to_bar(product.id, %{
               "initial_quantity" => "10",
               "threshold" => "2"
             })

    order =
      Repo.insert!(Order.changeset(%Order{}, %{name: "Bar account", order_number: "BAR-TEST-1"}))

    item =
      Repo.insert!(
        OrderItem.changeset(%OrderItem{}, %{
          order_id: order.id,
          product_id: product.id,
          quantity: 2,
          unit_price: Decimal.new("1"),
          vat_rate: Decimal.new("0"),
          subtotal: Decimal.new("2")
        })
      )

    assert :ok = Inventory.record_bar_stock_sale(item)
    assert Decimal.equal?(Inventory.get_bar_stock_level(product.id), Decimal.new("8"))

    assert {:ok, updated_item} = Sales.update_order_item(item, %{"quantity" => "3"})
    assert Decimal.equal?(Inventory.get_bar_stock_level(product.id), Decimal.new("7"))

    assert {:ok, _deleted_item} = Sales.delete_order_item(updated_item)
    assert Decimal.equal?(Inventory.get_bar_stock_level(product.id), Decimal.new("10"))
  end

  test "piece stock rejects fractional amounts" do
    product = create_product("Chips", "pcs")

    assert {:error, :invalid_quantity} =
             Inventory.add_product_to_bar(product.id, %{
               "initial_quantity" => "1.5",
               "threshold" => "0"
             })
  end

  defp create_product(name, unit) do
    Repo.insert!(Product.changeset(%Product{}, %{name: name, unit: unit}))
  end
end

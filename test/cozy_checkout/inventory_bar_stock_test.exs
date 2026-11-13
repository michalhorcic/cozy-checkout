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

  test "stock overview preserves zero, negative stock, thresholds, units and categories" do
    category = Repo.insert!(%CozyCheckout.Catalog.Category{name: "Bar drinks"})
    empty = tracked_product("Empty", "pcs", "2", category.id)
    negative = tracked_product("Negative", "pcs", "0")
    at_limit = tracked_product("At limit", "ml", "2")
    above = tracked_product("Above", "L", "2")
    unlimited = tracked_product("No alert", "pcs", "0")
    untracked = create_product("Not in bar", "pcs")
    deleted = tracked_product("Deleted", "pcs", "0")
    Repo.update!(Ecto.Changeset.change(deleted, deleted_at: DateTime.utc_now(:second)))

    bar_movement(negative, "sale", "-1")
    bar_movement(at_limit, "opening", "3000")
    bar_movement(at_limit, "sale", "-1000")
    bar_movement(above, "opening", "3000")
    bar_movement(unlimited, "opening", "4")

    rows = Map.new(Inventory.list_bar_stock_products(), &{&1.product.id, &1})
    assert map_size(rows) == 5
    refute Map.has_key?(rows, untracked.id)
    refute Map.has_key?(rows, deleted.id)
    assert rows[empty.id].status == :out_of_stock
    assert Decimal.equal?(rows[empty.id].stock, 0)
    assert rows[empty.id].product.category.name == "Bar drinks"
    assert rows[negative.id].status == :out_of_stock
    assert Decimal.equal?(rows[negative.id].stock, -1)
    assert rows[at_limit.id].status == :low_stock
    assert Decimal.equal?(rows[at_limit.id].raw_stock, 2000)
    assert Decimal.equal?(rows[at_limit.id].stock, 2)
    assert rows[at_limit.id].display_unit == "L"
    assert rows[above.id].status == :in_stock
    assert Decimal.equal?(rows[above.id].stock, 3)
    assert rows[unlimited.id].status == :in_stock
  end

  test "loss summary nets sales and reversals, ignores overages and converts volume" do
    drink = tracked_product("Draft drink", "ml", "0")
    empty = tracked_product("No movements", "pcs", "0")
    refunded = tracked_product("Refund exceeds sales", "pcs", "0")
    untracked = create_product("Untracked loss", "pcs")
    deleted = tracked_product("Deleted loss", "pcs", "0")
    Repo.update!(Ecto.Changeset.change(deleted, deleted_at: DateTime.utc_now(:second)))

    bar_movement(drink, "opening", "20000")
    bar_movement(drink, "restock", "5000")
    bar_movement(drink, "sale", "-12000")
    bar_movement(drink, "sale_reversal", "4000")
    bar_movement(drink, "count_adjustment", "-1000")
    bar_movement(drink, "count_adjustment", "3000")
    bar_movement(drink, "waste", "-1000")
    bar_movement(refunded, "sale", "-1")
    bar_movement(refunded, "sale_reversal", "2")
    bar_movement(untracked, "waste", "-1")
    bar_movement(deleted, "waste", "-1")

    summary = Inventory.get_bar_stock_loss_summary()
    assert hd(summary).product.id == drink.id
    rows = Map.new(summary, &{&1.product.id, &1})
    assert map_size(rows) == 3
    assert Decimal.equal?(rows[drink.id].sold, 8)
    assert Decimal.equal?(rows[drink.id].loss, 2)
    assert Decimal.equal?(rows[drink.id].loss_rate, 20)
    assert rows[drink.id].display_unit == "L"
    assert Decimal.equal?(rows[empty.id].loss_rate, 0)
    assert Decimal.equal?(rows[empty.id].sold, 0)
    assert Decimal.equal?(rows[empty.id].loss, 0)
    assert Decimal.equal?(rows[refunded.id].sold, 0)
    assert Decimal.equal?(rows[refunded.id].loss_rate, 0)
  end

  test "loss date filters preserve products without matching movements" do
    product = tracked_product("Dated stock", "pcs", "0")
    bar_movement(product, "waste", "-4", ~U[2026-10-31 23:59:59.000000Z])
    bar_movement(product, "sale", "-6", ~U[2026-11-01 00:00:00.000000Z])
    bar_movement(product, "waste", "-2", ~U[2026-11-30 23:59:59.000000Z])
    bar_movement(product, "waste", "-8", ~U[2026-12-01 00:00:00.000000Z])

    [row] =
      Inventory.get_bar_stock_loss_summary(%{
        start_date: ~D[2026-11-01],
        end_date: ~D[2026-11-30]
      })

    assert Decimal.equal?(row.sold, 6)
    assert Decimal.equal?(row.loss, 2)
    assert Decimal.equal?(row.loss_rate, 25)

    [before] = Inventory.get_bar_stock_loss_summary(%{end_date: ~D[2026-10-31]})
    assert Decimal.equal?(before.loss, 4)
    [later] = Inventory.get_bar_stock_loss_summary(%{start_date: ~D[2026-12-01]})
    assert Decimal.equal?(later.loss, 8)
    [outside] = Inventory.get_bar_stock_loss_summary(%{start_date: ~D[2027-01-01]})
    assert outside.product.id == product.id
    assert Decimal.equal?(outside.sold, 0)
    assert Decimal.equal?(outside.loss, 0)
  end

  test "overview and loss summary query counts stay constant as the bar grows" do
    category = Repo.insert!(%CozyCheckout.Catalog.Category{name: "Query count drinks"})
    tracked_product("First", "pcs", "0", category.id)
    initial_stock_queries = select_count(fn -> Inventory.list_bar_stock_products() end)
    initial_loss_queries = select_count(fn -> Inventory.get_bar_stock_loss_summary() end)
    assert initial_stock_queries == 2
    assert initial_loss_queries == 2

    for n <- 1..30 do
      product = tracked_product("Product #{n}", "pcs", "2", category.id)
      bar_movement(product, "opening", "10")
      bar_movement(product, "sale", "-2")
      bar_movement(product, "waste", "-1")
    end

    assert select_count(fn -> Inventory.list_bar_stock_products() end) == initial_stock_queries

    assert select_count(fn ->
             Inventory.get_bar_stock_loss_summary(%{start_date: Date.utc_today()})
           end) == initial_loss_queries
  end

  defp select_count(fun) do
    table = :ets.new(:bar_stock_selects, [:public, :bag])
    handler = {__MODULE__, make_ref()}
    caller = self()

    :telemetry.attach(
      handler,
      [:cozy_checkout, :repo, :query],
      fn _, _, metadata, _ ->
        if self() == caller and String.starts_with?(metadata.query, "SELECT") do
          :ets.insert(table, {make_ref(), metadata.query})
        end
      end,
      nil
    )

    try do
      fun.()
      :ets.info(table, :size)
    after
      :telemetry.detach(handler)
      :ets.delete(table)
    end
  end

  defp tracked_product(name, unit, threshold, category_id \\ nil) do
    Repo.insert!(
      Product.changeset(%Product{}, %{
        name: name,
        unit: unit,
        category_id: category_id,
        track_bar_stock: true,
        bar_stock_threshold: threshold
      })
    )
  end

  defp bar_movement(product, type, quantity, inserted_at \\ DateTime.utc_now()) do
    Repo.insert!(%CozyCheckout.Inventory.BarStockMovement{
      product_id: product.id,
      movement_type: type,
      quantity: Decimal.new(quantity),
      reason: if(type == "waste", do: "other"),
      inserted_at: inserted_at
    })
  end

  defp create_product(name, unit) do
    Repo.insert!(Product.changeset(%Product{}, %{name: name, unit: unit}))
  end
end

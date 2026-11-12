defmodule CozyCheckout.Adventure.BarStockTest do
  use CozyCheckout.DataCase, async: false
  alias CozyCheckout.Adventure.Sources.BarStock
  alias CozyCheckout.Catalog.Product
  alias CozyCheckout.Inventory.BarStockMovement
  alias CozyCheckout.Repo

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    :ok
  end

  test "one SELECT for any number of products; no fabricated stock or sufficiency" do
    product("Missing", nil, "pcs", 0)
    product("Empty", [2, -2], "pcs", 2)
    product("Negative", [-1], "pcs", 0)
    product("At limit", [1000, 1000], "ml", 2)
    product("Above", [3000], "L", 2)
    product("No limit", [4], "pcs", 0)
    hidden = product("Deleted", [1], "pcs", 2)

    Repo.update_all(from(p in Product, where: p.id == ^hidden.id),
      set: [deleted_at: DateTime.utc_now()]
    )

    untracked = product("Untracked", [1], "pcs", 2)

    Repo.update_all(from(p in Product, where: p.id == ^untracked.id),
      set: [track_bar_stock: false]
    )

    table = :ets.new(:bar_queries, [:public, :ordered_set])
    handler = {__MODULE__, make_ref()}
    :telemetry.attach(handler, [:cozy_checkout, :repo, :query], &__MODULE__.query/4, table)

    try do
      assert {:ok, snapshot} = BarStock.load()
      assert :ets.info(table, :size) == 1
      assert snapshot.tracked_count == 6
      products = Map.new(snapshot.products, &{&1.name, &1})
      assert products["Missing"].stock == nil
      assert products["Missing"].status == :unknown
      assert products["Empty"].status == :out_of_stock
      assert Decimal.equal?(products["Empty"].stock, 0)
      assert products["Negative"].status == :out_of_stock
      assert products["At limit"].status == :low_stock
      assert Decimal.equal?(products["At limit"].stock, 2)
      assert products["At limit"].unit == "L"
      assert products["Above"].status == :in_stock
      assert Decimal.equal?(products["Above"].stock, 3)
      assert products["Above"].unit == "L"
      assert products["No limit"].status == :no_limit
      assert products["No limit"].threshold == nil

      for n <- 1..40, do: product("Extra #{n}", [1], "pcs", 2)
      :ets.delete_all_objects(table)
      assert {:ok, bigger} = BarStock.load()
      assert bigger.tracked_count == 46
      assert :ets.info(table, :size) == 1
      refute BarStock.stale?(snapshot, DateTime.add(snapshot.loaded_at, 899))
      assert BarStock.stale?(snapshot, DateTime.add(snapshot.loaded_at, 900))
      :ets.delete_all_objects(table)
      Application.put_env(:cozy_checkout, :adventure_enabled, false)
      assert {:error, :disabled} = BarStock.load()
      assert :ets.info(table, :size) == 0
    after
      :telemetry.detach(handler)
      :ets.delete(table)
    end
  end

  def query(_, _, metadata, table) do
    if String.contains?(metadata.query, "FROM products p") do
      :ets.insert(table, {System.unique_integer([:monotonic]), metadata.query})
    end
  end

  defp product(name, movements, unit, threshold) do
    product =
      Repo.insert!(
        Product.changeset(%Product{}, %{
          name: name,
          unit: unit,
          track_bar_stock: true,
          bar_stock_threshold: threshold
        })
      )

    for quantity <- movements || [] do
      Repo.insert!(
        BarStockMovement.changeset(%BarStockMovement{}, %{
          product_id: product.id,
          quantity: quantity,
          movement_type: "restock"
        })
      )
    end

    product
  end
end

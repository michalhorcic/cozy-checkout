defmodule CozyCheckout.CatalogPricingTest do
  use CozyCheckout.DataCase, async: true
  @moduletag :financial
  import CozyCheckout.SalesFixtures
  alias CozyCheckout.{Catalog, Sales}
  alias CozyCheckout.Catalog.Pricelist

  test "active price includes both validity boundary dates and excludes outside dates" do
    {product, pricelist} = product_fixture("60", "12")

    {:ok, pricelist} =
      Catalog.update_pricelist(pricelist, %{valid_from: ~D[2026-10-01], valid_to: ~D[2026-10-05]})

    assert Catalog.get_active_pricelist_for_product(product.id, ~D[2026-10-01]).id == pricelist.id
    assert Catalog.get_active_pricelist_for_product(product.id, ~D[2026-10-05]).id == pricelist.id
    assert Catalog.get_active_pricelist_for_product(product.id, ~D[2026-09-30]) == nil
    assert Catalog.get_active_pricelist_for_product(product.id, ~D[2026-10-06]) == nil
  end

  test "inactive and soft-deleted prices never become the active price" do
    {product, pricelist} = product_fixture()
    {:ok, inactive} = Catalog.update_pricelist(pricelist, %{active: false})
    assert Catalog.get_active_pricelist_for_product(product.id) == nil
    {:ok, active} = Catalog.update_pricelist(inactive, %{active: true})
    {:ok, _} = Catalog.delete_pricelist(active)
    assert Catalog.get_active_pricelist_for_product(product.id) == nil
  end

  test "a product without any price cannot be sold" do
    order = order_fixture()
    {:ok, product} = Catalog.create_product(%{name: "Without price"})

    assert {:error, _} =
             Sales.create_order_item(%{
               "order_id" => order.id,
               "product_id" => product.id,
               "quantity" => "1"
             })

    assert Sales.get_order!(order.id).order_items == []
  end

  test "tier prices use the selected serving size without multiplying by its volume" do
    {product, pricelist} = tier_product()
    assert {:ok, price, vat, _} = Catalog.get_price_for_product(product.id, Decimal.new("300.0"))
    assert_amount(price, "45")
    assert_amount(vat, "12")
    assert {:ok, price, _, _} = Catalog.get_price_for_product(product.id, Decimal.new("500"))
    assert_amount(price, "70")
    order = order_fixture()

    {:ok, item} =
      Sales.create_order_item(%{
        "order_id" => order.id,
        "product_id" => product.id,
        "quantity" => "2",
        "unit_amount" => "500"
      })

    assert_amount(item.subtotal, "140")
    assert_amount(item.vat_rate, "12")
    assert_amount(item.unit_amount, "500")
    assert {:error, :no_price_for_amount} = Pricelist.get_price_for_amount(pricelist, "750")
  end

  @tag :known_bug
  test "missing tier cannot silently use a legacy price on a product with predefined sizes" do
    {product, pricelist} = tier_product()
    {:ok, _} = Catalog.update_pricelist(pricelist, %{price: "1"})
    assert {:error, :no_price_for_amount} = Catalog.get_price_for_product(product.id, "750")
  end

  test "changing a tier price preserves existing item prices and VAT" do
    {product, pricelist} = tier_product()
    order = order_fixture()

    attrs = %{
      "order_id" => order.id,
      "product_id" => product.id,
      "quantity" => "1",
      "unit_amount" => "500"
    }

    {:ok, first} = Sales.create_order_item(attrs)

    {:ok, _} =
      Catalog.update_pricelist(pricelist, %{
        vat_rate: "21",
        price_tiers: [
          %{"unit_amount" => 300, "price" => 50},
          %{"unit_amount" => 500, "price" => 80}
        ]
      })

    {:ok, second} = Sales.create_order_item(attrs)
    assert_amount(Repo.reload!(first).unit_price, "70")
    assert_amount(Repo.reload!(first).vat_rate, "12")
    assert_amount(second.unit_price, "80")
    assert_amount(second.vat_rate, "21")
  end

  test "invalid price tiers and reversed validity dates are rejected" do
    {:ok, product} = Catalog.create_product(%{name: "Tier validation"})
    base = %{product_id: product.id, vat_rate: "0", valid_from: ~D[2026-10-05]}

    for tiers <- [
          [],
          [%{"unit_amount" => 0, "price" => 45}],
          [%{"unit_amount" => 300, "price" => -1}],
          [%{"price" => 45}]
        ] do
      assert {:error, _} = Catalog.create_pricelist(Map.put(base, :price_tiers, tiers))
    end

    assert {:error, _} =
             Catalog.create_pricelist(Map.merge(base, %{price: "45", valid_to: ~D[2026-10-04]}))
  end

  defp tier_product do
    {:ok, product} =
      Catalog.create_product(%{
        name: "Tier product",
        unit: "ml",
        default_unit_amounts: "[300,500]"
      })

    {:ok, pricelist} =
      Catalog.create_pricelist(%{
        product_id: product.id,
        vat_rate: "12",
        valid_from: Date.utc_today(),
        price_tiers: [
          %{"unit_amount" => 300, "price" => 45},
          %{"unit_amount" => 500, "price" => 70}
        ]
      })

    {product, pricelist}
  end
end

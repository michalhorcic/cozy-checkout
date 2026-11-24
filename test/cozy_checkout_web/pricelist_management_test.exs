defmodule CozyCheckoutWeb.PricelistManagementTest do
  use CozyCheckout.DataCase, async: true

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]
  import CozyCheckout.SalesFixtures

  alias CozyCheckout.Catalog.Pricelist
  alias CozyCheckoutWeb.PricelistLive.Management

  test "update prefills the latest expired active price, excluding future and inactive prices" do
    {product, _} = product_fixture()
    today = Date.utc_today()
    old = price(product.id, Date.add(today, -20), "40")
    latest = price(product.id, Date.add(today, -1), "55")
    inactive = %{latest | id: Ecto.UUID.generate(), price: Decimal.new("90"), active: false}
    future = price(product.id, Date.add(today, 10), "80")

    socket = open_modal(product, [old, future, inactive, latest])

    assert socket.assigns.previous_pricelist == latest
    assert_amount(socket.assigns.form[:price].value, "55")
    assert socket.assigns.form[:valid_from].value == today
  end

  test "tiered prices are available for prefilling without copying a future price" do
    {product, _} = product_fixture()

    {:ok, product} =
      CozyCheckout.Catalog.update_product(product, %{unit: "L", default_unit_amounts: "[0.5,1,2]"})

    latest = %{
      price(product.id, Date.add(Date.utc_today(), -1), "55")
      | price: nil,
        price_tiers: [
          %{"unit_amount" => 0.5, "price" => 55},
          %{"unit_amount" => 1, "price" => 100}
        ]
    }

    socket = open_modal(product, [latest])

    html =
      render_component(
        &Management.render/1,
        Map.merge(socket.assigns, %{
          no_prices_count: 0,
          expired_prices_count: 0,
          incomplete_tiers_count: 0,
          products_no_prices: [],
          products_expired_prices: [],
          products_incomplete_tiers: []
        })
      )

    document = LazyHTML.from_fragment(html)

    assert LazyHTML.query(document, "input[id='price_0.5']") |> LazyHTML.attribute("value") == [
             "55"
           ]

    assert LazyHTML.query(document, "#price_1") |> LazyHTML.attribute("value") == ["100"]
    assert LazyHTML.query(document, "#price_2") |> LazyHTML.attribute("value") == []
  end

  test "products without expired prices start with a blank price" do
    {product, _} = product_fixture()
    socket = open_modal(product, [])
    assert socket.assigns.previous_pricelist == nil
    assert socket.assigns.form[:price].value == nil
  end

  defp open_modal(product, prices) do
    socket =
      %Phoenix.LiveView.Socket{}
      |> assign(products_expired_prices: [%{product | pricelists: prices}])

    {:noreply, socket} =
      Management.handle_event("open_add_price_modal", %{"product_id" => product.id}, socket)

    socket
  end

  defp price(product_id, valid_to, amount) do
    %Pricelist{
      id: Ecto.UUID.generate(),
      product_id: product_id,
      price: Decimal.new(amount),
      active: true,
      valid_from: Date.add(valid_to, -30),
      valid_to: valid_to
    }
  end
end

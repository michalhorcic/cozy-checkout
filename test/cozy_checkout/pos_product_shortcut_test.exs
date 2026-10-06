defmodule CozyCheckout.PosProductShortcutTest do
  use CozyCheckout.DataCase, async: true

  import CozyCheckout.SalesFixtures
  alias CozyCheckout.{Catalog, Sales}
  alias CozyCheckout.Catalog.PosProductShortcut
  alias CozyCheckoutWeb.PosLive.OrderManagement

  test "shortcuts can repeat a product for different preset sizes and are ordered manually" do
    {:ok, product} =
      Catalog.create_product(%{
        name: "Beer",
        unit: "ml",
        default_unit_amounts: "[300,500]"
      })

    {:ok, larger} =
      Catalog.create_pos_shortcut(%{
        product_id: product.id,
        unit_amount: "500",
        position: 2
      })

    {:ok, smaller} =
      Catalog.create_pos_shortcut(%{
        product_id: product.id,
        unit_amount: "300",
        position: 1
      })

    {:ok, hidden_product} =
      Catalog.create_product(%{
        name: "Hidden beer",
        unit: "ml",
        default_unit_amounts: "[500]",
        visible_in_pos: false
      })

    {:ok, hidden_shortcut} =
      Catalog.create_pos_shortcut(%{product_id: hidden_product.id, unit_amount: "500"})

    assert Enum.map(Catalog.list_pos_shortcuts(), & &1.id) == [smaller.id, larger.id]
    assert %PosProductShortcut{} = Catalog.get_pos_shortcut!(larger.id)
    assert hidden_shortcut.position == 3
    assert length(Catalog.list_pos_shortcuts_for_admin()) == 3

    {:ok, deleted} = Catalog.delete_pos_shortcut(larger)
    assert deleted.deleted_at.microsecond == {0, 0}
    assert Enum.map(Catalog.list_pos_shortcuts(), & &1.id) == [smaller.id]

    assert {:error, changeset} =
             Catalog.create_pos_shortcut(%{
               product_id: product.id,
               unit_amount: "750",
               position: 3
             })

    assert errors_on(changeset).unit_amount != []
    assert errors_on(changeset).unit_amount != []
  end

  test "using a fixed-size POS shortcut adds that exact size without opening the size picker" do
    {:ok, product} =
      Catalog.create_product(%{
        name: "Beer",
        unit: "ml",
        default_unit_amounts: "[300,500]"
      })

    {:ok, _pricelist} =
      Catalog.create_pricelist(%{
        product_id: product.id,
        vat_rate: "0",
        valid_from: Date.utc_today(),
        price_tiers: [
          %{"unit_amount" => 300, "price" => 45},
          %{"unit_amount" => 500, "price" => 70}
        ]
      })

    {:ok, shortcut} =
      Catalog.create_pos_shortcut(%{
        product_id: product.id,
        unit_amount: "500",
        position: 0
      })

    order = order_fixture()
    socket = mounted(order)

    {:noreply, socket} =
      OrderManagement.handle_event(
        "add_pos_shortcut",
        %{"shortcut-id" => shortcut.id},
        socket
      )

    [item] = Sales.get_order!(order.id).order_items
    assert Decimal.equal?(item.unit_amount, Decimal.new("500"))
    assert Decimal.equal?(item.unit_price, Decimal.new("70"))
    refute socket.assigns.show_unit_modal
  end

  defp mounted(order) do
    socket = %Phoenix.LiveView.Socket{
      endpoint: CozyCheckoutWeb.Endpoint,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{live_temp: %{}}
    }

    {:ok, socket} = OrderManagement.mount(%{"id" => order.id}, %{}, socket)
    socket
  end
end

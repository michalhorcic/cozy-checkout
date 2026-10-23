defmodule CozyCheckout.ListFilteringTest do
  use CozyCheckout.DataCase, async: true

  import CozyCheckout.SalesFixtures

  alias CozyCheckout.{Bookings, Catalog, Guests, Sales}

  test "empty pagination has no page links" do
    assert CozyCheckoutWeb.FlopComponents.page_numbers(%Flop.Meta{total_pages: 0}) == []
    assert CozyCheckoutWeb.FlopComponents.page_numbers(%Flop.Meta{total_pages: 1}) == [1]
  end

  test "order filters, requested sorting and pagination remain available" do
    first = order_fixture(%{"name" => "Alpha account"})
    second = order_fixture(%{"name" => "Zulu account"})
    removed = order_fixture(%{"name" => "Removed account"})
    {:ok, _} = Sales.delete_order(removed)

    params = %{
      "filters" => %{"0" => %{"field" => "status", "op" => "==", "value" => "open"}},
      "order_by" => ["order_number"],
      "order_directions" => ["asc"],
      "limit" => 1
    }

    expected = Enum.sort_by([first, second], & &1.order_number)
    assert {:ok, {[page_one], meta}} = Sales.list_orders_with_flop(params)
    assert page_one.id == hd(expected).id
    assert meta.total_count == 2
    assert {:ok, {[page_two], _}} = Sales.list_orders_with_flop(Map.put(params, "offset", 1))
    assert page_two.id == List.last(expected).id

    assert {:ok, {[match], _}} =
             Sales.list_orders_with_flop(%{
               "filters" => %{"0" => %{"field" => "name", "op" => "ilike", "value" => "alpha"}}
             })

    assert match.id == first.id
  end

  test "bookings retain arrival sorting and status filtering" do
    {:ok, guest} = Guests.create_guest(%{name: "Filtering guest"})

    bookings =
      for day <- [20, 10] do
        {:ok, booking} =
          Bookings.create_booking(%{
            guest_id: guest.id,
            check_in_date: Date.new!(2026, 11, day),
            check_out_date: Date.new!(2026, 11, day + 1)
          })

        booking
      end

    assert {:ok, {rows, _}} = Bookings.list_bookings_with_flop()
    assert Enum.map(rows, & &1.id) == Enum.map(Enum.reverse(bookings), & &1.id)
    {:ok, _} = Bookings.update_booking(hd(bookings), %{status: "cancelled"})

    assert {:ok, {[upcoming], _}} =
             Bookings.list_bookings_with_flop(%{
               "filters" => %{"0" => %{"field" => "status", "op" => "==", "value" => "upcoming"}}
             })

    assert upcoming.id == List.last(bookings).id
  end

  test "products keep alphabetical ordering, custom search and active filtering" do
    {:ok, zulu} = Catalog.create_product(%{name: "Zulu"})
    {:ok, alpha} = Catalog.create_product(%{name: "Alpha"})
    {:ok, _} = Catalog.create_product(%{name: "Inactive", active: false})

    params = %{"filters" => %{"0" => %{"field" => "active", "op" => "==", "value" => true}}}
    assert {:ok, {rows, _}} = Catalog.list_products_with_flop(params)
    assert Enum.map(rows, & &1.id) == [alpha.id, zulu.id]

    assert {:ok, {[match], _}} =
             Catalog.list_products_with_flop(Map.put(params, "product_name", "alph"))

    assert match.id == alpha.id
  end

  test "pricelists keep newest validity first and filter by product" do
    {product, current} = product_fixture()
    {other, _} = product_fixture()

    {:ok, older} =
      Catalog.create_pricelist(%{
        product_id: product.id,
        price: "90",
        vat_rate: "0",
        valid_from: Date.add(Date.utc_today(), -30)
      })

    assert {:ok, {rows, _}} =
             Catalog.list_pricelists_with_flop(%{
               "filters" => %{
                 "0" => %{"field" => "product_id", "op" => "==", "value" => product.id}
               }
             })

    assert Enum.map(rows, & &1.id) == [current.id, older.id]
    refute Enum.any?(rows, &(&1.product_id == other.id))
  end
end

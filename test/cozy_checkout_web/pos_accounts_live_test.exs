defmodule CozyCheckoutWeb.PosAccountsLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CozyCheckout.SalesFixtures
  import CozyCheckout.MenuFixtures, only: [menu_booking_fixture: 1]

  alias CozyCheckout.{Repo, Sales}
  alias CozyCheckout.Sales.Order
  alias CozyCheckoutWeb.AdminAuth

  setup do
    previous = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, previous),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    :ok
  end

  test "POS lists all open accounts without offering reservations", %{conn: conn} do
    booking =
      menu_booking_fixture(%{
        check_in_date: Date.utc_today(),
        check_out_date: Date.add(Date.utc_today(), 2)
      })

    booking = Repo.preload(booking, :guest)

    account = order_fixture(%{"name" => "Novákovi"})

    historical =
      order_fixture(%{
        "name" => nil,
        "guest_id" => booking.guest_id,
        "booking_id" => booking.id,
        "status" => "partially_paid"
      })

    paid = order_fixture(%{"status" => "paid"})
    cancelled = order_fixture(%{"status" => "cancelled"})
    deleted = order_fixture()
    {:ok, _} = Sales.delete_order(deleted)
    service = order_fixture(%{"is_service_order" => true})

    {:ok, view, html} = live(conn, "/pos")
    assert has_element?(view, "#pos-new-account", "Nový účet")
    assert has_element?(view, "#pos-order-#{account.id}", "Novákovi")
    assert has_element?(
             view,
             "#pos-order-#{account.id} img[src='/images/account-stamps/#{account.account_stamp}.svg']"
           )
    assert has_element?(view, "#pos-order-#{historical.id}", booking.guest.name)
    refute has_element?(view, "[phx-click='select_booking']")
    refute html =~ "Bez pobytu"
    refute html =~ "Zatím tu nejsou"

    for order <- [paid, cancelled, deleted, service] do
      refute has_element?(view, "#pos-order-#{order.id}")
    end

    view |> element("[phx-click='toggle_service_mode']") |> render_click()
    assert has_element?(view, "#pos-order-#{service.id}")
    refute has_element?(view, "#pos-order-#{account.id}")
    refute has_element?(view, "#pos-order-#{historical.id}")

    view |> element("#pos-order-#{service.id}") |> render_click()
    assert_redirect(view, "/pos/orders/#{service.id}")
  end

  test "empty POS creates a named account without a reservation", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    assert html =~ "Zatím tu nejsou žádné otevřené účty"

    view |> element("#pos-new-account") |> render_click()
    assert has_element?(view, "h3", "Nový účet")
    assert has_element?(view, "button[phx-click='create_quick_order'][disabled]")

    view |> form("#pos-stamp-form", account_stamp: "mushroom") |> render_change()
    assert has_element?(view, "#pos-stamp-picker input[value='mushroom'][checked]")

    render_keyup(view, "update_quick_order_name", %{"value" => "  Novákovi  "})
    view |> element("[phx-click='create_quick_order']") |> render_click()

    order = Repo.get_by!(Order, name: "Novákovi")
    assert order.booking_id == nil
    assert order.guest_id == nil
    assert order.account_stamp == "mushroom"
    assert_redirect(view, "/pos/orders/#{order.id}")

    {:ok, detail, _} = live(conn, "/pos/orders/#{order.id}")
    assert has_element?(detail, "img[src='/images/account-stamps/mushroom.svg']")
    refute render(detail) =~ "Standalone Order"
  end

  test "admin creates a named account with items without choosing a booking", %{conn: conn} do
    conn =
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    {product, _} = product_fixture()
    {:ok, view, _} = live(conn, "/admin/orders/new")
    assert has_element?(view, "input[name='order[name]']")
    refute has_element?(view, "select[name='order[booking_id]']")

    view
    |> form("#add-item-form", %{product_id: product.id, quantity: "1"})
    |> render_submit()

    render_click(view, "save")
    assert render(view) =~ "Vyplňte název účtu."
    refute Repo.get_by(Order, name: "Nový admin účet")

    view
    |> form("#order-form", order: %{name: "  Nový admin účet  ", account_stamp: "moon"})
    |> render_change()
    render_click(view, "save")

    order = Repo.get_by!(Order, name: "Nový admin účet") |> Repo.preload(:order_items)
    assert order.booking_id == nil
    assert order.guest_id == nil
    assert order.account_stamp == "moon"
    assert length(order.order_items) == 1
    assert_amount(order.total_amount, "100")
    assert_redirect(view, "/admin/orders/#{order.id}")
  end
end

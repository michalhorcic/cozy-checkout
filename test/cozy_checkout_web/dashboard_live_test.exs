defmodule CozyCheckoutWeb.DashboardLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.MenuFixtures
  alias CozyCheckout.{Bookings, Dashboard}
  alias CozyCheckoutWeb.AdminAuth

  setup %{conn: conn} do
    previous = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, previous),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    {:ok,
     conn:
       Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})}
  end

  test "month-wide stays, actionable catering warnings and planner totals render", %{conn: conn} do
    today = Date.utc_today()
    boundary = Dashboard.month_ahead(today)

    booking =
      menu_booking_fixture(%{
        check_in_date: boundary,
        check_out_date: Date.add(boundary, 6),
        meal_plan: nil
      })

    arriving = menu_booking_fixture(%{check_in_date: today, check_out_date: Date.add(today, 6)})
    {:ok, room} = CozyCheckout.Rooms.create_room(%{room_number: "101", capacity: 20})
    {:ok, _} = Bookings.add_room_to_booking(arriving.id, room.id)
    {:ok, view, _} = live(conn, "/admin")

    assert has_element?(view, "#dashboard-booking-#{booking.id}")
    assert has_element?(view, "#dashboard-booking-#{arriving.id}", "Dnes příjezd")
    assert has_element?(view, "#dashboard-booking-#{arriving.id}", "101")
    assert has_element?(view, "#dashboard-dinner", "15")

    assert has_element?(
             view,
             "#dashboard-issue-details-#{booking.id}[href='/admin/bookings/#{booking.id}/edit']"
           )

    assert has_element?(view, "#open-calendar[href='/admin/bookings/calendar']")
    assert has_element?(view, "#open-kitchen-shopping[href='/admin/kitchen-shopping']")

    result = view |> element("#dashboard-issue-details-#{booking.id}") |> render_click()
    {:ok, editor, _} = follow_redirect(result, conn)
    assert has_element?(editor, "#booking-form")

    assert has_element?(
             editor,
             "#admin-desktop a[href='/admin/bookings/calendar'][aria-current='page']"
           )
  end

  test "empty overview omits attention and refreshes when bookings change", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin")
    assert has_element?(view, "#stays-empty")
    refute has_element?(view, "#dashboard-attention")

    booking =
      menu_booking_fixture(%{
        check_in_date: Date.utc_today(),
        check_out_date: Date.add(Date.utc_today(), 3),
        meal_plan: nil
      })

    send(view.pid, :refresh_overview)
    assert has_element?(view, "#dashboard-booking-#{booking.id}")
    assert has_element?(view, "#portions-incomplete")
  end

  test "all existing areas remain reachable, active navigation follows routes, and locking works",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin")

    for path <-
          ~w(/admin/bookings/calendar /admin/meal-planner /admin/bar-stock /admin/emails /admin/orders /admin/payments /admin/categories /admin/products /admin/pos-shortcuts /admin/pricelists /admin/pricelists/management /admin/pricelists/print /admin/purchase_orders /admin/stock /admin/stock/restock /admin/stock-adjustments /admin/inventory-reports /admin/guests /admin/rooms /admin/bookings /admin/bookings/timeline /admin/ical-import /admin/economy /admin/statistics /admin/pohoda-export) do
      assert has_element?(view, "#admin-desktop a[href='#{path}']")
    end

    result =
      view |> element("#admin-desktop a[href='/admin/bookings/calendar']") |> render_click()

    {:ok, calendar, _} = follow_redirect(result, conn)

    assert has_element?(
             calendar,
             "#admin-desktop a[href='/admin/bookings/calendar'][aria-current='page']"
           )

    refute has_element?(calendar, "#admin-desktop-more[open]")

    assert has_element?(calendar, "#admin-brand-header form[action='/admin/logout']")
    conn = post(conn, "/admin/logout")
    assert redirected_to(conn) == "/pos"
    assert get_session(conn, AdminAuth.session_key()) == nil
  end
end

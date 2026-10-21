defmodule CozyCheckoutWeb.BookingMenuLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.MenuFixtures
  alias CozyCheckout.{Bookings, Meals}
  alias CozyCheckout.Meals.MenuPlanning
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

  defp preview(view, variant) do
    view
    |> form("#booking-menu-selection", selection: %{variant_id: variant.id})
    |> render_submit()
  end

  test "reviews, applies and manually edits a booking menu without changing the shared menu", %{
    conn: conn
  } do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    {:ok, _} = Meals.upsert_meal(~D[2027-01-09], "lunch", %{menu_text: "Společný oběd"})
    {:ok, detail, _} = live(conn, "/admin/bookings/#{booking.id}")
    assert has_element?(detail, "#booking-menu-link")
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/menu")
    assert has_element?(view, "#booking-menu-unassigned")
    preview(view, variant)
    assert has_element?(view, "#booking-menu-preview")
    assert has_element?(view, "#preview-portions-2027-01-09-lunch", "15 porcí")
    assert has_element?(view, "#booking-menu-preview", "Společné menu se liší")
    assert MenuPlanning.get_booking_menu(booking.id) == nil
    view |> element("#apply-booking-menu") |> render_click()
    refute has_element?(view, "#booking-menu-unassigned")
    assert has_element?(view, "#flash-success .bg-emerald-50", "Menu přiřazeno")
    menu = MenuPlanning.get_booking_menu(booking.id)
    item = hd(menu.items)
    assert has_element?(view, "#assigned-portions-#{item.id}", "15 porcí")
    view |> element("#edit-menu-item-#{item.id}") |> render_click()

    view
    |> form("#booking-menu-item-form",
      booking_menu_item: %{menu_text: "Dietní ruční večeře", supplements: "Bezlepková příloha"}
    )
    |> render_submit()

    assert has_element?(view, "#manual-menu-item-#{item.id}")
    assert has_element?(view, "#flash-success .bg-emerald-50", "Ruční úprava uložena")
    preview(view, variant)
    assert has_element?(view, "#booking-menu-preview", "Ruční úprava bude zachována")
    assert has_element?(view, "#booking-menu-preview", "Dietní ruční večeře")
    view |> element("#apply-booking-menu") |> render_click()
    assert hd(MenuPlanning.get_booking_menu(booking.id).items).menu_text == "Dietní ruční večeře"
    assert Meals.get_meal_by_date_and_type(~D[2027-01-09], "lunch").menu_text == "Společný oběd"
  end

  test "incompatible variant is explained and cannot be applied", %{conn: conn} do
    booking = menu_booking_fixture()
    variant = variant_fixture(%{meal_plan: "half_board"})
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/menu")
    preview(view, variant)
    assert has_element?(view, "#booking-menu-preview-errors", "Nesouhlasí režim stravování")
    assert has_element?(view, "#apply-booking-menu[disabled]")
    assert MenuPlanning.get_booking_menu(booking.id) == nil
  end

  test "late booking edits invalidate the preview instead of applying outdated portions", %{
    conn: conn
  } do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/menu")
    preview(view, variant)
    {:ok, _} = Bookings.update_booking(booking, %{meal_children: 8})
    view |> element("#apply-booking-menu") |> render_click()
    refute has_element?(view, "#booking-menu-preview")
    assert has_element?(view, "#flash-error .bg-red-50", "Podklady se od náhledu změnily")
    assert MenuPlanning.get_booking_menu(booking.id) == nil
    preview(view, variant)
    assert has_element?(view, "#preview-portions-2027-01-09-lunch", "18 porcí")
  end

  test "stale menu and orphaned manual edits require explicit release before changing dates", %{
    conn: conn
  } do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    menu = assign_variant(booking, variant)
    item = hd(menu.items)

    {:ok, _} =
      MenuPlanning.update_booking_item(
        booking.id,
        item.id,
        %{menu_text: "Chráněné jídlo"},
        MenuPlanning.item_version(item)
      )

    {:ok, _} =
      Bookings.update_booking(booking, %{
        check_in_date: ~D[2027-01-15],
        check_out_date: ~D[2027-01-17]
      })

    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/menu")
    assert has_element?(view, "#booking-menu-stale")
    preview(view, variant)
    assert has_element?(view, "#booking-menu-preview-errors", "Ruční úpravy mimo nový rozpis")
    assert has_element?(view, "#apply-booking-menu[disabled]")
    view |> element("#allow-replacement-#{item.id}") |> render_click()
    preview(view, variant)
    refute has_element?(view, "#apply-booking-menu[disabled]")
    view |> element("#apply-booking-menu") |> render_click()
    refute has_element?(view, "#booking-menu-stale")
    assert hd(MenuPlanning.get_booking_menu(booking.id).items).date == ~D[2027-01-15]
  end

  test "planner and print show both groups separately, including departure breakfasts", %{
    conn: conn
  } do
    week = Meals.start_of_week(Date.utc_today())
    first = menu_booking_fixture(%{check_in_date: Date.add(week, -2), check_out_date: week})

    second =
      menu_booking_fixture(%{
        check_in_date: Date.add(week, -2),
        check_out_date: week,
        meal_adults: 2,
        meal_children: 0
      })

    a = variant_fixture(%{name: "Menu první skupiny"})
    b = variant_fixture(%{name: "Menu druhé skupiny"})
    menu_a = assign_variant(first, a)
    menu_b = assign_variant(second, b)
    item_a = List.last(menu_a.items)
    item_b = List.last(menu_b.items)
    {:ok, view, _} = live(conn, "/admin/meal-planner")
    assert has_element?(view, "#menu-variants-link")
    assert has_element?(view, "#portions-#{week}-breakfast", "17 porcí")
    assert has_element?(view, "#group-menus-#{week}-breakfast-portions-#{item_a.id}", "15 porcí")
    assert has_element?(view, "#group-menus-#{week}-breakfast-portions-#{item_b.id}", "2 porcí")
    assert has_element?(view, "#mobile-group-menus-#{week}-breakfast", "Menu druhé skupiny")
    refute has_element?(view, "#booking-menu-issues")
    {:ok, printed, _} = live(conn, "/admin/meal-planner/print?week=#{week}")
    assert has_element?(printed, "#print-group-menus-#{week}-breakfast", "Menu první skupiny")
    assert has_element?(printed, "#print-group-menus-#{week}-breakfast", "Menu druhé skupiny")

    assert has_element?(
             printed,
             "#print-group-menus-#{week}-breakfast-portions-#{item_a.id}",
             "15 porcí"
           )
  end

  test "planner warns about a stale group menu while retaining its known portion count", %{
    conn: conn
  } do
    week = Meals.start_of_week(Date.utc_today())
    booking = menu_booking_fixture(%{check_in_date: week, check_out_date: Date.add(week, 2)})
    assign_variant(booking, variant_fixture())
    {:ok, _} = Bookings.update_booking(booking, %{last_meal: "lunch"})
    {:ok, view, _} = live(conn, "/admin/meal-planner")

    assert has_element?(
             view,
             "#booking-menu-issue-#{booking.id}",
             "Termín nebo stravování se změnilo"
           )

    assert has_element?(view, "#portions-#{week}-dinner", "15 porcí")
    refute has_element?(view, "#group-menus-#{week}-dinner")
  end

  test "a variant archived after opening the page refreshes the selection without crashing", %{
    conn: conn
  } do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/menu")
    {:ok, _} = MenuPlanning.delete_variant(variant)
    preview(view, variant)
    assert has_element?(view, "#flash-error", "Vyberte dostupnou variantu")
    refute has_element?(view, "#booking-menu-variant option[value='#{variant.id}']")
    refute has_element?(view, "#booking-menu-preview")
  end
end

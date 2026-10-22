defmodule CozyCheckoutWeb.BookingCateringIndexLiveTest do
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

    conn =
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    {:ok, conn: conn}
  end

  defp change(view, booking, field, value) do
    section = if field == "meal_plan", do: "plan", else: "counts"

    view
    |> form("#catering-#{section}-#{booking.id}", inline: %{field => value})
    |> render_change(%{"_target" => ["inline", field]})
  end

  defp choose_menu(view, booking, variant) do
    view
    |> form("#catering-menu-#{booking.id}", selection: %{variant_id: variant.id})
    |> render_change()
  end

  test "plans a menu before counts are known, then starts counting when both are supplied", %{
    conn: conn
  } do
    booking = menu_booking_fixture(%{meal_plan: nil})
    matching = variant_fixture(%{meal_plan: "half_board"})
    wrong_plan = variant_fixture()
    wrong_days = variant_fixture(%{days: 4, meal_plan: "half_board"})
    wrong_first = variant_fixture(%{first_meal: "breakfast", meal_plan: "half_board"})
    wrong_last = variant_fixture(%{last_meal: "dinner", meal_plan: "half_board"})
    removed = variant_fixture(%{meal_plan: "half_board"})
    {:ok, _} = MenuPlanning.delete_variant(removed)

    {:ok, view, _} = live(conn, "/admin/bookings")
    assert has_element?(view, "#catering-plan-input-#{booking.id} option[value=''][selected]")
    change(view, booking, "meal_plan", "half_board")
    saved = Bookings.get_booking!(booking.id)
    assert saved.first_meal == "dinner"
    assert saved.last_meal == "breakfast"
    assert saved.meal_adults == nil
    assert saved.meal_children == nil
    assert has_element?(view, "#catering-missing-counts-#{booking.id}")
    assert has_element?(view, "#catering-menu-input-#{booking.id} option[value='#{matching.id}']")

    for wrong <- [wrong_plan, wrong_days, wrong_first, wrong_last, removed] do
      refute has_element?(view, "#catering-menu-input-#{booking.id} option[value='#{wrong.id}']")
    end

    choose_menu(view, booking, matching)
    menu = MenuPlanning.get_booking_menu(booking.id)
    assert menu.menu_variant_id == matching.id
    assert length(menu.items) == 4
    assert MenuPlanning.kitchen_for_range(~D[2027-01-09], ~D[2027-01-09]).groups == %{}

    change(view, booking, "meal_adults", "12")
    assert Bookings.get_booking!(booking.id).meal_children == nil
    assert has_element?(view, "#catering-missing-counts-#{booking.id}")
    change(view, booking, "meal_children", "0")
    refute has_element?(view, "#catering-missing-counts-#{booking.id}")
    assert has_element?(view, "#catering-adults-#{booking.id}[value='12']")
    refute MenuPlanning.stale?(menu, Bookings.get_booking!(booking.id))

    assert Meals.get_portion_counts_for_range(~D[2027-01-09], ~D[2027-01-09])[~D[2027-01-09]][
             "dinner"
           ].total == 12

    assert [%{counts: %{total: 12}}] =
             MenuPlanning.kitchen_for_range(~D[2027-01-09], ~D[2027-01-09]).groups[
               {~D[2027-01-09], "dinner"}
             ]

    change(view, booking, "meal_adults", "")
    assert Bookings.get_booking!(booking.id).meal_adults == nil
    assert Bookings.get_booking!(booking.id).meal_children == 0
    assert MenuPlanning.kitchen_for_range(~D[2027-01-09], ~D[2027-01-09]).groups == %{}
    {:ok, refreshed, _} = live(conn, "/admin/bookings")

    assert has_element?(
             refreshed,
             "#catering-menu-input-#{booking.id} option[value='#{matching.id}'][selected]"
           )
  end

  test "invalid counts do not save and edits retain the current filters", %{conn: conn} do
    booking = menu_booking_fixture() |> then(&Bookings.get_booking!(&1.id))

    {:ok, view, _} =
      live(conn, "/admin/bookings?guest_search=#{booking.guest.name}&show_all=true")

    change(view, booking, "meal_children", "-1")
    assert has_element?(view, "#catering-error-#{booking.id}")
    assert Bookings.get_booking!(booking.id).meal_children == 5
    change(view, booking, "meal_children", "2")
    refute has_element?(view, "#catering-error-#{booking.id}")
    assert Bookings.get_booking!(booking.id).meal_children == 2

    assert URI.decode_query(URI.parse(assert_patch(view)).query)["guest_search"] ==
             booking.guest.name
  end

  test "changing board marks the assigned menu stale and none clears diner instructions", %{
    conn: conn
  } do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    assign_variant(booking, variant)
    {:ok, view, _} = live(conn, "/admin/bookings")
    change(view, booking, "meal_plan", "half_board")
    assert has_element?(view, "#catering-stale-#{booking.id}")
    assert MenuPlanning.kitchen_for_range(~D[2027-01-09], ~D[2027-01-09]).groups == %{}
    change(view, booking, "meal_plan", "none")
    saved = Bookings.get_booking!(booking.id)
    assert saved.meal_plan == "none"
    assert saved.meal_adults == nil
    refute has_element?(view, "#catering-counts-#{booking.id}")
    refute has_element?(view, "#catering-menu-#{booking.id}")
  end

  test "custom boundaries from the detail are respected and incompatible menu events are rejected",
       %{conn: conn} do
    booking = menu_booking_fixture(%{first_meal: "lunch", last_meal: "lunch"})
    matching = variant_fixture(%{first_meal: "lunch", last_meal: "lunch"})
    wrong = variant_fixture()
    {:ok, view, _} = live(conn, "/admin/bookings")
    assert has_element?(view, "#catering-menu-input-#{booking.id} option[value='#{matching.id}']")
    refute has_element?(view, "#catering-menu-input-#{booking.id} option[value='#{wrong.id}']")

    render_change(view, "assign_menu", %{
      "id" => booking.id,
      "selection" => %{"variant_id" => wrong.id}
    })

    assert has_element?(view, "#catering-error-#{booking.id}")
    assert MenuPlanning.get_booking_menu(booking.id) == nil
    change(view, booking, "meal_plan", "half_board")
    assert Bookings.get_booking!(booking.id).meal_plan == "full_board"
    assert has_element?(view, "#catering-error-#{booking.id}")
  end

  test "missing departure and cancelled bookings cannot be assigned catering", %{conn: conn} do
    missing = menu_booking_fixture(%{meal_plan: nil, check_out_date: nil})
    cancelled = menu_booking_fixture(%{status: "cancelled"})
    {:ok, view, _} = live(conn, "/admin/bookings")
    change(view, missing, "meal_plan", "full_board")
    assert has_element?(view, "#catering-error-#{missing.id}")
    assert Bookings.get_booking!(missing.id).meal_plan == nil
    assert has_element?(view, "#catering-plan-input-#{cancelled.id}[disabled]")

    render_change(view, "update_catering", %{
      "id" => cancelled.id,
      "inline" => %{"meal_adults" => "99"},
      "_target" => ["inline", "meal_adults"]
    })

    assert Bookings.get_booking!(cancelled.id).meal_adults == 10
  end
end

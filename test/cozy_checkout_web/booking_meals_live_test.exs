defmodule CozyCheckoutWeb.BookingMealsLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias CozyCheckout.{Bookings, Guests, Meals}
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

    {:ok, conn: conn, week: Meals.start_of_week(Date.utc_today())}
  end

  defp stay(date, overrides \\ %{}) do
    {:ok, guest} = Guests.create_guest(%{name: "Group #{System.unique_integer([:positive])}"})

    {:ok, booking} =
      Bookings.create_booking(
        Map.merge(
          %{
            guest_id: guest.id,
            check_in_date: Date.add(date, -2),
            check_out_date: date,
            meal_plan: "full_board",
            meal_adults: 10,
            meal_children: 5,
            first_meal: "dinner",
            last_meal: "breakfast"
          },
          overrides
        )
      )

    booking
  end

  test "edits catering, validates half board, and persists the form", %{conn: conn, week: week} do
    booking = stay(week, %{meal_plan: nil})
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/edit")
    assert has_element?(view, "#booking-catering")
    assert has_element?(view, "#booking_meal_plan option[value='']")
    refute has_element?(view, "#booking_meal_adults")

    view |> form("#booking-form", booking: %{meal_plan: "half_board"}) |> render_change()
    assert has_element?(view, "#booking_meal_adults")
    assert has_element?(view, "#booking_meal_children")

    view
    |> form("#booking-form",
      booking: %{
        meal_plan: "half_board",
        meal_adults: "10",
        meal_children: "0",
        first_meal: "lunch",
        last_meal: "breakfast"
      }
    )
    |> render_submit()

    assert has_element?(view, "#booking-catering", "Polopenze nezahrnuje oběd")
    assert Bookings.get_booking!(booking.id).meal_plan == nil

    view
    |> form("#booking-form",
      booking: %{
        meal_plan: "half_board",
        meal_adults: "10",
        meal_children: "0",
        first_meal: "dinner",
        last_meal: "breakfast"
      }
    )
    |> render_submit()

    assert URI.parse(assert_patch(view)).path == "/admin/bookings"
    updated = Bookings.get_booking!(booking.id)
    assert updated.meal_plan == "half_board"
    assert updated.meal_children == 0

    {:ok, detail, _} = live(conn, "/admin/bookings/#{booking.id}")
    assert has_element?(detail, "#booking-meal-plan", "Polopenze")
    assert has_element?(detail, "#booking-portions-#{week}-breakfast", "10 porcí")
    assert has_element?(detail, "#booking-portions-#{week}-lunch", "0 porcí")
  end

  test "new booking can save catering and respects a manually selected same-day checkout", %{
    conn: conn,
    week: week
  } do
    {:ok, guest} = Guests.create_guest(%{name: "New catering guest"})
    {:ok, view, _} = live(conn, "/admin/bookings/new")
    view |> element("#guest-search") |> render_keyup(%{"value" => guest.name})

    view
    |> element("[phx-click='select_guest'][phx-value-guest-id='#{guest.id}']")
    |> render_click()

    view
    |> form("#booking-form", booking: %{meal_plan: "full_board", check_in_date: to_string(week)})
    |> render_change(%{"_target" => ["booking", "check_in_date"]})

    view
    |> form("#booking-form", booking: %{check_out_date: to_string(week)})
    |> render_change(%{"_target" => ["booking", "check_out_date"]})

    assert has_element?(view, "#booking_check_out_date[value='#{week}']")

    result =
      view
      |> form("#booking-form",
        booking: %{
          check_in_date: to_string(week),
          check_out_date: to_string(week),
          meal_plan: "full_board",
          meal_adults: "0",
          meal_children: "5",
          first_meal: "lunch",
          last_meal: "lunch"
        }
      )
      |> render_submit()

    {:ok, detail, _} = follow_redirect(result, conn)
    assert has_element?(detail, "#booking-meal-plan", "Plná penze")
    assert has_element?(detail, "#booking-portions-#{week}-lunch", "5 porcí")
    assert has_element?(detail, "#booking-portions-#{week}-dinner", "0 porcí")
  end

  test "unknown and explicitly uncatered bookings are distinct in details", %{
    conn: conn,
    week: week
  } do
    booking = stay(week, %{meal_plan: nil})
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}")
    assert has_element?(view, "#booking-meals-incomplete")
    {:ok, _} = Bookings.update_booking(booking, %{meal_plan: "none"})
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}")
    assert has_element?(view, "#booking-meal-plan", "Bez stravy")
    refute has_element?(view, "#booking-meals-incomplete")
  end

  test "planner shows per-meal departure counts on desktop, mobile and in the editor", %{
    conn: conn,
    week: week
  } do
    stay(week)

    stay(week, %{
      meal_plan: "half_board",
      meal_adults: 2,
      meal_children: 0,
      check_out_date: Date.add(week, 2)
    })

    unknown = stay(week, %{meal_plan: nil})
    stay(week, %{meal_plan: "none"})
    stay(week, %{status: "cancelled"})
    {:ok, view, _} = live(conn, "/admin/meal-planner")
    assert has_element?(view, "#portions-#{week}-breakfast", "17 porcí")
    assert has_element?(view, "#portions-#{week}-breakfast", "12 dospělí · 5 děti")
    assert has_element?(view, "#portions-#{week}-lunch", "0 porcí")
    assert has_element?(view, "#portions-#{week}-dinner", "2 porcí")
    assert has_element?(view, "#mobile-portions-#{week}-breakfast", "17 porcí")
    assert has_element?(view, "#incomplete-catering-#{unknown.id}")
    assert has_element?(view, "#portions-#{week}-breakfast", "Neúplný součet")
    refute has_element?(view, "#portions-#{Date.add(week, 1)}-breakfast", "Neúplný součet")

    view |> element("td[phx-value-date='#{week}'][phx-value-type='breakfast']") |> render_click()
    assert has_element?(view, "#edit-meal-portions", "17 porcí")
    assert has_element?(view, "#edit-meal-portions", "Neúplný součet")
  end

  test "print includes portions even without menu text and preserves historical completed bookings",
       %{conn: conn} do
    week = ~D[2027-01-10]
    stay(week, %{status: "completed"})
    unknown = stay(week, %{meal_plan: nil})
    {:ok, view, _} = live(conn, "/admin/meal-planner/print?week=#{week}")
    assert has_element?(view, "#print-portions-#{week}-breakfast", "15 porcí")
    assert has_element?(view, "#print-portions-#{week}-breakfast", "10 dospělí · 5 děti")
    assert has_element?(view, "#print-portions-#{week}-lunch", "0 porcí")
    assert has_element?(view, "#incomplete-catering-#{unknown.id}")
  end
end

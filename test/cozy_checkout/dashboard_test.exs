defmodule CozyCheckout.DashboardTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.MenuFixtures
  alias CozyCheckout.{Bookings, Dashboard, Meals}

  test "month horizon clamps month ends and crosses years" do
    assert Dashboard.month_ahead(~D[2027-01-31]) == ~D[2027-02-28]
    assert Dashboard.month_ahead(~D[2028-01-31]) == ~D[2028-02-29]
    assert Dashboard.month_ahead(~D[2027-12-22]) == ~D[2028-01-22]
  end

  test "includes current stays and the inclusive month boundary, excluding inactive and deleted bookings" do
    today = ~D[2027-01-15]

    current =
      menu_booking_fixture(%{check_in_date: ~D[2027-01-10], check_out_date: ~D[2027-01-20]})

    leaving = menu_booking_fixture(%{check_in_date: ~D[2027-01-11], check_out_date: today})
    arriving = menu_booking_fixture(%{check_in_date: today, check_out_date: ~D[2027-01-22]})

    boundary =
      menu_booking_fixture(%{check_in_date: ~D[2027-02-15], check_out_date: ~D[2027-02-20]})

    menu_booking_fixture(%{check_in_date: ~D[2027-02-16], check_out_date: ~D[2027-02-20]})
    menu_booking_fixture(%{check_in_date: ~D[2027-01-10], check_out_date: ~D[2027-01-14]})

    menu_booking_fixture(%{
      status: "cancelled",
      check_in_date: today,
      check_out_date: ~D[2027-01-20]
    })

    menu_booking_fixture(%{
      status: "completed",
      check_in_date: today,
      check_out_date: ~D[2027-01-20]
    })

    deleted = menu_booking_fixture(%{check_in_date: today, check_out_date: ~D[2027-01-20]})
    Bookings.delete_booking(deleted)

    {:ok, invoice} = Bookings.create_default_invoice(current)
    {:ok, invoice} = Bookings.recalculate_invoice_totals(invoice)
    {:ok, _} = Bookings.transition_to_personal(invoice)
    {:ok, _} = Bookings.create_default_invoice(leaving)
    {:ok, _} = Bookings.create_default_invoice(arriving)

    {:ok, _} =
      Bookings.create_invoice_item(invoice.id, %{
        "name" => "Parkování",
        "quantity" => 99,
        "nights" => 1,
        "price_per_night" => "0",
        "vat_rate" => "0",
        "item_type" => "extra"
      })

    overview = Dashboard.overview(today)

    assert Enum.map(overview.bookings, & &1.id) == [
             current.id,
             leaving.id,
             arriving.id,
             boundary.id
           ]

    assert overview.last_date == ~D[2027-02-15]
    assert overview.arrivals == 1
    assert overview.departures == 1
    assert Enum.all?(overview.bookings, &Ecto.assoc_loaded?(&1.rooms))
    assert overview.occupancy == Bookings.get_occupancy_for_range(today, today)[today]
    assert overview.occupancy == 4
    assert overview.portions == Meals.get_portion_counts_for_range(today, today)[today]
    # Departure breakfast counts even though the departing group no longer occupies beds.
    assert overview.portions["breakfast"].total == 30
    assert overview.portions["dinner"].total == 45
  end

  test "attention includes missing catering and missing or stale menus, only for the displayed stays" do
    today = ~D[2027-01-08]
    unknown = menu_booking_fixture(%{meal_plan: nil})
    missing_menu = menu_booking_fixture()
    stale = menu_booking_fixture()
    variant = variant_fixture()
    assign_variant(stale, variant)
    {:ok, _} = Bookings.update_booking(stale, %{check_out_date: ~D[2027-01-11]})
    ready = menu_booking_fixture()
    assign_variant(ready, variant)
    uncatered = menu_booking_fixture(%{meal_plan: "none"})
    completed = menu_booking_fixture(%{status: "completed"})

    overview = Dashboard.overview(today)
    assert Enum.any?(overview.issues, &(&1.booking.id == unknown.id and &1.kind == :details))
    assert Enum.any?(overview.issues, &(&1.booking.id == missing_menu.id and &1.kind == :menu))
    assert Enum.any?(overview.issues, &(&1.booking.id == stale.id and &1.kind == :menu))
    refute Enum.any?(overview.issues, &(&1.booking.id in [ready.id, uncatered.id, completed.id]))
    assert Enum.count(overview.issues, &(&1.booking.id == unknown.id)) == 1
  end
end

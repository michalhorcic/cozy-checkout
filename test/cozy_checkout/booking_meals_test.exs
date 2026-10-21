defmodule CozyCheckout.BookingMealsTest do
  use CozyCheckout.DataCase, async: true

  alias CozyCheckout.Bookings
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Guests
  alias CozyCheckout.Meals

  setup do
    {:ok, guest} = Guests.create_guest(%{name: "Catering guest"})
    {:ok, guest: guest}
  end

  defp attrs(guest, overrides \\ %{}) do
    Map.merge(
      %{
        guest_id: guest.id,
        check_in_date: ~D[2027-01-08],
        check_out_date: ~D[2027-01-10],
        meal_plan: "full_board",
        meal_adults: 10,
        meal_children: 5,
        first_meal: "dinner",
        last_meal: "breakfast"
      },
      overrides
    )
  end

  test "legacy and imported bookings remain unspecified, distinct from no catering", %{
    guest: guest
  } do
    assert {:ok, unknown} =
             Bookings.create_booking(%{guest_id: guest.id, check_in_date: ~D[2027-01-08]})

    assert unknown.meal_plan == nil
    assert unknown.meal_adults == nil
    assert {:ok, none} = Bookings.update_booking(unknown, %{meal_plan: "none"})
    assert none.meal_plan == "none"
    refute Booking.meal_details_complete?(none)
  end

  test "persists counts without an invoice or individual guest records", %{guest: guest} do
    assert {:ok, booking} = Bookings.create_booking(attrs(guest))
    reloaded = Bookings.get_booking!(booking.id)
    assert reloaded.meal_adults == 10
    assert reloaded.meal_children == 5
    assert Booking.meal_details_complete?(reloaded)
    assert Bookings.get_invoice_by_booking_id(booking.id) == nil
  end

  test "catered bookings require departure, counts including explicit zeros, and both boundaries",
       %{guest: guest} do
    for field <- [:check_out_date, :meal_adults, :meal_children, :first_meal, :last_meal] do
      changeset = Booking.changeset(%Booking{}, attrs(guest, %{field => nil}))
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset)[field]
    end

    assert {:ok, booking} =
             Bookings.create_booking(attrs(guest, %{meal_adults: 0, meal_children: 5}))

    assert booking.meal_adults == 0
  end

  test "rejects negative, fractional and unknown catering values", %{guest: guest} do
    for overrides <- [
          %{meal_adults: -1},
          %{meal_children: -1},
          %{meal_children: "1.5"},
          %{meal_plan: "breakfast_only"},
          %{first_meal: "snack"},
          %{last_meal: "snack"}
        ] do
      refute Booking.changeset(%Booking{}, attrs(guest, overrides)).valid?
    end
  end

  test "half board cannot start or end with lunch", %{guest: guest} do
    for field <- [:first_meal, :last_meal] do
      changeset =
        Booking.changeset(
          %Booking{},
          attrs(guest, %{field => "lunch", :meal_plan => "half_board"})
        )

      assert "Polopenze nezahrnuje oběd" in errors_on(changeset)[field]
    end
  end

  test "same-day meals must be ordered and identical first/last meal is allowed", %{guest: guest} do
    same_day = attrs(guest, %{check_out_date: ~D[2027-01-08]})
    refute Booking.changeset(%Booking{}, same_day).valid?

    assert Booking.changeset(
             %Booking{},
             Map.merge(same_day, %{first_meal: "lunch", last_meal: "lunch"})
           ).valid?

    refute Booking.changeset(%Booking{}, attrs(guest, %{check_out_date: ~D[2027-01-07]})).valid?
  end

  test "switching to none or unspecified clears the old catering instructions", %{guest: guest} do
    {:ok, booking} = Bookings.create_booking(attrs(guest))

    for plan <- ["none", nil] do
      assert {:ok, updated} = Bookings.update_booking(booking, %{meal_plan: plan})
      assert updated.meal_adults == nil
      assert updated.meal_children == nil
      assert updated.first_meal == nil
      assert updated.last_meal == nil
    end
  end

  test "date edits recalculate portions without stored daily rows or invoice changes", %{
    guest: guest
  } do
    {:ok, booking} = Bookings.create_booking(attrs(guest))
    {:ok, invoice} = Bookings.create_default_invoice(booking)

    assert Meals.get_portion_counts_for_range(~D[2027-01-10], ~D[2027-01-10])[~D[2027-01-10]][
             "lunch"
           ].total == 0

    {:ok, _} = Bookings.update_booking(booking, %{check_out_date: ~D[2027-01-11]})

    assert Meals.get_portion_counts_for_range(~D[2027-01-10], ~D[2027-01-10])[~D[2027-01-10]][
             "lunch"
           ].total == 15

    assert Bookings.get_booking_invoice!(invoice.id).items == invoice.items
  end

  test "range query includes departure on its first day and completed history", %{guest: guest} do
    {:ok, booking} =
      Bookings.create_booking(
        attrs(guest, %{status: "completed", dietary_restrictions: "Bez lepku"})
      )

    day = Meals.get_portion_counts_for_range(~D[2027-01-10], ~D[2027-01-10])[~D[2027-01-10]]
    assert day["breakfast"] == %{adults: 10, children: 5, total: 15}
    assert day.incomplete_bookings == []

    assert [%{booking_id: id, dietary_restrictions: "Bez lepku"}] =
             Meals.get_dietary_restrictions_for_week(~D[2027-01-10])

    assert id == booking.id
    {:ok, _} = Bookings.delete_booking(booking)

    assert Meals.get_portion_counts_for_range(~D[2027-01-10], ~D[2027-01-10])[~D[2027-01-10]][
             "breakfast"
           ].total == 0
  end

  test "query exposes missing instructions but excludes uncatered, cancelled, deleted and outside stays",
       %{guest: guest} do
    {:ok, unknown} = Bookings.create_booking(%{guest_id: guest.id, check_in_date: ~D[2027-01-01]})

    for {offset, overrides} <- [
          {0, %{meal_plan: "none"}},
          {1, %{status: "cancelled"}},
          {2, %{}},
          {3, %{}}
        ] do
      {:ok, other_guest} = Guests.create_guest(%{name: "Other #{offset}"})
      {:ok, booking} = Bookings.create_booking(attrs(other_guest, overrides))
      if offset == 2, do: Bookings.delete_booking(booking)

      if offset == 3,
        do:
          Bookings.update_booking(booking, %{
            check_in_date: ~D[2027-02-01],
            check_out_date: ~D[2027-02-03]
          })
    end

    day = Meals.get_portion_counts_for_range(~D[2027-01-09], ~D[2027-01-09])[~D[2027-01-09]]
    assert day["breakfast"].total == 0
    assert Enum.map(day.incomplete_bookings, & &1.id) == [unknown.id]
    assert hd(day.incomplete_bookings).guest.name == "Catering guest"
  end
end

defmodule CozyCheckout.MenuFixtures do
  alias CozyCheckout.{Bookings, Guests}
  alias CozyCheckout.Meals.{MenuPlanning, SlotSchedule}

  def variant_attrs(overrides \\ %{}) do
    settings =
      Map.merge(
        %{
          name: "Varianta #{System.unique_integer([:positive])}",
          days: 3,
          meal_plan: "full_board",
          first_meal: "dinner",
          last_meal: "breakfast"
        },
        overrides
      )

    items =
      Enum.map(
        SlotSchedule.slots(
          settings.days,
          settings.meal_plan,
          settings.first_meal,
          settings.last_meal
        ),
        fn {day, type} ->
          %{
            day_number: day,
            meal_type: type,
            menu_text: "#{settings.name} – den #{day} #{type}",
            supplements: if(type == "lunch", do: "Zeleninová polévka", else: nil)
          }
        end
      )

    Map.put_new(settings, :items, items)
  end

  def variant_fixture(overrides \\ %{}) do
    {:ok, variant} = MenuPlanning.create_variant(variant_attrs(overrides))
    variant
  end

  def menu_booking_fixture(overrides \\ %{}) do
    {:ok, guest} = Guests.create_guest(%{name: "Skupina #{System.unique_integer([:positive])}"})

    {:ok, booking} =
      Bookings.create_booking(
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
      )

    booking
  end

  def assign_variant(booking, variant) do
    {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
    {:ok, menu} = MenuPlanning.apply_variant(booking.id, variant.id, preview.token)
    menu
  end
end

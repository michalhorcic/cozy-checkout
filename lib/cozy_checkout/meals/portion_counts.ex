defmodule CozyCheckout.Meals.PortionCounts do
  @moduledoc """
  Actual portions, independent of invoices, menu text and ingredient coefficients.
  Arrival/departure meals are inclusive. Missing instructions remain visible.
  """
  alias CozyCheckout.Bookings.Booking

  @meal_types ["breakfast", "lunch", "dinner"]
  @zero %{adults: 0, children: 0, total: 0}

  def for_range(bookings, start_date, end_date) do
    bookings = Enum.reject(bookings, &(&1.status == "cancelled" or not is_nil(&1.deleted_at)))
    {complete, other} = Enum.split_with(bookings, &Booking.meal_details_complete?/1)
    incomplete = Enum.reject(other, &(&1.meal_plan == "none"))

    Map.new(Date.range(start_date, end_date), fn date ->
      counts =
        Map.new(@meal_types, fn meal_type ->
          portions =
            complete
            |> Enum.filter(&serves?(&1, date, meal_type))
            |> Enum.reduce(@zero, fn booking, acc ->
              %{
                adults: acc.adults + booking.meal_adults,
                children: acc.children + booking.meal_children,
                total: acc.total + booking.meal_adults + booking.meal_children
              }
            end)

          {meal_type, portions}
        end)

      {date, Map.put(counts, :incomplete_bookings, Enum.filter(incomplete, &overlaps?(&1, date)))}
    end)
  end

  defp serves?(booking, date, meal_type) do
    overlaps?(booking, date) and
      (booking.meal_plan == "full_board" or meal_type != "lunch") and
      (date != booking.check_in_date or rank(meal_type) >= rank(booking.first_meal)) and
      (date != booking.check_out_date or rank(meal_type) <= rank(booking.last_meal))
  end

  defp overlaps?(booking, date) do
    Date.compare(booking.check_in_date, date) != :gt and
      (is_nil(booking.check_out_date) or Date.compare(booking.check_out_date, date) != :lt)
  end

  defp rank("breakfast"), do: 0
  defp rank("lunch"), do: 1
  defp rank("dinner"), do: 2
end

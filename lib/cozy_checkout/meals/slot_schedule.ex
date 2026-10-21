defmodule CozyCheckout.Meals.SlotSchedule do
  @moduledoc "Inclusive service slots; supplements belong to a slot and never add a serving."
  @types ["breakfast", "lunch", "dinner"]

  def slots(days, plan, first, last)
      when is_integer(days) and days > 0 and days <= 366 and
             plan in ["half_board", "full_board"] and first in @types and last in @types do
    for day <- 1..days,
        type <- @types,
        plan == "full_board" or type != "lunch",
        day != 1 or rank(type) >= rank(first),
        day != days or rank(type) <= rank(last),
        do: {day, type}
  end

  def slots(_, _, _, _), do: []

  def rank("breakfast"), do: 0
  def rank("lunch"), do: 1
  def rank("dinner"), do: 2
end

defmodule CozyCheckout.Recipes.Consumption do
  @moduledoc "Unrounded ingredient consumption; no packaging, reserves or stock movements."
  alias CozyCheckout.Recipes
  alias CozyCheckout.Recipes.Links
  alias CozyCheckout.Meals.{MenuPlanning, PortionCounts}

  def calculate(recipes, adults, children, factor)
      when is_integer(adults) and adults >= 0 and is_integer(children) and children >= 0 do
    factor = Decimal.new(to_string(factor))

    if Decimal.compare(factor, 0) == :lt or Decimal.compare(factor, 1) == :gt,
      do: raise(ArgumentError, "Invalid child factor")

    effective = Decimal.add(adults, Decimal.mult(children, factor))

    {quantities, issues} =
      Enum.reduce(recipes, {%{}, []}, fn recipe, {totals, issues} ->
        Enum.reduce(recipe.lines, {totals, issues}, fn line, {acc, warnings} ->
          case Recipes.to_base(line.quantity, line.unit, line.ingredient.base_unit) do
            {:ok, quantity} ->
              amount = quantity |> Decimal.mult(effective) |> Decimal.div(recipe.base_servings)

              row = %{
                id: line.ingredient.id,
                ingredient: line.ingredient,
                quantity: amount,
                unit: line.ingredient.base_unit
              }

              {Map.update(acc, line.ingredient.id, row, fn old ->
                 %{old | quantity: Decimal.add(old.quantity, amount)}
               end), warnings}

            {:error, _} ->
              {acc, ["Neslučitelné jednotky u suroviny #{line.ingredient.name}" | warnings]}
          end
        end)
      end)

    %{
      actual: adults + children,
      adults: adults,
      children: children,
      effective: effective,
      factor: factor,
      quantities:
        quantities |> Map.values() |> Enum.sort_by(&Recipes.normalize(&1.ingredient.name)),
      issues: Enum.uniq(issues)
    }
  end

  def for_booking_item(id) do
    item = Links.load!("booking", id)
    booking = item.booking_menu.booking

    cond do
      MenuPlanning.stale?(item.booking_menu, booking) ->
        {:error, :stale_menu}

      not CozyCheckout.Bookings.Booking.meal_details_complete?(booking) ->
        {:error, :incomplete_booking}

      booking.status == "cancelled" ->
        {:error, :cancelled_booking}

      true ->
        settings = Recipes.settings()

        factor =
          if item.meal_type == "breakfast",
            do: settings.breakfast_child_factor,
            else: settings.hot_child_factor

        counts =
          PortionCounts.for_range([booking], item.date, item.date)[item.date][item.meal_type]

        ids = Enum.reject([item.recipe_id | Links.supplement_ids(item)], &is_nil/1)
        recipes = Recipes.get_recipes(ids)
        result = calculate(recipes, counts.adults, counts.children, factor)
        issues = result.issues ++ CozyCheckout.Meals.MenuRecipes.issues(item)

        {:ok, Map.merge(result, %{item: item, recipes: recipes, issues: issues})}
    end
  end
end

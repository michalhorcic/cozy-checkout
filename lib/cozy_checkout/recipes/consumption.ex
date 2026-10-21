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
        recipes = Enum.map(ids, &Recipes.get_recipe!/1)
        result = calculate(recipes, counts.adults, counts.children, factor)
        selected_names = Enum.map(recipes, & &1.name)

        missing =
          String.split(item.supplements || "", "\n", trim: true)
          |> Enum.map(&Links.label_name/1)
          |> Enum.reject(&(&1 in selected_names))

        issues =
          result.issues ++
            if(is_nil(item.recipe_id),
              do: ["Chybí recept k hlavnímu jídlu nebo bufetu"],
              else: []
            ) ++ Enum.map(missing, &("Doplněk bez receptu: " <> &1))

        {:ok, Map.merge(result, %{item: item, recipes: recipes, issues: issues})}
    end
  end
end

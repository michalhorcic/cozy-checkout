defmodule CozyCheckout.KitchenCosts.Reports do
  @moduledoc "Ingredient-cost reports using the same actual services as the kitchen shopping list."
  import Ecto.Query
  alias CozyCheckout.{KitchenCosts, Recipes, Repo}
  alias CozyCheckout.Kitchen.ShoppingList
  alias CozyCheckout.KitchenCosts.Report

  def generate(first, last, booking_id \\ nil) do
    with {:ok, result} <- ShoppingList.generate(first, last, booking_id) do
      {meals, _cache} =
        Enum.map_reduce(result.meal_services, %{}, fn service, cache ->
          {recipes, cache} =
            Enum.map_reduce(service.recipes, cache, fn recipe, cache ->
              consumption =
                Recipes.Consumption.calculate(
                  [recipe],
                  service.counts.adults,
                  service.counts.children,
                  service.factor
                )

              {lines, cache} =
                Enum.map_reduce(
                  Enum.reject(consumption.quantities, &Decimal.equal?(&1.quantity, 0)),
                  cache,
                  fn row, cache ->
                    key = {row.id, service.date}

                    price =
                      Map.get_lazy(cache, key, fn ->
                        KitchenCosts.price_for(row.id, service.date)
                      end)

                    cost = if price.unit_price, do: Decimal.mult(row.quantity, price.unit_price)

                    {%{
                       ingredient_id: row.id,
                       ingredient_name: row.ingredient.name,
                       quantity: row.quantity,
                       unit: row.unit,
                       cost: cost,
                       price: price
                     }, Map.put(cache, key, price)}
                  end
                )

              {%{
                 id: recipe.id,
                 name: recipe.name,
                 base_servings: recipe.base_servings,
                 source_lines:
                   Enum.map(recipe.lines, fn line ->
                     %{
                       ingredient_id: line.ingredient_id,
                       ingredient_name: line.ingredient.name,
                       quantity: line.quantity,
                       unit: line.unit,
                       base_unit: line.ingredient.base_unit
                     }
                   end),
                 lines: lines,
                 known_total: Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.cost || 0, &2)),
                 issues: consumption.issues
               }, cache}
            end)

          {%{
             booking_id: service.booking.id,
             booking_name: service.booking.guest.name,
             date: service.date,
             meal_type: service.meal_type,
             item_id: service.item.id,
             adults: service.counts.adults,
             children: service.counts.children,
             portions: service.counts.total,
             factor: service.factor,
             recipes: recipes,
             known_total: Enum.reduce(recipes, Decimal.new(0), &Decimal.add(&1.known_total, &2)),
             issues: service.issues
           }, cache}
        end)

      menu_issues =
        result.issues
        |> Enum.filter(&is_nil(&1.ingredient))
        |> Enum.map(fn issue ->
          %{
            booking_id: issue.booking && issue.booking.id,
            booking_name: issue.booking && issue.booking.guest.name,
            message: issue.message
          }
        end)

      rows = for meal <- meals, recipe <- meal.recipes, line <- recipe.lines, do: line
      total = Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1.cost || 0, &2))
      recipe_issues = for meal <- meals, recipe <- meal.recipes, issue <- recipe.issues, do: issue
      warnings = Enum.uniq(Enum.flat_map(rows, & &1.price.warnings) ++ recipe_issues)

      complete =
        menu_issues == [] and recipe_issues == [] and Enum.all?(rows, &(not is_nil(&1.cost)))

      calculated_at = DateTime.truncate(DateTime.utc_now(), :second)

      snapshot = %{
        schema_version: 1,
        start_date: first,
        end_date: last,
        booking_id: blank_id(booking_id),
        calculated_at: calculated_at,
        known_total: total,
        complete: complete,
        portions: result.portions,
        services: result.services,
        groups: result.groups,
        average_per_portion: if(result.portions > 0, do: Decimal.div(total, result.portions)),
        meals: meals,
        booking_totals:
          Enum.map(result.booking_summaries, fn booking ->
            known_total =
              meals
              |> Enum.filter(&(&1.booking_id == booking.booking_id))
              |> Enum.reduce(Decimal.new(0), &Decimal.add(&1.known_total, &2))

            Map.merge(booking, %{
              known_total: known_total,
              average_per_portion:
                if(booking.portions > 0, do: Decimal.div(known_total, booking.portions))
            })
          end),
        issues: menu_issues,
        warnings: warnings,
        historical_recipe_notice:
          "Výpočet používá receptury dostupné v okamžiku přepočtu. Jde o kalkulované náklady na suroviny včetně DPH, bez práce, energií, odpadu a skladového výdeje."
      }

      {:ok, snapshot |> Jason.encode!() |> Jason.decode!()}
    end
  end

  @doc "Stores the reviewed server-side result unchanged. No update or delete API is exposed."
  def save(%{"schema_version" => 1} = snapshot) do
    %Report{}
    |> Ecto.Changeset.change(%{
      start_date: Date.from_iso8601!(snapshot["start_date"]),
      end_date: Date.from_iso8601!(snapshot["end_date"]),
      booking_id: snapshot["booking_id"],
      calculated_at: DateTime.from_iso8601(snapshot["calculated_at"]) |> elem(1),
      snapshot: snapshot
    })
    |> Ecto.Changeset.foreign_key_constraint(:booking_id)
    |> Repo.insert()
  end

  def list,
    do: Repo.all(from r in Report, order_by: [desc: r.inserted_at, desc: r.id], limit: 100)

  def get!(id), do: Repo.get!(Report, id)
  defp blank_id(id) when id in [nil, ""], do: nil
  defp blank_id(id), do: id
end

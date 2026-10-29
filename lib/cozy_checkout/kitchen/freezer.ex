defmodule CozyCheckout.Kitchen.Freezer do
  @moduledoc "Manual freezer inventory; never changes consumption or shopping quantities."
  import Ecto.Query
  import Ecto.Changeset
  alias CozyCheckout.{Repo, Recipes}
  alias CozyCheckout.Kitchen.FreezerItem
  alias CozyCheckout.Recipes.{Ingredient, Recipe, RecipeLine}
  alias CozyCheckout.Meals.BookingMenuItem

  def today, do: Date.utc_today()

  def list_items(search \\ "", archived \\ false) do
    Repo.all(
      from i in FreezerItem,
        where: ^archived == not is_nil(i.archived_at),
        order_by: [asc: i.frozen_on, asc: i.inserted_at, asc: i.id],
        preload: [:ingredient, :recipe]
    )
    |> Enum.filter(&String.contains?(Recipes.normalize(&1.name), Recipes.normalize(search)))
  end

  def create_item(attrs) do
    transaction(fn -> %FreezerItem{} |> validated(attrs) |> Repo.insert() end)
  end

  def update_item(item, attrs), do: transaction(fn -> persist(item, validated(item, attrs)) end)

  defp transaction(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, saved} -> saved
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def archive_item(item), do: persist(item, change(item, archived_at: now()))

  def remove(item, amount) do
    parsed = if amount == :all, do: {:ok, item.quantity}, else: Ecto.Type.cast(:decimal, amount)

    case parsed do
      {:ok, quantity} when not is_nil(quantity) ->
        if Decimal.compare(quantity, 0) == :gt && Decimal.compare(quantity, item.quantity) != :gt &&
             is_nil(item.archived_at) do
          remaining = Decimal.sub(item.quantity, quantity)
          cs = change(item, quantity: remaining)
          cs = if Decimal.equal?(remaining, 0), do: change(cs, archived_at: now()), else: cs
          persist(item, cs)
        else
          {:error, :invalid_amount}
        end

      _ ->
        {:error, :invalid_amount}
    end
  end

  defp persist(item, cs) do
    if item.archived_at do
      {:error, :archived}
    else
      cs |> optimistic_lock(:lock_version) |> Repo.update()
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  defp validated(item, attrs) do
    cs = FreezerItem.changeset(item, attrs)

    Enum.reduce([{:ingredient_id, Ingredient}, {:recipe_id, Recipe}], cs, fn {field, schema},
                                                                             cs ->
      id = get_field(cs, field)

      linked =
        if id && not Keyword.has_key?(cs.errors, field),
          do: Repo.one(from linked in schema, where: linked.id == ^id, lock: "FOR SHARE")

      cond do
        is_nil(id) ->
          cs

        is_nil(linked) ->
          add_error(cs, field, "Vyberte existující položku")

        linked.archived_at && (is_nil(item.id) || Map.get(item, field) != id) ->
          add_error(cs, field, "Položka je archivovaná")

        field == :ingredient_id && not Recipes.compatible?(get_field(cs, :unit), linked.base_unit) ->
          add_error(cs, :unit, "Jednotka neodpovídá surovině (#{linked.base_unit})")

        true ->
          cs
      end
    end)
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  # Fixed query count for a complete screen, including supplements and their ingredients.
  def presentation(items) do
    ids = items |> Enum.filter(&(Date.compare(&1.date, today()) != :lt)) |> Enum.map(& &1.id)

    linked =
      Repo.all(
        from i in BookingMenuItem,
          where: i.id in ^ids,
          preload: [:recipe, recipe_supplements: :recipe]
      )

    recipes_by_item =
      Map.new(linked, fn i ->
        recipes = [i.recipe | Enum.map(i.recipe_supplements, & &1.recipe)]
        {i.id, recipes |> Enum.reject(&is_nil/1) |> Enum.map(& &1.id) |> Enum.uniq()}
      end)

    recipe_ids = recipes_by_item |> Map.values() |> List.flatten() |> Enum.uniq()

    lines =
      Repo.all(
        from l in RecipeLine,
          where: l.recipe_id in ^recipe_ids,
          select: {l.recipe_id, l.ingredient_id}
      )

    stocks = list_items()

    matches =
      Map.new(recipes_by_item, fn {id, recipes} ->
        ingredients = for {recipe, ingredient} <- lines, recipe in recipes, do: ingredient

        {id,
         Enum.filter(
           stocks,
           &((&1.recipe_id && &1.recipe_id in recipes) ||
               (&1.ingredient_id && &1.ingredient_id in ingredients))
         )}
      end)

    %{
      by_item: matches,
      by_ingredient: Enum.group_by(Enum.filter(stocks, & &1.ingredient_id), & &1.ingredient_id),
      prepared: Enum.filter(stocks, &(&1.recipe_id in recipe_ids)),
      unlinked:
        stocks |> Enum.filter(&(is_nil(&1.recipe_id) && is_nil(&1.ingredient_id))) |> Enum.take(5)
    }
  end
end

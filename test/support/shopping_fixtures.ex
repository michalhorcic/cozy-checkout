defmodule CozyCheckout.ShoppingFixtures do
  import CozyCheckout.MenuFixtures
  import CozyCheckout.RecipeFixtures

  def shopping_recipe(attrs \\ %{}) do
    ingredient = ingredient_fixture(%{purchase_mode: "Sezona", package_size: "1"})
    {ingredient, recipe_fixture(ingredient, attrs)}
  end

  def shopping_variant(recipe, overrides \\ %{}, extra \\ nil) do
    attrs = variant_attrs(overrides)

    items =
      Enum.map(
        attrs.items,
        &Map.merge(&1, %{menu_text: recipe.name, supplements: extra && extra.name})
      )

    {:ok, variant} = CozyCheckout.Meals.MenuPlanning.create_variant(%{attrs | items: items})
    variant
  end

  def shopping_booking(recipe, overrides \\ %{}) do
    booking = menu_booking_fixture(overrides)
    days = Date.diff(booking.check_out_date, booking.check_in_date) + 1

    variant =
      shopping_variant(recipe, %{
        days: days,
        first_meal: booking.first_meal,
        last_meal: booking.last_meal,
        meal_plan: booking.meal_plan
      })

    menu = assign_variant(booking, variant)
    {CozyCheckout.Repo.preload(booking, :guest), menu}
  end
end

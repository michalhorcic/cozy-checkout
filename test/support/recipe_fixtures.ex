defmodule CozyCheckout.RecipeFixtures do
  alias CozyCheckout.Recipes

  def ingredient_fixture(attrs \\ %{}) do
    {:ok, ingredient} =
      Recipes.create_ingredient(
        Map.merge(
          %{
            name: "Surovina #{System.unique_integer([:positive])}",
            category: "Test",
            base_unit: "kg"
          },
          attrs
        )
      )

    ingredient
  end

  def recipe_fixture(ingredient \\ ingredient_fixture(), attrs \\ %{}) do
    {:ok, recipe} =
      Recipes.create_recipe(
        Map.merge(
          %{
            name: "Recept #{System.unique_integer([:positive])}",
            base_servings: "10",
            lines: [%{ingredient_id: ingredient.id, quantity: "2", unit: ingredient.base_unit}]
          },
          attrs
        )
      )

    recipe
  end
end

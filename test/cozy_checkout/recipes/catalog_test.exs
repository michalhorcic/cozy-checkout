defmodule CozyCheckout.Recipes.CatalogTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.RecipeFixtures
  alias CozyCheckout.Recipes
  alias CozyCheckout.Recipes.{Recipe, RecipeLine, Ingredient}

  test "ingredient autocomplete matches all words across name, category and notes without accents" do
    breakfast =
      ingredient_fixture(%{name: "Čerstvé mléko", category: "Snídaně", notes: "Bez laktózy"})

    other = ingredient_fixture(%{name: "Jiné mléko", category: "Snídaně"})

    assert Recipes.search_ingredients([breakfast, other], "LAKTOZY snidane cerstve") == [
             breakfast
           ]

    assert Recipes.search_ingredients([breakfast, other], "  mleko  ") == [breakfast, other]
    assert Recipes.search_ingredients([breakfast, other], "neexistuje") == []
  end

  test "migration imports every audited recipe, ingredient and source quantity" do
    snapshot =
      Application.app_dir(:cozy_checkout, "priv/recipes/drive_reference.json")
      |> File.read!()
      |> Jason.decode!()

    assert Repo.aggregate(from(r in Recipe, where: like(r.source_key, "drive:%")), :count) == 56
    assert Repo.aggregate(from(i in Ingredient, where: not is_nil(i.source_key)), :count) == 172
    assert Repo.aggregate(from(l in RecipeLine, where: not is_nil(l.source_row)), :count) == 600

    for source <- snapshot["ingredients"] do
      item = Repo.get_by!(Ingredient, name: source["name"])
      assert item.category == source["category"]
      assert item.base_unit == source["base_unit"]
      assert item.notes == source["notes"]
      assert item.purchase_mode == source["purchase_mode"]

      if source["package_size"],
        do: assert(Decimal.equal?(item.package_size, source["package_size"]))
    end

    for source <- snapshot["recipes"] do
      recipe = Repo.get_by!(Recipe, name: source["name"]) |> then(&Recipes.get_recipe!(&1.id))
      assert Decimal.equal?(recipe.base_servings, source["base_servings"])
      assert recipe.source_reference == source["source_reference"]
      assert recipe.notes == source["notes"]
      assert length(recipe.lines) == length(source["lines"])

      for {line, expected} <- Enum.zip(recipe.lines, source["lines"]) do
        assert line.ingredient.name == expected["ingredient_name"]
        assert Decimal.equal?(line.quantity, expected["quantity"])
        assert line.unit == expected["unit"]
        assert line.notes == expected["notes"]
        assert line.source_row == expected["source_row"]
      end
    end

    assert Decimal.equal?(Recipes.settings().hot_child_factor, "0.7")
    assert Decimal.equal?(Recipes.settings().breakfast_child_factor, "0.7")
  end

  test "recipe CRUD preserves notes, order and decimal values" do
    a = ingredient_fixture()
    b = ingredient_fixture(%{base_unit: "l"})
    recipe = recipe_fixture(a)
    [line] = recipe.lines

    assert {:ok, updated} =
             Recipes.update_recipe(recipe, %{
               name: "Nová receptura",
               source_reference: "https://example.com/recept",
               lines: [
                 %{ingredient_id: b.id, quantity: "125.5", unit: "ml", notes: "Pracovní odhad"},
                 %{id: line.id, ingredient_id: a.id, quantity: "500", unit: "g"}
               ]
             })

    assert Enum.map(updated.lines, & &1.unit) == ["ml", "g"]
    assert hd(updated.lines).notes == "Pracovní odhad"
    assert {:error, :stale} = Recipes.update_recipe(recipe, %{name: "Starý editor"})
    assert Recipes.get_recipe!(recipe.id).name == "Nová receptura"
  end

  test "invalid quantities, empty recipe, incompatible units are rejected" do
    ingredient = ingredient_fixture()

    for attrs <- [
          %{base_servings: "0"},
          %{lines: []},
          %{lines: [%{ingredient_id: ingredient.id, quantity: "-1", unit: "kg"}]},
          %{lines: [%{ingredient_id: ingredient.id, quantity: "1", unit: "l"}]},
          %{lines: [%{ingredient_id: Ecto.UUID.generate(), quantity: "1", unit: "kg"}]}
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Recipes.create_recipe(
                 Map.merge(
                   %{
                     name: "Invalid #{System.unique_integer([:positive])}",
                     base_servings: "4",
                     lines: [%{ingredient_id: ingredient.id, quantity: "1", unit: "kg"}]
                   },
                   attrs
                 )
               )
    end
  end

  test "unit change of a used ingredient is blocked; stale edits cannot overwrite" do
    ingredient = ingredient_fixture()
    recipe_fixture(ingredient)
    assert {:error, cs} = Recipes.update_ingredient(ingredient, %{base_unit: "l"})
    assert errors_on(cs).base_unit != []
    assert {:ok, _} = Recipes.update_ingredient(ingredient, %{notes: "První editor"})
    assert {:error, :stale} = Recipes.update_ingredient(ingredient, %{notes: "Druhý editor"})
    assert Recipes.get_ingredient!(ingredient.id).notes == "První editor"
  end

  test "catalogue searches ignore accents and settings validate and detect stale edits" do
    ingredient = ingredient_fixture(%{name: "Žlutá čočka", category: "Luštěniny"})
    recipe = recipe_fixture(ingredient, %{name: "Čočková polévka test hledání"})
    assert [^recipe] = Recipes.list_recipes("cockova polevka test hledani")
    assert [^ingredient] = Recipes.list_ingredients("zluta cocka")
    settings = Recipes.settings()
    assert {:error, _} = Recipes.update_settings(settings, %{hot_child_factor: "1.1"})

    assert {:ok, saved} =
             Recipes.update_settings(settings, %{
               hot_child_factor: "0.5",
               breakfast_child_factor: "0.8"
             })

    assert Decimal.equal?(saved.hot_child_factor, "0.5")
    assert {:error, :stale} = Recipes.update_settings(settings, %{hot_child_factor: "0.6"})
  end

  test "an existing ingredient line can be removed without rebuilding deletion changesets" do
    ingredient = ingredient_fixture()

    recipe =
      recipe_fixture(ingredient, %{
        lines: [
          %{ingredient_id: ingredient.id, quantity: "1", unit: "kg"},
          %{ingredient_id: ingredient.id, quantity: "2", unit: "kg"}
        ]
      })

    [removed, retained] = recipe.lines

    assert {:ok, saved} =
             Recipes.update_recipe(recipe, %{
               lines: [
                 %{id: retained.id, ingredient_id: ingredient.id, quantity: "2", unit: "kg"}
               ]
             })

    assert Enum.map(saved.lines, & &1.id) == [retained.id]
    refute Repo.get(RecipeLine, removed.id)
  end

  test "invalid remaining lines roll back a requested ingredient removal" do
    ingredient = ingredient_fixture()

    recipe =
      recipe_fixture(ingredient, %{
        lines: [
          %{ingredient_id: ingredient.id, quantity: "1", unit: "kg"},
          %{ingredient_id: ingredient.id, quantity: "2", unit: "kg"}
        ]
      })

    [_removed, retained] = recipe.lines

    assert {:error, %Ecto.Changeset{valid?: false} = cs} =
             Recipes.update_recipe(recipe, %{
               lines: [
                 %{id: retained.id, ingredient_id: ingredient.id, quantity: "2", unit: "l"}
               ]
             })

    assert Enum.any?(Ecto.Changeset.get_change(cs, :lines), fn line ->
             Keyword.has_key?(line.errors, :unit)
           end)

    assert Recipes.get_recipe!(recipe.id).lines == recipe.lines
  end

  test "archived ingredients can remain in a recipe but cannot be newly selected" do
    ingredient = ingredient_fixture()
    other = ingredient_fixture()
    recipe = recipe_fixture(ingredient)
    [line] = recipe.lines
    assert {:ok, _} = Recipes.archive_ingredient(ingredient)

    assert {:ok, saved} =
             Recipes.update_recipe(recipe, %{
               lines: [
                 %{id: line.id, ingredient_id: ingredient.id, quantity: "3", unit: "kg"}
               ]
             })

    assert Decimal.equal?(hd(saved.lines).quantity, "3")

    assert {:error, %Ecto.Changeset{valid?: false}} =
             Recipes.create_recipe(%{
               name: "New archived ingredient",
               base_servings: "4",
               lines: [
                 %{ingredient_id: ingredient.id, quantity: "1", unit: "kg"}
               ]
             })

    other_recipe = recipe_fixture(other)
    [other_line] = other_recipe.lines

    assert {:error, %Ecto.Changeset{valid?: false}} =
             Recipes.update_recipe(other_recipe, %{
               lines: [
                 %{id: other_line.id, ingredient_id: ingredient.id, quantity: "1", unit: "kg"}
               ]
             })
  end
end

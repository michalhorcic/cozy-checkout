defmodule CozyCheckout.Kitchen.ShoppingListTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.MenuFixtures
  import CozyCheckout.RecipeFixtures
  import CozyCheckout.ShoppingFixtures
  alias CozyCheckout.{Recipes, Bookings}
  alias CozyCheckout.Kitchen.ShoppingList
  alias CozyCheckout.Recipes.{Links, Recipe}

  test "all groups sum before package rounding and retain a complete provenance trail" do
    {ingredient, recipe} = shopping_recipe()
    {first, _} = shopping_booking(recipe)
    {second, _} = shopping_booking(recipe, %{meal_adults: 2, meal_children: 0})
    assert {:ok, result} = ShoppingList.generate(~D[2027-01-08], ~D[2027-01-10])
    assert result.issues == []
    assert result.groups == 2
    assert result.services == 10
    assert result.covered_services == 10
    assert result.portions == 85
    assert [%{id: id, quantity: quantity, buy_quantity: buy, sources: sources}] = result.rows
    assert id == ingredient.id
    assert Decimal.equal?(quantity, "15.5")
    assert Decimal.equal?(buy, "16")
    assert length(sources) == 10

    assert Enum.sort(Enum.uniq(Enum.map(sources, & &1.booking.id))) ==
             Enum.sort([first.id, second.id])

    assert Decimal.equal?(
             Enum.reduce(sources, Decimal.new(0), &Decimal.add(&1.quantity, &2)),
             quantity
           )
  end

  test "rounding each group separately would overbuy; only the shared aggregate is rounded" do
    {_, recipe} = shopping_recipe()
    # One meal per group: a shared total of 0.8 kg requires one package, not two.
    for _ <- 1..2,
        do:
          shopping_booking(recipe, %{
            check_out_date: ~D[2027-01-08],
            first_meal: "dinner",
            last_meal: "dinner",
            meal_adults: 2,
            meal_children: 0
          })

    {:ok, result} = ShoppingList.generate(~D[2027-01-08], ~D[2027-01-08])
    [row] = result.rows
    assert Decimal.equal?(row.quantity, "0.8")
    assert Decimal.equal?(row.packages, "1")
    assert length(row.sources) == 2
  end

  test "main and soup share an ingredient without counting another meal or extra portions" do
    ingredient = ingredient_fixture(%{purchase_mode: "Sezona"})
    main = recipe_fixture(ingredient)

    soup =
      recipe_fixture(ingredient, %{
        base_servings: "5",
        lines: [%{ingredient_id: ingredient.id, quantity: "500", unit: "g"}]
      })

    booking =
      menu_booking_fixture(%{
        check_out_date: ~D[2027-01-08],
        first_meal: "dinner",
        last_meal: "dinner"
      })

    variant = shopping_variant(main, %{days: 1, first_meal: "dinner", last_meal: "dinner"}, soup)
    assign_variant(booking, variant)
    {:ok, result} = ShoppingList.generate(~D[2027-01-08], ~D[2027-01-08])
    assert result.services == 1
    assert result.portions == 15
    [row] = result.rows
    assert Decimal.equal?(row.quantity, "4.05")
    assert length(row.sources) == 2
    assert result.issues == []
  end

  test "selecting one booking and part of its stay includes only actual services" do
    {_, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe)
    shopping_booking(recipe, %{meal_adults: 100, meal_children: 0})
    {:ok, result} = ShoppingList.generate(~D[2027-01-09], ~D[2027-01-09], booking.id)
    assert result.groups == 1
    assert result.services == 3
    [row] = result.rows
    assert Decimal.equal?(row.quantity, "8.1")
    assert Enum.all?(row.sources, &(&1.booking.id == booking.id and &1.date == ~D[2027-01-09]))
  end

  test "half board never adds a lunch and child factors stay separate for breakfast" do
    {_, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe, %{meal_plan: "half_board"})

    {:ok, _} =
      Recipes.update_settings(Recipes.settings(), %{
        hot_child_factor: "0.5",
        breakfast_child_factor: "0.8"
      })

    {:ok, result} = ShoppingList.generate(~D[2027-01-08], ~D[2027-01-10], booking.id)
    assert result.services == 4
    [row] = result.rows
    refute Enum.any?(row.sources, &(&1.meal_type == "lunch"))
    assert Decimal.equal?(row.quantity, "10.6")
  end

  test "unknown catering, absent menu and stale menu remain visible and do not silently contribute" do
    {_, recipe} = shopping_recipe()
    unknown = menu_booking_fixture(%{meal_plan: nil})
    missing = menu_booking_fixture()
    {stale, _} = shopping_booking(recipe)
    {:ok, _} = Bookings.update_booking(stale, %{last_meal: "lunch"})
    {:ok, result} = ShoppingList.generate(~D[2027-01-08], ~D[2027-01-10])
    assert result.rows == []
    assert result.covered_services == 0

    assert Enum.sort(Enum.map(result.issues, & &1.booking.id)) ==
             Enum.sort([unknown.id, missing.id, stale.id])
  end

  test "cancelled, deleted and uncatered bookings are excluded" do
    for attrs <- [%{status: "cancelled"}, %{meal_plan: "none"}] do
      menu_booking_fixture(attrs)
    end

    booking = menu_booking_fixture()

    Repo.update!(
      Ecto.Changeset.change(booking, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    )

    {:ok, result} = ShoppingList.generate(~D[2027-01-08], ~D[2027-01-10])
    assert result.groups == 0
    assert result.rows == []
    assert result.issues == []
  end

  test "partial recipe links and missing service rows give actionable issues" do
    {_, recipe} = shopping_recipe()
    {booking, menu} = shopping_booking(recipe)
    [first, second | _] = menu.items
    {:ok, _} = Links.save("booking", first.id, nil, [recipe.id], Links.version(first))
    Repo.delete!(second)
    {:ok, result} = ShoppingList.generate(~D[2027-01-08], ~D[2027-01-10], booking.id)
    assert result.services == 5
    assert result.covered_services == 3
    assert length(result.issues) == 2
    assert Enum.any?(result.issues, &(&1.item && &1.item.id == first.id))
    [row] = result.rows
    assert length(row.sources) == 4
  end

  test "recipe edits change totals and checklist fingerprints; zero consumption does not create rows" do
    {ingredient, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe)
    {:ok, before} = ShoppingList.generate(~D[2027-01-08], ~D[2027-01-10], booking.id)
    [line] = recipe.lines

    {:ok, _} =
      Recipes.update_recipe(recipe, %{
        lines: [%{id: line.id, ingredient_id: ingredient.id, quantity: "3", unit: "kg"}]
      })

    {:ok, after_edit} = ShoppingList.generate(~D[2027-01-08], ~D[2027-01-10], booking.id)
    assert hd(before.rows).fingerprint != hd(after_edit.rows).fingerprint
    assert Decimal.equal?(hd(after_edit.rows).quantity, "20.25")
    {:ok, _} = Bookings.update_booking(booking, %{meal_adults: 0, meal_children: 0})
    {:ok, empty} = ShoppingList.generate(~D[2027-01-08], ~D[2027-01-10], booking.id)
    assert empty.rows == []
    assert empty.issues == []
  end

  test "buying rules match the sheet while ongoing purchases remain visible" do
    ingredient = ingredient_fixture(%{purchase_mode: "Sezona", package_size: "1"})

    row = %{
      id: ingredient.id,
      ingredient: ingredient,
      quantity: Decimal.new("2.000000000001"),
      unit: "kg",
      sources: []
    }

    assert Decimal.equal?(ShoppingList.purchase(row).packages, "2")

    ongoing =
      ShoppingList.purchase(%{row | ingredient: %{ingredient | purchase_mode: "Průběžně"}})

    assert is_nil(ongoing.packages)
    assert Decimal.equal?(ongoing.buy_quantity, row.quantity)
    unknown = ShoppingList.purchase(%{row | ingredient: %{ingredient | purchase_mode: nil}})
    assert unknown.buy_quantity == nil
    assert unknown.purchase_issue != nil
  end

  test "buffet norms are explicit estimates, editable and automatically linked to breakfasts" do
    data =
      Application.app_dir(:cozy_checkout, "priv/recipes/breakfast_buffet.json")
      |> File.read!()
      |> Jason.decode!()

    buffet =
      Repo.get_by!(Recipe, source_key: "kitchen:breakfast-buffet:v1")
      |> then(&Recipes.get_recipe!(&1.id))

    assert length(buffet.lines) == 9

    for {line, source} <- Enum.zip(buffet.lines, data["lines"]) do
      assert line.ingredient.name == source["ingredient_name"]
      assert Decimal.equal?(line.quantity, source["quantity"])
      assert line.unit == source["unit"]
    end

    {booking, _} = shopping_booking(buffet)
    {:ok, result} = ShoppingList.generate(~D[2027-01-10], ~D[2027-01-10], booking.id)
    assert result.buffet?
    assert result.covered_services == 1
    assert result.issues == []
    milk = Enum.find(result.rows, &(&1.ingredient.name == "Mléko"))
    assert Decimal.equal?(milk.quantity, "2.025")
    assert hd(milk.sources).meal_type == "breakfast"
  end

  test "invalid ranges and unavailable scopes are rejected" do
    for {first, last} <- [
          {~D[2027-01-10], ~D[2027-01-08]},
          {~D[2027-01-01], ~D[2028-01-02]},
          {nil, nil}
        ] do
      assert {:error, :invalid_range} = ShoppingList.generate(first, last)
    end

    for id <- ["bad-id", Ecto.UUID.generate()] do
      assert {:error, :booking_unavailable} =
               ShoppingList.generate(~D[2027-01-08], ~D[2027-01-10], id)
    end
  end

  test "fractional piece consumption remains exact while shopping asks for whole pieces" do
    ingredient = ingredient_fixture(%{purchase_mode: "Průběžně", base_unit: "ks"})

    row =
      ShoppingList.purchase(%{
        id: ingredient.id,
        ingredient: ingredient,
        quantity: Decimal.new("13.5"),
        unit: "ks",
        sources: []
      })

    assert Decimal.equal?(row.quantity, "13.5")
    assert Decimal.equal?(row.buy_quantity, "14")
  end
end

defmodule CozyCheckout.Recipes.ConsumptionTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.RecipeFixtures
  import CozyCheckout.MenuFixtures
  alias CozyCheckout.Recipes
  alias CozyCheckout.Recipes.{Consumption, Links}
  alias CozyCheckout.Meals.MenuPlanning

  test "main and supplements aggregate shared ingredients using adult equivalents, never extra portions" do
    ingredient = ingredient_fixture()

    main =
      recipe_fixture(ingredient, %{
        lines: [%{ingredient_id: ingredient.id, quantity: "2000", unit: "g"}]
      })

    soup =
      recipe_fixture(ingredient, %{
        base_servings: "5",
        lines: [%{ingredient_id: ingredient.id, quantity: "0.5", unit: "kg"}]
      })

    result = Consumption.calculate([main, soup], 10, 5, "0.7")
    assert result.actual == 15
    assert Decimal.equal?(result.effective, "13.5")
    assert [%{quantity: quantity, unit: "kg"}] = result.quantities
    assert Decimal.equal?(quantity, "4.05")
    assert result.issues == []
    assert [%{quantity: zero}] = Consumption.calculate([main], 0, 0, "0.7").quantities
    assert Decimal.equal?(zero, 0)
  end

  test "only compatible units convert, fractions remain exact until display" do
    assert {:ok, grams} = Recipes.to_base(Decimal.new("125.5"), "g", "kg")
    assert Decimal.equal?(grams, "0.1255")
    assert {:ok, ml} = Recipes.to_base(Decimal.new("12.34"), "ml", "l")
    assert Decimal.equal?(ml, "0.01234")

    for {unit, base} <- [{"kg", "l"}, {"ks", "kg"}, {"ml", "kg"}],
        do: assert(Recipes.to_base(Decimal.new(1), unit, base) == {:error, :incompatible_unit})

    assert Recipes.format_quantity(Decimal.new("0.1255"), "kg") == "125,5 g"
    assert Recipes.format_quantity(Decimal.new("0.00000001"), "l") == "< 0,001 ml"
  end

  test "booking uses live counts and distinct breakfast/hot child coefficients" do
    recipe = recipe_fixture()
    variant = variant_fixture()

    for item <- variant.items do
      assert {:ok, _} = Links.save("variant", item.id, recipe.id, [], Links.version(item))
    end

    booking = menu_booking_fixture()
    menu = assign_variant(booking, MenuPlanning.get_variant!(variant.id))

    assert {:ok, _} =
             Recipes.update_settings(Recipes.settings(), %{
               hot_child_factor: "0.5",
               breakfast_child_factor: "0.8"
             })

    dinner = Enum.find(menu.items, &(&1.meal_type == "dinner"))
    breakfast = Enum.find(menu.items, &(&1.meal_type == "breakfast"))
    assert {:ok, hot} = Consumption.for_booking_item(dinner.id)
    assert hot.actual == 15
    assert Decimal.equal?(hot.effective, "12.5")
    assert {:ok, cold} = Consumption.for_booking_item(breakfast.id)
    assert Decimal.equal?(cold.effective, "14")
    assert {:ok, _} = CozyCheckout.Bookings.update_booking(booking, %{meal_children: 10})
    assert {:ok, updated} = Consumption.for_booking_item(dinner.id)
    assert updated.actual == 20
    assert Decimal.equal?(updated.effective, "15")
  end

  test "unlinked menu warns, stale and cancelled bookings cannot be calculated or linked" do
    booking = menu_booking_fixture()
    [item | _] = assign_variant(booking, variant_fixture()).items
    assert {:ok, result} = Consumption.for_booking_item(item.id)
    assert result.issues != []
    recipe = recipe_fixture()

    assert {:ok, changed} =
             CozyCheckout.Bookings.update_booking(booking, %{check_out_date: ~D[2027-01-11]})

    assert {:error, :stale_menu} = Consumption.for_booking_item(item.id)

    assert {:error, :stale_booking} =
             Links.save("booking", item.id, recipe.id, [], Links.version(item))

    assert {:ok, _} =
             CozyCheckout.Bookings.update_booking(changed, %{
               check_out_date: booking.check_out_date,
               status: "cancelled"
             })

    assert {:error, :cancelled_booking} = Consumption.for_booking_item(item.id)
  end
end

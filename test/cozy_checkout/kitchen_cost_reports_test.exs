defmodule CozyCheckout.KitchenCosts.ReportsTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.RecipeFixtures
  import CozyCheckout.MenuFixtures
  import CozyCheckout.ShoppingFixtures
  alias CozyCheckout.{KitchenCosts, Recipes, Bookings}
  alias CozyCheckout.KitchenCosts.Reports

  defp buy(ingredient, attrs \\ %{}) do
    KitchenCosts.confirm_purchase(
      Map.merge(
        %{
          merchant: "Nákup pro report",
          purchased_on: ~D[2027-01-01],
          total_paid: "100",
          import_id: Ecto.UUID.generate(),
          document_number: Ecto.UUID.generate(),
          lines: [
            %{
              line_number: 1,
              source_name: "Surovina",
              classification: "ingredient",
              ingredient_id: ingredient.id,
              quantity: "1",
              unit: ingredient.base_unit,
              line_total: "100"
            }
          ]
        },
        attrs
      )
    )
  end

  test "one weekend uses actual meals and child factors; saved report survives price, recipe and booking edits" do
    {ingredient, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe)
    assert {:ok, purchase} = buy(ingredient)
    assert {:ok, report} = Reports.generate(~D[2027-01-08], ~D[2027-01-10], booking.id)
    assert report["complete"]
    assert report["portions"] == 75
    assert report["services"] == 5
    assert length(report["meals"]) == 5
    assert Decimal.equal?(report["known_total"], "1350")
    assert Decimal.equal?(report["average_per_portion"], "18")
    assert {:ok, stored} = Reports.save(report)
    [line] = recipe.lines

    assert {:ok, _} =
             Recipes.update_recipe(recipe, %{
               lines: [%{id: line.id, ingredient_id: ingredient.id, quantity: "3", unit: "kg"}]
             })

    assert {:ok, _} =
             buy(
               ingredient,
               %{
                 total_paid: "200",
                 lines: [
                   %{
                     line_number: 1,
                     source_name: "Opravená cena",
                     classification: "ingredient",
                     ingredient_id: ingredient.id,
                     quantity: "1",
                     unit: "kg",
                     line_total: "200"
                   }
                 ]
               }
               |> Map.put(:document_number, purchase.document_number)
               |> then(&Map.put(&1, :import_id, Ecto.UUID.generate()))
             )

    # Replacing a price is separately exercised below; changing both source datasets cannot mutate the snapshot.
    assert {:ok, _} = Bookings.update_booking(booking, %{meal_adults: 20})
    assert Reports.get!(stored.id).snapshot == report
    assert {:ok, recomputed} = Reports.generate(~D[2027-01-08], ~D[2027-01-10], booking.id)
    refute recomputed["known_total"] == report["known_total"]
    assert {:ok, next} = Reports.save(recomputed)
    refute next.id == stored.id
  end

  test "replacement prices do not rewrite a saved snapshot" do
    {ingredient, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe)
    assert {:ok, purchase} = buy(ingredient)
    {:ok, before} = Reports.generate(~D[2027-01-09], ~D[2027-01-09], booking.id)
    {:ok, saved} = Reports.save(before)

    attrs = %{
      merchant: purchase.merchant,
      purchased_on: purchase.purchased_on,
      total_paid: "200",
      lines: [
        %{
          line_number: 1,
          source_name: "Surovina",
          classification: "ingredient",
          ingredient_id: ingredient.id,
          quantity: "1",
          unit: "kg",
          line_total: "200"
        }
      ]
    }

    assert {:ok, _} = KitchenCosts.confirm_purchase(attrs, replaces_id: purchase.id)
    {:ok, after_edit} = Reports.generate(~D[2027-01-09], ~D[2027-01-09], booking.id)
    assert Decimal.equal?(after_edit["known_total"], Decimal.mult(before["known_total"], 2))
    assert Reports.get!(saved.id).snapshot == before
  end

  test "partial stay and breakfast coefficient, supplements and completed bookings retain actual portion counts" do
    ingredient = ingredient_fixture()
    main = recipe_fixture(ingredient)
    soup = recipe_fixture(ingredient)
    booking = menu_booking_fixture(%{status: "completed"})
    variant = shopping_variant(main, %{}, soup)
    assign_variant(booking, variant)

    {:ok, _} =
      Recipes.update_settings(Recipes.settings(), %{
        breakfast_child_factor: "0.8",
        hot_child_factor: "0.5"
      })

    {:ok, _} = buy(ingredient)
    {:ok, report} = Reports.generate(~D[2027-01-09], ~D[2027-01-09], booking.id)
    assert report["portions"] == 45
    assert length(report["meals"]) == 3
    assert Enum.all?(report["meals"], &(&1["date"] == "2027-01-09"))

    for meal <- report["meals"] do
      assert Decimal.equal?(
               meal["factor"],
               if(meal["meal_type"] == "breakfast", do: "0.8", else: "0.5")
             )

      assert length(meal["recipes"]) == 2
    end
  end

  test "missing prices are incomplete and missing or stale menus stay visible; purchasing settings are irrelevant" do
    ingredient = ingredient_fixture()
    recipe = recipe_fixture(ingredient)
    {booking, _} = shopping_booking(recipe)
    {:ok, missing} = Reports.generate(~D[2027-01-09], ~D[2027-01-09], booking.id)
    refute missing["complete"]
    assert Decimal.equal?(missing["known_total"], "0")
    assert missing["warnings"] != []
    {:ok, _} = buy(ingredient)
    {:ok, priced} = Reports.generate(~D[2027-01-09], ~D[2027-01-09], booking.id)
    assert priced["complete"]
    {:ok, _} = Bookings.update_booking(booking, %{last_meal: "lunch"})
    {:ok, stale} = Reports.generate(~D[2027-01-09], ~D[2027-01-09], booking.id)
    refute stale["complete"]
    assert stale["meals"] == []
    assert stale["issues"] != []
  end

  test "date and unavailable booking validation; cancelled, deleted and uncatered stays are excluded" do
    for attrs <- [%{status: "cancelled"}, %{meal_plan: "none"}], do: menu_booking_fixture(attrs)
    booking = menu_booking_fixture()

    Repo.update!(
      Ecto.Changeset.change(booking, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    )

    assert {:ok, report} = Reports.generate(~D[2027-01-08], ~D[2027-01-10])
    assert report["groups"] == 0
    assert {:error, :invalid_range} = Reports.generate(~D[2027-01-10], ~D[2027-01-08])
    assert {:error, :invalid_range} = Reports.generate(~D[2027-01-01], ~D[2028-01-02])

    assert {:error, :booking_unavailable} =
             Reports.generate(~D[2027-01-08], ~D[2027-01-10], Ecto.UUID.generate())
  end
end

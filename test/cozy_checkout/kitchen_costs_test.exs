defmodule CozyCheckout.KitchenCostsTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.RecipeFixtures
  alias CozyCheckout.{KitchenCosts, Recipes}
  alias CozyCheckout.KitchenCosts.{Purchase, PurchaseLine, ManualPrice}

  defp line(ingredient, attrs \\ %{}) do
    Map.merge(
      %{
        line_number: 1,
        source_name: "Značka A 1 kg",
        classification: "ingredient",
        ingredient_id: ingredient.id,
        quantity: "1",
        unit: ingredient.base_unit,
        line_total: "100"
      },
      attrs
    )
  end

  defp purchase(lines, attrs \\ %{}) do
    total = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.line_total, &2))

    Map.merge(
      %{
        import_id: Ecto.UUID.generate(),
        merchant: "Obchod",
        purchased_on: ~D[2026-10-27],
        document_number: Ecto.UUID.generate(),
        total_paid: total,
        lines: lines
      },
      attrs
    )
  end

  test "packaged, weighed and non-food items reconcile the receipt including rounding" do
    ingredient = ingredient_fixture()
    original = %{"schema_version" => 1, "warnings" => ["Zkontrolujte balení"]}

    rows = [
      line(ingredient, %{
        quantity: "280",
        unit: "g",
        package_count: "2",
        package_quantity: "140",
        package_unit: "g",
        line_total: "59.80"
      }),
      line(ingredient, %{
        line_number: 2,
        source_name: "Vážené zboží",
        quantity: "0.723",
        line_total: "40.10"
      }),
      line(ingredient, %{
        line_number: 3,
        ingredient_id: nil,
        classification: "other",
        source_name: "Drogerie",
        quantity: "1",
        unit: "ks",
        line_total: "20"
      }),
      line(ingredient, %{
        line_number: 4,
        ingredient_id: nil,
        classification: "unassigned",
        source_name: "Neznámá položka",
        line_total: "30"
      })
    ]

    assert {:ok, saved} =
             KitchenCosts.confirm_purchase(
               purchase(rows, %{rounding: "0.10", total_paid: "150", original_json: original})
             )

    assert saved.original_json == original
    assert saved.confirmed_at
    assert Decimal.equal?(Enum.find(saved.lines, &(&1.line_number == 1)).base_quantity, "0.28")
    assert Enum.count(saved.lines, &is_nil(&1.ingredient_id)) == 2
    assert Enum.any?(KitchenCosts.list_unassigned_lines(), &(&1.purchase_id == saved.id))
    price = KitchenCosts.price_for(ingredient.id, ~D[2026-10-27])
    assert Decimal.equal?(price.total, "99.90")
    assert Decimal.equal?(price.quantity, "1.003")
  end

  test "invalid totals, units, packaging, mappings and line numbers do not persist anything" do
    ingredient = ingredient_fixture()

    invalid_rows = [
      [line(ingredient, %{quantity: "0"})],
      [line(ingredient, %{quantity: "-1"})],
      [line(ingredient, %{line_total: "-10"})],
      [line(ingredient, %{unit: "l"})],
      [line(ingredient, %{ingredient_id: Ecto.UUID.generate()})],
      [line(ingredient, %{classification: "other"})],
      [line(ingredient, %{classification: "ingredient", ingredient_id: nil})],
      [line(ingredient, %{package_count: "2"})],
      [line(ingredient, %{package_count: "2", package_quantity: "140", package_unit: "g"})],
      [line(ingredient), line(ingredient)]
    ]

    for rows <- invalid_rows do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               KitchenCosts.confirm_purchase(purchase(rows))
    end

    assert {:error, cs} =
             KitchenCosts.confirm_purchase(purchase([line(ingredient)], %{total_paid: "99"}))

    assert errors_on(cs).total_paid != []

    assert {:error, _} =
             KitchenCosts.confirm_purchase(purchase([line(ingredient)], %{currency: "EUR"}))

    assert {:error, _} = KitchenCosts.confirm_purchase(purchase([], %{total_paid: "0"}))
    assert Repo.aggregate(Purchase, :count) == 0
    assert Repo.aggregate(PurchaseLine, :count) == 0
  end

  test "one invalid ingredient rolls back the whole purchase" do
    ingredient = ingredient_fixture()

    rows = [
      line(ingredient),
      line(ingredient, %{line_number: 2, ingredient_id: Ecto.UUID.generate()})
    ]

    assert {:error, _} = KitchenCosts.confirm_purchase(purchase(rows))
    assert Repo.aggregate(PurchaseLine, :count) == 0
    assert Repo.aggregate(Purchase, :count) == 0
  end

  test "an import is idempotent and a different import of the same receipt needs acknowledgement" do
    ingredient = ingredient_fixture()
    attrs = purchase([line(ingredient)])
    assert {:ok, first} = KitchenCosts.confirm_purchase(attrs)
    assert {:ok, repeated} = KitchenCosts.confirm_purchase(attrs)
    assert first.id == repeated.id
    duplicate = %{attrs | import_id: Ecto.UUID.generate(), merchant: "  OBCHOD  "}
    assert {:error, :possible_duplicate} = KitchenCosts.confirm_purchase(duplicate)
    assert {:ok, other} = KitchenCosts.confirm_purchase(duplicate, allow_duplicate: true)
    refute first.id == other.id
    assert Repo.aggregate(Purchase, :count) == 2
  end

  test "replacements exclude the old price while preserving original JSON and line snapshots" do
    ingredient = ingredient_fixture()
    attrs = purchase([line(ingredient)], %{original_json: %{"unmodified" => true}})
    assert {:ok, first} = KitchenCosts.confirm_purchase(attrs)

    replacement_attrs =
      purchase([line(ingredient, %{line_total: "200"})], %{document_number: first.document_number})

    assert {:ok, second} = KitchenCosts.confirm_purchase(replacement_attrs, replaces_id: first.id)
    assert second.replaces_id == first.id
    assert KitchenCosts.get_purchase!(first.id) == first
    assert Decimal.equal?(KitchenCosts.price_for(ingredient.id, ~D[2026-10-27]).unit_price, "200")

    assert {:error, :already_replaced} =
             KitchenCosts.confirm_purchase(purchase([line(ingredient)]), replaces_id: first.id)

    assert {:ok, third} =
             KitchenCosts.confirm_purchase(purchase([line(ingredient, %{line_total: "300"})]),
               replaces_id: second.id
             )

    assert third.replaces_id == second.id
    assert Decimal.equal?(KitchenCosts.price_for(ingredient.id, ~D[2026-10-27]).unit_price, "300")
  end

  test "invalid replacement keeps the old version active and unresolved rows leave the queue only after replacement" do
    ingredient = ingredient_fixture()
    attrs = purchase([line(ingredient, %{ingredient_id: nil, classification: "unassigned"})])
    assert {:ok, first} = KitchenCosts.confirm_purchase(attrs)

    assert {:error, _} =
             KitchenCosts.confirm_purchase(purchase([line(ingredient, %{unit: "l"})]),
               replaces_id: first.id
             )

    assert Enum.any?(KitchenCosts.list_unassigned_lines(), &(&1.purchase_id == first.id))

    assert {:ok, _} =
             KitchenCosts.confirm_purchase(purchase([line(ingredient)]), replaces_id: first.id)

    refute Enum.any?(KitchenCosts.list_unassigned_lines(), &(&1.purchase_id == first.id))
  end

  test "two brands and changing packaging use total quantity, not the average of unit prices" do
    ingredient = ingredient_fixture()

    assert {:ok, _} =
             KitchenCosts.confirm_purchase(
               purchase([
                 line(ingredient, %{
                   quantity: "200",
                   unit: "g",
                   package_count: "2",
                   package_quantity: "100",
                   package_unit: "g",
                   line_total: "20"
                 })
               ])
             )

    assert {:ok, _} =
             KitchenCosts.confirm_purchase(
               purchase([
                 line(ingredient, %{
                   source_name: "Značka B 400 g",
                   quantity: "800",
                   unit: "g",
                   package_count: "2",
                   package_quantity: "400",
                   package_unit: "g",
                   line_total: "160"
                 })
               ])
             )

    price = KitchenCosts.price_for(ingredient.id, ~D[2026-10-27])
    assert price.source == "weighted_average"
    assert length(price.lines) == 2
    assert Decimal.equal?(price.quantity, "1")
    assert Decimal.equal?(price.unit_price, "180")
  end

  test "90 calendar days include the meal date and day minus 89, exclude day minus 90 and future prices" do
    ingredient = ingredient_fixture()
    date = ~D[2026-10-27]

    for {offset, total} <- [{-90, "999"}, {-89, "100"}, {0, "200"}, {1, "888"}] do
      assert {:ok, _} =
               KitchenCosts.confirm_purchase(
                 purchase([line(ingredient, %{line_total: total})], %{
                   purchased_on: Date.add(date, offset)
                 })
               )
    end

    price = KitchenCosts.price_for(ingredient.id, date)
    assert Decimal.equal?(price.unit_price, "150")
    assert Enum.map(price.lines, & &1.purchased_on) == [Date.add(date, -89), date]
    assert KitchenCosts.price_for(ingredient.id, Date.add(date, -91)).source == "missing"
  end

  test "millilitres convert to litres and pieces remain pieces without estimating density" do
    milk = ingredient_fixture(%{base_unit: "l"})
    bread = ingredient_fixture(%{base_unit: "ks"})

    assert {:ok, _} =
             KitchenCosts.confirm_purchase(
               purchase([
                 line(milk, %{quantity: "1500", unit: "ml", line_total: "45"}),
                 line(bread, %{line_number: 2, quantity: "10", unit: "ks", line_total: "50"})
               ])
             )

    assert Decimal.equal?(KitchenCosts.price_for(milk.id, ~D[2026-10-27]).unit_price, "30")
    assert Decimal.equal?(KitchenCosts.price_for(bread.id, ~D[2026-10-27]).unit_price, "5")
    assert {:error, _} = KitchenCosts.confirm_purchase(purchase([line(milk, %{unit: "ks"})]))
    assert {:error, _} = KitchenCosts.confirm_purchase(purchase([line(bread, %{unit: "g"})]))
  end

  test "older fallback uses the latest purchase day and takes precedence over a manual estimate" do
    ingredient = ingredient_fixture()

    for {date, total} <- [
          {~D[2026-01-01], "10"},
          {~D[2026-02-01], "200"},
          {~D[2026-02-01], "100"}
        ] do
      assert {:ok, _} =
               KitchenCosts.confirm_purchase(
                 purchase([line(ingredient, %{line_total: total})], %{purchased_on: date})
               )
    end

    assert {:ok, _} =
             KitchenCosts.create_manual_price(%{
               ingredient_id: ingredient.id,
               valid_from: ~D[2026-01-01],
               unit_price: "50",
               note: "Odhad"
             })

    price = KitchenCosts.price_for(ingredient.id, ~D[2026-10-27])
    assert price.source == "older_purchase"
    assert price.warnings != []
    assert Decimal.equal?(price.unit_price, "150")
    assert length(price.lines) == 2
  end

  test "manual estimates are dated, positive and explicitly labelled; future estimates cannot price past meals" do
    ingredient = ingredient_fixture()

    attrs = %{
      ingredient_id: ingredient.id,
      valid_from: ~D[2026-10-27],
      unit_price: "120.123456789",
      note: "Odhad s DPH"
    }

    assert {:ok, manual} = KitchenCosts.create_manual_price(attrs)
    assert {:error, _} = KitchenCosts.create_manual_price(attrs)

    assert {:error, _} =
             KitchenCosts.create_manual_price(%{
               attrs
               | valid_from: ~D[2026-10-26],
                 unit_price: "-1"
             })

    price = KitchenCosts.price_for(ingredient.id, ~D[2026-10-27])
    assert price.source == "manual_estimate"
    assert price.manual_price_id == manual.id
    assert price.warnings != []
    assert Decimal.equal?(price.unit_price, "120.123456789")
    assert KitchenCosts.price_for(ingredient.id, ~D[2026-10-26]).unit_price == nil

    assert {:ok, newer} =
             KitchenCosts.create_manual_price(%{
               attrs
               | valid_from: ~D[2026-10-28],
                 unit_price: "150"
             })

    assert KitchenCosts.price_for(ingredient.id, ~D[2026-10-28]).manual_price_id == newer.id
    assert Repo.aggregate(ManualPrice, :count) == 2
  end

  test "missing price is not zero; existing consumption factors and unrounded quantities are preserved" do
    ingredient = ingredient_fixture()
    missing = ingredient_fixture()
    recipe = recipe_fixture(ingredient)
    other = recipe_fixture(missing)

    assert {:ok, _} =
             KitchenCosts.confirm_purchase(purchase([line(ingredient, %{line_total: "123.45"})]))

    consumption = Recipes.Consumption.calculate([recipe, other], 2, 1, "0.7")
    cost = KitchenCosts.cost_consumption(consumption, ~D[2026-10-27])
    refute cost.complete?
    assert Decimal.equal?(cost.known_total, "66.663")
    assert Enum.find(cost.quantities, &(&1.id == missing.id)).cost == nil
    assert cost.actual == 3
    assert cost.effective == consumption.effective
    assert cost.issues != []

    assert {:ok, _} =
             KitchenCosts.create_manual_price(%{
               ingredient_id: missing.id,
               valid_from: ~D[2026-10-27],
               unit_price: "50",
               note: "Odhad"
             })

    estimated = KitchenCosts.cost_consumption(consumption, ~D[2026-10-27])
    assert estimated.complete?
    assert estimated.issues != []
    assert Decimal.equal?(estimated.known_total, "93.663")
  end

  test "purchase snapshots survive rename, and purchase or estimate prevents base-unit changes" do
    ingredient = ingredient_fixture()
    assert {:ok, saved} = KitchenCosts.confirm_purchase(purchase([line(ingredient)]))
    assert {:error, cs} = Recipes.update_ingredient(ingredient, %{base_unit: "l"})
    assert errors_on(cs).base_unit != []
    assert {:ok, renamed} = Recipes.update_ingredient(ingredient, %{name: "Jiný název"})
    assert hd(KitchenCosts.get_purchase!(saved.id).lines).ingredient_name == ingredient.name
    assert {:ok, _} = Recipes.archive_ingredient(renamed)
    assert {:error, _} = KitchenCosts.confirm_purchase(purchase([line(renamed)]))
    assert Decimal.equal?(KitchenCosts.price_for(ingredient.id, ~D[2026-10-27]).unit_price, "100")

    estimated = ingredient_fixture()

    assert {:ok, _} =
             KitchenCosts.create_manual_price(%{
               ingredient_id: estimated.id,
               valid_from: ~D[2026-10-27],
               unit_price: "100",
               note: "Odhad"
             })

    assert {:error, _} = Recipes.update_ingredient(estimated, %{base_unit: "ks"})
  end
end

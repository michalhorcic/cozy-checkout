defmodule CozyCheckout.Kitchen.FreezerTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.RecipeFixtures
  import CozyCheckout.ShoppingFixtures
  alias CozyCheckout.{Recipes, Repo}
  alias CozyCheckout.Kitchen.{Freezer, FreezerItem, ShoppingList}

  defp attrs(extra \\ %{}),
    do:
      Map.merge(%{name: "Zásoba", quantity: "500", unit: "g", frozen_on: Freezer.today()}, extra)

  test "separate batches, oldest first, corrections and soft deletion" do
    {:ok, newer} = Freezer.create_item(attrs())
    {:ok, older} = Freezer.create_item(attrs(%{frozen_on: Date.add(Freezer.today(), -20)}))
    assert Enum.map(Freezer.list_items(), & &1.id) == [older.id, newer.id]
    {:ok, older} = Freezer.update_item(older, %{name: "Hrášek", location: "Horní zásuvka"})
    assert [found] = Freezer.list_items("hrasek")
    assert found.id == older.id
    {:ok, removed} = Freezer.archive_item(older)
    assert removed.archived_at
    assert length(Freezer.list_items()) == 1
    assert length(Freezer.list_items("", true)) == 1
    assert Repo.get!(FreezerItem, older.id)
  end

  test "partial and full removal, invalid amounts and optimistic conflicts" do
    {:ok, item} = Freezer.create_item(attrs())

    for amount <- ["-1", "0", "501", "invalid", nil] do
      assert {:error, :invalid_amount} = Freezer.remove(item, amount)
    end

    {:ok, changed} = Freezer.remove(item, "200")
    assert Decimal.equal?(changed.quantity, 300)
    assert {:error, :stale} = Freezer.remove(item, "1")
    assert {:error, :stale} = Freezer.update_item(item, %{quantity: "600"})
    assert {:error, :stale} = Freezer.archive_item(item)
    {:ok, empty} = Freezer.remove(changed, :all)
    assert Decimal.equal?(empty.quantity, 0)
    assert empty.archived_at
    assert Freezer.list_items() == []
    assert {:error, :archived} = Freezer.update_item(empty, %{quantity: "20"})
  end

  test "units, links, positive stock and archived catalogue validation" do
    ingredient = ingredient_fixture()
    recipe = recipe_fixture(ingredient)
    assert {:error, _} = Freezer.create_item(attrs(%{quantity: "0"}))
    assert {:error, _} = Freezer.create_item(attrs(%{unit: "box"}))

    assert {:error, _} =
             Freezer.create_item(attrs(%{ingredient_id: ingredient.id, recipe_id: recipe.id}))

    assert {:error, _} = Freezer.create_item(attrs(%{ingredient_id: Ecto.UUID.generate()}))

    assert {:error, _} =
             Freezer.create_item(attrs(%{ingredient_id: ingredient.id, unit: "porce"}))

    {:ok, item} = Freezer.create_item(attrs(%{ingredient_id: ingredient.id}))
    assert {:ok, base} = Recipes.to_base(item.quantity, item.unit, ingredient.base_unit)
    assert Decimal.equal?(base, "0.5")
    assert {:error, _} = Recipes.update_ingredient(ingredient, %{base_unit: "l"})
    {:ok, _} = Recipes.archive_ingredient(ingredient)
    assert {:ok, _} = Freezer.update_item(item, %{name: "Hrášek"})
    assert {:error, _} = Freezer.create_item(attrs(%{ingredient_id: ingredient.id}))
    assert hd(Freezer.list_items()).ingredient.archived_at

    for unit <- ~w(kg g l ml ks porce) do
      assert {:ok, _} = Freezer.create_item(attrs(%{recipe_id: recipe.id, unit: unit}))
    end
  end

  test "freezer links alone prevent changing the ingredient base unit" do
    ingredient = ingredient_fixture()
    {:ok, _} = Freezer.create_item(attrs(%{ingredient_id: ingredient.id}))
    assert {:error, cs} = Recipes.update_ingredient(ingredient, %{base_unit: "l"})
    assert cs.errors[:base_unit]
  end

  test "database constraints reject invalid stock and mutually exclusive links" do
    ingredient = ingredient_fixture()
    recipe = recipe_fixture(ingredient)

    for invalid <- [
          attrs(%{quantity: "-1"}),
          attrs(%{quantity: "0"}),
          attrs(%{ingredient_id: Ecto.UUID.generate()}),
          attrs(%{unit: "box"}),
          attrs(%{ingredient_id: ingredient.id, recipe_id: recipe.id})
        ] do
      assert_raise Ecto.ConstraintError, fn ->
        Repo.transaction(
          fn ->
            Repo.insert!(struct(FreezerItem, Map.update!(invalid, :quantity, &Decimal.new/1)))
          end,
          mode: :savepoint
        )
      end
    end
  end

  test "batch ID matches include supplements, deduplicate and exclude past meals" do
    {ingredient, recipe} = shopping_recipe()
    extra_ingredient = ingredient_fixture()

    extra =
      recipe_fixture(extra_ingredient, %{
        lines: [
          %{ingredient_id: extra_ingredient.id, quantity: "1", unit: "kg"},
          %{ingredient_id: ingredient.id, quantity: "1", unit: "kg"}
        ]
      })

    {booking, menu} =
      shopping_booking(recipe, %{
        check_in_date: Freezer.today(),
        check_out_date: Date.add(Freezer.today(), 1)
      })

    item = hd(menu.items)
    # Attach a second recipe using the same public API as the menu editor.
    {:ok, _} =
      CozyCheckout.Recipes.Links.save(
        "booking",
        item.id,
        recipe.id,
        [extra.id],
        CozyCheckout.Recipes.Links.version(item)
      )

    {:ok, stock} = Freezer.create_item(attrs(%{ingredient_id: ingredient.id}))
    {:ok, extra_stock} = Freezer.create_item(attrs(%{ingredient_id: extra_ingredient.id}))
    {:ok, prepared} = Freezer.create_item(attrs(%{recipe_id: extra.id, unit: "porce"}))
    {:ok, unlinked} = Freezer.create_item(attrs(%{name: recipe.name}))
    unrelated = ingredient_fixture()
    {:ok, _} = Freezer.create_item(attrs(%{ingredient_id: unrelated.id, name: ingredient.name}))
    result = Freezer.presentation(menu.items)

    assert Enum.sort(Enum.map(result.by_item[item.id], & &1.id)) ==
             Enum.sort([stock.id, extra_stock.id, prepared.id])

    assert Enum.map(result.prepared, & &1.id) == [prepared.id]
    assert Enum.map(result.unlinked, & &1.id) == [unlinked.id]

    assert Freezer.presentation([%{id: item.id, date: Date.add(Freezer.today(), -1)}]).by_item ==
             %{}

    assert booking.id
    {:ok, _} = Freezer.remove(extra_stock, :all)

    refute Enum.any?(
             Freezer.presentation(menu.items).by_item[item.id],
             &(&1.id == extra_stock.id)
           )

    item = CozyCheckout.Recipes.Links.load!("booking", item.id)

    {:ok, _} =
      CozyCheckout.Meals.MenuPlanning.update_booking_item(
        booking.id,
        item.id,
        %{menu_text: "Jiné jídlo", supplements: ""},
        CozyCheckout.Meals.MenuPlanning.item_version(item)
      )

    assert Freezer.presentation(menu.items).by_item[item.id] == []
  end

  test "all shopping output stays identical through stock creation, editing and removal" do
    {ingredient, recipe} = shopping_recipe()
    first = Freezer.today()
    last = Date.add(first, 1)
    {booking, _} = shopping_booking(recipe, %{check_in_date: first, check_out_date: last})
    shopping_booking(recipe, %{check_in_date: first, check_out_date: last})
    {:ok, baseline} = ShoppingList.generate(first, last)
    {:ok, selected} = ShoppingList.generate(first, last, booking.id)
    {:ok, stock} = Freezer.create_item(attrs(%{ingredient_id: ingredient.id}))

    {:ok, prepared} =
      Freezer.create_item(attrs(%{recipe_id: recipe.id, unit: "porce", quantity: "4"}))

    assert ShoppingList.generate(first, last) == {:ok, baseline}
    assert ShoppingList.generate(first, last, booking.id) == {:ok, selected}
    {:ok, stock} = Freezer.update_item(stock, %{quantity: "200"})
    assert ShoppingList.generate(first, last) == {:ok, baseline}
    assert {:ok, _} = Freezer.remove(stock, :all)
    assert {:ok, _} = Freezer.archive_item(prepared)
    assert ShoppingList.generate(first, last) == {:ok, baseline}
    assert ShoppingList.generate(first, last, booking.id) == {:ok, selected}
  end

  test "unlinked suggestions are bounded and oldest first" do
    for days <- 1..7 do
      {:ok, _} =
        Freezer.create_item(
          attrs(%{name: "Omáčka #{days}", frozen_on: Date.add(Freezer.today(), -days)})
        )
    end

    assert Enum.map(Freezer.presentation([]).unlinked, & &1.name) ==
             ["Omáčka 7", "Omáčka 6", "Omáčka 5", "Omáčka 4", "Omáčka 3"]
  end
end

defmodule CozyCheckout.Meals.MenuRecipesTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.MenuFixtures
  import CozyCheckout.RecipeFixtures
  alias CozyCheckout.{Recipes, Repo, QueryRecorder}
  alias CozyCheckout.Meals.{MenuRecipes, MenuPlanning, MenuVariant, BookingMenuItem}
  alias CozyCheckout.Recipes.Links

  defp attrs(recipe_id \\ nil) do
    %{
      "name" => "Recipe menu #{System.unique_integer([:positive])}",
      "days" => 1,
      "meal_plan" => "full_board",
      "first_meal" => "lunch",
      "last_meal" => "lunch",
      "items" => [
        %{
          "day_number" => 1,
          "meal_type" => "lunch",
          "recipe_id" => recipe_id,
          "supplement_recipe_ids" => [],
          "reviewed" => true
        }
      ]
    }
  end

  defp save(attrs), do: MenuRecipes.save_variant(%MenuVariant{items: []}, attrs)

  test "an empty main is a persisted draft, not an assignable menu" do
    assert {:ok, draft} = save(attrs())
    refute MenuRecipes.readiness(draft).ready?
    assert hd(draft.items).menu_text == nil

    booking =
      menu_booking_fixture(%{
        check_in_date: ~D[2027-01-09],
        check_out_date: ~D[2027-01-09],
        first_meal: "lunch",
        last_meal: "lunch"
      })

    assert {:error, {:invalid_menu, _}} = MenuPlanning.assign_variant(booking.id, draft.id)
    assert MenuPlanning.get_booking_menu(booking.id) == nil
    recipe = recipe_fixture()

    params =
      MenuRecipes.variant_params(draft) |> put_in(["items", Access.at(0), "recipe_id"], recipe.id)

    assert {:ok, ready} = MenuRecipes.save_variant(draft, params)
    assert MenuRecipes.readiness(ready).ready?
    assert {:ok, _} = MenuPlanning.assign_variant(booking.id, ready.id)
  end

  test "links and ordered supplements save atomically with settings; client wording is ignored" do
    main = recipe_fixture()
    first = recipe_fixture()
    second = recipe_fixture()

    params =
      attrs(main.id)
      |> put_in(["items", Access.at(0), "supplement_recipe_ids"], [second.id, first.id])
      |> put_in(["items", Access.at(0), "menu_text"], "Spoofed title")

    assert {:ok, menu} = save(params)
    item = hd(menu.items)
    assert item.menu_text == nil
    assert MenuRecipes.display(item).main == main.name
    assert Links.supplement_ids(item) == [second.id, first.id]
    assert item.recipe_links_reviewed_at

    assert {:error, :stale_variant} =
             MenuRecipes.save_variant(%{menu | lock_version: 0}, MenuRecipes.variant_params(menu))
  end

  test "unknown IDs, foreign item IDs and duplicate recipes roll back the entire menu" do
    main = recipe_fixture()
    {:ok, menu} = save(attrs(main.id))
    other = variant_fixture()

    for {field, value} <- [
          {"recipe_id", Ecto.UUID.generate()},
          {"recipe_id", "bad-id"},
          {"id", hd(other.items).id},
          {"supplement_recipe_ids", ["bad-id"]},
          {"supplement_recipe_ids", [Ecto.UUID.generate()]},
          {"supplement_recipe_ids", [main.id]},
          {"supplement_recipe_ids", [main.id, main.id]}
        ] do
      params =
        MenuRecipes.variant_params(menu)
        |> Map.put("name", "Must not save")
        |> put_in(["items", Access.at(0), field], value)

      assert {:error, _} = MenuRecipes.save_variant(menu, params)
      assert MenuPlanning.get_variant!(menu.id).name == menu.name
      assert hd(MenuPlanning.get_variant!(menu.id).items).recipe_id == main.id
    end
  end

  test "invalid recipe IDs roll back booking edits without changing notes or links" do
    booking = menu_booking_fixture()
    item = hd(assign_variant(booking, variant_fixture()).items)
    version = Links.version(item)

    for {field, value} <- [
          {"recipe_id", "bad-id"},
          {"recipe_id", Ecto.UUID.generate()},
          {"supplement_recipe_ids", ["bad-id"]},
          {"supplement_recipe_ids", [Ecto.UUID.generate()]}
        ] do
      params =
        MenuRecipes.item_params(item)
        |> Map.put("note", "Must not save")
        |> Map.put(field, value)

      assert {:error, _} = MenuRecipes.save_booking_item(booking.id, item.id, params, version)
      saved = Links.load!("booking", item.id)
      assert saved.note == item.note
      assert saved.recipe_id == item.recipe_id
      assert Links.supplement_ids(saved) == Links.supplement_ids(item)
      assert Links.version(saved) == version
    end
  end

  test "legacy main and supplements require explicit review; reviewed wording never affects consumption" do
    main = recipe_fixture()
    variant = legacy_variant_fixture()
    item = hd(variant.items)
    assert MenuRecipes.legacy?(item)

    params =
      MenuRecipes.variant_params(variant) |> put_in(["items", Access.at(0), "recipe_id"], main.id)

    assert {:ok, unreviewed} = MenuRecipes.save_variant(variant, params)
    assert MenuRecipes.legacy?(hd(unreviewed.items))

    params =
      MenuRecipes.variant_params(unreviewed) |> put_in(["items", Access.at(0), "reviewed"], true)

    assert {:ok, reviewed} = MenuRecipes.save_variant(unreviewed, params)
    refute MenuRecipes.legacy?(hd(reviewed.items))
    assert hd(reviewed.items).menu_text == item.menu_text
    assert MenuRecipes.display(hd(reviewed.items)).main == main.name
    assert MenuRecipes.issues(hd(reviewed.items)) == []
    assert {:ok, _} = Recipes.update_recipe(main, %{name: "Přejmenovaný recept #{main.id}"})

    assert MenuRecipes.display(hd(MenuPlanning.get_variant!(reviewed.id).items)).main =~
             "Přejmenovaný recept"
  end

  test "archived references can stay and be duplicated as drafts, but cannot be newly selected or assigned" do
    recipe = recipe_fixture()
    variant = variant_fixture()
    item = hd(variant.items)
    {:ok, _} = Links.save("variant", item.id, recipe.id, [], Links.version(item))
    variant = MenuPlanning.get_variant!(variant.id)
    booking = menu_booking_fixture()
    menu = assign_variant(booking, variant)
    assert {:ok, _} = Recipes.archive_recipe(recipe)
    params = MenuRecipes.variant_params(MenuPlanning.get_variant!(variant.id))
    assert {:ok, retained} = MenuRecipes.save_variant(variant, params)
    refute MenuRecipes.readiness(retained).ready?
    assert {:ok, copy} = MenuRecipes.duplicate(retained)
    refute MenuRecipes.readiness(copy).ready?
    assert hd(copy.items).recipe_id == recipe.id
    assert {:error, :unavailable_recipe} = save(attrs(recipe.id))

    assert {:error, {:invalid_menu, _}} =
             MenuPlanning.assign_variant(menu_booking_fixture().id, retained.id)

    assert {:ok, result} = CozyCheckout.Recipes.Consumption.for_booking_item(hd(menu.items).id)
    assert Enum.any?(result.recipes, &(&1.id == recipe.id))
  end

  test "booking notes preserve links, protect manual changes and detect same-second conflicts" do
    variant = variant_fixture()
    booking = menu_booking_fixture()
    item = hd(assign_variant(booking, variant).items)
    version = Links.version(item)
    params = MenuRecipes.item_params(item) |> Map.put("note", "Bez cibule")
    assert {:ok, edited} = MenuRecipes.save_booking_item(booking.id, item.id, params, version)
    assert edited.recipe_id == item.recipe_id
    assert Links.supplement_ids(edited) == Links.supplement_ids(item)
    assert edited.manually_edited

    assert {:error, :stale_item} =
             MenuRecipes.save_booking_item(booking.id, item.id, params, version)

    reapplied = assign_variant(booking, variant)
    assert hd(reapplied.items).note == "Bez cibule"
    other_booking = menu_booking_fixture()

    assert {:error, :stale_item} =
             MenuRecipes.save_booking_item(
               other_booking.id,
               item.id,
               params,
               Links.version(edited)
             )
  end

  test "renaming recipes updates assigned history and grouped menus without marking manual edits" do
    recipe = recipe_fixture()
    variant = variant_fixture()
    item = hd(variant.items)
    {:ok, _} = Links.save("variant", item.id, recipe.id, [], Links.version(item))

    booking =
      menu_booking_fixture(%{
        check_in_date: ~D[2020-01-03],
        check_out_date: ~D[2020-01-05],
        status: "completed"
      })

    menu = assign_variant(booking, MenuPlanning.get_variant!(variant.id))
    {:ok, renamed} = Recipes.update_recipe(recipe, %{name: "Nové jméno #{recipe.id}"})
    stored = hd(MenuPlanning.get_booking_menu(booking.id).items)
    assert MenuRecipes.display(stored).main == renamed.name
    refute stored.manually_edited

    [group] =
      MenuPlanning.kitchen_for_range(~D[2020-01-03], ~D[2020-01-03]).groups[
        {~D[2020-01-03], "dinner"}
      ]

    assert group.menu_text == renamed.name
    assert {:ok, result} = CozyCheckout.Recipes.Consumption.for_booking_item(hd(menu.items).id)
    refute Enum.any?(result.issues, &String.contains?(&1, "Původní"))
  end

  test "legacy booking data remains a partial calculation with actionable warnings" do
    booking = menu_booking_fixture()
    menu = assign_variant(booking, variant_fixture())
    item = hd(menu.items)

    Repo.update!(
      Ecto.Changeset.change(item,
        recipe_links_reviewed_at: nil,
        supplements: "Nedohledaná příloha"
      )
    )

    assert {:ok, result} =
             CozyCheckout.Kitchen.ShoppingList.generate(
               booking.check_in_date,
               booking.check_out_date,
               booking.id
             )

    assert result.rows != []
    assert result.covered_services < result.services
    assert Enum.any?(result.issues, &String.contains?(&1.message, "Nedohledaná příloha"))
    assert Repo.get!(BookingMenuItem, item.id).supplements == "Nedohledaná příloha"
  end

  test "menu list preloads all recipe names with a constant number of queries" do
    variant_fixture()
    {_, first_queries} = QueryRecorder.record(&MenuPlanning.list_variants/0)
    for _ <- 1..4, do: variant_fixture()
    {variants, many_queries} = QueryRecorder.record(&MenuPlanning.list_variants/0)
    assert length(first_queries) == length(many_queries)

    {_, display_queries} =
      QueryRecorder.record(fn -> Enum.each(variants, &MenuRecipes.readiness/1) end)

    assert display_queries == []
  end

  test "past shopping quantities and fingerprints follow changed ingredients, not recipe snapshots" do
    ingredient = ingredient_fixture(%{purchase_mode: "Průběžně"})
    recipe = recipe_fixture(ingredient)
    variant = variant_fixture()
    first = hd(variant.items)
    {:ok, _} = Links.save("variant", first.id, recipe.id, [], Links.version(first))

    booking =
      menu_booking_fixture(%{
        check_in_date: ~D[2020-01-03],
        check_out_date: ~D[2020-01-05],
        status: "completed"
      })

    assign_variant(booking, MenuPlanning.get_variant!(variant.id))

    {:ok, before} =
      CozyCheckout.Kitchen.ShoppingList.generate(
        booking.check_in_date,
        booking.check_out_date,
        booking.id
      )

    before_row = Enum.find(before.rows, &(&1.id == ingredient.id))
    [line] = recipe.lines

    {:ok, _} =
      Recipes.update_recipe(recipe, %{
        lines: [%{id: line.id, ingredient_id: ingredient.id, quantity: "4", unit: "kg"}]
      })

    {:ok, after_change} =
      CozyCheckout.Kitchen.ShoppingList.generate(
        booking.check_in_date,
        booking.check_out_date,
        booking.id
      )

    after_row = Enum.find(after_change.rows, &(&1.id == ingredient.id))
    assert Decimal.equal?(after_row.quantity, Decimal.mult(before_row.quantity, 2))
    refute after_row.fingerprint == before_row.fingerprint
  end

  test "template edits remain independent from assigned recipe selections" do
    variant = variant_fixture()
    booking = menu_booking_fixture()
    menu = assign_variant(booking, variant)
    original = hd(menu.items)
    replacement = recipe_fixture()

    params =
      MenuRecipes.variant_params(variant)
      |> put_in(["items", Access.at(0), "recipe_id"], replacement.id)

    assert {:ok, _} = MenuRecipes.save_variant(variant, params)
    assert hd(MenuPlanning.get_booking_menu(booking.id).items).recipe_id == original.recipe_id
    refute hd(MenuPlanning.get_booking_menu(booking.id).items).manually_edited
  end
end

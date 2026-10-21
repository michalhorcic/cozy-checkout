defmodule CozyCheckout.Recipes.LinksTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.RecipeFixtures
  import CozyCheckout.MenuFixtures
  alias CozyCheckout.Recipes
  alias CozyCheckout.Recipes.Links
  alias CozyCheckout.Meals.MenuPlanning

  test "exact source names bind main and soup; booking receives independent recipe links" do
    main = recipe_fixture()
    soup = recipe_fixture()
    attrs = variant_attrs()

    items =
      Enum.map(
        attrs.items,
        &Map.merge(&1, %{menu_text: main.name, supplements: "Polévka k obědu: #{soup.name}"})
      )

    {:ok, variant} = MenuPlanning.create_variant(%{attrs | items: items})
    assert Enum.all?(variant.items, &(&1.recipe_id == main.id))
    assert Links.supplement_ids(hd(variant.items)) == [soup.id]
    booking = menu_booking_fixture()
    menu = assign_variant(booking, variant)
    item = hd(menu.items)
    assert item.recipe_id == main.id
    assert Links.supplement_ids(item) == [soup.id]

    variant_item =
      Enum.find(
        variant.items,
        &(&1.day_number == item.day_number and &1.meal_type == item.meal_type)
      )

    assert {:ok, _} =
             Links.save("variant", variant_item.id, soup.id, [], Links.version(variant_item))

    unchanged = Links.load!("booking", item.id)
    assert unchanged.recipe_id == main.id
    assert Links.supplement_ids(unchanged) == [soup.id]
  end

  test "manual booking recipe choice survives another variant application and stale editors fail" do
    variant = variant_fixture()
    booking = menu_booking_fixture()
    item = hd(assign_variant(booking, variant).items)
    recipe = recipe_fixture()
    extra = recipe_fixture()

    assert {:ok, saved} =
             Links.save(
               "booking",
               item.id,
               recipe.id,
               [extra.id, extra.id, recipe.id],
               Links.version(item)
             )

    assert saved.manually_edited
    assert saved.menu_text == item.menu_text
    assert Links.supplement_ids(saved) == [extra.id]
    assert {:error, :stale} = Links.save("booking", item.id, nil, [], Links.version(item))
    assign_variant(booking, variant)
    retained = Links.load!("booking", item.id)
    assert retained.recipe_id == recipe.id
    assert Links.supplement_ids(retained) == [extra.id]
  end

  test "recipe-link change invalidates an already reviewed variant preview" do
    variant = variant_fixture()
    booking = menu_booking_fixture()
    {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
    item = hd(variant.items)
    recipe = recipe_fixture()
    assert {:ok, _} = Links.save("variant", item.id, recipe.id, [], Links.version(item))

    assert {:error, :stale_preview} =
             MenuPlanning.apply_variant(booking.id, variant.id, preview.token)
  end

  test "supplement-only change invalidates the booking item version and preview" do
    variant = variant_fixture()
    booking = menu_booking_fixture()
    item = hd(assign_variant(booking, variant).items)
    recipe = recipe_fixture()
    {:ok, first} = Links.save("booking", item.id, recipe.id, [], Links.version(item))
    {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
    extra = recipe_fixture()
    {:ok, _} = Links.save("booking", item.id, recipe.id, [extra.id], Links.version(first))

    assert {:error, :stale_item} =
             MenuPlanning.update_booking_item(
               booking.id,
               item.id,
               %{menu_text: "Stará editace"},
               Links.version(first)
             )

    assert {:error, :stale_preview} =
             MenuPlanning.apply_variant(booking.id, variant.id, preview.token)
  end

  test "archived recipes remain usable in existing menus but cannot be newly selected" do
    variant = variant_fixture()
    item = hd(variant.items)
    recipe = recipe_fixture()
    {:ok, saved} = Links.save("variant", item.id, recipe.id, [], Links.version(item))
    assert {:ok, _} = Recipes.archive_recipe(recipe)
    assert {:ok, _} = Links.save("variant", item.id, recipe.id, [], Links.version(saved))
    other = Enum.at(variant.items, 1)

    assert {:error, :unavailable_recipe} =
             Links.save("variant", other.id, recipe.id, [], Links.version(other))

    booking = menu_booking_fixture()
    menu = assign_variant(booking, MenuPlanning.get_variant!(variant.id))
    linked = Enum.find(menu.items, &(&1.recipe_id == recipe.id))
    assert {:ok, %{recipes: [_]}} = CozyCheckout.Recipes.Consumption.for_booking_item(linked.id)
  end

  test "rebuilding and saving a variant preserves links at existing service coordinates" do
    variant = variant_fixture()
    item = hd(variant.items)
    recipe = recipe_fixture()
    {:ok, _} = Links.save("variant", item.id, recipe.id, [], Links.version(item))
    current = MenuPlanning.get_variant!(variant.id)
    form = MenuPlanning.variant_form(current, %{name: "Přejmenovaná varianta"})
    assert {:ok, _} = Repo.update(Ecto.Changeset.optimistic_lock(form, :lock_version))
    assert Links.load!("variant", item.id).recipe_id == recipe.id
  end

  test "changing dish text clears obsolete quantities while leaving other courses linked" do
    variant = variant_fixture()
    item = hd(variant.items)
    main = recipe_fixture()
    soup = recipe_fixture()
    {:ok, _} = Links.save("variant", item.id, main.id, [soup.id], Links.version(item))
    booking = menu_booking_fixture()
    booking_item = hd(assign_variant(booking, MenuPlanning.get_variant!(variant.id)).items)

    {:ok, _} =
      MenuPlanning.update_booking_item(
        booking.id,
        booking_item.id,
        %{menu_text: "Úplně jiný chod"},
        Links.version(booking_item)
      )

    changed = Links.load!("booking", booking_item.id)
    assert is_nil(changed.recipe_id)
    assert Links.supplement_ids(changed) == [soup.id]

    current = MenuPlanning.get_variant!(variant.id)

    items =
      Enum.map(current.items, fn i ->
        Map.take(i, [:id, :day_number, :meal_type, :menu_text, :supplements])
        |> Map.put(:supplements, "Změněný doplněk")
      end)

    {:ok, _} = MenuPlanning.update_variant(current, %{items: items})
    changed = Links.load!("variant", item.id)
    assert changed.recipe_id == main.id
    assert Links.supplement_ids(changed) == []
  end
end

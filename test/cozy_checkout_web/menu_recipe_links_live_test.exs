defmodule CozyCheckoutWeb.MenuRecipeLinksLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.MenuFixtures
  import CozyCheckout.RecipeFixtures
  alias CozyCheckout.Meals.MenuPlanning
  alias CozyCheckout.Recipes.Links
  alias CozyCheckoutWeb.AdminAuth

  setup %{conn: conn} do
    previous = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, previous),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    {:ok,
     conn:
       Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})}
  end

  defp search(view, id, query),
    do: view |> form("#menu-editor-#{id}-search", recipe_search: query) |> render_change()

  test "main and ordered extras are edited in the same form and cancel writes nothing", %{
    conn: conn
  } do
    main = recipe_fixture()
    extra = recipe_fixture()
    variant = variant_fixture()
    first = hd(variant.items)
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/#{variant.id}/edit")
    search(view, variant.id, main.name)

    view
    |> element("#editor-recipe-#{main.id} button[phx-click='select_recipe']")
    |> render_click()

    assert has_element?(view, "#menu-slot-0", main.name)

    assert MenuPlanning.get_variant!(variant.id).items |> hd() |> Map.get(:recipe_id) ==
             first.recipe_id

    view
    |> element("#menu-slot-0 button[phx-click='activate'][phx-value-role='extra']")
    |> render_click()

    search(view, variant.id, extra.name)

    view
    |> element("#editor-recipe-#{extra.id} button[phx-click='select_recipe']")
    |> render_click()

    assert has_element?(view, "#menu-slot-0", extra.name)
    view |> form("#menu-editor-#{variant.id}-form") |> render_submit()
    updated = hd(MenuPlanning.get_variant!(variant.id).items)
    assert updated.recipe_id == main.id
    assert Links.supplement_ids(updated) == [extra.id]
  end

  test "drag payload uses the same server validation and undo restores the selection", %{
    conn: conn
  } do
    main = recipe_fixture()
    variant = variant_fixture()
    old = hd(variant.items).recipe.name
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/#{variant.id}/edit")

    view
    |> element("#menu-editor-#{variant.id}")
    |> render_hook("drop_recipe", %{index: "0", role: "main", id: main.id})

    assert has_element?(view, "#menu-slot-0", main.name)
    view |> element("button[phx-click='undo']") |> render_click()
    assert has_element?(view, "#menu-slot-0", old)

    view
    |> element("#menu-editor-#{variant.id}")
    |> render_hook("drop_recipe", %{index: "0", role: "main", id: "invalid"})

    assert has_element?(view, "[role='alert']", "Neplatný výběr")
    assert MenuPlanning.get_variant!(variant.id).lock_version == variant.lock_version
  end

  test "legacy evidence is visible and explicit review is saved without becoming a note", %{
    conn: conn
  } do
    variant = legacy_variant_fixture()
    original = hd(variant.items)
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/#{variant.id}/edit")
    assert has_element?(view, "#menu-slot-0", original.menu_text)

    view
    |> form("#menu-editor-#{variant.id}-form", editor: %{items: %{"0" => %{reviewed: "true"}}})
    |> render_submit()

    saved = hd(MenuPlanning.get_variant!(variant.id).items)
    assert saved.recipe_links_reviewed_at
    assert saved.note == nil
    assert saved.menu_text == original.menu_text
    assert saved.recipe_id == nil
  end

  test "copying a day shows impact and respects destination meal boundaries", %{conn: conn} do
    variant = variant_fixture()
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/#{variant.id}/edit")
    # Day 2 breakfast is the active source; only dinner exists on destination day 1.
    view
    |> element("#menu-slot-1 button[phx-click='activate'][phx-value-role='main']")
    |> render_click()

    view
    |> form("#menu-editor-#{variant.id}-form", editor: %{transfer_day: "1"})
    |> render_change()

    view |> element("button[phx-click='copy_day']") |> render_click()
    assert has_element?(view, "#menu-impact")
    view |> element("#menu-impact button[phx-click='confirm']") |> render_click()
    source_dinner = Enum.find(variant.items, &(&1.day_number == 2 && &1.meal_type == "dinner"))
    assert has_element?(view, "#menu-slot-0", source_dinner.recipe.name)
    view |> form("#menu-editor-#{variant.id}-form") |> render_submit()
    saved = MenuPlanning.get_variant!(variant.id)
    assert length(saved.items) == 5
    assert hd(saved.items).recipe_id == source_dinner.recipe_id
  end

  test "paged searches preserve selected recipes outside results", %{conn: conn} do
    ingredient = ingredient_fixture()
    prefix = "Picker pagination #{System.unique_integer([:positive])}"

    recipes =
      for n <- 1..32,
          do:
            recipe_fixture(ingredient, %{
              name: "#{prefix} #{String.pad_leading(to_string(n), 2, "0")}"
            })

    variant = variant_fixture()
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/#{variant.id}/edit")
    search(view, variant.id, prefix)
    last = List.last(recipes)
    refute has_element?(view, "#editor-recipe-#{last.id}")
    view |> element("button[phx-click='more']") |> render_click()
    assert has_element?(view, "#editor-recipe-#{last.id}")

    view
    |> element("#editor-recipe-#{last.id} button[phx-click='select_recipe']")
    |> render_click()

    search(view, variant.id, "no matching recipe")
    assert has_element?(view, "#menu-slot-0", last.name)
    refute has_element?(view, "#editor-recipe-#{last.id}")
  end

  test "old variant link editor redirects to the integrated editor", %{conn: conn} do
    variant = variant_fixture()
    item = hd(variant.items)

    assert {:error, {:live_redirect, %{to: path}}} =
             live(conn, "/admin/recipes/menu/variant/#{item.id}")

    assert path =~ "/admin/meal-planner/variants/#{variant.id}/edit"
    assert path =~ "slot=#{item.id}"
  end

  test "breakfast propagation can be undone and supplement order is explicit", %{conn: conn} do
    variant = variant_fixture()
    first_extra = recipe_fixture()
    second_extra = recipe_fixture()
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/#{variant.id}/edit")

    view
    |> element("#menu-slot-1 button[phx-click='activate'][phx-value-role='main']")
    |> render_click()

    view |> element("button[phx-click='breakfasts']") |> render_click()
    view |> element("#menu-impact button[phx-click='confirm']") |> render_click()
    assert has_element?(view, "#menu-slot-4", Enum.at(variant.items, 1).recipe.name)
    view |> element("button[phx-click='undo']") |> render_click()
    assert has_element?(view, "#menu-slot-4", Enum.at(variant.items, 4).recipe.name)

    view
    |> element("#menu-slot-0 button[phx-click='activate'][phx-value-role='extra']")
    |> render_click()

    for recipe <- [first_extra, second_extra] do
      search(view, variant.id, recipe.name)

      view
      |> element("#editor-recipe-#{recipe.id} button[phx-click='select_recipe']")
      |> render_click()
    end

    view
    |> element(
      "#menu-slot-0 button[phx-click='reorder'][phx-value-id='#{second_extra.id}'][phx-value-direction='up']"
    )
    |> render_click()

    view |> form("#menu-editor-#{variant.id}-form") |> render_submit()

    assert Links.supplement_ids(hd(MenuPlanning.get_variant!(variant.id).items)) == [
             second_extra.id,
             first_extra.id
           ]
  end
end

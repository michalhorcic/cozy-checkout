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

  test "saved names and state-dependent actions are visible in both variant and booking menus", %{
    conn: conn
  } do
    main = recipe_fixture()
    extra = recipe_fixture()
    variant = variant_fixture()
    item = hd(variant.items)
    {:ok, editor, _} = live(conn, "/admin/meal-planner/variants/#{variant.id}/edit")
    assert has_element?(editor, "#variant-item-recipes-#{item.id} [data-missing-main]")
    assert has_element?(editor, "#variant-item-recipes-#{item.id} a", "Připojit recepty")

    {:ok, picker, _} = live(conn, "/admin/recipes/menu/variant/#{item.id}")
    picker |> element("#choose-main-#{main.id}") |> render_click()
    picker |> element("#choose-extra-#{extra.id}") |> render_click()
    result = picker |> element("#save-recipe-links") |> render_click()

    {:ok, editor, _} =
      follow_redirect(result, conn, "/admin/meal-planner/variants/#{variant.id}/edit")

    assert has_element?(editor, "#variant-item-recipes-#{item.id} [data-linked-main]", main.name)

    assert has_element?(
             editor,
             "#variant-item-recipes-#{item.id} [data-linked-extras]",
             extra.name
           )

    assert has_element?(editor, "#variant-item-recipes-#{item.id} a", "Upravit připojené recepty")

    booking = menu_booking_fixture()
    menu = assign_variant(booking, MenuPlanning.get_variant!(variant.id))
    copied = Enum.find(menu.items, &(&1.recipe_id == main.id))
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/menu")
    assert has_element?(view, "#item-recipes-#{copied.id} [data-linked-main]", main.name)
    assert has_element?(view, "#item-recipes-#{copied.id} [data-linked-extras]", extra.name)
    assert has_element?(view, "#item-recipes-#{copied.id} a", "Upravit připojené recepty")
    missing = Enum.find(menu.items, &is_nil(&1.recipe_id))
    assert has_element?(view, "#item-recipes-#{missing.id} [data-missing-main]")
    assert has_element?(view, "#item-recipes-#{missing.id} a", "Připojit recepty")

    view |> element("#edit-menu-item-#{copied.id}") |> render_click()

    view
    |> form("#booking-menu-item-form", booking_menu_item: %{menu_text: "Změněný hlavní chod"})
    |> render_submit()

    assert has_element?(view, "#item-recipes-#{copied.id} [data-missing-main]")
    refute has_element?(view, "#item-recipes-#{copied.id} [data-linked-main]")
    assert has_element?(view, "#item-recipes-#{copied.id} [data-linked-extras]", extra.name)
  end

  test "an extra-only assignment never looks like a connected main recipe", %{conn: conn} do
    extra = recipe_fixture()
    variant = variant_fixture()
    item = hd(variant.items)
    {:ok, _} = Links.save("variant", item.id, nil, [extra.id], Links.version(item))
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/#{variant.id}/edit")
    assert has_element?(view, "#variant-item-recipes-#{item.id} [data-missing-main]")
    refute has_element?(view, "#variant-item-recipes-#{item.id} [data-linked-main]")
    assert has_element?(view, "#variant-item-recipes-#{item.id} [data-linked-extras]", extra.name)
    assert has_element?(view, "#variant-item-recipes-#{item.id} a", "Upravit připojené recepty")
  end

  test "cards reflect selection and dirty state resets when changes are undone", %{conn: conn} do
    main = recipe_fixture()
    extra = recipe_fixture()
    variant = variant_fixture()
    item = hd(variant.items)
    {:ok, view, _} = live(conn, "/admin/recipes/menu/variant/#{item.id}")
    refute has_element?(view, "#recipe-links-unsaved")
    assert has_element?(view, "#recipe-links-status", "zatím nejsou připojené")
    view |> element("#choose-main-#{main.id}") |> render_click()
    assert has_element?(view, "#recipe-role-#{main.id}", "Hlavní recept")
    assert has_element?(view, "#recipe-choices article[data-selection='main'] .bg-emerald-100")
    assert has_element?(view, "#choose-main-#{main.id}[aria-pressed='true'][disabled]")
    assert has_element?(view, "#recipe-links-unsaved", "Neuložené změny")
    assert Links.load!("variant", item.id).recipe_id == nil

    view |> element("#selected-main-recipe button") |> render_click()
    refute has_element?(view, "#recipe-role-#{main.id}")
    refute has_element?(view, "#recipe-links-unsaved")
    view |> element("#choose-extra-#{extra.id}") |> render_click()
    assert has_element?(view, "#recipe-role-#{extra.id}", "Doplněk")
    assert has_element?(view, "#choose-extra-#{extra.id}[aria-pressed='true'][disabled]")
    view |> element("#selected-extra-#{extra.id} button") |> render_click()
    refute has_element?(view, "#recipe-links-unsaved")
  end

  test "persisted selections stay marked across searches and calculations without becoming dirty",
       %{conn: conn} do
    main = recipe_fixture()
    extra = recipe_fixture()
    variant = variant_fixture()
    item = hd(variant.items)
    {:ok, _} = Links.save("variant", item.id, main.id, [extra.id], Links.version(item))
    {:ok, view, _} = live(conn, "/admin/recipes/menu/variant/#{item.id}")
    assert has_element?(view, "#recipe-links-status", "přiřazení je uložené")
    assert has_element?(view, "#recipe-role-#{main.id}", "Hlavní recept")
    assert has_element?(view, "#recipe-role-#{extra.id}", "Doplněk")
    view |> form("#link-search-form", search: main.name) |> render_change()
    assert has_element?(view, "#recipe-role-#{main.id}")
    refute has_element?(view, "#recipe-role-#{extra.id}")
    view |> form("#link-search-form", search: "") |> render_change()
    assert has_element?(view, "#recipe-role-#{extra.id}")

    view
    |> form("#variant-consumption-calculator", calculator: %{adults: "12", children: "3"})
    |> render_change()

    refute has_element?(view, "#recipe-links-unsaved")
    view |> element("#choose-main-#{extra.id}") |> render_click()
    assert has_element?(view, "#recipe-role-#{extra.id}", "Hlavní recept")
    refute has_element?(view, "#recipe-role-#{main.id}")
    assert has_element?(view, "#recipe-links-unsaved")
    view |> element("#choose-main-#{main.id}") |> render_click()
    view |> element("#choose-extra-#{extra.id}") |> render_click()
    refute has_element?(view, "#recipe-links-unsaved")
  end

  test "variant text changes expose pending disconnection and restoring text restores the saved summary",
       %{conn: conn} do
    main = recipe_fixture()
    extra = recipe_fixture()
    variant = variant_fixture()
    item = hd(variant.items)
    {:ok, _} = Links.save("variant", item.id, main.id, [extra.id], Links.version(item))
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/#{variant.id}/edit")

    view
    |> form("#menu-variant-form",
      menu_variant: %{items: %{"0" => %{menu_text: "Jiný hlavní chod"}}}
    )
    |> render_change()

    assert has_element?(view, "#variant-item-recipes-#{item.id} [data-text-changed]")
    refute has_element?(view, "#variant-item-recipes-#{item.id} [data-linked-main]")
    assert has_element?(view, "#variant-item-recipes-#{item.id} [data-linked-extras]", extra.name)
    refute has_element?(view, "#variant-item-recipes-#{item.id} a")
    assert Links.load!("variant", item.id).recipe_id == main.id

    view
    |> form("#menu-variant-form", menu_variant: %{items: %{"0" => %{menu_text: item.menu_text}}})
    |> render_change()

    refute has_element?(view, "#variant-item-recipes-#{item.id} [data-text-changed]")
    assert has_element?(view, "#variant-item-recipes-#{item.id} [data-linked-main]", main.name)
    assert has_element?(view, "#variant-item-recipes-#{item.id} a", "Upravit připojené recepty")
  end
end

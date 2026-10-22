defmodule CozyCheckoutWeb.FoodNavigationLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.MenuFixtures
  import CozyCheckout.RecipeFixtures
  import CozyCheckout.ShoppingFixtures
  alias CozyCheckout.Recipes
  alias CozyCheckoutWeb.{AdminAuth, FoodNavigation}

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

  test "all food screens expose the same navigation with a single active section", %{conn: conn} do
    recipe = recipe_fixture()
    variant = variant_fixture()
    booking = menu_booking_fixture()
    menu = assign_variant(booking, variant)
    item = hd(menu.items)

    for {path, section} <- [
          {"/admin/meal-planner", :planner},
          {"/admin/kitchen-shopping", :shopping},
          {"/admin/recipes", :recipes},
          {"/admin/recipes/#{recipe.id}", :recipes},
          {"/admin/recipes/#{recipe.id}/edit", :recipes},
          {"/admin/ingredients", :ingredients},
          {"/admin/meal-planner/variants/#{variant.id}/edit", :variants},
          {"/admin/meal-planner/templates", :templates},
          {"/admin/meal-planner/portion-settings", :settings},
          {"/admin/bookings/#{booking.id}/menu", :planner},
          {"/admin/recipes/menu/booking/#{item.id}", :planner},
          {"/admin/recipes/menu/variant/#{hd(variant.items).id}", :variants}
        ] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#food-layout")
      assert has_element?(view, "#food-desktop-#{section}[aria-current='page']")
      assert has_element?(view, "#food-mobile-#{section}[aria-current='page']")
      assert view |> element("#food-desktop a[aria-current='page']") |> render()

      for entry <- [:planner, :shopping, :variants, :recipes, :ingredients, :templates, :settings] do
        assert has_element?(view, "#food-desktop-#{entry}")
        assert has_element?(view, "#food-mobile-#{entry}")
      end
    end
  end

  test "template tools remain usable after navigating from the sidebar", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/recipes")
    result = view |> element("#food-desktop-templates") |> render_click()
    {:ok, templates, _} = follow_redirect(result, conn, "/admin/meal-planner/templates")
    assert has_element?(templates, "#food-main h1", "Šablony textů jídel")
    templates |> element("a[href='/admin/meal-planner/templates/new']") |> render_click()

    templates
    |> form("#template-form",
      meal_template: %{
        name: "Navigační šablona",
        category: "dinner",
        default_menu_text: "Ukázková večeře"
      }
    )
    |> render_submit()

    assert_patch(templates, "/admin/meal-planner/templates")
    assert has_element?(templates, "#meal_templates", "Navigační šablona")
    assert has_element?(templates, "#food-desktop-templates[aria-current='page']")
  end

  test "changing weeks keeps the selected week in the URL and the shopping link", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/meal-planner?week=2027-01-08")
    assert has_element?(view, "#portions-2027-01-03-breakfast")
    view |> element("button[phx-click='next_week']") |> render_click()
    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["from"] == "2027-01-10"
    assert has_element?(view, "#portions-2027-01-10-breakfast")
    result = view |> element("#food-desktop-shopping") |> render_click()
    {:ok, shopping, _} = follow_redirect(result, conn)
    assert has_element?(shopping, "#range_from[value='2027-01-10']")
    assert has_element?(shopping, "#range_to[value='2027-01-16']")
  end

  test "shopping recipe drill-down, edit and return retain the date range and booking", %{
    conn: conn
  } do
    {ingredient, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe)
    range = %{"from" => "2027-01-08", "to" => "2027-01-10", "booking" => booking.id}
    {:ok, shopping, _} = live(conn, FoodNavigation.path(:shopping, range))
    shopping |> element("#shopping-sources-#{ingredient.id} button") |> render_click()

    result =
      shopping
      |> element("#shopping-source-#{ingredient.id}-0 a[href*='adults=']")
      |> render_click()

    {:ok, detail, _} = follow_redirect(result, conn)
    assert has_element?(detail, "#food-back", "Zpět na nákup")
    result = detail |> element("#edit-recipe") |> render_click()
    {:ok, editor, _} = follow_redirect(result, conn)

    result =
      editor
      |> form("#recipe-form", recipe: %{notes: "Zachovat nákupní kontext"})
      |> render_submit()

    {:ok, detail, _} = follow_redirect(result, conn)
    assert has_element?(detail, "#food-back", "Zpět na nákup")
    result = detail |> element("#food-back") |> render_click()
    {:ok, shopping, _} = follow_redirect(result, conn)
    assert has_element?(shopping, "#range_from[value='2027-01-08']")
    assert has_element?(shopping, "#range_to[value='2027-01-10']")
    assert has_element?(shopping, "#range_booking option[value='#{booking.id}'][selected]")
    assert has_element?(shopping, "#shopping-groups", "1")
  end

  test "booking menu offers a purchase scoped to that booking and its stay", %{conn: conn} do
    booking = menu_booking_fixture()
    menu = assign_variant(booking, variant_fixture())
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/menu")
    result = view |> element("#food-desktop-shopping") |> render_click()
    {:ok, shopping, _} = follow_redirect(result, conn)
    assert has_element?(shopping, "#range_booking option[value='#{booking.id}'][selected]")
    assert has_element?(shopping, "#range_from[value='2027-01-08']")
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/menu")
    result = view |> element("#item-recipes-#{hd(menu.items).id} a") |> render_click()
    {:ok, picker, _} = follow_redirect(result, conn)
    assert has_element?(picker, "#food-back", "Zpět k menu rezervace")

    assert has_element?(
             picker,
             "#recipe-link-context",
             CozyCheckout.Guests.get_guest!(booking.guest_id).name
           )
  end

  test "settings validate percentages and reject a stale editor", %{conn: conn} do
    {:ok, first, _} = live(conn, "/admin/meal-planner/portion-settings")
    {:ok, stale, _} = live(conn, "/admin/meal-planner/portion-settings")

    first
    |> form("#portion-settings-form", portions: %{hot: "101", breakfast: "70"})
    |> render_submit()

    assert has_element?(first, "#portion-settings-error", "od 0 do 100")
    assert Decimal.equal?(Recipes.settings().hot_child_factor, "0.7")

    first
    |> form("#portion-settings-form", portions: %{hot: "60", breakfast: "75"})
    |> render_submit()

    assert has_element?(first, "#flash-success")

    stale
    |> form("#portion-settings-form", portions: %{hot: "50", breakfast: "50"})
    |> render_submit()

    assert has_element?(stale, "#portion-settings-error", "mezitím změnil")
    assert Decimal.equal?(Recipes.settings().hot_child_factor, "0.6")
  end

  test "portion settings require the same admin authentication" do
    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(Phoenix.ConnTest.build_conn(), "/admin/meal-planner/portion-settings")
  end
end

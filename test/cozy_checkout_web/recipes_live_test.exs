defmodule CozyCheckoutWeb.RecipesLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.RecipeFixtures
  import CozyCheckout.MenuFixtures
  alias CozyCheckout.Recipes
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

  test "library searches without accents and recipe detail recalculates adults and children", %{
    conn: conn
  } do
    ingredient = ingredient_fixture(%{name: "Červená čočka pro UI"})
    recipe = recipe_fixture(ingredient, %{name: "Čočková polévka pro UI"})
    {:ok, view, _} = live(conn, "/admin/recipes")
    assert has_element?(view, "#recipes-#{recipe.id}")
    view |> form("#recipe-search-form", search: "cockova polevka pro ui") |> render_change()
    assert has_element?(view, "#recipe-count", "1 recept")
    assert has_element?(view, "#recipes-#{recipe.id}")
    view |> form("#recipe-search-form", search: "neexistujici_recept_abc") |> render_change()
    refute has_element?(view, "#recipes-#{recipe.id}")

    {:ok, detail, _} = live(conn, "/admin/recipes/#{recipe.id}")

    detail
    |> form("#recipe-calculator", calculator: %{adults: "10", children: "5", percent: "70"})
    |> render_change()

    assert has_element?(detail, "#actual-portions", "15")
    assert has_element?(detail, "#consumption-#{ingredient.id}", "2,7 kg")

    detail
    |> form("#recipe-calculator", calculator: %{adults: "-1", children: "5", percent: "70"})
    |> render_change()

    assert has_element?(detail, "#calculator-error")
  end

  test "recipe creation, nested line removal and editing preserve entered values", %{conn: conn} do
    ingredient = ingredient_fixture()
    {:ok, view, _} = live(conn, "/admin/recipes/new")

    params = %{
      name: "Recept z formuláře",
      base_servings: "10",
      lines: %{"0" => %{ingredient_id: ingredient.id, quantity: "500", unit: "g"}}
    }

    view |> form("#recipe-form", recipe: params) |> render_change()
    view |> element("#add-recipe-line") |> render_click()
    assert has_element?(view, "#recipe_lines_1_quantity")
    view |> element("button[phx-click='remove_line'][phx-value-index='1']") |> render_click()
    refute has_element?(view, "#recipe_lines_1_quantity")
    assert has_element?(view, "#recipe_name[value='Recept z formuláře']")
    view |> form("#recipe-form") |> render_submit()
    [recipe] = Recipes.list_recipes("Recept z formuláře")
    assert_redirect(view, "/admin/recipes/#{recipe.id}")
    assert Decimal.equal?(hd(recipe.lines).quantity, "500")

    {:ok, editor, _} = live(conn, "/admin/recipes/#{recipe.id}/edit")

    editor
    |> form("#recipe-form", recipe: %{name: "Upravený recept z formuláře"})
    |> render_submit()

    assert_redirect(editor, "/admin/recipes/#{recipe.id}")
    assert Recipes.get_recipe!(recipe.id).name == "Upravený recept z formuláře"
  end

  test "invalid recipe shows inline errors and does not save", %{conn: conn} do
    ingredient = ingredient_fixture()
    {:ok, view, _} = live(conn, "/admin/recipes/new")

    view
    |> form("#recipe-form",
      recipe: %{
        name: "Chybný recept UI",
        base_servings: "10",
        lines: %{"0" => %{ingredient_id: ingredient.id, quantity: "1", unit: "l"}}
      }
    )
    |> render_submit()

    assert has_element?(view, "#recipe-form", "Jednotka neodpovídá")
    assert Recipes.list_recipes("Chybný recept UI") == []
  end

  test "ingredient modal creates and searches, and prevents a used base unit change", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/admin/ingredients/new")

    view
    |> form("#ingredient-form",
      ingredient: %{name: "Nová UI surovina", category: "Zelenina", base_unit: "kg"}
    )
    |> render_submit()

    assert_patch(view, "/admin/ingredients")
    [ingredient] = Recipes.list_ingredients("Nová UI surovina")
    assert has_element?(view, "#ingredients-#{ingredient.id}")
    recipe_fixture(ingredient)
    view |> element("#ingredients-#{ingredient.id} a") |> render_click()
    view |> form("#ingredient-form", ingredient: %{base_unit: "l"}) |> render_submit()
    assert has_element?(view, "#ingredient-form", "Jednotku používané suroviny nelze změnit")
  end

  test "portion settings accept percentages but leave actual portions independent", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/recipes")
    view |> element("#portion-settings") |> render_click()
    assert has_element?(view, "#portion-settings-form")

    view
    |> form("#portion-settings-form", portions: %{hot: "50", breakfast: "80"})
    |> render_submit()

    refute has_element?(view, "#portion-settings-form")
    assert Decimal.equal?(Recipes.settings().hot_child_factor, "0.5")
    assert Decimal.equal?(Recipes.settings().breakfast_child_factor, "0.8")
  end

  test "variant selects main plus supplement and booking calculates for its own group", %{
    conn: conn
  } do
    ingredient = ingredient_fixture()
    recipe = recipe_fixture(ingredient)
    extra = recipe_fixture(ingredient)
    variant = variant_fixture()
    item = hd(variant.items)
    {:ok, view, _} = live(conn, "/admin/recipes/menu/variant/#{item.id}")
    view |> element("#choose-main-#{recipe.id}") |> render_click()
    view |> element("#choose-extra-#{extra.id}") |> render_click()
    assert has_element?(view, "#selected-main-recipe", recipe.name)
    assert has_element?(view, "#selected-extra-#{extra.id}")

    view
    |> form("#variant-consumption-calculator", calculator: %{adults: "10", children: "5"})
    |> render_change()

    assert has_element?(view, "#menu-consumption-#{ingredient.id}", "5,4 kg")
    view |> element("#save-recipe-links") |> render_click()
    assert_redirect(view, "/admin/meal-planner/variants/#{variant.id}/edit")
    assert Links.load!("variant", item.id).recipe_id == recipe.id

    booking = menu_booking_fixture()
    menu = assign_variant(booking, CozyCheckout.Meals.MenuPlanning.get_variant!(variant.id))
    saved = Enum.find(menu.items, &(&1.recipe_id == recipe.id))
    {:ok, group, _} = live(conn, "/admin/recipes/menu/booking/#{saved.id}")
    assert has_element?(group, "#menu-consumption", "15 porcí pro výdej")
    assert has_element?(group, "#menu-consumption-#{ingredient.id}", "5,4 kg")
    refute has_element?(group, "#variant-consumption-calculator")
    group |> element("#selected-extra-#{extra.id} button") |> render_click()
    group |> element("#save-recipe-links") |> render_click()
    assert Links.load!("booking", saved.id).manually_edited
    assert Links.supplement_ids(Links.load!("booking", saved.id)) == []
  end

  test "stale booking blocks ingredient calculation and saving", %{conn: conn} do
    booking = menu_booking_fixture()
    item = hd(assign_variant(booking, variant_fixture()).items)
    {:ok, _} = CozyCheckout.Bookings.update_booking(booking, %{last_meal: "lunch"})
    {:ok, view, _} = live(conn, "/admin/recipes/menu/booking/#{item.id}")
    assert has_element?(view, "#recipe-link-blocked")
    assert has_element?(view, "#save-recipe-links[disabled]")
    refute has_element?(view, "#menu-consumption")
  end

  test "recipe and ingredient routes require admin login" do
    conn = Phoenix.ConnTest.build_conn()

    for route <- ["/admin/recipes", "/admin/recipes/new", "/admin/ingredients"] do
      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, route)
    end
  end

  test "new ingredient can be created inline without losing a drafted recipe", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/recipes/new")

    view
    |> form("#recipe-form", recipe: %{name: "Rozpracovaný recept", base_servings: "8"})
    |> render_change()

    view |> element("#quick-new-ingredient") |> render_click()

    view
    |> form("#quick-ingredient-form",
      ingredient: %{name: "Inline UI surovina", category: "Mléčné", base_unit: "l"}
    )
    |> render_submit()

    [ingredient] = Recipes.list_ingredients("Inline UI surovina")
    refute has_element?(view, "#quick-ingredient-form")
    assert has_element?(view, "#recipe_name[value='Rozpracovaný recept']")

    assert has_element?(
             view,
             "#recipe_lines_0_ingredient_id option[value='#{ingredient.id}'][selected]"
           )

    assert has_element?(view, "#recipe_lines_0_unit option[value='l'][selected]")

    view
    |> form("#recipe-form", recipe: %{lines: %{"0" => %{quantity: "1.25"}}})
    |> render_submit()

    [recipe] = Recipes.list_recipes("Rozpracovaný recept")
    assert_redirect(view, "/admin/recipes/#{recipe.id}")
    assert hd(recipe.lines).ingredient_id == ingredient.id
  end

  test "source attribution stays plain text unless it is a valid web URL", %{conn: conn} do
    recipe =
      recipe_fixture(ingredient_fixture(), %{source_reference: "Mr. Cook - vlastní recept"})

    {:ok, view, _} = live(conn, "/admin/recipes/#{recipe.id}")
    assert has_element?(view, "#recipe-source-attribution", "Mr. Cook")
    refute has_element?(view, "a[href='Mr. Cook - vlastní recept']")
    assert is_nil(Recipes.source_url(%{source_reference: "javascript:alert(1)"}))

    assert Recipes.source_url(%{source_reference: "https://example.com/recept"}) ==
             "https://example.com/recept"
  end

  test "removing persisted ingredient lines keeps edits and saves the remaining line", %{
    conn: conn
  } do
    ingredient = ingredient_fixture()

    recipe =
      recipe_fixture(ingredient, %{
        lines: [
          %{ingredient_id: ingredient.id, quantity: "1", unit: "kg"},
          %{ingredient_id: ingredient.id, quantity: "2", unit: "kg"},
          %{ingredient_id: ingredient.id, quantity: "3", unit: "kg"}
        ]
      })

    last_id = List.last(recipe.lines).id
    {:ok, view, _} = live(conn, "/admin/recipes/#{recipe.id}/edit")

    view
    |> form("#recipe-form",
      recipe: %{notes: "Zachovat poznámku", lines: %{"2" => %{quantity: "4"}}}
    )
    |> render_change()

    view |> element("button[phx-click='remove_line'][phx-value-index='0']") |> render_click()
    view |> element("button[phx-click='remove_line'][phx-value-index='0']") |> render_click()
    refute has_element?(view, "#recipe_lines_1_quantity")
    view |> form("#recipe-form") |> render_submit()
    assert_redirect(view, "/admin/recipes/#{recipe.id}")
    saved = Recipes.get_recipe!(recipe.id)
    assert [line] = saved.lines
    assert line.id == last_id
    assert Decimal.equal?(line.quantity, "4")
    assert saved.notes == "Zachovat poznámku"
  end

  test "removing the last ingredient shows an error and allows adding a replacement", %{
    conn: conn
  } do
    ingredient = ingredient_fixture()
    recipe = recipe_fixture(ingredient)
    {:ok, view, _} = live(conn, "/admin/recipes/#{recipe.id}/edit")

    view |> element("button[phx-click='remove_line'][phx-value-index='0']") |> render_click()
    refute has_element?(view, "#recipe_lines_0_quantity")
    view |> form("#recipe-form", recipe: %{notes: "Bez surovin"}) |> render_change()
    refute has_element?(view, "#recipe_lines_0_quantity")
    view |> form("#recipe-form") |> render_submit()

    assert has_element?(
             view,
             "#recipe-lines-errors[role='alert']",
             "Přidejte alespoň jednu surovinu"
           )

    assert Recipes.get_recipe!(recipe.id).lines == recipe.lines

    view |> element("#add-recipe-line") |> render_click()

    view
    |> form("#recipe-form",
      recipe: %{
        lines: %{
          "0" => %{
            ingredient_id: ingredient.id,
            quantity: "5",
            unit: "kg"
          }
        }
      }
    )
    |> render_submit()

    assert_redirect(view, "/admin/recipes/#{recipe.id}")
    assert [line] = Recipes.get_recipe!(recipe.id).lines
    assert line.id != hd(recipe.lines).id
    assert Decimal.equal?(line.quantity, "5")
  end
end

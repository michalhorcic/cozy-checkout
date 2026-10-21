defmodule CozyCheckoutWeb.ShoppingLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.MenuFixtures
  import CozyCheckout.ShoppingFixtures
  alias CozyCheckout.Recipes
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

  defp path(booking \\ "") do
    "/admin/kitchen-shopping?" <>
      URI.encode_query(%{from: "2027-01-08", to: "2027-01-10", booking: booking})
  end

  test "shopping displays totals, recipe provenance and contextual recipe calculator", %{
    conn: conn
  } do
    {ingredient, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe)
    {:ok, view, _} = live(conn, path())
    assert has_element?(view, "#shopping-total", "1")
    assert has_element?(view, "#shopping-coverage", "5")
    assert has_element?(view, "#shopping-buy-#{ingredient.id}", "14 kg")
    assert has_element?(view, "#shopping-consumption-#{ingredient.id}", "13,5 kg")
    refute has_element?(view, "#shopping-breakdown-#{ingredient.id}")
    view |> element("#shopping-sources-#{ingredient.id} button") |> render_click()
    assert has_element?(view, "#shopping-sources-#{ingredient.id} button[aria-expanded='true']")
    assert has_element?(view, "#shopping-sources-#{ingredient.id}", recipe.name)
    assert has_element?(view, "#shopping-sources-#{ingredient.id}", booking.guest.name)

    assert has_element?(
             view,
             "#shopping-sources-#{ingredient.id} a[href*='adults=10'][href*='children=5']"
           )

    refute has_element?(view, "#shopping-warnings")

    {:ok, detail, _} = live(conn, "/admin/recipes/#{recipe.id}?adults=10&children=5&percent=70")
    assert has_element?(detail, "#actual-portions", "15")
    assert has_element?(detail, "#consumption-#{ingredient.id}", "2,7 kg")
    assert has_element?(detail, "#calculator_adults[value='10']")
  end

  test "date and group selection are bookmarkable and restrict totals", %{conn: conn} do
    {_, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe)
    shopping_booking(recipe)
    {:ok, view, _} = live(conn, path())
    assert has_element?(view, "#shopping-groups", "2")

    view
    |> form("#shopping-range-form",
      range: %{from: "2027-01-09", to: "2027-01-09", booking: booking.id}
    )
    |> render_submit()

    params = assert_patch(view) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert params == %{"from" => "2027-01-09", "to" => "2027-01-09", "booking" => booking.id}
    assert has_element?(view, "#shopping-groups", "1")
    assert has_element?(view, "#shopping-coverage", "3")
    assert has_element?(view, "#print-shopping-list[href*='booking=#{booking.id}']")
  end

  test "search ignores accents and mode/category filters can be combined", %{conn: conn} do
    {ingredient, recipe} = shopping_recipe()

    {:ok, ingredient} =
      Recipes.update_ingredient(ingredient, %{
        name: "Červená čočka UI",
        category: "Luštěniny",
        purchase_mode: "Průběžně"
      })

    shopping_booking(Recipes.get_recipe!(recipe.id))
    {:ok, view, _} = live(conn, path())

    view
    |> form("#shopping-filter-form",
      filter: %{search: "cervena cocka", category: "Luštěniny", mode: "Průběžně"}
    )
    |> render_change()

    assert has_element?(view, "#rows-#{ingredient.id}")
    view |> form("#shopping-filter-form", filter: %{mode: "Sezona"}) |> render_change()
    refute has_element?(view, "#rows-#{ingredient.id}")
    assert has_element?(view, "#shopping-visible-count", "0 z 1")
    assert has_element?(view, "#shopping-empty")
  end

  test "purchase packaging can be edited inline and immediately recalculates the list", %{
    conn: conn
  } do
    {ingredient, recipe} = shopping_recipe()
    shopping_booking(recipe)
    {:ok, view, _} = live(conn, path())
    view |> element("#shopping-item-settings-#{ingredient.id}") |> render_click()
    assert has_element?(view, "#shopping-purchase-form")
    view |> form("#shopping-purchase-form", ingredient: %{package_size: "2.5"}) |> render_submit()
    refute has_element?(view, "#shopping-purchase-form")
    assert has_element?(view, "#flash-success .bg-emerald-50", "Nákupní nastavení uloženo")
    assert has_element?(view, "#shopping-buy-#{ingredient.id}", "15 kg")
    assert Decimal.equal?(Recipes.get_ingredient!(ingredient.id).package_size, "2.5")
    view |> element("#shopping-item-settings-#{ingredient.id}") |> render_click()
    view |> form("#shopping-purchase-form", ingredient: %{package_size: "0"}) |> render_submit()
    assert has_element?(view, "#shopping-purchase-form")
    assert Decimal.equal?(Recipes.get_ingredient!(ingredient.id).package_size, "2.5")
  end

  test "missing menu is explicit, with a link back to resolve it", %{conn: conn} do
    booking = menu_booking_fixture()
    {:ok, view, _} = live(conn, path())
    assert has_element?(view, "#shopping-warnings", "Seznam zatím není úplný")
    assert has_element?(view, "#shopping-issues[open]")
    assert has_element?(view, "#shopping-issues a[href='/admin/bookings/#{booking.id}/menu']")
    assert has_element?(view, "#shopping-total", "0")
  end

  test "invalid date selection and unavailable booking never leave an old purchase list visible",
       %{conn: conn} do
    {_, recipe} = shopping_recipe()
    shopping_booking(recipe)
    {:ok, view, _} = live(conn, path())

    view
    |> form("#shopping-range-form", range: %{from: "2027-01-11", to: "2027-01-08"})
    |> render_submit()

    assert has_element?(view, "#shopping-range-error")
    refute has_element?(view, "#shopping-rows")
    {:ok, bad, _} = live(conn, path(Ecto.UUID.generate()))
    assert has_element?(bad, "#shopping-range-error")
    refute has_element?(bad, "#shopping-rows")
  end

  test "refresh uses changed booking portions and invalidates row signatures", %{conn: conn} do
    {ingredient, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe)
    {:ok, view, _} = live(conn, path(booking.id))
    before = view |> element("#shopping-check-#{ingredient.id}") |> render()
    {:ok, _} = CozyCheckout.Bookings.update_booking(booking, %{meal_adults: 20})
    view |> element("#refresh-shopping") |> render_click()
    assert has_element?(view, "#shopping-consumption-#{ingredient.id}", "23,5 kg")
    after_refresh = view |> element("#shopping-check-#{ingredient.id}") |> render()
    # A changed calculation must not reuse a previous completed check.
    fingerprint = fn html ->
      LazyHTML.from_fragment(html)
      |> LazyHTML.filter("input")
      |> LazyHTML.attribute("data-fingerprint")
    end

    refute fingerprint.(before) == fingerprint.(after_refresh)
  end

  test "print preserves all quantities, scope and incomplete warnings", %{conn: conn} do
    {ingredient, recipe} = shopping_recipe()
    {booking, _} = shopping_booking(recipe)
    menu_booking_fixture()
    {:ok, view, _} = live(conn, "/admin/kitchen-shopping/print?from=2027-01-08&to=2027-01-10")
    assert has_element?(view, "#print-shopping")
    assert has_element?(view, "#shopping-warnings")
    assert has_element?(view, "#shopping-buy-#{ingredient.id}", "14 kg")
    refute has_element?(view, "#shopping-filter-form")

    {:ok, scoped, _} =
      live(
        conn,
        "/admin/kitchen-shopping/print?from=2027-01-08&to=2027-01-10&booking=#{booking.id}"
      )

    refute has_element?(scoped, "#shopping-warnings")
    assert has_element?(scoped, "#shopping-buy-#{ingredient.id}", "14 kg")
  end

  test "buffet estimates are visible and directly editable", %{conn: conn} do
    buffet =
      CozyCheckout.Repo.get_by!(CozyCheckout.Recipes.Recipe,
        source_key: "kitchen:breakfast-buffet:v1"
      )
      |> then(&Recipes.get_recipe!(&1.id))

    {booking, _} = shopping_booking(buffet)
    {:ok, view, _} = live(conn, path(booking.id))
    assert has_element?(view, "#buffet-estimate-note")
    assert has_element?(view, "#edit-buffet-norms[href='/admin/recipes/#{buffet.id}/edit']")
    {:ok, library, _} = live(conn, "/admin/recipes")
    assert has_element?(library, "#recipes-#{buffet.id}", "pracovní norma bufetu")
  end

  test "planner and booking expose shopping and all shopping routes require login", %{conn: conn} do
    booking = menu_booking_fixture()
    {:ok, detail, _} = live(conn, "/admin/bookings/#{booking.id}")
    assert has_element?(detail, "#booking-shopping-link[href*='booking=#{booking.id}']")
    {:ok, planner, _} = live(conn, "/admin/meal-planner")
    assert has_element?(planner, "#kitchen-shopping-link")

    for route <- ["/admin/kitchen-shopping", "/admin/kitchen-shopping/print"] do
      assert {:error, {:redirect, %{to: "/admin/login"}}} =
               live(Phoenix.ConnTest.build_conn(), route)
    end
  end

  test "a missing purchase mode stays visible and cannot be ticked as purchased", %{conn: conn} do
    {ingredient, recipe} = shopping_recipe()
    {:ok, _} = Recipes.update_ingredient(ingredient, %{purchase_mode: nil})
    shopping_booking(recipe)
    {:ok, view, _} = live(conn, path())
    assert has_element?(view, "#shopping-warnings", "Zvolte způsob nákupu")
    assert has_element?(view, "#shopping-buy-#{ingredient.id}", "Doplnit nákup")
    assert has_element?(view, "#shopping-check-#{ingredient.id}[disabled]")
    assert has_element?(view, "#shopping-item-settings-#{ingredient.id}")
  end
end

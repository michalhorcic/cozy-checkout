defmodule CozyCheckoutWeb.FreezerLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.RecipeFixtures
  import CozyCheckout.ShoppingFixtures
  alias CozyCheckout.Kitchen.Freezer
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

  test "PIN protects freezer HTTP and LiveView access", %{conn: conn} do
    public = Plug.Conn.clear_session(conn)
    assert {:error, {:redirect, %{to: to}}} = live(public, "/admin/freezer")
    assert to =~ "/admin/login"
  end

  test "manual creation, editing, partial removal, all and archived filtering", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/freezer?from=2026-10-28&to=2026-10-29")
    assert has_element?(view, "#freezer-empty")
    assert has_element?(view, "#food-desktop-freezer[aria-current='page']")
    view |> element("#new-freezer-item") |> render_click()

    view
    |> form("#freezer-form",
      freezer_item: %{
        name: "Zbytek omáčky",
        quantity: "4",
        unit: "porce",
        frozen_on: Date.to_iso8601(Freezer.today())
      }
    )
    |> render_submit()

    [item] = Freezer.list_items()
    assert has_element?(view, "#freezer-item-#{item.id}", "Zbytek omáčky")
    view |> element("#freezer-item-#{item.id} button[phx-click='edit']") |> render_click()

    view
    |> form("#freezer-form", freezer_item: %{name: "Omáčka", location: "Horní zásuvka"})
    |> render_submit()

    assert has_element?(view, "#freezer-item-#{item.id}", "Horní zásuvka")
    view |> element("#freezer-item-#{item.id} button[phx-click='remove']") |> render_click()
    view |> form("#freezer-remove-form", amount: "1") |> render_submit()
    assert Decimal.equal?(hd(Freezer.list_items()).quantity, 3)
    view |> element("#freezer-item-#{item.id} button[phx-click='remove']") |> render_click()
    view |> element("button[phx-click='all']") |> render_click()
    refute has_element?(view, "#freezer-item-#{item.id}")
    view |> form("#freezer-filter", filter: %{archived: "true"}) |> render_change()
    assert has_element?(view, "#freezer-item-#{item.id}", "Omáčka")
  end

  test "selection fills name and incompatible unit errors stay visible", %{conn: conn} do
    ingredient = ingredient_fixture()
    {:ok, view, _} = live(conn, "/admin/freezer")
    view |> element("#new-freezer-item") |> render_click()

    view
    |> form("#freezer-form", freezer_item: %{link: "ingredient:#{ingredient.id}"})
    |> render_change()

    assert has_element?(view, "input[name='freezer_item[name]'][value='#{ingredient.name}']")

    view
    |> form("#freezer-form", freezer_item: %{quantity: "1", unit: "porce"})
    |> render_submit()

    assert render(view) =~ "Jednotka neodpovídá"
    assert Freezer.list_items() == []
  end

  test "stale editor refreshes instead of overwriting a newer amount", %{conn: conn} do
    {:ok, stock} =
      Freezer.create_item(%{
        name: "Hrášek",
        quantity: "500",
        unit: "g",
        frozen_on: Freezer.today()
      })

    {:ok, view, _} = live(conn, "/admin/freezer")
    view |> element("#freezer-item-#{stock.id} button[phx-click='edit']") |> render_click()
    {:ok, _} = Freezer.remove(stock, "100")
    view |> form("#freezer-form", freezer_item: %{quantity: "600"}) |> render_submit()
    assert render(view) =~ "Položka se mezitím změnila"
    assert Decimal.equal?(hd(Freezer.list_items()).quantity, 400)
  end

  test "menu, planner and shopping show current matches, print excludes them", %{conn: conn} do
    {ingredient, recipe} = shopping_recipe()
    first = Freezer.today()
    last = Date.add(first, 1)
    {booking, _} = shopping_booking(recipe, %{check_in_date: first, check_out_date: last})

    {:ok, _} =
      Freezer.create_item(%{
        name: "Mražený hrášek",
        quantity: "500",
        unit: "g",
        ingredient_id: ingredient.id,
        frozen_on: first
      })

    {:ok, _} =
      Freezer.create_item(%{
        name: "Guláš v krabičce",
        quantity: "4",
        unit: "porce",
        recipe_id: recipe.id,
        frozen_on: first
      })

    {:ok, _} =
      Freezer.create_item(%{name: "Zbytek omáčky", quantity: "1", unit: "l", frozen_on: first})

    query = "from=#{first}&to=#{last}&booking=#{booking.id}"

    for path <- [
          "/admin/bookings/#{booking.id}/menu",
          "/admin/meal-planner?#{query}",
          "/admin/kitchen-shopping?#{query}"
        ] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "[data-freezer-notice]", "Mražený hrášek")
      assert has_element?(view, "[data-freezer-notice]", "Guláš v krabičce")
      assert render(view) =~ "nákupní množství se nemění"
    end

    {:ok, print, _} = live(conn, "/admin/kitchen-shopping/print?#{query}")
    refute has_element?(print, "[data-freezer-notice]")

    {:ok, changed} =
      CozyCheckout.Bookings.update_booking(booking, %{check_out_date: Date.add(last, 1)})

    {:ok, stale, _} = live(conn, "/admin/bookings/#{booking.id}/menu")
    assert has_element?(stale, "#booking-menu-stale")
    refute has_element?(stale, "[data-freezer-notice]", "Mražený hrášek")
    {:ok, _} = CozyCheckout.Bookings.update_booking(changed, %{status: "cancelled"})
    {:ok, menu, _} = live(conn, "/admin/bookings/#{booking.id}/menu")
    refute has_element?(menu, "[data-freezer-notice]", "Mražený hrášek")
    assert has_element?(menu, "[data-freezer-notice]", "Zbytek omáčky")
  end
end

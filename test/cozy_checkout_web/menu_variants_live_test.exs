defmodule CozyCheckoutWeb.MenuVariantsLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.MenuFixtures
  alias CozyCheckout.Meals.MenuPlanning
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

  test "explicit reference import is visible and repeatable without duplicates", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants")
    assert has_element?(view, "#import-menu-variants")
    view |> element("#import-menu-variants") |> render_click()
    assert length(MenuPlanning.list_variants()) == 9
    assert has_element?(view, "#flash-success .bg-emerald-50", "Přidáno")
    assert has_element?(view, "#menu-variants", "Víkend 3 dny")
    view |> element("#import-menu-variants") |> render_click()
    assert length(MenuPlanning.list_variants()) == 9
  end

  test "saves and reopens a draft without entering dish names", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/new")
    assert has_element?(view, "#menu-editor-new-form")
    refute has_element?(view, "textarea[name*='menu_text']")

    view
    |> form("#menu-editor-new-form", editor: %{name: "Rozpracovaný víkend"})
    |> render_submit()

    assert_patch(view, "/admin/meal-planner/variants")
    [variant] = MenuPlanning.list_variants()
    assert variant.name == "Rozpracovaný víkend"
    refute CozyCheckout.Meals.MenuRecipes.readiness(variant).ready?
    assert has_element?(view, "#menu-variant-#{variant.id}", "Chybí 5 podání")
    view |> element("#menu-variant-#{variant.id} a", "Upravit") |> render_click()
    assert has_element?(view, "input[name='editor[name]'][value='Rozpracovaný víkend']")
  end

  test "schedule changes preserve IDs and require confirmation before losing filled slots", %{
    conn: conn
  } do
    variant = variant_fixture()
    first = hd(variant.items)
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/#{variant.id}/edit")
    form_id = "#menu-editor-#{variant.id}-form"
    view |> form(form_id, editor: %{days: "2"}) |> render_change()
    view |> element("#build-menu-variant") |> render_click()
    assert has_element?(view, "#menu-impact", "Potvrdit změnu")
    assert MenuPlanning.get_variant!(variant.id).days == 3
    view |> element("#menu-impact button[phx-click='cancel_pending']") |> render_click()
    assert has_element?(view, "#menu-slot-4")
    view |> element("#build-menu-variant") |> render_click()
    view |> element("#menu-impact button[phx-click='confirm']") |> render_click()
    refute has_element?(view, "#menu-slot-2")
    view |> form(form_id) |> render_submit()
    updated = MenuPlanning.get_variant!(variant.id)
    assert updated.days == 2
    assert hd(updated.items).id == first.id
    assert hd(updated.items).recipe_id == first.recipe_id
  end

  test "overview filters by linked recipe and duplicates the menu without changing the source", %{
    conn: conn
  } do
    variant = variant_fixture()
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants")

    view
    |> form("#menu-filters", filters: %{search: hd(variant.items).recipe.name})
    |> render_change()

    assert has_element?(view, "#menu-variant-#{variant.id}")
    assert has_element?(view, "#menu-preview-#{variant.id}", hd(variant.items).recipe.name)
    view |> element("#menu-variant-#{variant.id} button[phx-click='duplicate']") |> render_click()
    assert_patch(view)
    assert length(MenuPlanning.list_variants()) == 2
    assert MenuPlanning.get_variant!(variant.id).lock_version == variant.lock_version
  end

  test "archiving a variant leaves the assigned booking menu intact", %{conn: conn} do
    variant = variant_fixture()
    booking = menu_booking_fixture()
    menu = assign_variant(booking, variant)
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants")
    view |> element("#menu-variant-#{variant.id} button[phx-click='delete']") |> render_click()
    refute has_element?(view, "#menu-variant-#{variant.id}")
    assert MenuPlanning.get_booking_menu(booking.id).id == menu.id
  end

  test "variant management and booking menu stay behind admin authentication" do
    conn = Phoenix.ConnTest.build_conn()

    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(conn, "/admin/meal-planner/variants")

    booking = menu_booking_fixture()

    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(conn, "/admin/bookings/#{booking.id}/menu")
  end
end

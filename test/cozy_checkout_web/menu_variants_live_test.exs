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
    assert has_element?(view, "#menu-variants", "Víkend 3 dny")
    view |> element("#import-menu-variants") |> render_click()
    assert length(MenuPlanning.list_variants()) == 9
  end

  test "creates and edits a complete variant through the form", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/new")
    assert has_element?(view, "#menu-variant-form")
    attrs = variant_attrs(%{name: "Testovací víkend"})
    params = params(attrs)
    view |> form("#menu-variant-form", menu_variant: params) |> render_submit()
    assert_patch(view, "/admin/meal-planner/variants")
    [variant] = MenuPlanning.list_variants()
    assert has_element?(view, "#variants-#{variant.id}", "Testovací víkend")
    view |> element("#variants-#{variant.id} a", "Upravit") |> render_click()
    assert_patch(view, "/admin/meal-planner/variants/#{variant.id}/edit")

    view
    |> form("#menu-variant-form", menu_variant: %{name: "Upravený víkend"})
    |> render_submit()

    assert_patch(view, "/admin/meal-planner/variants")
    assert MenuPlanning.get_variant!(variant.id).name == "Upravený víkend"
  end

  test "changing length requires rebuilding and preserves typed menu text", %{conn: conn} do
    variant = variant_fixture()
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants/#{variant.id}/edit")
    first = hd(variant.items)

    view
    |> form("#menu-variant-form",
      menu_variant: %{
        days: "4",
        items: %{"0" => %{id: first.id, menu_text: "Zachovat připravenou večeři"}}
      }
    )
    |> render_change()

    view |> element("#build-menu-variant") |> render_click()
    assert has_element?(view, "#menu_variant_items_0_menu_text", "Zachovat připravenou večeři")
    assert has_element?(view, "#menu_variant_items_7_menu_text", "Snídaňový bufet")
    assert MenuPlanning.get_variant!(variant.id).days == 3
  end

  test "archiving a variant leaves the assigned booking menu intact", %{conn: conn} do
    variant = variant_fixture()
    booking = menu_booking_fixture()
    menu = assign_variant(booking, variant)
    {:ok, view, _} = live(conn, "/admin/meal-planner/variants")
    view |> element("#variants-#{variant.id} button[phx-click='delete']") |> render_click()
    refute has_element?(view, "#variants-#{variant.id}")
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

  defp params(attrs) do
    Map.put(
      attrs,
      :items,
      Map.new(Enum.with_index(attrs.items), fn {item, index} -> {to_string(index), item} end)
    )
  end
end

defmodule CozyCheckoutWeb.ApplicationIdentityLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias CozyCheckoutWeb.AdminAuth

  setup do
    previous = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, previous),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)
  end

  test "guests see the house identity while the PIN screen identifies the internal app", %{
    conn: conn
  } do
    {:ok, pos, _} = live(conn, ~p"/pos")
    assert has_element?(pos, "#pos-house-name", "Jindřichův dům")
    refute has_element?(pos, "#admin-brand-header")
    refute has_element?(pos, "img[src='/images/cozy-knot.svg']")

    {:ok, login, _} = live(conn, ~p"/admin/login")
    assert has_element?(login, "h1", "Cozy Checkout")
    assert has_element?(login, "#admin-pin-form")
    refute has_element?(login, "#admin-brand-header")
  end

  test "authenticated navigation retains the admin layout across food and ordinary screens", %{
    conn: conn
  } do
    conn =
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    {:ok, admin, _} = live(conn, ~p"/admin")
    assert has_element?(admin, "#admin-brand-header a[href='/admin']", "Cozy Checkout")

    {:ok, food, _} = live(conn, ~p"/admin/recipes")
    assert has_element?(food, "#food-desktop img[src='/images/cozy-knot.svg']")
    result = food |> element("#food-desktop a[href='/admin']") |> render_click()
    {:ok, dashboard, _} = follow_redirect(result, conn, ~p"/admin")
    assert has_element?(dashboard, "#admin-brand-header a[href='/admin']", "Cozy Checkout")
    refute has_element?(dashboard, "#food-layout")
  end
end

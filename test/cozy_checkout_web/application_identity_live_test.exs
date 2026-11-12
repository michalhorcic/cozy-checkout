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
    assert has_element?(pos, "#pos-design-switcher[role='group'][aria-label='Barevný design']")

    assert has_element?(
             pos,
             "#pos-design-switcher button[type='button'][data-design-theme='light']",
             "Původní"
           )

    assert has_element?(
             pos,
             "#pos-design-switcher button[type='button'][data-design-theme='noir']",
             "Cozy Noir"
           )

    refute has_element?(pos, "#admin-brand-header")
    refute has_element?(pos, "img[src='/images/cozy-knot.svg']")

    {:ok, login, _} = live(conn, ~p"/admin/login")
    assert has_element?(login, "h1", "Cozy Checkout")
    assert has_element?(login, "#admin-pin-form")
    refute has_element?(login, "#admin-brand-header")
  end

  test "header offers the game only when enabled and never on public screens", %{conn: conn} do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:cozy_checkout, :adventure_enabled),
        else: Application.put_env(:cozy_checkout, :adventure_enabled, previous)
    end)

    Application.put_env(:cozy_checkout, :adventure_enabled, true)

    authenticated =
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    for path <- [~p"/admin", ~p"/admin/recipes"] do
      {:ok, view, _} = live(authenticated, path)

      assert has_element?(
               view,
               "#admin-brand-header #admin-adventure-entry[href='/admin/adventure']",
               "Do hry"
             )
    end

    {:ok, admin, _} = live(authenticated, ~p"/admin")
    result = admin |> element("#admin-adventure-entry") |> render_click()
    {:ok, game, _} = follow_redirect(result, authenticated, ~p"/admin/adventure")
    assert has_element?(game, "#adventure-game-layout")

    {:ok, pos, _} = live(conn, ~p"/pos")
    refute has_element?(pos, "#admin-adventure-entry")
    {:ok, login, _} = live(conn, ~p"/admin/login")
    refute has_element?(login, "#admin-adventure-entry")

    Application.put_env(:cozy_checkout, :adventure_enabled, false)
    {:ok, disabled, _} = live(authenticated, ~p"/admin")
    refute has_element?(disabled, "#admin-adventure-entry")
  end

  test "authenticated navigation retains the admin layout across food and ordinary screens", %{
    conn: conn
  } do
    conn =
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    {:ok, admin, _} = live(conn, ~p"/admin")
    assert has_element?(admin, "#admin-brand-header a[href='/admin']", "Cozy Checkout")
    assert has_element?(admin, "#admin-design-switcher[phx-hook='DesignSwitcher']")

    {:ok, food, _} = live(conn, ~p"/admin/recipes")
    assert has_element?(food, "#food-desktop img[src='/images/cozy-knot.svg']")
    assert has_element?(food, "#admin-brand-header #admin-design-switcher")
    assert length(Floki.find(render(food), ".design-switcher")) == 1
    refute has_element?(food, "#food-desktop .design-switcher")
    refute has_element?(food, "#food-mobile .design-switcher")
    result = food |> element("#food-desktop a[href='/admin']") |> render_click()
    {:ok, dashboard, _} = follow_redirect(result, conn, ~p"/admin")
    assert has_element?(dashboard, "#admin-brand-header a[href='/admin']", "Cozy Checkout")
    refute has_element?(dashboard, "#food-layout")
  end
end

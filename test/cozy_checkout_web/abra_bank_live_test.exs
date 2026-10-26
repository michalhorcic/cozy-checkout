defmodule CozyCheckoutWeb.AbraBankLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckoutWeb.AdminAuth

  setup do
    old = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      if old,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, old),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    :ok
  end

  test "bank data requires admin PIN and the view provides no payment confirmation", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, "/admin/billing/bank")
    assert to =~ "/admin/login"

    conn =
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    {:ok, view, _} = live(conn, "/admin/billing/bank")
    assert has_element?(view, "#bank-status")
    refute has_element?(view, "[phx-click=payment]")
    refute has_element?(view, "[phx-click=confirm]")
  end
end

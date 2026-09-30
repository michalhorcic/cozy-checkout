defmodule CozyCheckoutWeb.AdminSessionController do
  use CozyCheckoutWeb, :controller

  import Plug.Conn,
    only: [configure_session: 2, delete_session: 2, get_session: 2, put_session: 3]

  alias CozyCheckoutWeb.{AdminAuth, AdminAuthRateLimiter}

  def create(conn, %{"pin" => pin}) when is_binary(pin) do
    address = conn.remote_ip

    cond do
      not AdminAuth.enabled?() ->
        reject(conn, "Admin PIN is not configured on the server.")

      not AdminAuthRateLimiter.allowed?(address) ->
        reject(conn, "Too many incorrect PIN attempts. Wait one minute and try again.")

      AdminAuth.verify_pin(pin) ->
        AdminAuthRateLimiter.reset(address)
        destination = AdminAuth.safe_return_to(get_session(conn, AdminAuth.return_to_key()))

        conn
        |> configure_session(renew: true)
        |> delete_session(AdminAuth.return_to_key())
        |> put_session(AdminAuth.session_key(), System.system_time(:second))
        |> redirect(to: destination)

      true ->
        AdminAuthRateLimiter.record_failure(address)
        reject(conn, "Incorrect PIN.")
    end
  end

  def create(conn, _params), do: reject(conn, "Enter your PIN.")

  def delete(conn, _params) do
    conn
    |> delete_session(AdminAuth.session_key())
    |> delete_session(AdminAuth.return_to_key())
    |> redirect(to: "/pos")
  end

  def lock(conn, _params) do
    conn
    |> delete_session(AdminAuth.session_key())
    |> delete_session(AdminAuth.return_to_key())
    |> redirect(to: "/admin/login")
  end

  defp reject(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: "/admin/login")
  end
end

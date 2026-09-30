defmodule CozyCheckoutWeb.AdminAuth do
  use Phoenix.LiveView

  import Plug.Conn, only: [get_session: 2, put_session: 3, halt: 1]
  import Phoenix.Controller, only: [current_path: 1]

  @session_key "admin_authenticated_at"
  @return_to_key "admin_return_to"
  @pin_hash_config_key :admin_pin_hash
  @pbkdf2_iterations 200_000
  @hash_bytes 32
  @session_lifetime_seconds 12 * 60 * 60
  @idle_timeout_seconds 15 * 60
  @idle_timeout_ms @idle_timeout_seconds * 1_000

  def init(opts), do: opts

  def call(conn, _opts) do
    if session_authenticated?(get_session(conn, @session_key)) do
      conn
    else
      conn = put_session(conn, @return_to_key, current_path(conn))

      conn =
        if enabled?() do
          Phoenix.Controller.put_flash(
            conn,
            :error,
            "Admin session expired. Enter the PIN to continue."
          )
        else
          Phoenix.Controller.put_flash(conn, :error, "Admin PIN is not configured on the server.")
        end

      conn
      |> Phoenix.Controller.redirect(to: "/admin/login")
      |> halt()
    end
  end

  def enabled?, do: not is_nil(configured_hash())

  def valid_pin?(pin) when is_binary(pin), do: Regex.match?(~r/\A\d{6,8}\z/, pin)
  def valid_pin?(_pin), do: false

  def hash_pin(pin) do
    unless valid_pin?(pin) do
      raise ArgumentError, "admin PIN must contain 6 to 8 digits"
    end

    salt = :crypto.strong_rand_bytes(16)
    digest = derive_hash(pin, salt)
    Base.encode64(salt) <> "." <> Base.encode64(digest)
  end

  def verify_pin(pin) do
    with true <- valid_pin?(pin),
         {salt, expected_digest} when is_binary(salt) and is_binary(expected_digest) <-
           configured_hash() do
      actual_digest = derive_hash(pin, salt)
      Plug.Crypto.secure_compare(expected_digest, actual_digest)
    else
      _ -> false
    end
  end

  def session_authenticated?(timestamp) when is_integer(timestamp) do
    now = System.system_time(:second)
    timestamp <= now and now - timestamp < @session_lifetime_seconds
  end

  def session_authenticated?(_timestamp), do: false

  def session_key, do: @session_key
  def return_to_key, do: @return_to_key

  def safe_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/admin/") and not String.starts_with?(path, "//") and
         path != "/admin/login" do
      path
    else
      "/admin"
    end
  end

  def safe_return_to(_path), do: "/admin"

  def on_mount(:ensure_admin, _params, session, socket) do
    authenticated_at = Map.get(session, @session_key)

    if enabled?() and session_authenticated?(authenticated_at) do
      socket = assign(socket, :admin_authenticated_at, authenticated_at)
      {:cont, install_idle_hooks(socket)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/admin/login")}
    end
  end

  defp install_idle_hooks(socket) do
    socket
    |> reset_idle_timer()
    |> attach_hook(:admin_idle_event, :handle_event, fn event, _params, socket ->
      cond do
        not session_authenticated?(socket.assigns.admin_authenticated_at) ->
          {:halt, Phoenix.LiveView.redirect(socket, to: "/admin/lock")}

        event == "heartbeat" ->
          {:cont, socket}

        true ->
          {:cont, reset_idle_timer(socket)}
      end
    end)
    |> attach_hook(:admin_idle_timer, :handle_info, fn
      {:admin_idle_timeout, timer_ref}, socket ->
        if timer_ref == socket.assigns.admin_idle_timer_ref do
          {:halt, Phoenix.LiveView.redirect(socket, to: "/admin/lock")}
        else
          {:cont, socket}
        end

      _message, socket ->
        {:cont, socket}
    end)
  end

  defp reset_idle_timer(socket) do
    if timer = socket.assigns[:admin_idle_timer], do: Process.cancel_timer(timer)

    timer_ref = make_ref()
    timer = Process.send_after(self(), {:admin_idle_timeout, timer_ref}, @idle_timeout_ms)

    socket
    |> assign(:admin_idle_timer_ref, timer_ref)
    |> assign(:admin_idle_timer, timer)
  end

  defp configured_hash do
    case Application.get_env(:cozy_checkout, @pin_hash_config_key) do
      hash when is_binary(hash) ->
        case String.split(hash, ".", parts: 2) do
          [salt, digest] ->
            with {:ok, salt} <- Base.decode64(salt),
                 {:ok, digest} <- Base.decode64(digest),
                 true <- byte_size(salt) == 16 and byte_size(digest) == @hash_bytes do
              {salt, digest}
            else
              _ -> nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp derive_hash(pin, salt) do
    :crypto.pbkdf2_hmac(:sha256, pin, salt, @pbkdf2_iterations, @hash_bytes)
  end
end

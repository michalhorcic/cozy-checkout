defmodule CozyCheckoutWeb.AdminLoginLive do
  use CozyCheckoutWeb, :live_view
  import Phoenix.Controller, only: [get_csrf_token: 0]

  alias CozyCheckoutWeb.AdminAuth

  @impl true
  def mount(_params, session, socket) do
    if AdminAuth.session_authenticated?(Map.get(session, AdminAuth.session_key())) do
      {:ok, redirect(socket, to: "/admin")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Přihlášení")
       |> assign(:pin_configured, AdminAuth.enabled?())}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      content_class="mx-auto w-full max-w-sm"
      main_class="flex min-h-screen items-center bg-secondary-50 px-4 py-12 sm:px-6 lg:px-8"
      show_header={false}
    >
      <section class="rounded-xl border border-secondary-200 bg-white p-8 shadow-sm">
        <div class="mb-6 text-center">
          <img src={~p"/images/cozy-knot.svg"} alt="" width="56" height="56" class="mx-auto mb-4" />
          <h1 class="text-2xl font-bold text-primary-500">Cozy Checkout</h1>
          <p class="mt-2 text-sm text-primary-400">Jindřichův dům · Administrace</p>
        </div>

        <%= if @pin_configured do %>
          <form action={~p"/admin/login"} method="post" id="admin-pin-form" class="space-y-5">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <div>
              <label for="admin-pin" class="mb-1 block text-sm font-medium text-gray-700">
                Zadejte PIN
              </label>
              <input
                id="admin-pin"
                name="pin"
                type="password"
                inputmode="numeric"
                autocomplete="one-time-code"
                pattern="[0-9]{6,8}"
                minlength="6"
                maxlength="8"
                required
                autofocus
                class="block w-full rounded-md border-gray-300 text-center text-2xl tracking-[0.4em] shadow-sm focus:border-primary-500 focus:ring-primary-500"
              />
            </div>
            <button
              type="submit"
              class="w-full rounded-md bg-primary-600 px-4 py-3 font-semibold text-white transition-colors hover:bg-primary-700"
            >
              Odemknout
            </button>
          </form>
        <% else %>
          <p class="rounded-md bg-amber-50 p-4 text-sm text-amber-900">
            Admin PIN is not configured. Set the <code>ADMIN_PIN_HASH</code>
            environment variable and restart the server.
          </p>
        <% end %>

        <.link
          navigate={~p"/pos"}
          class="mt-5 block text-center text-sm text-gray-500 hover:text-gray-800"
        >
          Zpět do pokladny
        </.link>
      </section>
    </Layouts.app>
    """
  end
end

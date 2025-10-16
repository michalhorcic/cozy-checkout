defmodule CozyCheckoutWeb.GuestLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Guests
  alias CozyCheckout.Guests.Guest

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :guests, Guests.list_guests())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Guest")
    |> assign(:guest, Guests.get_guest!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Guest")
    |> assign(:guest, %Guest{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Guests")
    |> assign(:guest, nil)
  end

  @impl true
  def handle_info({CozyCheckoutWeb.GuestLive.FormComponent, {:saved, guest}}, socket) do
    {:noreply, stream_insert(socket, :guests, guest)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    guest = Guests.get_guest!(id)
    {:ok, _} = Guests.delete_guest(guest)

    {:noreply, stream_delete(socket, :guests, guest)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8 flex items-center justify-between">
        <div>
          <.link navigate={~p"/admin"} class="text-blue-600 hover:text-blue-800 mb-2 inline-block">
            ← Back to Dashboard
          </.link>
          <h1 class="text-4xl font-bold text-gray-900">{@page_title}</h1>
        </div>
        <.link patch={~p"/admin/guests/new"}>
          <.button>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Guest
          </.button>
        </.link>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Name
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Email
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Phone
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Notes
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody id="guests" phx-update="stream" class="bg-white divide-y divide-gray-200">
            <tr :for={{id, guest} <- @streams.guests} id={id} class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                {guest.name}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {guest.email || "—"}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {guest.phone || "—"}
              </td>
              <td class="px-6 py-4 text-sm text-gray-500">
                {if guest.notes, do: String.slice(guest.notes, 0, 50) <> "...", else: "—"}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <.link
                  patch={~p"/admin/guests/#{guest}/edit"}
                  class="text-indigo-600 hover:text-indigo-900 mr-4"
                >
                  Edit
                </.link>
                <.link
                  phx-click={JS.push("delete", value: %{id: guest.id})}
                  data-confirm="Are you sure?"
                  class="text-red-600 hover:text-red-900"
                >
                  Delete
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="guest-modal"
        show
        on_cancel={JS.patch(~p"/admin/guests")}
      >
        <.live_component
          module={CozyCheckoutWeb.GuestLive.FormComponent}
          id={@guest.id || :new}
          title={@page_title}
          action={@live_action}
          guest={@guest}
          patch={~p"/admin/guests"}
        />
      </.modal>
    </div>
    """
  end
end

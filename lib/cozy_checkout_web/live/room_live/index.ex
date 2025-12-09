defmodule CozyCheckoutWeb.RoomLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Rooms
  alias CozyCheckout.Rooms.Room

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :rooms, Rooms.list_rooms())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Room")
    |> assign(:room, Rooms.get_room!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Room")
    |> assign(:room, %Room{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Rooms")
    |> assign(:room, nil)
  end

  @impl true
  def handle_info({CozyCheckoutWeb.RoomLive.FormComponent, {:saved, room}}, socket) do
    {:noreply, stream_insert(socket, :rooms, room)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    room = Rooms.get_room!(id)
    {:ok, _} = Rooms.delete_room(room)

    {:noreply, stream_delete(socket, :rooms, room)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8 flex items-center justify-between">
        <div>
          <.link navigate={~p"/admin"} class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block">
            ← Back to Dashboard
          </.link>
          <h1 class="text-4xl font-bold text-primary-500">{@page_title}</h1>
        </div>
        <.link patch={~p"/admin/rooms/new"}>
          <.button>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Room
          </.button>
        </.link>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-secondary-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                Room Number
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                Name
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                Capacity
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                Description
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-primary-400 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody id="rooms" phx-update="stream" class="bg-white divide-y divide-gray-200">
            <tr :for={{id, room} <- @streams.rooms} id={id} class="hover:bg-secondary-50">
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-primary-500">
                {room.room_number}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-primary-400">
                {room.name || "—"}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-primary-400">
                {room.capacity} {if room.capacity == 1, do: "person", else: "people"}
              </td>
              <td class="px-6 py-4 text-sm text-primary-400">
                {if room.description, do: String.slice(room.description, 0, 50) <> "...", else: "—"}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <.link
                  patch={~p"/admin/rooms/#{room}/edit"}
                  class="text-tertiary-600 hover:text-white-900 mr-4"
                >
                  Edit
                </.link>
                <.link
                  phx-click={JS.push("delete", value: %{id: room.id})}
                  data-confirm="Are you sure?"
                  class="text-error hover:text-error-dark"
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
        id="room-modal"
        show
        on_cancel={JS.patch(~p"/admin/rooms")}
      >
        <.live_component
          module={CozyCheckoutWeb.RoomLive.FormComponent}
          id={@room.id || :new}
          title={@page_title}
          action={@live_action}
          room={@room}
          patch={~p"/admin/rooms"}
        />
      </.modal>
    </div>
    """
  end
end

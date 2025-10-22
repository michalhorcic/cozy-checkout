defmodule CozyCheckoutWeb.BookingLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Bookings
  alias CozyCheckout.Bookings.Booking

  @impl true
  def mount(_params, _session, socket) do
    bookings =
      Bookings.list_bookings()
      |> Enum.map(fn booking ->
        rooms = Bookings.list_booking_rooms(booking.id)
        Map.put(booking, :rooms_list, rooms)
      end)

    {:ok, stream(socket, :bookings, bookings)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Booking")
    |> assign(:booking, Bookings.get_booking!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Booking")
    |> assign(:booking, %Booking{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Bookings")
    |> assign(:booking, nil)
  end

  @impl true
  def handle_info({CozyCheckoutWeb.BookingLive.FormComponent, {:saved, booking}}, socket) do
    updated_booking = Bookings.get_booking!(booking.id)
    rooms = Bookings.list_booking_rooms(updated_booking.id)
    updated_booking = Map.put(updated_booking, :rooms_list, rooms)

    {:noreply, stream_insert(socket, :bookings, updated_booking)}
  end

  @impl true
  def handle_info({:guest_created, guest}, socket) do
    # Forward the message to the FormComponent
    send_update(CozyCheckoutWeb.BookingLive.FormComponent,
      id: socket.assigns.booking.id || :new,
      guest_created: guest
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    booking = Bookings.get_booking!(id)
    {:ok, _} = Bookings.delete_booking(booking)

    {:noreply, stream_delete(socket, :bookings, booking)}
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
        <.link patch={~p"/admin/bookings/new"}>
          <.button>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Booking
          </.button>
        </.link>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Guest
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Room
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Check-in
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Check-out
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Status
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody id="bookings" phx-update="stream" class="bg-white divide-y divide-gray-200">
            <tr :for={{id, booking} <- @streams.bookings} id={id} class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                {booking.guest.name}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= if Map.get(booking, :rooms_list) && booking.rooms_list != [] do %>
                  {Enum.map_join(booking.rooms_list, ", ", & &1.room_number)}
                <% else %>
                  —
                <% end %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {Calendar.strftime(booking.check_in_date, "%b %d, %Y")}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {if booking.check_out_date, do: Calendar.strftime(booking.check_out_date, "%b %d, %Y"), else: "—"}
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class={[
                  "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                  status_badge_class(booking.status)
                ]}>
                  {String.capitalize(booking.status)}
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <.link
                  navigate={~p"/admin/bookings/#{booking}"}
                  class="text-blue-600 hover:text-blue-900 mr-4"
                >
                  View
                </.link>
                <.link
                  patch={~p"/admin/bookings/#{booking}/edit"}
                  class="text-indigo-600 hover:text-indigo-900 mr-4"
                >
                  Edit
                </.link>
                <.link
                  phx-click={JS.push("delete", value: %{id: booking.id})}
                  data-confirm="Are you sure? This will not delete associated orders."
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
        id="booking-modal"
        show
        on_cancel={JS.patch(~p"/admin/bookings")}
      >
        <.live_component
          module={CozyCheckoutWeb.BookingLive.FormComponent}
          id={@booking.id || :new}
          title={@page_title}
          action={@live_action}
          booking={@booking}
          patch={~p"/admin/bookings"}
        />
      </.modal>
    </div>
    """
  end

  defp status_badge_class("upcoming"), do: "bg-blue-100 text-blue-800"
  defp status_badge_class("active"), do: "bg-green-100 text-green-800"
  defp status_badge_class("completed"), do: "bg-gray-100 text-gray-800"
  defp status_badge_class("cancelled"), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"
end

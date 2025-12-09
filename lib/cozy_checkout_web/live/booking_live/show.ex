defmodule CozyCheckoutWeb.BookingLive.Show do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Bookings

  import CozyCheckoutWeb.FlopComponents, only: [build_path_with_params: 2]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _, socket) do
    booking = Bookings.get_booking!(id)
    rooms = Bookings.list_booking_rooms(booking.id)

    # Extract filter params (all params except "id")
    filter_params = Map.delete(params, "id")

    {:noreply,
     socket
     |> assign(:page_title, "Booking Details")
     |> assign(:booking, booking)
     |> assign(:rooms, rooms)
     |> assign(:filter_params, filter_params)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link
          navigate={build_path_with_params(~p"/admin/bookings", @filter_params)}
          class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block"
        >
          ← Back to Bookings
        </.link>
        <div class="flex items-center justify-between">
          <h1 class="text-4xl font-bold text-primary-500">{@page_title}</h1>
          <div class="flex space-x-3">
            <.link
              navigate={~p"/admin/bookings/#{@booking}/guests"}
              class="inline-flex items-center px-4 py-2 bg-tertiary-500 hover:bg-tertiary-600 text-white font-semibold rounded-lg shadow-md transition-colors duration-200"
            >
              <.icon name="hero-user-group" class="w-5 h-5 mr-2" /> Manage Guests
            </.link>
            <.link patch={~p"/admin/bookings/#{@booking}/edit"}>
              <.button>
                <.icon name="hero-pencil" class="w-5 h-5 mr-2" /> Edit Booking
              </.button>
            </.link>
          </div>
        </div>
      </div>

      <div class="space-y-6">
        <%!-- Guest Information --%>
        <div class="bg-white shadow-lg rounded-lg p-6">
          <h2 class="text-2xl font-bold text-primary-500 mb-4">Guest Information</h2>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <p class="text-sm text-primary-400">Name</p>
              <p class="text-lg font-medium text-primary-500">{@booking.guest.name}</p>
            </div>
            <div :if={@booking.guest.email}>
              <p class="text-sm text-primary-400">Email</p>
              <p class="text-lg font-medium text-primary-500">{@booking.guest.email}</p>
            </div>
            <div :if={@booking.guest.phone}>
              <p class="text-sm text-primary-400">Phone</p>
              <p class="text-lg font-medium text-primary-500">{@booking.guest.phone}</p>
            </div>
          </div>
          <div :if={@booking.guest.notes} class="mt-4">
            <p class="text-sm text-primary-400">Guest Notes</p>
            <p class="text-primary-500">{@booking.guest.notes}</p>
          </div>
        </div>

        <%!-- Booking Information --%>
        <div class="bg-white shadow-lg rounded-lg p-6">
          <h2 class="text-2xl font-bold text-primary-500 mb-4">Booking Details</h2>
          <div class="grid grid-cols-2 gap-4">
            <div :if={@rooms != []}>
              <p class="text-sm text-primary-400">Rooms</p>
              <div class="flex flex-wrap gap-2 mt-1">
                <%= for room <- @rooms do %>
                  <span class="px-3 py-1 bg-info-light text-tertiary-800 rounded-full text-sm font-medium">
                    {room.room_number}
                    <%= if room.name do %>
                      - {room.name}
                    <% end %>
                  </span>
                <% end %>
              </div>
            </div>
            <div>
              <p class="text-sm text-primary-400">Status</p>
              <span class={[
                "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                status_badge_class(@booking.status)
              ]}>
                {String.capitalize(@booking.status)}
              </span>
            </div>
            <div>
              <p class="text-sm text-primary-400">Check-in Date</p>
              <p class="text-lg font-medium text-primary-500">
                {Calendar.strftime(@booking.check_in_date, "%B %d, %Y")}
              </p>
            </div>
            <div :if={@booking.check_out_date}>
              <p class="text-sm text-primary-400">Check-out Date</p>
              <p class="text-lg font-medium text-primary-500">
                {Calendar.strftime(@booking.check_out_date, "%B %d, %Y")}
              </p>
            </div>
          </div>
          <div :if={@booking.short_note} class="mt-4">
            <p class="text-sm text-primary-400">Group/Tag</p>
            <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-info-light text-tertiary-800">
              {@booking.short_note}
            </span>
          </div>
          <div :if={@booking.notes} class="mt-4">
            <p class="text-sm text-primary-400">Booking Notes</p>
            <p class="text-primary-500">{@booking.notes}</p>
          </div>
        </div>

        <%!-- Associated Orders --%>
        <div class="bg-white shadow-lg rounded-lg p-6">
          <h2 class="text-2xl font-bold text-primary-500 mb-4">Orders</h2>
          <%= if @booking.orders == [] do %>
            <p class="text-primary-400">No orders yet for this booking.</p>
          <% else %>
            <div class="overflow-hidden">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-secondary-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                      Order Date
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                      Status
                    </th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-primary-400 uppercase tracking-wider">
                      Total
                    </th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-primary-400 uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <tr :for={order <- @booking.orders} class="hover:bg-secondary-50">
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-primary-500">
                      {Calendar.strftime(order.inserted_at, "%b %d, %Y %I:%M %p")}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={[
                        "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                        order_status_badge_class(order.status)
                      ]}>
                        {String.capitalize(order.status)}
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-primary-500 text-right">
                      {CozyCheckoutWeb.CurrencyHelper.format_currency(order.total_amount)}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      <.link
                        navigate={~p"/admin/orders/#{order}"}
                        class="text-tertiary-600 hover:text-white-900"
                      >
                        View
                      </.link>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

        <%!-- Invoice Details --%>
        <.live_component
          module={CozyCheckoutWeb.BookingLive.InvoiceComponent}
          id="booking-invoice"
          booking={@booking}
        />
      </div>
    </div>
    """
  end

  defp status_badge_class("upcoming"), do: "bg-tertiary-100 text-tertiary-800"
  defp status_badge_class("active"), do: "bg-success-light text-success-dark"
  defp status_badge_class("completed"), do: "bg-secondary-100 text-primary-500"
  defp status_badge_class("cancelled"), do: "bg-error-light text-error-dark"
  defp status_badge_class(_), do: "bg-secondary-100 text-primary-500"

  defp order_status_badge_class("open"), do: "bg-warning-light text-warning-dark"
  defp order_status_badge_class("paid"), do: "bg-success-light text-success-dark"
  defp order_status_badge_class("partially_paid"), do: "bg-tertiary-100 text-tertiary-800"
  defp order_status_badge_class("cancelled"), do: "bg-error-light text-error-dark"
  defp order_status_badge_class(_), do: "bg-secondary-100 text-primary-500"
end

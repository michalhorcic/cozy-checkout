defmodule CozyCheckoutWeb.BookingLive.Show do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Bookings

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    booking = Bookings.get_booking!(id)

    {:noreply,
     socket
     |> assign(:page_title, "Booking Details")
     |> assign(:booking, booking)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link navigate={~p"/admin/bookings"} class="text-blue-600 hover:text-blue-800 mb-2 inline-block">
          ← Back to Bookings
        </.link>
        <div class="flex items-center justify-between">
          <h1 class="text-4xl font-bold text-gray-900">{@page_title}</h1>
          <.link patch={~p"/admin/bookings/#{@booking}/edit"}>
            <.button>
              <.icon name="hero-pencil" class="w-5 h-5 mr-2" /> Edit Booking
            </.button>
          </.link>
        </div>
      </div>

      <div class="space-y-6">
        <%!-- Guest Information --%>
        <div class="bg-white shadow-lg rounded-lg p-6">
          <h2 class="text-2xl font-bold text-gray-900 mb-4">Guest Information</h2>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <p class="text-sm text-gray-500">Name</p>
              <p class="text-lg font-medium text-gray-900">{@booking.guest.name}</p>
            </div>
            <div :if={@booking.guest.email}>
              <p class="text-sm text-gray-500">Email</p>
              <p class="text-lg font-medium text-gray-900">{@booking.guest.email}</p>
            </div>
            <div :if={@booking.guest.phone}>
              <p class="text-sm text-gray-500">Phone</p>
              <p class="text-lg font-medium text-gray-900">{@booking.guest.phone}</p>
            </div>
          </div>
          <div :if={@booking.guest.notes} class="mt-4">
            <p class="text-sm text-gray-500">Guest Notes</p>
            <p class="text-gray-900">{@booking.guest.notes}</p>
          </div>
        </div>

        <%!-- Booking Information --%>
        <div class="bg-white shadow-lg rounded-lg p-6">
          <h2 class="text-2xl font-bold text-gray-900 mb-4">Booking Details</h2>
          <div class="grid grid-cols-2 gap-4">
            <div :if={@booking.room_number}>
              <p class="text-sm text-gray-500">Room Number</p>
              <p class="text-lg font-medium text-gray-900">{@booking.room_number}</p>
            </div>
            <div>
              <p class="text-sm text-gray-500">Status</p>
              <span class={[
                "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                status_badge_class(@booking.status)
              ]}>
                {String.capitalize(@booking.status)}
              </span>
            </div>
            <div>
              <p class="text-sm text-gray-500">Check-in Date</p>
              <p class="text-lg font-medium text-gray-900">
                {Calendar.strftime(@booking.check_in_date, "%B %d, %Y")}
              </p>
            </div>
            <div :if={@booking.check_out_date}>
              <p class="text-sm text-gray-500">Check-out Date</p>
              <p class="text-lg font-medium text-gray-900">
                {Calendar.strftime(@booking.check_out_date, "%B %d, %Y")}
              </p>
            </div>
          </div>
          <div :if={@booking.notes} class="mt-4">
            <p class="text-sm text-gray-500">Booking Notes</p>
            <p class="text-gray-900">{@booking.notes}</p>
          </div>
        </div>

        <%!-- Associated Orders --%>
        <div class="bg-white shadow-lg rounded-lg p-6">
          <h2 class="text-2xl font-bold text-gray-900 mb-4">Orders</h2>
          <%= if @booking.orders == [] do %>
            <p class="text-gray-500">No orders yet for this booking.</p>
          <% else %>
            <div class="overflow-hidden">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Order Date
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Status
                    </th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Total
                    </th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <tr :for={order <- @booking.orders} class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
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
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      {CozyCheckoutWeb.CurrencyHelper.format_currency(order.total_amount)}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      <.link
                        navigate={~p"/admin/orders/#{order}"}
                        class="text-indigo-600 hover:text-indigo-900"
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
      </div>
    </div>
    """
  end

  defp status_badge_class("upcoming"), do: "bg-blue-100 text-blue-800"
  defp status_badge_class("active"), do: "bg-green-100 text-green-800"
  defp status_badge_class("completed"), do: "bg-gray-100 text-gray-800"
  defp status_badge_class("cancelled"), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp order_status_badge_class("open"), do: "bg-yellow-100 text-yellow-800"
  defp order_status_badge_class("paid"), do: "bg-green-100 text-green-800"
  defp order_status_badge_class("partially_paid"), do: "bg-blue-100 text-blue-800"
  defp order_status_badge_class("cancelled"), do: "bg-red-100 text-red-800"
  defp order_status_badge_class(_), do: "bg-gray-100 text-gray-800"
end

defmodule CozyCheckoutWeb.OrderLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :orders, Sales.list_orders())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Orders")
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    order = Sales.get_order!(id)
    {:ok, _} = Sales.delete_order(order)

    {:noreply, stream_delete(socket, :orders, order)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8 flex items-center justify-between">
        <div>
          <.link navigate={~p"/"} class="text-blue-600 hover:text-blue-800 mb-2 inline-block">
            ← Back to Dashboard
          </.link>
          <h1 class="text-4xl font-bold text-gray-900">{@page_title}</h1>
        </div>
        <.link navigate={~p"/orders/new"}>
          <.button>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" />
            New Order
          </.button>
        </.link>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Order #
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Guest
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Total
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Status
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Date
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody id="orders" phx-update="stream" class="bg-white divide-y divide-gray-200">
            <tr :for={{id, order} <- @streams.orders} id={id} class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                {order.order_number}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {order.guest && order.guest.name}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                ${order.total_amount}
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class={[
                  "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                  case order.status do
                    "paid" -> "bg-green-100 text-green-800"
                    "partially_paid" -> "bg-yellow-100 text-yellow-800"
                    "open" -> "bg-blue-100 text-blue-800"
                    "cancelled" -> "bg-red-100 text-red-800"
                    _ -> "bg-gray-100 text-gray-800"
                  end
                ]}>
                  {String.replace(order.status, "_", " ") |> String.capitalize()}
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {Calendar.strftime(order.inserted_at, "%Y-%m-%d %H:%M")}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <.link navigate={~p"/orders/#{order}"} class="text-blue-600 hover:text-blue-900 mr-4">
                  View
                </.link>
                <.link
                  phx-click={JS.push("delete", value: %{id: order.id})}
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
    </div>
    """
  end
end

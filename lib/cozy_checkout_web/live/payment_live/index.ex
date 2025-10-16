defmodule CozyCheckoutWeb.PaymentLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales

  @impl true
  def mount(_params, _session, socket) do
    # Get all orders with their payments
    orders = Sales.list_orders()

    # Build a list of all payments across orders
    payments =
      orders
      |> Enum.flat_map(fn order ->
        order.payments
        |> Enum.map(fn payment ->
          Map.put(payment, :order, order)
        end)
      end)
      |> Enum.sort_by(& &1.payment_date, {:desc, Date})

    {:ok, stream(socket, :payments, payments)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Payments")
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    # Find payment in the stream
    payment =
      socket.assigns.streams.payments
      |> Enum.find(fn {_dom_id, p} -> p.id == id end)
      |> elem(1)

    case Sales.delete_payment(payment) do
      {:ok, _} ->
        {:noreply, stream_delete(socket, :payments, payment)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete payment")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link navigate={~p"/admin"} class="text-blue-600 hover:text-blue-800 mb-2 inline-block">
          ← Back to Dashboard
        </.link>
        <h1 class="text-4xl font-bold text-gray-900">{@page_title}</h1>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Date
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Order #
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Guest
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Method
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Amount
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Notes
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody id="payments" phx-update="stream" class="bg-white divide-y divide-gray-200">
            <tr :for={{id, payment} <- @streams.payments} id={id} class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {Calendar.strftime(payment.payment_date, "%Y-%m-%d")}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                <.link
                  navigate={~p"/admin/orders/#{payment.order}"}
                  class="text-blue-600 hover:text-blue-800"
                >
                  {payment.order.order_number}
                </.link>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {payment.order.guest.name}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {String.replace(payment.payment_method, "_", " ") |> String.capitalize()}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-green-600">
                {format_currency(payment.amount)}
              </td>
              <td class="px-6 py-4 text-sm text-gray-500">
                {payment.notes || "—"}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <.link
                  phx-click={JS.push("delete", value: %{id: payment.id})}
                  data-confirm="Are you sure? This will update the order status."
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

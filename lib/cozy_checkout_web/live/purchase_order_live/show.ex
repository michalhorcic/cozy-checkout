defmodule CozyCheckoutWeb.PurchaseOrderLive.Show do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Inventory

  import CozyCheckoutWeb.CurrencyHelper

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    purchase_order = Inventory.get_purchase_order!(id)

    {:noreply,
     socket
     |> assign(:page_title, "Purchase Order #{purchase_order.order_number}")
     |> assign(:purchase_order, purchase_order)}
  end

  @impl true
  def handle_event("delete_item", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.purchase_order.purchase_order_items, &(&1.id == id))
    {:ok, _} = Inventory.delete_purchase_order_item(item)

    # Reload purchase order
    purchase_order = Inventory.get_purchase_order!(socket.assigns.purchase_order.id)

    {:noreply,
     socket
     |> assign(:purchase_order, purchase_order)
     |> put_flash(:info, "Item deleted successfully")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link
          navigate={~p"/admin/purchase_orders"}
          class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block"
        >
          ← Back to Purchase Orders
        </.link>
        <div class="flex items-center justify-between">
          <h1 class="text-4xl font-bold text-primary-500">{@page_title}</h1>
          <.link navigate={~p"/admin/purchase_orders/#{@purchase_order}/edit"}>
            <.button>
              <.icon name="hero-pencil" class="w-5 h-5 mr-2" /> Edit
            </.button>
          </.link>
        </div>
      </div>

      <div class="space-y-6">
        <%!-- Purchase Order Information --%>
        <div class="bg-white shadow-lg rounded-lg p-6">
          <h2 class="text-2xl font-bold text-primary-500 mb-4">Order Information</h2>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <p class="text-sm text-primary-400">Order Number</p>
              <p class="text-lg font-medium text-primary-500">{@purchase_order.order_number}</p>
            </div>
            <div>
              <p class="text-sm text-primary-400">Order Date</p>
              <p class="text-lg font-medium text-primary-500">
                {Calendar.strftime(@purchase_order.order_date, "%B %d, %Y")}
              </p>
            </div>
            <div :if={@purchase_order.supplier_note}>
              <p class="text-sm text-primary-400">Supplier</p>
              <p class="text-lg font-medium text-primary-500">{@purchase_order.supplier_note}</p>
            </div>
            <div :if={@purchase_order.total_cost}>
              <p class="text-sm text-primary-400">Total Cost</p>
              <p class="text-lg font-medium text-primary-500">
                {format_currency(@purchase_order.total_cost)}
              </p>
            </div>
          </div>
          <div :if={@purchase_order.notes} class="mt-4">
            <p class="text-sm text-primary-400">Notes</p>
            <p class="text-primary-500">{@purchase_order.notes}</p>
          </div>
        </div>

        <%!-- Items --%>
        <div class="bg-white shadow-lg rounded-lg p-6">
          <h2 class="text-2xl font-bold text-primary-500 mb-4">Items</h2>

          <%= if @purchase_order.purchase_order_items == [] do %>
            <p class="text-gray-500 italic">No items in this purchase order yet.</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Product
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Quantity
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Unit Amount
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Cost Price
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Total
                    </th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <%= for item <- @purchase_order.purchase_order_items do %>
                    <tr class="hover:bg-gray-50">
                      <td class="px-6 py-4">
                        <div class="text-sm font-medium text-gray-900">{item.product.name}</div>
                        <div class="text-sm text-gray-500">{item.product.category.name}</div>
                        <%= if item.notes do %>
                          <div class="text-xs text-gray-400 mt-1">{item.notes}</div>
                        <% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                        {item.quantity}
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                        <%= if item.unit_amount do %>
                          {Decimal.to_string(item.unit_amount)} {item.product.unit || ""}
                        <% else %>
                          —
                        <% end %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                        {format_currency(item.cost_price)}
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        {format_currency(Decimal.mult(item.cost_price, item.quantity))}
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                        <.link
                          phx-click={JS.push("delete_item", value: %{id: item.id})}
                          data-confirm="Are you sure you want to delete this item?"
                          class="text-rose-600 hover:text-rose-900"
                        >
                          Delete
                        </.link>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end

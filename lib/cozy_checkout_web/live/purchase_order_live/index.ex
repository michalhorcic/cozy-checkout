defmodule CozyCheckoutWeb.PurchaseOrderLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Inventory
  alias CozyCheckout.Inventory.PurchaseOrder

  import CozyCheckoutWeb.CurrencyHelper

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Purchase Orders")
    |> assign(:purchase_orders, Inventory.list_purchase_orders())
    |> assign(:purchase_order, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Purchase Order")
    |> assign(:purchase_orders, Inventory.list_purchase_orders())
    |> assign(:purchase_order, %PurchaseOrder{order_number: Inventory.generate_purchase_order_number()})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Purchase Order")
    |> assign(:purchase_orders, Inventory.list_purchase_orders())
    |> assign(:purchase_order, Inventory.get_purchase_order!(id))
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    purchase_order = Inventory.get_purchase_order!(id)
    {:ok, _} = Inventory.delete_purchase_order(purchase_order)

    {:noreply,
     socket
     |> put_flash(:info, "Purchase order deleted successfully")
     |> push_navigate(to: ~p"/admin/purchase_orders")}
  end

  @impl true
  def handle_info({CozyCheckoutWeb.PurchaseOrderLive.FormComponent, {:saved, _purchase_order}}, socket) do
    {:noreply,
     socket
     |> assign(:purchase_orders, Inventory.list_purchase_orders())
     |> put_flash(:info, "Purchase order saved successfully")}
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
        <.link patch={~p"/admin/purchase_orders/new"}>
          <.button>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Purchase Order
          </.button>
        </.link>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gradient-to-r from-primary-500 to-secondary-600">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                Order Number
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                Date
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                Supplier
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                Items
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                Total Cost
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-white uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= if @purchase_orders == [] do %>
              <tr>
                <td colspan="6" class="px-6 py-8 text-center text-gray-500">
                  <div class="flex flex-col items-center justify-center">
                    <.icon name="hero-archive-box" class="w-12 h-12 text-gray-400 mb-2" />
                    <p class="text-lg">No purchase orders yet</p>
                    <p class="text-sm">Click "New Purchase Order" to get started</p>
                  </div>
                </td>
              </tr>
            <% else %>
              <%= for purchase_order <- @purchase_orders do %>
                <tr class="hover:bg-gray-50 transition-colors">
                  <td class="px-6 py-4 whitespace-nowrap">
                    <.link
                      navigate={~p"/admin/purchase_orders/#{purchase_order}"}
                      class="text-tertiary-600 hover:text-tertiary-800 font-medium"
                    >
                      {purchase_order.order_number}
                    </.link>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {Calendar.strftime(purchase_order.order_date, "%B %d, %Y")}
                  </td>
                  <td class="px-6 py-4 text-sm text-gray-900">
                    {purchase_order.supplier_note || "—"}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-blue-100 text-blue-800">
                      {length(purchase_order.purchase_order_items || [])} items
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    <%= if purchase_order.total_cost do %>
                      {format_currency(purchase_order.total_cost)}
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <.link
                      navigate={~p"/admin/purchase_orders/#{purchase_order}"}
                      class="text-tertiary-600 hover:text-tertiary-900 mr-4"
                    >
                      View
                    </.link>
                    <.link
                      patch={~p"/admin/purchase_orders/#{purchase_order}/edit"}
                      class="text-indigo-600 hover:text-indigo-900 mr-4"
                    >
                      Edit
                    </.link>
                    <.link
                      phx-click={JS.push("delete", value: %{id: purchase_order.id})}
                      data-confirm="Are you sure you want to delete this purchase order?"
                      class="text-rose-600 hover:text-rose-900"
                    >
                      Delete
                    </.link>
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>

    <.modal
      :if={@live_action in [:new, :edit]}
      id="purchase-order-modal"
      show
      on_cancel={JS.patch(~p"/admin/purchase_orders")}
    >
      <.live_component
        module={CozyCheckoutWeb.PurchaseOrderLive.FormComponent}
        id={@purchase_order.id || :new}
        title={@page_title}
        action={@live_action}
        purchase_order={@purchase_order}
        patch={~p"/admin/purchase_orders"}
      />
    </.modal>
    """
  end
end

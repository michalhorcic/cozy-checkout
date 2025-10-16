defmodule CozyCheckoutWeb.OrderLive.Show do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales
  alias CozyCheckoutWeb.OrderItemGrouper

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    order = Sales.get_order!(id)
    payments = Sales.list_payments_for_order(id)
    grouped_items = OrderItemGrouper.group_order_items(order.order_items)

    total_paid =
      Enum.reduce(payments, Decimal.new("0"), fn payment, acc ->
        Decimal.add(acc, payment.amount)
      end)

    {:noreply,
     socket
     |> assign(:page_title, "Order Details")
     |> assign(:order, order)
     |> assign(:grouped_items, grouped_items)
     |> assign(:payments, payments)
     |> assign(:total_paid, total_paid)
     |> assign(:amount_due, Decimal.sub(order.total_amount, total_paid))}
  end

  @impl true
  def handle_event("expand_group", params, socket) do
    product_id = params["product-id"] || params["product_id"]
    unit_amount_str = params["unit-amount"] || params["unit_amount"] || params["value"]

    unit_amount = parse_unit_amount(unit_amount_str)

    grouped_items =
      OrderItemGrouper.expand_group(socket.assigns.grouped_items, product_id, unit_amount)

    {:noreply, assign(socket, :grouped_items, grouped_items)}
  end

  @impl true
  def handle_event("collapse_group", params, socket) do
    product_id = params["product-id"] || params["product_id"]
    unit_amount_str = params["unit-amount"] || params["unit_amount"] || params["value"]

    unit_amount = parse_unit_amount(unit_amount_str)

    grouped_items =
      OrderItemGrouper.collapse_group(socket.assigns.grouped_items, product_id, unit_amount)

    {:noreply, assign(socket, :grouped_items, grouped_items)}
  end

  defp parse_unit_amount(""), do: nil
  defp parse_unit_amount(nil), do: nil

  defp parse_unit_amount(unit_amount_str) when is_binary(unit_amount_str) do
    case Decimal.parse(unit_amount_str) do
      {amount, _} -> amount
      :error -> nil
    end
  end

  defp parse_unit_amount(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link navigate={~p"/admin/orders"} class="text-blue-600 hover:text-blue-800 mb-2 inline-block">
          ← Back to Orders
        </.link>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-4xl font-bold text-gray-900">Order {@order.order_number}</h1>
            <p class="text-gray-600 mt-2">
              {Calendar.strftime(@order.inserted_at, "%B %d, %Y at %H:%M")}
            </p>
          </div>
          <div class="flex items-center space-x-4">
            <.link :if={@order.status != "paid"} navigate={~p"/admin/orders/#{@order}/edit"}>
              <.button>
                <.icon name="hero-pencil" class="w-5 h-5 mr-2" /> Edit Order
              </.button>
            </.link>
            <div
              :if={@order.status == "paid"}
              class="text-sm text-gray-500 italic"
              title="Paid orders cannot be edited as they serve as accounting history"
            >
              <.icon name="hero-lock-closed" class="w-5 h-5 inline" /> Locked for accounting
            </div>
            <span class={[
              "px-4 py-2 inline-flex text-lg font-semibold rounded-full",
              case @order.status do
                "paid" -> "bg-green-100 text-green-800"
                "partially_paid" -> "bg-yellow-100 text-yellow-800"
                "open" -> "bg-blue-100 text-blue-800"
                "cancelled" -> "bg-red-100 text-red-800"
                _ -> "bg-gray-100 text-gray-800"
              end
            ]}>
              {String.replace(@order.status, "_", " ") |> String.capitalize()}
            </span>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div class="lg:col-span-2 space-y-6">
          <%!-- Guest Information --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Guest Information</h2>
            <div class="space-y-2">
              <div class="flex justify-between">
                <span class="text-gray-600">Name:</span>
                <span class="font-medium">{@order.guest.name}</span>
              </div>
              <div :if={@order.guest.room_number} class="flex justify-between">
                <span class="text-gray-600">Room:</span>
                <span class="font-medium">{@order.guest.room_number}</span>
              </div>
              <div :if={@order.guest.phone} class="flex justify-between">
                <span class="text-gray-600">Phone:</span>
                <span class="font-medium">{@order.guest.phone}</span>
              </div>
            </div>
          </div>

          <%!-- Order Items --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Order Items</h2>
            <div class="space-y-3">
              <div
                :for={group <- @grouped_items}
                class="border border-gray-200 rounded-lg overflow-hidden"
              >
                <!-- Grouped Item Display -->
                <div class="p-4 bg-gray-50">
                  <div class="flex items-center justify-between">
                    <div class="flex-1">
                      <div class="font-medium text-gray-900">{group.product.name}</div>
                      <div class="text-sm text-gray-500">
                        <%= if group.unit_amount do %>
                          {Decimal.round(group.total_quantity, 2)} × {group.unit_amount}{group.product.unit} = {Decimal.mult(
                            group.total_quantity,
                            group.unit_amount
                          )}{group.product.unit}
                          <span class="text-gray-400">|</span>
                        <% else %>
                          Total Quantity: {Decimal.round(group.total_quantity, 2)}
                          <span class="text-gray-400">|</span>
                        <% end %>
                        {format_currency(group.price_per_unit)} (VAT: {group.vat_rate}%)
                        <%= if group.grouped? do %>
                          <span class="ml-2 text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded-full">
                            {length(group.items)} items
                          </span>
                        <% end %>
                      </div>
                    </div>
                    <div class="text-lg font-bold text-gray-900">
                      {format_currency(group.total_price)}
                    </div>
                  </div>

    <!-- Expand/Collapse Button for Grouped Items -->
                  <%= if group.grouped? do %>
                    <button
                      phx-click={if group.expanded?, do: "collapse_group", else: "expand_group"}
                      phx-value-product-id={group.product.id}
                      phx-value-unit-amount={group.unit_amount || ""}
                      class="mt-3 text-sm text-blue-600 hover:text-blue-800 font-medium flex items-center gap-1"
                    >
                      <%= if group.expanded? do %>
                        <.icon name="hero-chevron-up" class="w-4 h-4" /> Hide individual items
                      <% else %>
                        <.icon name="hero-chevron-down" class="w-4 h-4" />
                        Show {length(group.items)} individual items
                      <% end %>
                    </button>
                  <% end %>
                </div>

    <!-- Individual Items (when expanded) -->
                <%= if group.expanded? do %>
                  <div class="border-t border-gray-200">
                    <div
                      :for={item <- group.items}
                      class="p-3 bg-white border-b border-gray-100 last:border-b-0"
                    >
                      <div class="flex items-center justify-between text-sm">
                        <div class="text-gray-600">
                          <%= if item.unit_amount do %>
                            {item.quantity} × {item.unit_amount}{item.product.unit}
                          <% else %>
                            Qty: {item.quantity}
                          <% end %>
                        </div>
                        <div class="text-gray-900 font-medium">
                          {format_currency(item.subtotal)}
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Payment History --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Payment History</h2>

            <div :if={@payments == []} class="text-center py-8 text-gray-500">
              No payments recorded yet
            </div>

            <div :if={@payments != []} class="space-y-3">
              <div
                :for={payment <- @payments}
                class="flex items-center justify-between p-4 bg-gray-50 rounded-lg"
              >
                <div class="flex-1">
                  <div class="font-medium text-gray-900">
                    {String.replace(payment.payment_method, "_", " ") |> String.capitalize()}
                  </div>
                  <div class="text-sm text-gray-500">
                    {Calendar.strftime(payment.payment_date, "%B %d, %Y")}
                  </div>
                  <div :if={payment.notes} class="text-sm text-gray-500 mt-1">
                    {payment.notes}
                  </div>
                </div>
                <div class="text-lg font-bold text-green-600">+{format_currency(payment.amount)}</div>
              </div>
            </div>

            <.link
              :if={@order.status != "paid" and @order.status != "cancelled"}
              navigate={~p"/admin/payments/new?order_id=#{@order.id}"}
              class="block mt-4"
            >
              <.button class="w-full">
                <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Add Payment
              </.button>
            </.link>
          </div>

          <div :if={@order.notes} class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Notes</h2>
            <p class="text-gray-600">{@order.notes}</p>
          </div>
        </div>

        <%!-- Order Summary --%>
        <div class="lg:col-span-1">
          <div class="bg-white shadow-lg rounded-lg p-6 sticky top-8">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Summary</h2>

            <div class="space-y-3">
              <div class="flex justify-between text-gray-600">
                <span>Subtotal:</span>
                <span>
                  {format_currency(
                    Decimal.add(@order.total_amount, @order.discount_amount || Decimal.new("0"))
                  )}
                </span>
              </div>

              <div
                :if={Decimal.gt?(@order.discount_amount || Decimal.new("0"), 0)}
                class="flex justify-between text-gray-600"
              >
                <span>Discount:</span>
                <span class="text-red-600">-{format_currency(@order.discount_amount)}</span>
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-xl font-bold text-gray-900">
                  <span>Total:</span>
                  <span>{format_currency(@order.total_amount)}</span>
                </div>
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-green-600 font-medium">
                  <span>Paid:</span>
                  <span>{format_currency(@total_paid)}</span>
                </div>
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-xl font-bold">
                  <span class={
                    if Decimal.gt?(@amount_due, 0), do: "text-red-600", else: "text-green-600"
                  }>
                    Amount Due:
                  </span>
                  <span class={
                    if Decimal.gt?(@amount_due, 0), do: "text-red-600", else: "text-green-600"
                  }>
                    {format_currency(@amount_due)}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

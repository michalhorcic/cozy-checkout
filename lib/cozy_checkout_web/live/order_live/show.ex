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
        <.link
          navigate={~p"/admin/orders"}
          class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block"
        >
          ← Back to Orders
        </.link>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-4xl font-bold text-primary-500">Order {@order.order_number}</h1>
            <p class="text-primary-400 mt-2">
              {Calendar.strftime(@order.inserted_at, "%B %d, %Y at %H:%M")}
            </p>
          </div>
          <div class="flex items-center space-x-4">
            <.link navigate={~p"/admin/orders/#{@order}/receipt"} target="_blank">
              <.button class="btn-soft">
                <.icon name="hero-printer" class="w-5 h-5 mr-2" /> Print Receipt
              </.button>
            </.link>
            <.link :if={@order.status != "paid"} navigate={~p"/admin/orders/#{@order}/edit"}>
              <.button>
                <.icon name="hero-pencil" class="w-5 h-5 mr-2" /> Edit Order
              </.button>
            </.link>
            <div
              :if={@order.status == "paid"}
              class="text-sm text-primary-400 italic"
              title="Paid orders cannot be edited as they serve as accounting history"
            >
              <.icon name="hero-lock-closed" class="w-5 h-5 inline" /> Locked for accounting
            </div>
            <span class={[
              "px-4 py-2 inline-flex text-lg font-semibold rounded-full",
              case @order.status do
                "paid" -> "bg-success-light text-success-dark"
                "partially_paid" -> "bg-warning-light text-warning-dark"
                "open" -> "bg-tertiary-100 text-tertiary-800"
                "cancelled" -> "bg-error-light text-error-dark"
                _ -> "bg-secondary-100 text-primary-500"
              end
            ]}>
              {String.replace(@order.status, "_", " ") |> String.capitalize()}
            </span>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div class="lg:col-span-2 space-y-6">
          <%!-- Booking Information --%>
          <%= if @order.booking_id do %>
            <div class="bg-white shadow-lg rounded-lg p-6">
              <h2 class="text-2xl font-bold text-primary-500 mb-4">Booking Information</h2>
              <div class="space-y-2">
                <div class="flex justify-between">
                  <span class="text-primary-400">Guest Name:</span>
                  <span class="font-medium">
                    {if @order.guest, do: @order.guest.name, else: "Unknown"}
                  </span>
                </div>
                <div :if={@order.booking.room_number} class="flex justify-between">
                  <span class="text-primary-400">Room:</span>
                  <span class="font-medium">{@order.booking.room_number}</span>
                </div>
                <div :if={@order.guest && @order.guest.phone} class="flex justify-between">
                  <span class="text-primary-400">Phone:</span>
                  <span class="font-medium">{@order.guest.phone}</span>
                </div>
                <div :if={@order.booking.check_in_date} class="flex justify-between">
                  <span class="text-primary-400">Check-in:</span>
                  <span class="font-medium">
                    {Calendar.strftime(@order.booking.check_in_date, "%B %d, %Y")}
                  </span>
                </div>
                <div :if={@order.booking.check_out_date} class="flex justify-between">
                  <span class="text-primary-400">Check-out:</span>
                  <span class="font-medium">
                    {Calendar.strftime(@order.booking.check_out_date, "%B %d, %Y")}
                  </span>
                </div>
              </div>
            </div>
          <% else %>
            <div class="bg-white shadow-lg rounded-lg p-6">
              <h2 class="text-2xl font-bold text-primary-500 mb-4 flex items-center gap-3">
                Order Information
                <span class="px-3 py-1 bg-info-light text-purple-700 text-sm font-semibold rounded-full">
                  Standalone Order
                </span>
              </h2>
              <div class="space-y-2">
                <div class="flex justify-between">
                  <span class="text-primary-400">Order Name:</span>
                  <span class="font-medium">{@order.name}</span>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Order Items --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-primary-500 mb-4">Order Items</h2>
            <div class="space-y-3">
              <div
                :for={group <- @grouped_items}
                class="border border-secondary-200 rounded-lg overflow-hidden"
              >
                <!-- Grouped Item Display -->
                <div class="p-4 bg-secondary-50">
                  <div class="flex items-center justify-between">
                    <div class="flex-1">
                      <div class="font-medium text-primary-500">{group.product.name}</div>
                      <div class="text-sm text-primary-400">
                        <%= if group.unit_amount do %>
                          {Decimal.round(group.total_quantity, 2)} × {group.unit_amount}{group.product.unit} = {Decimal.mult(
                            group.total_quantity,
                            group.unit_amount
                          )}{group.product.unit}
                          <span class="text-primary-300">|</span>
                        <% else %>
                          Total Quantity: {Decimal.round(group.total_quantity, 2)}
                          <span class="text-primary-300">|</span>
                        <% end %>
                        {format_currency(group.price_per_unit)} (VAT: {group.vat_rate}%)
                        <%= if group.grouped? do %>
                          <span class="ml-2 text-xs bg-tertiary-100 text-tertiary-800 px-2 py-1 rounded-full">
                            {length(group.items)} items
                          </span>
                        <% end %>
                      </div>
                    </div>
                    <div class="text-lg font-bold text-primary-500">
                      {format_currency(group.total_price)}
                    </div>
                  </div>

    <!-- Expand/Collapse Button for Grouped Items -->
                  <%= if group.grouped? do %>
                    <button
                      phx-click={if group.expanded?, do: "collapse_group", else: "expand_group"}
                      phx-value-product-id={group.product.id}
                      phx-value-unit-amount={group.unit_amount || ""}
                      class="mt-3 text-sm text-tertiary-600 hover:text-tertiary-800 font-medium flex items-center gap-1"
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
                  <div class="border-t border-secondary-200">
                    <div
                      :for={item <- group.items}
                      class="p-3 bg-white border-b border-gray-100 last:border-b-0"
                    >
                      <div class="flex items-center justify-between text-sm">
                        <div class="text-primary-400">
                          <%= if item.unit_amount do %>
                            {item.quantity} × {item.unit_amount}{item.product.unit}
                          <% else %>
                            Qty: {item.quantity}
                          <% end %>
                        </div>
                        <div class="text-primary-500 font-medium">
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
            <h2 class="text-2xl font-bold text-primary-500 mb-4">Payment History</h2>

            <div :if={@payments == []} class="text-center py-8 text-primary-400">
              No payments recorded yet
            </div>

            <div :if={@payments != []} class="space-y-3">
              <div
                :for={payment <- @payments}
                class="flex items-center justify-between p-4 bg-secondary-50 rounded-lg"
              >
                <div class="flex-1">
                  <div class="font-medium text-primary-500">
                    {String.replace(payment.payment_method, "_", " ") |> String.capitalize()}
                  </div>
                  <div class="text-sm text-primary-400">
                    {Calendar.strftime(payment.payment_date, "%B %d, %Y")}
                  </div>
                  <div :if={payment.notes} class="text-sm text-primary-400 mt-1">
                    {payment.notes}
                  </div>
                </div>
                <div class="text-lg font-bold text-success-dark">+{format_currency(payment.amount)}</div>
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
            <h2 class="text-2xl font-bold text-primary-500 mb-4">Notes</h2>
            <p class="text-primary-400">{@order.notes}</p>
          </div>
        </div>

        <%!-- Order Summary --%>
        <div class="lg:col-span-1">
          <div class="bg-white shadow-lg rounded-lg p-6 sticky top-8">
            <h2 class="text-2xl font-bold text-primary-500 mb-4">Summary</h2>

            <div class="space-y-3">
              <%
                items_subtotal = Enum.reduce(@order.order_items, Decimal.new("0"), fn item, acc ->
                  if is_nil(item.deleted_at) do
                    Decimal.add(acc, item.subtotal)
                  else
                    acc
                  end
                end)
              %>

              <div class="flex justify-between text-primary-400">
                <span>Subtotal (Items):</span>
                <span>{format_currency(items_subtotal)}</span>
              </div>

              <div
                :if={Decimal.gt?(@order.discount_amount || Decimal.new("0"), 0)}
                class="flex justify-between text-primary-400"
              >
                <span>Discount:</span>
                <span class="text-error">-{format_currency(@order.discount_amount)}</span>
              </div>

              <%= if @order.discount_reason && @order.discount_reason != "" do %>
                <div class="text-sm text-primary-400 italic pl-4">
                  Reason: {@order.discount_reason}
                </div>
              <% end %>

              <div
                :if={Decimal.gt?(@order.tips_amount || Decimal.new("0"), 0)}
                class="flex justify-between text-primary-400"
              >
                <span>Tips:</span>
                <span class="text-success-dark">+{format_currency(@order.tips_amount)}</span>
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-xl font-bold text-primary-500">
                  <span>Total:</span>
                  <span>{format_currency(@order.total_amount)}</span>
                </div>
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-success-dark font-medium">
                  <span>Paid:</span>
                  <span>{format_currency(@total_paid)}</span>
                </div>
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-xl font-bold">
                  <span class={
                    if Decimal.gt?(@amount_due, 0), do: "text-error", else: "text-success-dark"
                  }>
                    Amount Due:
                  </span>
                  <span class={
                    if Decimal.gt?(@amount_due, 0), do: "text-error", else: "text-success-dark"
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

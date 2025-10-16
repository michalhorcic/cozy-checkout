defmodule CozyCheckoutWeb.OrderLive.Show do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    order = Sales.get_order!(id)
    payments = Sales.list_payments_for_order(id)

    total_paid =
      Enum.reduce(payments, Decimal.new("0"), fn payment, acc ->
        Decimal.add(acc, payment.amount)
      end)

    {:noreply,
     socket
     |> assign(:page_title, "Order Details")
     |> assign(:order, order)
     |> assign(:payments, payments)
     |> assign(:total_paid, total_paid)
     |> assign(:amount_due, Decimal.sub(order.total_amount, total_paid))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link navigate={~p"/orders"} class="text-blue-600 hover:text-blue-800 mb-2 inline-block">
          ← Back to Orders
        </.link>
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-4xl font-bold text-gray-900">Order {@order.order_number}</h1>
            <p class="text-gray-600 mt-2">
              {Calendar.strftime(@order.inserted_at, "%B %d, %Y at %H:%M")}
            </p>
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
              <div :for={item <- @order.order_items} class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                <div class="flex-1">
                  <div class="font-medium text-gray-900">{item.product.name}</div>
                  <div class="text-sm text-gray-500">
                    {item.quantity} × ${item.unit_price} (VAT: {item.vat_rate}%)
                  </div>
                </div>
                <div class="text-lg font-bold text-gray-900">${item.subtotal}</div>
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
              <div :for={payment <- @payments} class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
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
                <div class="text-lg font-bold text-green-600">+${payment.amount}</div>
              </div>
            </div>

            <.link
              :if={@order.status != "paid" and @order.status != "cancelled"}
              navigate={~p"/payments/new?order_id=#{@order.id}"}
              class="block mt-4"
            >
              <.button class="w-full">
                <.icon name="hero-plus" class="w-5 h-5 mr-2" />
                Add Payment
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
                  ${Decimal.add(@order.total_amount, @order.discount_amount || Decimal.new("0"))}
                </span>
              </div>

              <div :if={Decimal.gt?(@order.discount_amount || Decimal.new("0"), 0)} class="flex justify-between text-gray-600">
                <span>Discount:</span>
                <span class="text-red-600">-${@order.discount_amount}</span>
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-xl font-bold text-gray-900">
                  <span>Total:</span>
                  <span>${@order.total_amount}</span>
                </div>
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-green-600 font-medium">
                  <span>Paid:</span>
                  <span>${@total_paid}</span>
                </div>
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-xl font-bold">
                  <span class={if Decimal.gt?(@amount_due, 0), do: "text-red-600", else: "text-green-600"}>
                    Amount Due:
                  </span>
                  <span class={if Decimal.gt?(@amount_due, 0), do: "text-red-600", else: "text-green-600"}>
                    ${@amount_due}
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

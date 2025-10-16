defmodule CozyCheckoutWeb.PaymentLive.New do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales
  alias CozyCheckout.Sales.Payment

  @impl true
  def mount(params, _session, socket) do
    order_id = Map.get(params, "order_id")
    order = if order_id, do: Sales.get_order!(order_id), else: nil

    payment = %Payment{payment_date: Date.utc_today(), payment_method: "cash"}

    socket =
      socket
      |> assign(:page_title, "New Payment")
      |> assign(:payment, payment)
      |> assign(:order, order)
      |> assign(:orders, if(order, do: [order], else: Sales.list_orders()))
      |> assign(:form, to_form(Sales.change_payment(payment)))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"payment" => payment_params}, socket) do
    changeset = Sales.change_payment(socket.assigns.payment, payment_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"payment" => payment_params}, socket) do
    case Sales.create_payment(payment_params) do
      {:ok, payment} ->
        order = Sales.get_order!(payment.order_id)

        {:noreply,
         socket
         |> put_flash(:info, "Payment recorded successfully")
         |> push_navigate(to: ~p"/admin/orders/#{order}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link
          navigate={if @order, do: ~p"/admin/orders/#{@order}", else: ~p"/admin/payments"}
          class="text-blue-600 hover:text-blue-800 mb-2 inline-block"
        >
          ← Back
        </.link>
        <h1 class="text-4xl font-bold text-gray-900">{@page_title}</h1>
      </div>

      <div class="bg-white shadow-lg rounded-lg p-8">
        <.form for={@form} id="payment-form" phx-change="validate" phx-submit="save">
          <.input
            :if={!@order}
            field={@form[:order_id]}
            type="select"
            label="Order"
            prompt="Select an order"
            options={
              Enum.map(
                @orders,
                &{"#{&1.order_number} - #{&1.guest.name} (#{format_currency(&1.total_amount)})",
                 &1.id}
              )
            }
            required
          />

          <input :if={@order} type="hidden" name="payment[order_id]" value={@order.id} />

          <div :if={@order} class="mb-6 p-4 bg-gray-50 rounded-lg">
            <h3 class="font-semibold text-gray-900 mb-2">Order Details</h3>
            <div class="space-y-1 text-sm">
              <div class="flex justify-between">
                <span class="text-gray-600">Order:</span>
                <span class="font-medium">{@order.order_number}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">Guest:</span>
                <span class="font-medium">{@order.guest.name}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-600">Total:</span>
                <span class="font-medium">{format_currency(@order.total_amount)}</span>
              </div>
            </div>
          </div>

          <.input field={@form[:amount]} type="number" label="Amount" step="0.01" required />

          <.input
            field={@form[:payment_method]}
            type="select"
            label="Payment Method"
            options={[{"Cash", "cash"}, {"QR Code", "qr_code"}]}
            required
          />

          <.input field={@form[:payment_date]} type="date" label="Payment Date" required />

          <.input field={@form[:notes]} type="textarea" label="Notes" />

          <div class="mt-6">
            <.button type="submit" phx-disable-with="Recording..." class="w-full">
              Record Payment
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end

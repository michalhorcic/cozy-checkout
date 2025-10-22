defmodule CozyCheckoutWeb.OrderLive.New do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.{Sales, Bookings, Catalog}
  alias CozyCheckout.Sales.Order

  @impl true
  def mount(_params, _session, socket) do
    order_number = Sales.generate_order_number()

    socket =
      socket
      |> assign(:page_title, "New Order")
      |> assign(:order, %Order{order_number: order_number})
      |> assign(:form, to_form(Sales.change_order(%Order{order_number: order_number})))
      |> assign(:bookings, Bookings.list_active_bookings())
      |> assign(:products, Catalog.list_products())
      |> assign(:order_items, [])
      |> assign(:selected_booking_id, nil)
      |> assign(:discount_amount, Decimal.new("0"))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"order" => order_params}, socket) do
    changeset = Sales.change_order(socket.assigns.order, order_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event(
        "add_item",
        %{"product_id" => product_id, "quantity" => quantity} = params,
        socket
      ) do
    quantity = String.to_integer(quantity)
    unit_amount = Map.get(params, "unit_amount", "")

    unit_amount =
      case unit_amount do
        "" ->
          nil

        value ->
          case Decimal.parse(value) do
            {amount, _} -> amount
            :error -> nil
          end
      end

    product_id =
      case product_id do
        "" -> nil
        id -> id
      end

    if product_id && quantity > 0 do
      product = Catalog.get_product!(product_id)
      pricelist = Catalog.get_active_pricelist_for_product(product_id)

      if pricelist do
        unit_price = pricelist.price
        vat_rate = pricelist.vat_rate
        subtotal = Decimal.mult(unit_price, quantity)

        item = %{
          id: :erlang.unique_integer([:positive]),
          product: product,
          product_id: product_id,
          quantity: quantity,
          unit_amount: unit_amount,
          unit_price: unit_price,
          vat_rate: vat_rate,
          subtotal: subtotal
        }

        order_items = socket.assigns.order_items ++ [item]

        {:noreply, assign(socket, order_items: order_items)}
      else
        {:noreply, put_flash(socket, :error, "No active pricelist found for #{product.name}")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    id = String.to_integer(id)
    order_items = Enum.reject(socket.assigns.order_items, &(&1.id == id))

    {:noreply, assign(socket, order_items: order_items)}
  end

  def handle_event("update_discount", %{"value" => discount}, socket) do
    discount_amount =
      case discount do
        "" ->
          Decimal.new("0")

        value ->
          case Decimal.parse(value) do
            {amount, _} -> amount
            :error -> Decimal.new("0")
          end
      end

    {:noreply, assign(socket, discount_amount: discount_amount)}
  end

  def handle_event("save", _params, socket) do
    # Get the order params from the form
    booking_id = Ecto.Changeset.get_field(socket.assigns.form.source, :booking_id)

    if socket.assigns.order_items == [] do
      {:noreply, put_flash(socket, :error, "Please add at least one item to the order")}
    else
      if is_nil(booking_id) do
        {:noreply, put_flash(socket, :error, "Please select a booking")}
      else
        booking = Bookings.get_booking!(booking_id)

        order_params = %{
          "booking_id" => booking_id,
          "guest_id" => booking.guest_id,
          "notes" => Ecto.Changeset.get_field(socket.assigns.form.source, :notes),
          "order_number" => socket.assigns.order.order_number
        }

        case create_order_with_items(socket, order_params) do
          {:ok, order} ->
            {:noreply,
             socket
             |> put_flash(:info, "Order created successfully")
             |> push_navigate(to: ~p"/admin/orders/#{order}")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to create order: #{inspect(reason)}")}
        end
      end
    end
  end

  defp create_order_with_items(socket, order_params) do
    items_total =
      socket.assigns.order_items
      |> Enum.reduce(Decimal.new("0"), fn item, acc ->
        Decimal.add(acc, item.subtotal)
      end)

    discount = socket.assigns.discount_amount
    total = Decimal.sub(items_total, discount)
    total = if Decimal.lt?(total, 0), do: Decimal.new("0"), else: total

    order_attrs =
      order_params
      |> Map.put("total_amount", total)
      |> Map.put("discount_amount", discount)

    case Sales.create_order(order_attrs) do
      {:ok, order} ->
        # Create order items - pass values in the correct format
        results =
          Enum.map(socket.assigns.order_items, fn item ->
            item_attrs = %{
              "order_id" => order.id,
              "product_id" => item.product_id,
              "quantity" => Integer.to_string(item.quantity),
              "unit_price" => item.unit_price,
              "vat_rate" => item.vat_rate,
              "subtotal" => item.subtotal
            }

            # Add unit_amount if it exists
            item_attrs =
              if item.unit_amount do
                Map.put(item_attrs, "unit_amount", item.unit_amount)
              else
                item_attrs
              end

            Sales.create_order_item(item_attrs)
          end)

        # Check if any item creation failed
        case Enum.find(results, fn result -> match?({:error, _}, result) end) do
          nil ->
            {:ok, Sales.get_order!(order.id)}

          {:error, changeset} ->
            # Rollback by deleting the order
            Sales.delete_order(order)
            {:error, changeset}
        end

      error ->
        error
    end
  end

  defp calculate_total(order_items, discount) do
    items_total =
      Enum.reduce(order_items, Decimal.new("0"), fn item, acc ->
        Decimal.add(acc, item.subtotal)
      end)

    total = Decimal.sub(items_total, discount)
    if Decimal.lt?(total, 0), do: Decimal.new("0"), else: total
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link
          navigate={~p"/admin/orders"}
          class="text-blue-600 hover:text-blue-800 mb-2 inline-block"
        >
          ← Back to Orders
        </.link>
        <h1 class="text-4xl font-bold text-gray-900">{@page_title}</h1>
        <p class="text-gray-600 mt-2">Order #{@order.order_number}</p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <%!-- Order Form --%>
        <div class="lg:col-span-2 space-y-8">
          <%!-- Booking Selection --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Booking Information</h2>
            <.form for={@form} id="order-form" phx-change="validate">
              <.input
                field={@form[:booking_id]}
                type="select"
                label="Booking"
                prompt="Select a booking"
                options={
                  Enum.map(
                    @bookings,
                    &{&1.guest.name <>
                       if(&1.room_number, do: " (Room #{&1.room_number})", else: "") <>
                       " - #{Calendar.strftime(&1.check_in_date, "%b %d")}", &1.id}
                  )
                }
                required
              />
              <.input field={@form[:notes]} type="textarea" label="Order Notes" />
            </.form>
          </div>

          <%!-- Add Items --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Add Items</h2>
            <form phx-submit="add_item" id="add-item-form" class="space-y-4">
              <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div class="md:col-span-2">
                  <label class="block text-sm font-medium text-gray-700 mb-1">Product</label>
                  <select
                    name="product_id"
                    id="product-select"
                    phx-hook="ProductUnitTracker"
                    data-products={
                      Jason.encode!(
                        Enum.map(@products, fn p ->
                          %{id: p.id, unit: p.unit, default_amounts: p.default_unit_amounts}
                        end)
                      )
                    }
                    class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    required
                  >
                    <option value="">Select a product</option>
                    <option :for={product <- @products} value={product.id}>
                      {product.name}{if product.unit, do: " (#{product.unit})", else: ""}
                    </option>
                  </select>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Quantity</label>
                  <input
                    type="number"
                    name="quantity"
                    min="1"
                    value="1"
                    class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    required
                  />
                </div>
              </div>

              <div id="unit-amount-container" class="hidden">
                <label class="block text-sm font-medium text-gray-700 mb-1">
                  Unit Amount <span id="unit-label" class="text-gray-500"></span>
                </label>
                <input
                  type="number"
                  name="unit_amount"
                  id="unit-amount-input"
                  step="0.01"
                  min="0"
                  placeholder="e.g., 500 for 500ml"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
                <p class="mt-1 text-sm text-gray-500" id="unit-help-text"></p>
              </div>

              <.button type="submit" class="w-full">
                <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Add Item
              </.button>
            </form>
          </div>

          <%!-- Order Items List --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Order Items</h2>

            <div :if={@order_items == []} class="text-center py-8 text-gray-500">
              No items added yet
            </div>

            <div :if={@order_items != []} class="space-y-2">
              <div
                :for={item <- @order_items}
                class="flex items-center justify-between p-4 bg-gray-50 rounded-lg"
              >
                <div class="flex-1">
                  <div class="font-medium text-gray-900">{item.product.name}</div>
                  <div class="text-sm text-gray-500">
                    <%= if item.unit_amount do %>
                      {item.quantity} × {item.unit_amount}{item.product.unit} = {Decimal.mult(
                        item.quantity,
                        item.unit_amount
                      )}{item.product.unit}
                      <span class="text-gray-400">|</span>
                    <% else %>
                      Quantity: {item.quantity}
                      <span class="text-gray-400">|</span>
                    <% end %>
                    {format_currency(item.unit_price)} (VAT: {item.vat_rate}%)
                  </div>
                </div>
                <div class="flex items-center space-x-4">
                  <div class="text-lg font-bold text-gray-900">{format_currency(item.subtotal)}</div>
                  <button
                    type="button"
                    phx-click="remove_item"
                    phx-value-id={item.id}
                    class="text-red-600 hover:text-red-800"
                  >
                    <.icon name="hero-trash" class="w-5 h-5" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Order Summary --%>
        <div class="lg:col-span-1">
          <div class="bg-white shadow-lg rounded-lg p-6 sticky top-8">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Order Summary</h2>

            <div class="space-y-3">
              <div class="flex justify-between text-gray-600">
                <span>Subtotal:</span>
                <span>
                  {format_currency(
                    Enum.reduce(@order_items, Decimal.new("0"), fn item, acc ->
                      Decimal.add(acc, item.subtotal)
                    end)
                  )}
                </span>
              </div>

              <div class="border-t pt-3">
                <label class="block text-sm font-medium text-gray-700 mb-1">Discount</label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={@discount_amount}
                  phx-change="update_discount"
                  name="discount"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-xl font-bold text-gray-900">
                  <span>Total:</span>
                  <span>{format_currency(calculate_total(@order_items, @discount_amount))}</span>
                </div>
              </div>
            </div>

            <button
              type="button"
              phx-click="save"
              class="w-full mt-6 btn btn-primary"
              disabled={@order_items == []}
            >
              Create Order
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

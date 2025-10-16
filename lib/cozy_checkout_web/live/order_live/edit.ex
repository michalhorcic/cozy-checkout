defmodule CozyCheckoutWeb.OrderLive.Edit do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.{Sales, Catalog}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    order = Sales.get_order!(id)
    products = Catalog.list_products()

    socket =
      socket
      |> assign(:page_title, "Edit Order")
      |> assign(:order, order)
      |> assign(:products, products)
      |> assign(:form, to_form(Sales.change_order(order)))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"order" => order_params}, socket) do
    changeset = Sales.change_order(socket.assigns.order, order_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("add_item", %{"product_id" => product_id, "quantity" => quantity}, socket) do
    quantity = String.to_integer(quantity)

    product_id =
      case product_id do
        "" -> nil
        id -> id
      end

    if product_id && quantity > 0 do
      product = Catalog.get_product!(product_id)
      pricelist = Catalog.get_active_pricelist_for_product(product_id)

      if pricelist do
        # Create the order item directly
        attrs = %{
          "order_id" => socket.assigns.order.id,
          "product_id" => product_id,
          "quantity" => Integer.to_string(quantity),
          "unit_price" => pricelist.price,
          "vat_rate" => pricelist.vat_rate,
          "subtotal" => Decimal.mult(pricelist.price, quantity)
        }

        case Sales.create_order_item(attrs) do
          {:ok, _item} ->
            # Recalculate order total
            {:ok, updated_order} = Sales.recalculate_order_total(socket.assigns.order)

            # Reload order with items
            order = Sales.get_order!(updated_order.id)

            {:noreply,
             socket
             |> assign(:order, order)
             |> put_flash(:info, "Item added successfully")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to add item")}
        end
      else
        {:noreply, put_flash(socket, :error, "No active pricelist found for #{product.name}")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    # Find the order item
    order_item = Enum.find(socket.assigns.order.order_items, &(&1.id == id))

    if order_item do
      case Sales.delete_order_item(order_item) do
        {:ok, _} ->
          # Recalculate order total
          {:ok, updated_order} = Sales.recalculate_order_total(socket.assigns.order)

          # Reload order with items
          order = Sales.get_order!(updated_order.id)

          {:noreply,
           socket
           |> assign(:order, order)
           |> put_flash(:info, "Item removed successfully")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove item")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_discount", %{"value" => discount}, socket) do
    discount_amount =
      case discount do
        "" -> Decimal.new("0")
        value ->
          case Decimal.parse(value) do
            {amount, _} -> amount
            :error -> Decimal.new("0")
          end
      end

    order_params = %{
      "discount_amount" => discount_amount
    }

    case Sales.update_order(socket.assigns.order, order_params) do
      {:ok, _order} ->
        # Recalculate order total
        {:ok, updated_order} = Sales.recalculate_order_total(socket.assigns.order)

        # Reload order
        order = Sales.get_order!(updated_order.id)

        {:noreply, assign(socket, :order, order)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update discount")}
    end
  end

  def handle_event("save", _params, socket) do
    # Get the order params from the form
    order_params = %{
      "notes" => Ecto.Changeset.get_field(socket.assigns.form.source, :notes)
    }

    case Sales.update_order(socket.assigns.order, order_params) do
      {:ok, order} ->
        {:noreply,
         socket
         |> put_flash(:info, "Order updated successfully")
         |> push_navigate(to: ~p"/orders/#{order}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link navigate={~p"/orders/#{@order}"} class="text-blue-600 hover:text-blue-800 mb-2 inline-block">
          ← Back to Order
        </.link>
        <h1 class="text-4xl font-bold text-gray-900">{@page_title}</h1>
        <p class="text-gray-600 mt-2">Order #{@order.order_number}</p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <%!-- Order Form --%>
        <div class="lg:col-span-2 space-y-8">
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
            </div>
          </div>

          <%!-- Order Notes --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Order Notes</h2>
            <.form for={@form} id="order-form" phx-change="validate">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </.form>
          </div>

          <%!-- Add Items --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Add Items</h2>
            <form phx-submit="add_item" class="space-y-4">
              <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div class="md:col-span-2">
                  <label class="block text-sm font-medium text-gray-700 mb-1">Product</label>
                  <select
                    name="product_id"
                    class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    required
                  >
                    <option value="">Select a product</option>
                    <option :for={product <- @products} value={product.id}>{product.name}</option>
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
              <.button type="submit" class="w-full">
                <.icon name="hero-plus" class="w-5 h-5 mr-2" />
                Add Item
              </.button>
            </form>
          </div>

          <%!-- Order Items List --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Order Items</h2>

            <div :if={@order.order_items == []} class="text-center py-8 text-gray-500">
              No items in this order yet
            </div>

            <div :if={@order.order_items != []} class="space-y-2">
              <div
                :for={item <- Enum.reject(@order.order_items, & &1.deleted_at)}
                class="flex items-center justify-between p-4 bg-gray-50 rounded-lg"
              >
                <div class="flex-1">
                  <div class="font-medium text-gray-900">{item.product.name}</div>
                  <div class="text-sm text-gray-500">
                    {item.quantity} × ${item.unit_price} (VAT: {item.vat_rate}%)
                  </div>
                </div>
                <div class="flex items-center space-x-4">
                  <div class="text-lg font-bold text-gray-900">${item.subtotal}</div>
                  <button
                    type="button"
                    phx-click="remove_item"
                    phx-value-id={item.id}
                    data-confirm="Are you sure you want to remove this item?"
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
                  ${Decimal.add(@order.total_amount, @order.discount_amount || Decimal.new("0"))}
                </span>
              </div>

              <div class="border-t pt-3">
                <label class="block text-sm font-medium text-gray-700 mb-1">Discount</label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={@order.discount_amount || 0}
                  phx-change="update_discount"
                  name="discount"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-xl font-bold text-gray-900">
                  <span>Total:</span>
                  <span>${@order.total_amount}</span>
                </div>
              </div>

              <div class="border-t pt-3">
                <div class="space-y-1 text-sm">
                  <div class="flex justify-between">
                    <span class="text-gray-600">Status:</span>
                    <span class={[
                      "font-semibold",
                      case @order.status do
                        "paid" -> "text-green-600"
                        "partially_paid" -> "text-yellow-600"
                        "open" -> "text-blue-600"
                        "cancelled" -> "text-red-600"
                        _ -> "text-gray-600"
                      end
                    ]}>
                      {String.replace(@order.status, "_", " ") |> String.capitalize()}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <button
              type="button"
              phx-click="save"
              class="w-full mt-6 btn btn-primary"
            >
              Save Changes
            </button>

            <.link navigate={~p"/orders/#{@order}"} class="block mt-3">
              <button type="button" class="w-full btn btn-soft">
                Cancel
              </button>
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

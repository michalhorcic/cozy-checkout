defmodule CozyCheckoutWeb.OrderLive.Edit do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.{Sales, Catalog}
  alias CozyCheckoutWeb.OrderItemGrouper

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    order = Sales.get_order!(id)

    # Prevent editing paid orders - they serve as history for accounting
    if order.status == "paid" do
      socket =
        socket
        |> put_flash(:error, "Cannot edit paid orders. They serve as accounting history.")
        |> redirect(to: ~p"/admin/orders/#{order}")

      {:ok, socket}
    else
      products = Catalog.list_products()
      grouped_items = OrderItemGrouper.group_order_items(order.order_items)

      socket =
        socket
        |> assign(:page_title, "Edit Order")
        |> assign(:order, order)
        |> assign(:grouped_items, grouped_items)
        |> assign(:products, products)
        |> assign(:form, to_form(Sales.change_order(order)))

      {:ok, socket}
    end
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
        # Create the order item directly
        attrs = %{
          "order_id" => socket.assigns.order.id,
          "product_id" => product_id,
          "quantity" => Integer.to_string(quantity),
          "unit_price" => pricelist.price,
          "vat_rate" => pricelist.vat_rate,
          "subtotal" => Decimal.mult(pricelist.price, quantity)
        }

        # Add unit_amount if it exists
        attrs =
          if unit_amount do
            Map.put(attrs, "unit_amount", unit_amount)
          else
            attrs
          end

        case Sales.create_order_item(attrs) do
          {:ok, _item} ->
            # Recalculate order total
            {:ok, updated_order} = Sales.recalculate_order_total(socket.assigns.order)

            # Reload order with items
            order = Sales.get_order!(updated_order.id)
            grouped_items = OrderItemGrouper.group_order_items(order.order_items)

            {:noreply,
             socket
             |> assign(:order, order)
             |> assign(:grouped_items, grouped_items)
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
          grouped_items = OrderItemGrouper.group_order_items(order.order_items)

          {:noreply,
           socket
           |> assign(:order, order)
           |> assign(:grouped_items, grouped_items)
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
        "" ->
          Decimal.new("0")

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
        grouped_items = OrderItemGrouper.group_order_items(order.order_items)

        {:noreply,
         socket
         |> assign(:order, order)
         |> assign(:grouped_items, grouped_items)}

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
         |> push_navigate(to: ~p"/admin/orders/#{order}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
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

  @impl true
  def handle_event("remove_group", params, socket) do
    item_ids_json = params["item-ids"] || params["item_ids"]

    case Jason.decode(item_ids_json) do
      {:ok, item_ids} ->
        # Delete all items in the group
        Enum.each(item_ids, fn item_id ->
          order_item = Enum.find(socket.assigns.order.order_items, &(&1.id == item_id))
          if order_item, do: Sales.delete_order_item(order_item)
        end)

        # Recalculate order total
        {:ok, updated_order} = Sales.recalculate_order_total(socket.assigns.order)

        # Reload order
        order = Sales.get_order!(updated_order.id)
        grouped_items = OrderItemGrouper.group_order_items(order.order_items)

        {:noreply,
         socket
         |> assign(:order, order)
         |> assign(:grouped_items, grouped_items)
         |> put_flash(:info, "Items removed successfully")}

      {:error, _} ->
        {:noreply, socket}
    end
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
          navigate={~p"/admin/orders/#{@order}"}
          class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block"
        >
          ← Back to Order
        </.link>
        <h1 class="text-4xl font-bold text-primary-500">{@page_title}</h1>
        <p class="text-primary-400 mt-2">Order #{@order.order_number}</p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <%!-- Order Form --%>
        <div class="lg:col-span-2 space-y-8">
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

          <%!-- Order Notes --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-primary-500 mb-4">Order Notes</h2>
            <.form for={@form} id="order-form" phx-change="validate">
              <.input field={@form[:notes]} type="textarea" label="Notes" />
            </.form>
          </div>

          <%!-- Add Items --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-primary-500 mb-4">Add Items</h2>
            <form phx-submit="add_item" id="add-item-form-edit" class="space-y-4">
              <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div class="md:col-span-2">
                  <label class="block text-sm font-medium text-primary-500 mb-1">Product</label>
                  <select
                    name="product_id"
                    id="product-select-edit"
                    phx-hook="ProductUnitTracker"
                    data-products={
                      Jason.encode!(
                        Enum.map(@products, fn p ->
                          %{id: p.id, unit: p.unit, default_amounts: p.default_unit_amounts}
                        end)
                      )
                    }
                    class="mt-1 block w-full rounded-md border-secondary-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    required
                  >
                    <option value="">Select a product</option>
                    <option :for={product <- @products} value={product.id}>
                      {product.name}{if product.unit, do: " (#{product.unit})", else: ""}
                    </option>
                  </select>
                </div>
                <div>
                  <label class="block text-sm font-medium text-primary-500 mb-1">Quantity</label>
                  <input
                    type="number"
                    name="quantity"
                    min="1"
                    value="1"
                    class="mt-1 block w-full rounded-md border-secondary-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    required
                  />
                </div>
              </div>

              <div id="unit-amount-container" class="hidden">
                <label class="block text-sm font-medium text-primary-500 mb-1">
                  Unit Amount <span id="unit-label" class="text-primary-400"></span>
                </label>
                <input
                  type="number"
                  name="unit_amount"
                  id="unit-amount-input"
                  step="0.01"
                  min="0"
                  placeholder="e.g., 500 for 500ml"
                  class="mt-1 block w-full rounded-md border-secondary-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
                <p class="mt-1 text-sm text-primary-400" id="unit-help-text"></p>
              </div>

              <.button type="submit" class="w-full">
                <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Add Item
              </.button>
            </form>
          </div>

          <%!-- Order Items List --%>
          <div class="bg-white shadow-lg rounded-lg p-6">
            <h2 class="text-2xl font-bold text-primary-500 mb-4">Order Items</h2>

            <div :if={@grouped_items == []} class="text-center py-8 text-primary-400">
              No items in this order yet
            </div>

            <div :if={@grouped_items != []} class="space-y-2">
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
                    <div class="flex items-center space-x-4">
                      <div class="text-lg font-bold text-primary-500">
                        {format_currency(group.total_price)}
                      </div>
                      <button
                        type="button"
                        phx-click="remove_group"
                        phx-value-item-ids={Jason.encode!(group.item_ids)}
                        data-confirm={
                          if group.grouped?,
                            do:
                              "Are you sure you want to remove all #{length(group.items)} items in this group?",
                            else: "Are you sure you want to remove this item?"
                        }
                        class="text-error hover:text-error-dark"
                      >
                        <.icon name="hero-trash" class="w-5 h-5" />
                      </button>
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
                      <div class="flex items-center justify-between">
                        <div class="text-sm text-primary-400">
                          <%= if item.unit_amount do %>
                            {item.quantity} × {item.unit_amount}{item.product.unit}
                          <% else %>
                            Qty: {item.quantity}
                          <% end %>
                        </div>
                        <div class="flex items-center space-x-3">
                          <div class="text-sm text-primary-500 font-medium">
                            {format_currency(item.subtotal)}
                          </div>
                          <button
                            type="button"
                            phx-click="remove_item"
                            phx-value-id={item.id}
                            data-confirm="Are you sure you want to remove this item?"
                            class="text-error hover:text-error-dark"
                          >
                            <.icon name="hero-x-mark" class="w-4 h-4" />
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <%!-- Order Summary --%>
        <div class="lg:col-span-1">
          <div class="bg-white shadow-lg rounded-lg p-6 sticky top-8">
            <h2 class="text-2xl font-bold text-primary-500 mb-4">Order Summary</h2>

            <div class="space-y-3">
              <div class="flex justify-between text-primary-400">
                <span>Subtotal:</span>
                <span>
                  {format_currency(
                    Decimal.add(@order.total_amount, @order.discount_amount || Decimal.new("0"))
                  )}
                </span>
              </div>

              <div class="border-t pt-3">
                <label class="block text-sm font-medium text-primary-500 mb-1">Discount</label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={@order.discount_amount || 0}
                  phx-change="update_discount"
                  name="discount"
                  class="block w-full rounded-md border-secondary-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>

              <div class="border-t pt-3">
                <div class="flex justify-between text-xl font-bold text-primary-500">
                  <span>Total:</span>
                  <span>{format_currency(@order.total_amount)}</span>
                </div>
              </div>

              <div class="border-t pt-3">
                <div class="space-y-1 text-sm">
                  <div class="flex justify-between">
                    <span class="text-primary-400">Status:</span>
                    <span class={[
                      "font-semibold",
                      case @order.status do
                        "paid" -> "text-success-dark"
                        "partially_paid" -> "text-yellow-600"
                        "open" -> "text-tertiary-600"
                        "cancelled" -> "text-error"
                        _ -> "text-primary-400"
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

            <.link navigate={~p"/admin/orders/#{@order}"} class="block mt-3">
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

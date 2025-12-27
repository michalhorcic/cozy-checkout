defmodule CozyCheckoutWeb.PurchaseOrderLive.FormComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Inventory
  alias CozyCheckout.Catalog

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="purchase-order-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:order_number]}
          type="text"
          label="Order Number"
          required
          readonly={@action == :edit}
        />

        <.input field={@form[:order_date]} type="date" label="Order Date" required />

        <.input
          field={@form[:supplier_note]}
          type="text"
          label="Supplier"
          placeholder="e.g., Jan's Brewery, Makro"
        />

        <.input field={@form[:notes]} type="textarea" label="Notes" rows="3" />

        <.input field={@form[:total_cost]} type="number" label="Total Cost" step="0.01" />

        <div class="mt-6">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-lg font-semibold text-gray-900">Items</h3>
            <button
              type="button"
              phx-click="add_item"
              phx-target={@myself}
              class="inline-flex items-center px-3 py-2 border border-transparent text-sm leading-4 font-medium rounded-md text-white bg-tertiary-600 hover:bg-tertiary-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-tertiary-500"
            >
              <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Add Item
            </button>
          </div>

          <%= if @items == [] do %>
            <p class="text-sm text-gray-500 italic">No items yet. Click "Add Item" to add products.</p>
          <% else %>
            <div class="space-y-4">
              <%= for {item, index} <- Enum.with_index(@items) do %>
                <div class="border border-gray-200 rounded-lg p-4 bg-gray-50">
                  <div class="flex justify-between items-start mb-3">
                    <h4 class="text-sm font-medium text-gray-700">Item #{index + 1}</h4>
                    <button
                      type="button"
                      phx-click="remove_item"
                      phx-value-index={index}
                      phx-target={@myself}
                      class="text-rose-600 hover:text-rose-800"
                    >
                      <.icon name="hero-trash" class="w-4 h-4" />
                    </button>
                  </div>

                  <%!-- Hidden field to track existing items by ID --%>
                  <%= if item[:id] do %>
                    <input type="hidden" name={"items[#{index}][id]"} value={item.id} />
                  <% end %>

                  <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Product <span class="text-rose-600">*</span>
                      </label>

                      <%!-- Show selected product or search input --%>
                      <%= if item.product_id do %>
                        <div class="relative">
                          <div class="flex items-center gap-2 p-3 bg-emerald-50 border-2 border-emerald-200 rounded-lg">
                            <.icon name="hero-check-circle" class="w-5 h-5 text-emerald-600 flex-shrink-0" />
                            <div class="flex-1 min-w-0">
                              <% selected_product = Enum.find(@products, &(&1.id == item.product_id)) %>
                              <div class="font-medium text-gray-900">{selected_product.name}</div>
                              <div class="text-sm text-gray-600">{selected_product.category.name}</div>
                            </div>
                            <button
                              type="button"
                              phx-click="clear_product"
                              phx-value-index={index}
                              phx-target={@myself}
                              class="p-1 hover:bg-emerald-100 rounded transition-colors"
                              title="Clear selection"
                            >
                              <.icon name="hero-x-mark" class="w-5 h-5 text-gray-500" />
                            </button>
                          </div>
                          <input type="hidden" name={"items[#{index}][product_id]"} value={item.product_id} />
                        </div>
                      <% else %>
                        <div class="relative" id={"product-search-#{index}"}>
                          <input
                            type="text"
                            id={"product-search-input-#{index}"}
                            value={get_in(@product_searches, [index]) || ""}
                            placeholder="Type to search products..."
                            phx-keyup="search_products"
                            phx-value-index={index}
                            phx-debounce="300"
                            phx-target={@myself}
                            autocomplete="off"
                            class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
                          />

                          <%!-- Search results dropdown --%>
                          <%= if get_in(@show_product_suggestions, [index]) do %>
                            <% search_query = get_in(@product_searches, [index]) || "" %>
                            <% filtered_products = @products
                              |> Enum.filter(fn p ->
                                query = String.downcase(search_query)
                                String.contains?(String.downcase(p.name), query) ||
                                String.contains?(String.downcase(p.category.name), query)
                              end)
                              |> Enum.take(10) %>

                            <div class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-lg overflow-auto border border-gray-200">
                              <%= if filtered_products == [] do %>
                                <div class="px-4 py-3 text-sm text-gray-500">
                                  No products found
                                </div>
                              <% else %>
                                <%= for product <- filtered_products do %>
                                  <button
                                    type="button"
                                    phx-click="select_product"
                                    phx-value-index={index}
                                    phx-value-product-id={product.id}
                                    phx-target={@myself}
                                    class="w-full text-left px-4 py-2 hover:bg-tertiary-600 hover:text-white transition-colors"
                                  >
                                    <div class="font-medium">{product.name}</div>
                                    <div class="text-sm opacity-75">
                                      {product.category.name}
                                      <%= if product.unit do %>
                                        <span class="ml-2">• {product.unit}</span>
                                      <% end %>
                                    </div>
                                  </button>
                                <% end %>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>

                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Quantity <span class="text-rose-600">*</span>
                      </label>
                      <input
                        type="number"
                        name={"items[#{index}][quantity]"}
                        value={item.quantity}
                        required
                        min="1"
                        step="1"
                        class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
                      />
                    </div>

                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Unit Amount {get_unit_label(item, @products)}
                      </label>
                      <input
                        type="number"
                        name={"items[#{index}][unit_amount]"}
                        value={item.unit_amount}
                        step="0.01"
                        placeholder="e.g., 500 for 500ml"
                        class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
                      />
                    </div>

                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Cost Price <span class="text-rose-600">*</span>
                      </label>
                      <input
                        type="text"
                        inputmode="decimal"
                        name={"items[#{index}][cost_price]"}
                        value={item.cost_price}
                        required
                        pattern="^\d+\.?\d*$"
                        placeholder="0.0000"
                        class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
                      />
                    </div>

                    <div class="md:col-span-2">
                      <label class="block text-sm font-medium text-gray-700 mb-1">Notes</label>
                      <input
                        type="text"
                        name={"items[#{index}][notes]"}
                        value={item.notes}
                        placeholder="Optional notes about this item"
                        class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
                      />
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="mt-6 flex items-center justify-end gap-x-6">
          <.button type="submit" phx-disable-with="Saving...">Save Purchase Order</.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{purchase_order: purchase_order} = assigns, socket) do
    # Load products with categories
    products = Catalog.list_products() |> Catalog.preload_categories()

    # Initialize items from existing purchase order items or empty list
    items =
      if purchase_order.id do
        Enum.map(purchase_order.purchase_order_items || [], fn item ->
          %{
            id: item.id,
            product_id: item.product_id,
            quantity: item.quantity,
            unit_amount: item.unit_amount,
            cost_price: item.cost_price,
            notes: item.notes
          }
        end)
      else
        []
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:products, products)
     |> assign(:items, items)
     |> assign(:deleted_item_ids, [])
     |> assign(:product_searches, %{})
     |> assign(:show_product_suggestions, %{})
     |> assign_form(Inventory.change_purchase_order(purchase_order))}
  end

  @impl true
  def handle_event("search_products", %{"index" => index, "value" => search_query}, socket) do
    index = String.to_integer(index)
    product_searches = Map.put(socket.assigns.product_searches, index, search_query)
    show_suggestions = Map.put(socket.assigns.show_product_suggestions, index, String.length(search_query) >= 2)

    {:noreply,
     socket
     |> assign(:product_searches, product_searches)
     |> assign(:show_product_suggestions, show_suggestions)}
  end

  @impl true
  def handle_event("select_product", %{"index" => index, "product-id" => product_id}, socket) do
    index = String.to_integer(index)

    # Update the item with the selected product
    items = List.update_at(socket.assigns.items, index, fn item ->
      Map.put(item, :product_id, product_id)
    end)

    # Clear the search for this index
    product_searches = Map.delete(socket.assigns.product_searches, index)
    show_suggestions = Map.put(socket.assigns.show_product_suggestions, index, false)

    {:noreply,
     socket
     |> assign(:items, items)
     |> assign(:product_searches, product_searches)
     |> assign(:show_product_suggestions, show_suggestions)}
  end

  @impl true
  def handle_event("clear_product", %{"index" => index}, socket) do
    index = String.to_integer(index)

    # Clear the product_id for this item
    items = List.update_at(socket.assigns.items, index, fn item ->
      Map.put(item, :product_id, nil)
    end)

    # Reset search state
    product_searches = Map.delete(socket.assigns.product_searches, index)
    show_suggestions = Map.put(socket.assigns.show_product_suggestions, index, false)

    {:noreply,
     socket
     |> assign(:items, items)
     |> assign(:product_searches, product_searches)
     |> assign(:show_product_suggestions, show_suggestions)}
  end

  @impl true
  def handle_event("validate", %{"purchase_order" => purchase_order_params} = params, socket) do
    changeset =
      socket.assigns.purchase_order
      |> Inventory.change_purchase_order(purchase_order_params)
      |> Map.put(:action, :validate)

    # Update items from form params to preserve user input
    items =
      case params do
        %{"items" => items_params} ->
          # Merge form params with existing items to preserve IDs and product_ids
          items_params
          |> Map.values()
          |> Enum.with_index()
          |> Enum.map(fn {item_params, index} ->
            existing_item = Enum.at(socket.assigns.items, index) || %{}

            %{
              id: item_params["id"] || existing_item[:id],
              product_id: item_params["product_id"] || existing_item[:product_id],
              quantity: parse_integer(item_params["quantity"]),
              unit_amount: parse_decimal(item_params["unit_amount"]),
              cost_price: parse_decimal(item_params["cost_price"]),
              notes: item_params["notes"]
            }
          end)
        _ ->
          socket.assigns.items
      end

    {:noreply,
     socket
     |> assign(:items, items)
     |> assign_form(changeset)}
  end

  # IMPORTANT: handle_event must match the exact params structure sent by the client
  # phx-click sends simple params, but phx-change sends the entire form structure
  def handle_event("add_item", _params, socket) do
    new_item = %{
      product_id: nil,
      quantity: 1,
      unit_amount: nil,
      cost_price: nil,
      notes: nil
    }

    items = socket.assigns.items ++ [new_item]
    {:noreply, assign(socket, :items, items)}
  end

  def handle_event("remove_item", %{"index" => index}, socket) do
    index = String.to_integer(index)
    item_to_remove = Enum.at(socket.assigns.items, index)
    items = List.delete_at(socket.assigns.items, index)

    # Track deleted item IDs if the item exists in database
    deleted_item_ids =
      if item_to_remove[:id] do
        [item_to_remove.id | socket.assigns.deleted_item_ids]
      else
        socket.assigns.deleted_item_ids
      end

    {:noreply,
     socket
     |> assign(:items, items)
     |> assign(:deleted_item_ids, deleted_item_ids)}
  end

  # This catches the save event with items
  def handle_event("save", %{"purchase_order" => purchase_order_params, "items" => items_params}, socket) do
    save_purchase_order(socket, socket.assigns.action, purchase_order_params, items_params)
  end

  # This catches the save event without items
  def handle_event("save", %{"purchase_order" => purchase_order_params}, socket) do
    save_purchase_order(socket, socket.assigns.action, purchase_order_params, %{})
  end

  # IMPORTANT: Catch-all for unmatched events to prevent crashes
  # This helps debug what params are actually being sent
  def handle_event(event, params, socket) do
    require Logger
    Logger.warning("Unhandled event in FormComponent: #{event}, params: #{inspect(params)}")
    {:noreply, socket}
  end

  defp save_purchase_order(socket, :new, purchase_order_params, items_params) do
    # Generate order number if not provided
    purchase_order_params =
      if purchase_order_params["order_number"] == "" do
        Map.put(purchase_order_params, "order_number", Inventory.generate_purchase_order_number())
      else
        purchase_order_params
      end

    case Inventory.create_purchase_order(purchase_order_params) do
      {:ok, purchase_order} ->
        # Create items
        create_items(purchase_order, items_params)

        notify_parent({:saved, purchase_order})

        {:noreply,
         socket
         |> put_flash(:info, "Purchase order created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_purchase_order(socket, :edit, purchase_order_params, items_params) do
    case Inventory.update_purchase_order(socket.assigns.purchase_order, purchase_order_params) do
      {:ok, purchase_order} ->
        # Delete removed items first
        delete_items(socket.assigns.deleted_item_ids)

        # Update/create items
        create_items(purchase_order, items_params)

        notify_parent({:saved, purchase_order})

        {:noreply,
         socket
         |> put_flash(:info, "Purchase order updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp delete_items(deleted_item_ids) do
    # Delete items directly by ID using Repo
    alias CozyCheckout.Repo
    alias CozyCheckout.Inventory.PurchaseOrderItem

    Enum.each(deleted_item_ids, fn item_id ->
      Repo.get(PurchaseOrderItem, item_id)
      |> case do
        nil -> :ok
        item -> Repo.delete(item)
      end
    end)
  end

  defp create_items(purchase_order, items_params) do
    items_params
    |> Map.values()
    |> Enum.each(fn item_params ->
      if item_params["product_id"] && item_params["product_id"] != "" do
        if item_params["id"] do
          # Update existing item
          case Inventory.get_purchase_order_item(item_params["id"]) do
            nil -> :ok
            item -> Inventory.update_purchase_order_item(item, item_params)
          end
        else
          # Create new item
          Inventory.create_purchase_order_item(purchase_order, item_params)
        end
      end
    end)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp get_unit_label(item, products) do
    case Enum.find(products, &(&1.id == item.product_id)) do
      nil -> ""
      product when product.unit -> "(#{product.unit})"
      _ -> ""
    end
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil
  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil
  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> value  # Keep as string if can't parse, for error display
    end
  end
  defp parse_decimal(value), do: value

  defp change_purchase_order(purchase_order, attrs \\ %{}) do
    Inventory.PurchaseOrder.changeset(purchase_order, attrs)
  end
end

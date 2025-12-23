defmodule CozyCheckoutWeb.StockAdjustmentLive.FormComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Inventory
  alias CozyCheckout.Catalog

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Record inventory adjustments for spillage, breakage, theft, or corrections</:subtitle>
      </.header>

      <.form
        for={@form}
        id="stock-adjustment-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="grid grid-cols-1 gap-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">
              Product <span class="text-rose-600">*</span>
            </label>
            <select
              name="stock_adjustment[product_id]"
              required
              phx-target={@myself}
              phx-change="select_product"
              class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
            >
              <option value="">Select a product...</option>
              <%= for product <- @products do %>
                <option value={product.id} selected={@form[:product_id].value == product.id}>
                  {product.name} - {product.category.name}
                </option>
              <% end %>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">
              Adjustment Type <span class="text-rose-600">*</span>
            </label>
            <select
              name="stock_adjustment[adjustment_type]"
              required
              class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
            >
              <option value="">Select type...</option>
              <option value="increase" selected={@form[:adjustment_type].value == "increase"}>Increase (found/returned stock)</option>
              <option value="decrease" selected={@form[:adjustment_type].value == "decrease"}>Decrease (general reduction)</option>
              <option value="spillage" selected={@form[:adjustment_type].value == "spillage"}>Spillage</option>
              <option value="breakage" selected={@form[:adjustment_type].value == "breakage"}>Breakage</option>
              <option value="theft" selected={@form[:adjustment_type].value == "theft"}>Theft</option>
              <option value="spoilage" selected={@form[:adjustment_type].value == "spoilage"}>Spoilage</option>
              <option value="expired" selected={@form[:adjustment_type].value == "expired"}>Expired</option>
              <option value="correction" selected={@form[:adjustment_type].value == "correction"}>Inventory Count Correction</option>
              <option value="other" selected={@form[:adjustment_type].value == "other"}>Other</option>
            </select>
            <p class="mt-1 text-xs text-gray-500">
              Use negative quantity for reductions (spillage, breakage, etc.) or positive for increases
            </p>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Quantity <span class="text-rose-600">*</span>
              </label>
              <input
                type="number"
                name="stock_adjustment[quantity]"
                value={@form[:quantity].value}
                required
                step="1"
                placeholder="Use - for reduction, + for increase"
                class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
              />
              <p class="mt-1 text-xs text-gray-500">
                Example: -5 for 5 units lost, +10 for 10 units found
              </p>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Unit Amount {get_unit_label(@selected_product)}
              </label>
              <input
                type="number"
                name="stock_adjustment[unit_amount]"
                value={@form[:unit_amount].value}
                step="0.01"
                placeholder="e.g., 500 for 500ml"
                class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
              />
            </div>
          </div>

          <div>
            <.input
              field={@form[:reason]}
              type="text"
              label="Reason"
              required
              placeholder="e.g., Dropped keg, Inventory count correction"
            />
          </div>

          <div>
            <.input
              field={@form[:notes]}
              type="textarea"
              label="Additional Notes"
              rows="3"
              placeholder="Optional detailed information about this adjustment"
            />
          </div>
        </div>

        <div class="mt-6 flex items-center justify-end gap-x-6">
          <.button type="submit" phx-disable-with="Saving...">
            Save Adjustment
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{stock_adjustment: stock_adjustment} = assigns, socket) do
    products = Catalog.list_products() |> Catalog.preload_categories()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:products, products)
     |> assign(:selected_product, nil)
     |> assign_form(Inventory.change_stock_adjustment(stock_adjustment))}
  end

  @impl true
  def handle_event("select_product", %{"stock_adjustment" => %{"product_id" => product_id}}, socket) do
    selected_product =
      if product_id != "" do
        Enum.find(socket.assigns.products, &(&1.id == product_id))
      else
        nil
      end

    {:noreply, assign(socket, :selected_product, selected_product)}
  end

  @impl true
  def handle_event("validate", %{"stock_adjustment" => stock_adjustment_params}, socket) do
    changeset =
      socket.assigns.stock_adjustment
      |> Inventory.change_stock_adjustment(stock_adjustment_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"stock_adjustment" => stock_adjustment_params}, socket) do
    save_stock_adjustment(socket, socket.assigns.action, stock_adjustment_params)
  end

  defp save_stock_adjustment(socket, :new, stock_adjustment_params) do
    case Inventory.create_stock_adjustment(stock_adjustment_params) do
      {:ok, stock_adjustment} ->
        # Reload with preloaded associations
        stock_adjustment = Inventory.get_stock_adjustment!(stock_adjustment.id)
        notify_parent({:saved, stock_adjustment})

        {:noreply,
         socket
         |> put_flash(:info, "Stock adjustment created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_stock_adjustment(socket, :edit, stock_adjustment_params) do
    case Inventory.update_stock_adjustment(socket.assigns.stock_adjustment, stock_adjustment_params) do
      {:ok, stock_adjustment} ->
        # Reload with preloaded associations
        stock_adjustment = Inventory.get_stock_adjustment!(stock_adjustment.id)
        notify_parent({:saved, stock_adjustment})

        {:noreply,
         socket
         |> put_flash(:info, "Stock adjustment updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp get_unit_label(nil), do: ""
  defp get_unit_label(product) when product.unit, do: "(#{product.unit})"
  defp get_unit_label(_), do: ""
end

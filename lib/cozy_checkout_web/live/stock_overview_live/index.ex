defmodule CozyCheckoutWeb.StockOverviewLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Inventory
  alias CozyCheckout.Catalog

  import CozyCheckoutWeb.CurrencyHelper

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:categories, Catalog.list_categories())
     |> assign(:selected_category_id, nil)
     |> assign(:search_query, "")
     |> assign(:show_inactive, false)
     |> assign(:show_stock_only, false)
     |> assign(:restock_modal_open, false)
     |> assign(:restock_product, nil)
     |> assign(:restock_unit_amounts, [])
     |> assign(:restock_unit_amount, nil)
     |> load_stock_overview()}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Stock Overview")}
  end

  @impl true
  def handle_event("filters_changed", params, socket) do
    category_id = if params["category_id"] == "", do: nil, else: params["category_id"]
    show_inactive = Map.has_key?(params, "show_inactive")
    show_stock_only = Map.has_key?(params, "show_stock_only")

    {:noreply,
     socket
     |> assign(:selected_category_id, category_id)
     |> assign(:search_query, params["search"] || "")
     |> assign(:show_inactive, show_inactive)
     |> assign(:show_stock_only, show_stock_only)
     |> load_stock_overview()}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_category_id, nil)
     |> assign(:search_query, "")
     |> assign(:show_inactive, false)
     |> assign(:show_stock_only, false)
     |> load_stock_overview()}
  end

  @impl true
  def handle_event("open_restock_modal", %{"product-id" => product_id}, socket) do
    item = Enum.find(socket.assigns.stock_items, fn i -> i.product.id == product_id end)

    if item do
      product = item.product

      unit_amounts =
        if product.default_unit_amounts && product.default_unit_amounts not in ["", "[]"] do
          Jason.decode!(product.default_unit_amounts)
        else
          []
        end

      {:noreply,
       socket
       |> assign(:restock_modal_open, true)
       |> assign(:restock_product, product)
       |> assign(:restock_unit_amounts, unit_amounts)
       |> assign(:restock_unit_amount, List.first(unit_amounts))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_restock_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:restock_modal_open, false)
     |> assign(:restock_product, nil)}
  end

  @impl true
  def handle_event("save_restock", %{"restock" => params}, socket) do
    product = socket.assigns.restock_product

    quantity =
      case Integer.parse(params["quantity"] || "") do
        {n, ""} when n > 0 -> n
        _ -> nil
      end

    if is_nil(quantity) do
      {:noreply, put_flash(socket, :error, "Quantity must be a positive number")}
    else
      unit_amount = if params["unit_amount"] in [nil, ""], do: nil, else: params["unit_amount"]
      cost_price = if params["cost_price"] in [nil, ""], do: nil, else: params["cost_price"]

      case Inventory.quick_restock(product.id, %{
             quantity: quantity,
             unit_amount: unit_amount,
             cost_price: cost_price
           }) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Added #{quantity} × #{product.name} to stock")
           |> assign(:restock_modal_open, false)
           |> assign(:restock_product, nil)
           |> load_stock_overview()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to save — check that quantity is valid")}
      end
    end
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  defp load_stock_overview(socket) do
    stock_items = Inventory.get_stock_overview()

    # Apply filters
    stock_items =
      stock_items
      |> filter_by_active(socket.assigns.show_inactive)
      |> filter_by_stock_only(socket.assigns.show_stock_only)
      |> filter_by_category(socket.assigns.selected_category_id)
      |> filter_by_search(socket.assigns.search_query)
      |> add_stock_status()

    assign(socket, :stock_items, stock_items)
  end

  defp filter_by_active(items, true), do: items

  defp filter_by_active(items, false) do
    Enum.filter(items, fn item -> item.product.active end)
  end

  defp filter_by_stock_only(items, false), do: items

  defp filter_by_stock_only(items, true) do
    Enum.filter(items, fn item -> !item.product.visible_in_pos end)
  end

  defp filter_by_category(items, nil), do: items

  defp filter_by_category(items, category_id) do
    Enum.filter(items, fn item ->
      item.product && item.product.category_id == category_id
    end)
  end

  defp filter_by_search(items, ""), do: items

  defp filter_by_search(items, query) do
    query = String.downcase(query)

    Enum.filter(items, fn item ->
      item.product &&
        String.contains?(String.downcase(item.product.name), query)
    end)
  end

  defp add_stock_status(items) do
    Enum.map(items, fn item ->
      status = determine_stock_status(item.stock, item.product.low_stock_threshold)
      Map.put(item, :status, status)
    end)
  end

  defp determine_stock_status(stock, threshold) do
    # Round down to get integer value for comparison
    stock_int = stock |> Decimal.round(0, :down) |> Decimal.to_integer()

    cond do
      stock_int <= 0 -> :out_of_stock
      stock_int <= threshold -> :low_stock
      true -> :in_stock
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link
          navigate={~p"/admin"}
          class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block"
        >
          ← Back to Dashboard
        </.link>
        <div class="flex items-end justify-between gap-4">
          <h1 class="text-4xl font-bold text-primary-500">{@page_title}</h1>
          <.link
            navigate={~p"/admin/stock/restock"}
            class="inline-flex items-center gap-2 px-4 py-2.5 bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-semibold rounded-lg transition-colors shadow-sm flex-shrink-0 mb-1"
          >
            <.icon name="hero-shopping-cart" class="w-4 h-4" /> Shopping Trip
          </.link>
        </div>
      </div>

      <%!-- Filters --%>
      <div class="bg-white shadow-lg rounded-lg p-6 mb-6">
        <form phx-change="filters_changed">
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Category</label>
              <select
                name="category_id"
                class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
              >
                <option value="">All Categories</option>
                <%= for category <- @categories do %>
                  <option value={category.id} selected={@selected_category_id == category.id}>
                    {category.name}
                  </option>
                <% end %>
              </select>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Search Product</label>
              <input
                type="text"
                phx-debounce="300"
                name="search"
                value={@search_query}
                placeholder="Type to search..."
                class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
              />
            </div>

            <div class="flex items-end">
              <button
                type="button"
                phx-click="clear_filters"
                class="w-full px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-colors"
              >
                Clear Filters
              </button>
            </div>
          </div>
          <div class="mt-3 pt-3 border-t border-gray-100 flex flex-wrap gap-x-6 gap-y-2">
            <label class="inline-flex items-center gap-2 cursor-pointer select-none">
              <input
                type="checkbox"
                name="show_inactive"
                value="true"
                checked={@show_inactive}
                class="rounded border-gray-300 text-tertiary-600 focus:ring-tertiary-500"
              />
              <span class="text-sm text-gray-600">Show inactive products</span>
            </label>
            <label class="inline-flex items-center gap-2 cursor-pointer select-none">
              <input
                type="checkbox"
                name="show_stock_only"
                value="true"
                checked={@show_stock_only}
                class="rounded border-gray-300 text-tertiary-600 focus:ring-tertiary-500"
              />
              <span class="text-sm text-gray-600">Stock-only products</span>
            </label>
          </div>
        </form>
      </div>

      <%!-- Stock Legend --%>
      <div class="bg-white shadow-lg rounded-lg p-4 mb-6">
        <div class="flex items-center justify-center gap-8">
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-rose-500 rounded"></div>
            <span class="text-sm text-gray-700">Out of Stock</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-amber-500 rounded"></div>
            <span class="text-sm text-gray-700">Low Stock</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 bg-emerald-500 rounded"></div>
            <span class="text-sm text-gray-700">In Stock</span>
          </div>
        </div>
      </div>

      <%!-- Stock Table --%>
      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <%= if @stock_items == [] do %>
          <div class="px-6 py-8 text-center text-gray-500">
            <div class="flex flex-col items-center justify-center">
              <.icon name="hero-archive-box" class="w-12 h-12 text-gray-400 mb-2" />
              <p class="text-lg">No stock data available</p>
              <p class="text-sm">Start by creating purchase orders to track inventory</p>
            </div>
          </div>
        <% else %>
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gradient-to-r from-primary-500 to-secondary-600">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                  Status
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                  Product
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                  Category
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                  Current Stock
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                  Low Stock Alert
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-white uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= for item <- @stock_items do %>
                <tr class={[
                  "hover:bg-gray-50 transition-colors",
                  item.status == :out_of_stock && "bg-rose-50",
                  item.status == :low_stock && "bg-amber-50"
                ]}>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class={[
                      "w-3 h-3 rounded-full",
                      item.status == :out_of_stock && "bg-rose-500",
                      item.status == :low_stock && "bg-amber-500",
                      item.status == :in_stock && "bg-emerald-500"
                    ]}>
                    </div>
                  </td>
                  <td class="px-6 py-4">
                    <div class="flex items-center gap-2">
                      <span class="text-sm font-medium text-gray-900">{item.product.name}</span>
                      <%= if !item.product.visible_in_pos do %>
                        <span class="px-1.5 py-0.5 text-xs font-semibold bg-violet-100 text-violet-700 rounded">Stock only</span>
                      <% end %>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {item.product.category.name}
                  </td>
                  <td class="px-6 py-4">
                    <div class={[
                      "text-sm font-semibold",
                      item.status == :out_of_stock && "text-rose-600",
                      item.status == :low_stock && "text-amber-600",
                      item.status == :in_stock && "text-emerald-600"
                    ]}>
                      <%= if Decimal.compare(item.stock, 0) == :eq do %>
                        <span class="text-gray-400">Out of stock</span>
                      <% else %>
                        {Decimal.to_string(Decimal.round(item.stock, 2))} {item.display_unit}
                      <% end %>
                    </div>

                    <%!-- Show conversion hint for volume products --%>
                    <%= if item.display_unit == "L" && item.product.default_unit_amounts && item.product.default_unit_amounts != "" && item.product.default_unit_amounts != "[]" do %>
                      <div class="text-xs text-gray-500 mt-1 space-x-3">
                        <%= for amount <- Jason.decode!(item.product.default_unit_amounts) do %>
                          <% servings =
                            item.raw_stock
                            |> Decimal.div(amount)
                            |> Decimal.round(0, :down)
                            |> Decimal.to_integer() %>
                          <%= if servings > 0 do %>
                            <span class="inline-block">
                              ≈ {servings} × {format_number(amount)}{item.product.unit}
                            </span>
                          <% end %>
                        <% end %>
                      </div>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= if item.product.low_stock_threshold > 0 do %>
                      ≤ {item.product.low_stock_threshold}
                    <% else %>
                      <span class="text-gray-400">Not set</span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-right">
                    <button
                      type="button"
                      phx-click="open_restock_modal"
                      phx-value-product-id={item.product.id}
                      class="inline-flex items-center gap-1 px-3 py-1.5 bg-emerald-100 hover:bg-emerald-200 text-emerald-800 text-xs font-semibold rounded-lg transition-colors"
                    >
                      <.icon name="hero-plus" class="w-3.5 h-3.5" /> Restock
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>

      <%!-- Summary Statistics --%>
      <div class="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="bg-white shadow-lg rounded-lg p-6">
          <div class="flex items-center">
            <div class="flex-shrink-0 bg-emerald-100 rounded-md p-3">
              <.icon name="hero-check-circle" class="w-6 h-6 text-emerald-600" />
            </div>
            <div class="ml-4">
              <p class="text-sm font-medium text-gray-500">In Stock</p>
              <p class="text-2xl font-semibold text-gray-900">
                {Enum.count(@stock_items, &(&1.status == :in_stock))}
              </p>
            </div>
          </div>
        </div>

        <div class="bg-white shadow-lg rounded-lg p-6">
          <div class="flex items-center">
            <div class="flex-shrink-0 bg-amber-100 rounded-md p-3">
              <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-amber-600" />
            </div>
            <div class="ml-4">
              <p class="text-sm font-medium text-gray-500">Low Stock</p>
              <p class="text-2xl font-semibold text-gray-900">
                {Enum.count(@stock_items, &(&1.status == :low_stock))}
              </p>
            </div>
          </div>
        </div>

        <div class="bg-white shadow-lg rounded-lg p-6">
          <div class="flex items-center">
            <div class="flex-shrink-0 bg-rose-100 rounded-md p-3">
              <.icon name="hero-x-circle" class="w-6 h-6 text-rose-600" />
            </div>
            <div class="ml-4">
              <p class="text-sm font-medium text-gray-500">Out of Stock</p>
              <p class="text-2xl font-semibold text-gray-900">
                {Enum.count(@stock_items, &(&1.status == :out_of_stock))}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <%!-- Quick Restock Modal --%>
    <%= if @restock_modal_open do %>
      <div
        class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4"
        phx-click="close_restock_modal"
      >
        <div
          class="bg-white rounded-xl shadow-2xl w-full max-w-md"
          phx-window-keydown="close_restock_modal"
          phx-key="Escape"
          phx-click="noop"
        >
          <div class="flex justify-between items-start px-6 py-4 border-b border-gray-200">
            <div>
              <h2 class="text-xl font-bold text-gray-900">Quick Restock</h2>
              <p class="text-sm text-gray-500 mt-0.5">{@restock_product.name}</p>
            </div>
            <button
              phx-click="close_restock_modal"
              class="text-gray-400 hover:text-gray-600 transition-colors mt-0.5"
            >
              <.icon name="hero-x-mark" class="w-6 h-6" />
            </button>
          </div>

          <form id="restock-form" phx-submit="save_restock">
            <div class="px-6 py-5 space-y-5">
              <%= cond do %>
                <% @restock_unit_amounts != [] -> %>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-2">Unit Size</label>
                    <div class="flex flex-wrap gap-2">
                      <%= for amount <- @restock_unit_amounts do %>
                        <label class="cursor-pointer">
                          <input
                            type="radio"
                            name="restock[unit_amount]"
                            value={amount}
                            checked={@restock_unit_amount == amount}
                            class="sr-only peer"
                          />
                          <span class="flex items-center px-4 py-2 rounded-lg border-2 border-gray-200 peer-checked:border-tertiary-500 peer-checked:bg-tertiary-50 text-sm font-semibold hover:border-gray-300 transition-colors select-none">
                            {format_number(amount)}{@restock_product.unit}
                          </span>
                        </label>
                      <% end %>
                    </div>
                  </div>
                <% @restock_product.unit && @restock_product.unit not in ["pcs"] -> %>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-2">
                      Unit Size ({@restock_product.unit})
                    </label>
                    <input
                      type="number"
                      name="restock[unit_amount]"
                      min="1"
                      step="any"
                      placeholder="e.g. 500"
                      class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
                    />
                  </div>
                <% true -> %>
              <% end %>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Quantity
                  <%= if @restock_product.unit && @restock_product.unit != "" do %>
                    <span class="text-gray-400 font-normal">(units)</span>
                  <% end %>
                </label>
                <input
                  type="number"
                  name="restock[quantity]"
                  min="1"
                  step="1"
                  value="1"
                  required
                  autofocus
                  class="block w-full text-2xl font-bold text-center rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 py-4"
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Cost per item
                  <span class="text-gray-400 font-normal">(optional)</span>
                </label>
                <div class="relative">
                  <input
                    type="number"
                    name="restock[cost_price]"
                    min="0"
                    step="0.01"
                    placeholder="0.00"
                    class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm pr-16"
                  />
                  <span class="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-gray-400 pointer-events-none">
                    CZK
                  </span>
                </div>
              </div>
            </div>

            <div class="px-6 py-4 bg-gray-50 border-t border-gray-200 rounded-b-xl flex justify-end gap-3">
              <button
                type="button"
                phx-click="close_restock_modal"
                class="px-4 py-2 text-sm font-medium text-gray-600 hover:text-gray-900 transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="inline-flex items-center px-5 py-2 bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-semibold rounded-lg transition-colors"
              >
                <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Add to Stock
              </button>
            </div>
          </form>
        </div>
      </div>
    <% end %>
    """
  end
end

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
     |> load_stock_overview()}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Stock Overview")}
  end

  @impl true
  def handle_event("filter_category", %{"category_id" => category_id}, socket) do
    category_id = if category_id == "", do: nil, else: category_id

    {:noreply,
     socket
     |> assign(:selected_category_id, category_id)
     |> load_stock_overview()}
  end

  @impl true
  def handle_event("search", %{"search" => search_query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, search_query)
     |> load_stock_overview()}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_category_id, nil)
     |> assign(:search_query, "")
     |> load_stock_overview()}
  end

  defp load_stock_overview(socket) do
    stock_items = Inventory.get_stock_overview()

    # Apply filters
    stock_items =
      stock_items
      |> filter_by_category(socket.assigns.selected_category_id)
      |> filter_by_search(socket.assigns.search_query)
      |> add_stock_status()

    assign(socket, :stock_items, stock_items)
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
    stock_int = Decimal.to_integer(stock)

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
        <.link navigate={~p"/admin"} class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block">
          ← Back to Dashboard
        </.link>
        <h1 class="text-4xl font-bold text-primary-500">{@page_title}</h1>
      </div>

      <%!-- Filters --%>
      <div class="bg-white shadow-lg rounded-lg p-6 mb-6">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">Category</label>
            <select
              phx-change="filter_category"
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
              phx-change="search"
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
                  Unit Amount
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                  Current Stock
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                  Low Stock Alert
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
                    <div class="text-sm font-medium text-gray-900">{item.product.name}</div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {item.product.category.name}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= if item.unit_amount do %>
                      {format_number(item.unit_amount)} {item.product.unit || ""}
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span class={[
                      "text-sm font-semibold",
                      item.status == :out_of_stock && "text-rose-600",
                      item.status == :low_stock && "text-amber-600",
                      item.status == :in_stock && "text-emerald-600"
                    ]}>
                      {format_number(item.stock)}
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= if item.product.low_stock_threshold > 0 do %>
                      ≤ {item.product.low_stock_threshold}
                    <% else %>
                      <span class="text-gray-400">Not set</span>
                    <% end %>
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
    """
  end
end

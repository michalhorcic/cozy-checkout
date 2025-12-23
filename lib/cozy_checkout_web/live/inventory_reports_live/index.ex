defmodule CozyCheckoutWeb.InventoryReportsLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Inventory
  alias CozyCheckout.Catalog

  import CozyCheckoutWeb.CurrencyHelper

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Inventory Reports")
     |> assign(:active_tab, "valuation")
     |> assign(:products, Catalog.list_products() |> Catalog.preload_categories())
     |> assign_filters()
     |> load_reports()}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign_filters(params)
     |> load_reports()}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign_filters()
     |> load_reports()}
  end

  defp assign_filters(socket, params \\ %{}) do
    socket
    |> assign(:start_date, params["start_date"] || "")
    |> assign(:end_date, params["end_date"] || "")
    |> assign(:product_id, params["product_id"] || "")
    |> assign(:transaction_type, params["transaction_type"] || "")
  end

  defp load_reports(socket) do
    filters = build_filters(socket.assigns)

    valuation = Inventory.get_inventory_valuation()
    profit_analysis = Inventory.get_profit_analysis(filters)
    movements = Inventory.get_stock_movements(filters)

    # Calculate summary metrics
    total_value = valuation
      |> Enum.map(& &1.total_value)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    total_profit = profit_analysis
      |> Enum.map(& &1.total_profit)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    avg_margin = if Enum.empty?(profit_analysis) do
      Decimal.new(0)
    else
      profit_analysis
      |> Enum.map(& &1.profit_margin_percent)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
      |> Decimal.div(length(profit_analysis))
    end

    socket
    |> assign(:valuation_items, valuation)
    |> assign(:profit_items, profit_analysis)
    |> assign(:movements, movements)
    |> assign(:total_inventory_value, total_value)
    |> assign(:total_profit, total_profit)
    |> assign(:avg_profit_margin, avg_margin)
    |> assign(:movement_count, length(movements))
  end

  defp build_filters(assigns) do
    filters = %{}

    filters = if assigns.start_date != "" && assigns.end_date != "" do
      Map.merge(filters, %{
        start_date: Date.from_iso8601!(assigns.start_date),
        end_date: Date.from_iso8601!(assigns.end_date)
      })
    else
      filters
    end

    filters = if assigns.product_id != "" do
      Map.put(filters, :product_id, assigns.product_id)
    else
      filters
    end

    filters = if assigns.transaction_type != "" do
      Map.put(filters, :transaction_type, assigns.transaction_type)
    else
      filters
    end

    filters
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

      <%!-- Summary Cards --%>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <div class="bg-gradient-to-br from-emerald-500 to-teal-600 rounded-lg shadow-lg p-6 text-white">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-emerald-100 text-sm font-medium">Total Inventory Value</p>
              <p class="text-3xl font-bold mt-1">{format_currency(@total_inventory_value)}</p>
            </div>
            <.icon name="hero-archive-box" class="w-12 h-12 opacity-80" />
          </div>
        </div>

        <div class="bg-gradient-to-br from-blue-500 to-indigo-600 rounded-lg shadow-lg p-6 text-white">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-blue-100 text-sm font-medium">Total Profit</p>
              <p class="text-3xl font-bold mt-1">{format_currency(@total_profit)}</p>
            </div>
            <.icon name="hero-currency-dollar" class="w-12 h-12 opacity-80" />
          </div>
        </div>

        <div class="bg-gradient-to-br from-purple-500 to-pink-600 rounded-lg shadow-lg p-6 text-white">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-purple-100 text-sm font-medium">Avg. Profit Margin</p>
              <p class="text-3xl font-bold mt-1">{Decimal.round(@avg_profit_margin, 1)}%</p>
            </div>
            <.icon name="hero-chart-bar" class="w-12 h-12 opacity-80" />
          </div>
        </div>
      </div>

      <%!-- Filters --%>
      <div class="bg-white shadow-lg rounded-lg p-6 mb-6">
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Filters</h3>
        <form phx-change="filter">
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
              <input
                type="date"
                name="start_date"
                value={@start_date}
                class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">End Date</label>
              <input
                type="date"
                name="end_date"
                value={@end_date}
                class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Product</label>
              <select
                name="product_id"
                class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
              >
                <option value="">All Products</option>
                <%= for product <- @products do %>
                  <option value={product.id} selected={@product_id == product.id}>
                    {product.name} - {product.category.name}
                  </option>
                <% end %>
              </select>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Transaction Type</label>
              <select
                name="transaction_type"
                class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
              >
                <option value="">All Types</option>
                <option value="purchase" selected={@transaction_type == "purchase"}>Purchases</option>
                <option value="sale" selected={@transaction_type == "sale"}>Sales</option>
                <option value="adjustment" selected={@transaction_type == "adjustment"}>Adjustments</option>
              </select>
            </div>
          </div>
          <div class="mt-4">
            <button
              type="button"
              phx-click="clear_filters"
              class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-colors"
            >
              Clear Filters
            </button>
          </div>
        </form>
      </div>

      <%!-- Tabs --%>
      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <div class="border-b border-gray-200">
          <nav class="flex -mb-px">
            <button
              phx-click="change_tab"
              phx-value-tab="valuation"
              class={[
                "px-6 py-4 text-sm font-medium border-b-2 transition-colors",
                @active_tab == "valuation" && "border-tertiary-500 text-tertiary-600",
                @active_tab != "valuation" && "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              Inventory Valuation
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="profit"
              class={[
                "px-6 py-4 text-sm font-medium border-b-2 transition-colors",
                @active_tab == "profit" && "border-tertiary-500 text-tertiary-600",
                @active_tab != "profit" && "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              Profit Analysis
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="movements"
              class={[
                "px-6 py-4 text-sm font-medium border-b-2 transition-colors",
                @active_tab == "movements" && "border-tertiary-500 text-tertiary-600",
                @active_tab != "movements" && "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              Stock Movements ({@movement_count})
            </button>
          </nav>
        </div>

        <%!-- Tab Content --%>
        <div class="p-6">
          <%= if @active_tab == "valuation" do %>
            <.valuation_table items={@valuation_items} />
          <% end %>

          <%= if @active_tab == "profit" do %>
            <.profit_table items={@profit_items} />
          <% end %>

          <%= if @active_tab == "movements" do %>
            <.movements_table movements={@movements} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp valuation_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead>
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Product
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Current Stock
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Unit Cost
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Total Value
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <%= for item <- @items do %>
            <tr class="hover:bg-gray-50">
              <td class="px-6 py-4">
                <div class="text-sm font-medium text-gray-900">{item.product.name}</div>
                <div class="text-sm text-gray-500">{item.product.category.name}</div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                {Decimal.to_string(Decimal.round(item.stock, 2))} {item.product.unit || "pcs"}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= if item.unit_cost do %>
                  {format_currency(item.unit_cost)}
                <% else %>
                  <span class="text-gray-400">—</span>
                <% end %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm font-semibold text-gray-900">
                {format_currency(item.total_value)}
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp profit_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead>
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Product
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Avg Cost
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Avg Sale Price
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Profit/Unit
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Margin %
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Total Sold
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Total Profit
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <%= for item <- @items do %>
            <tr class="hover:bg-gray-50">
              <td class="px-6 py-4">
                <div class="text-sm font-medium text-gray-900">{item.product.name}</div>
                <div class="text-sm text-gray-500">{item.product.category.name}</div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= if item.avg_purchase_cost do %>
                  {format_currency(item.avg_purchase_cost)}
                <% else %>
                  <span class="text-gray-400">—</span>
                <% end %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= if item.avg_sale_price do %>
                  {format_currency(item.avg_sale_price)}
                <% else %>
                  <span class="text-gray-400">—</span>
                <% end %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm">
                <span class={[
                  "font-semibold",
                  Decimal.compare(item.profit_per_unit, 0) == :gt && "text-emerald-600",
                  Decimal.compare(item.profit_per_unit, 0) == :lt && "text-rose-600",
                  Decimal.compare(item.profit_per_unit, 0) == :eq && "text-gray-900"
                ]}>
                  {format_currency(item.profit_per_unit)}
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class={[
                  "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                  Decimal.compare(item.profit_margin_percent, 30) != :lt && "bg-emerald-100 text-emerald-800",
                  Decimal.compare(item.profit_margin_percent, 30) == :lt && Decimal.compare(item.profit_margin_percent, 15) != :lt && "bg-amber-100 text-amber-800",
                  Decimal.compare(item.profit_margin_percent, 15) == :lt && Decimal.compare(item.profit_margin_percent, 0) == :gt && "bg-orange-100 text-orange-800",
                  Decimal.compare(item.profit_margin_percent, 0) != :gt && "bg-rose-100 text-rose-800"
                ]}>
                  {Decimal.round(item.profit_margin_percent, 1)}%
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= if is_struct(item.total_sold, Decimal) do %>
                  {Decimal.to_string(item.total_sold)}
                <% else %>
                  {item.total_sold}
                <% end %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm">
                <span class={[
                  "font-bold",
                  Decimal.compare(item.total_profit, 0) == :gt && "text-emerald-600",
                  Decimal.compare(item.total_profit, 0) == :lt && "text-rose-600",
                  Decimal.compare(item.total_profit, 0) == :eq && "text-gray-900"
                ]}>
                  {format_currency(item.total_profit)}
                </span>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp movements_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead>
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Date
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Type
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Product
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Quantity
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Price
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Reference
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <%= for movement <- @movements do %>
            <tr class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                {Calendar.strftime(movement.date, "%b %d, %Y")}
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class={[
                  "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                  movement.type == "purchase" && "bg-blue-100 text-blue-800",
                  movement.type == "sale" && "bg-rose-100 text-rose-800",
                  String.starts_with?(movement.type, "adjustment") && "bg-amber-100 text-amber-800"
                ]}>
                  {format_type(movement.type)}
                </span>
              </td>
              <td class="px-6 py-4">
                <div class="text-sm font-medium text-gray-900">{movement.product_name}</div>
                <div class="text-sm text-gray-500">{movement.category_name}</div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class={[
                  "text-sm font-semibold",
                  Decimal.compare(movement.quantity, 0) == :gt && "text-emerald-600",
                  Decimal.compare(movement.quantity, 0) == :lt && "text-rose-600"
                ]}>
                  {format_quantity(movement.quantity, movement.unit_amount, movement.unit)}
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <%= if movement.price do %>
                  {format_currency(movement.price)}
                <% else %>
                  <span class="text-gray-400">—</span>
                <% end %>
              </td>
              <td class="px-6 py-4">
                <div class="text-sm text-gray-900">{movement.reference}</div>
                <%= if movement.notes do %>
                  <div class="text-xs text-gray-500">{movement.notes}</div>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp format_type("purchase"), do: "Purchase"
  defp format_type("sale"), do: "Sale"
  defp format_type("adjustment-" <> type), do: "Adj: #{type}"
  defp format_type(type), do: type

  defp format_quantity(quantity, unit_amount, unit) do
    # Convert to Decimal if it's an integer
    quantity = if is_integer(quantity), do: Decimal.new(quantity), else: quantity

    base = if Decimal.compare(quantity, 0) == :gt, do: "+", else: ""
    amount_str = if unit_amount, do: " × #{unit_amount}", else: ""
    unit_str = if unit, do: " #{unit}", else: ""

    "#{base}#{Decimal.to_string(quantity)}#{amount_str}#{unit_str}"
  end
end

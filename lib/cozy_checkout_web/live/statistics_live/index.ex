defmodule CozyCheckoutWeb.StatisticsLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales

  @impl true
  def mount(_params, _session, socket) do
    # Default to last 30 days
    date_to = Date.utc_today()
    date_from = Date.add(date_to, -30)

    socket =
      socket
      |> assign(:date_from, date_from)
      |> assign(:date_to, date_to)
      |> assign(:status_filter, ["paid", "open"])
      |> assign(:preset, "last_30_days")
      |> load_statistics()

    {:ok, socket}
  end

  @impl true
  def handle_event("apply_preset", %{"preset" => preset}, socket) do
    date_to = Date.utc_today()

    date_from =
      case preset do
        "last_7_days" -> Date.add(date_to, -7)
        "last_30_days" -> Date.add(date_to, -30)
        "last_90_days" -> Date.add(date_to, -90)
        "this_month" -> Date.beginning_of_month(date_to)
        "last_month" -> Date.beginning_of_month(Date.add(date_to, -30))
        "this_year" -> %{date_to | month: 1, day: 1}
        _ -> Date.add(date_to, -30)
      end

    date_to =
      case preset do
        "last_month" -> Date.end_of_month(Date.add(Date.utc_today(), -30))
        _ -> date_to
      end

    socket =
      socket
      |> assign(:date_from, date_from)
      |> assign(:date_to, date_to)
      |> assign(:preset, preset)
      |> load_statistics()

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_dates", %{"date_from" => date_from, "date_to" => date_to}, socket) do
    with {:ok, from} <- Date.from_iso8601(date_from),
         {:ok, to} <- Date.from_iso8601(date_to) do
      socket =
        socket
        |> assign(:date_from, from)
        |> assign(:date_to, to)
        |> assign(:preset, "custom")
        |> load_statistics()

      {:noreply, socket}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid date format")}
    end
  end

  @impl true
  def handle_event("update_status_filter", %{"status" => status_map}, socket) do
    status_filter =
      status_map
      |> Enum.filter(fn {_k, v} -> v == "true" end)
      |> Enum.map(fn {k, _v} -> k end)

    socket =
      socket
      |> assign(:status_filter, status_filter)
      |> load_statistics()

    {:noreply, socket}
  end

  defp load_statistics(socket) do
    date_from = socket.assigns.date_from
    date_to = socket.assigns.date_to
    status_filter = socket.assigns.status_filter

    # Convert dates to datetime for database queries
    datetime_from = DateTime.new!(date_from, ~T[00:00:00])
    datetime_to = DateTime.new!(date_to, ~T[23:59:59])

    categories_with_products =
      Sales.get_product_statistics(datetime_from, datetime_to, status_filter)

    most_popular = Sales.get_most_popular_products(datetime_from, datetime_to, status_filter, 10)
    top_revenue = Sales.get_top_revenue_products(datetime_from, datetime_to, status_filter, 10)
    overall = Sales.get_overall_statistics(datetime_from, datetime_to, status_filter)

    socket
    |> assign(:categories_with_products, categories_with_products)
    |> assign(:most_popular, most_popular)
    |> assign(:top_revenue, top_revenue)
    |> assign(:overall, overall)
  end

  defp format_unit_display(nil, _), do: "—"

  defp format_unit_display(_total_amount, unit) when is_nil(unit), do: "—"

  defp format_unit_display(total_amount, unit) do
    if Decimal.eq?(total_amount, 0) do
      "—"
    else
      # Convert to appropriate unit
      formatted_amount =
        case unit do
          "ml" ->
            # Convert to L if >= 1000ml
            ml = Decimal.to_float(total_amount)

            if ml >= 1000 do
              l = ml / 1000
              "#{CozyCheckoutWeb.CurrencyHelper.format_number(l)} L"
            else
              "#{CozyCheckoutWeb.CurrencyHelper.format_number(ml)} ml"
            end

          "L" ->
            "#{CozyCheckoutWeb.CurrencyHelper.format_number(Decimal.to_float(total_amount))} L"

          "pcs" ->
            "#{CozyCheckoutWeb.CurrencyHelper.format_number(Decimal.to_float(total_amount))} pcs"

          _ ->
            "#{CozyCheckoutWeb.CurrencyHelper.format_number(Decimal.to_float(total_amount))} #{unit}"
        end

      formatted_amount
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
        <!-- Header -->
        <div class="mb-8">
          <div class="flex items-center justify-between">
            <div>
              <h1 class="text-3xl font-bold text-gray-900">Sales Statistics</h1>
              <p class="mt-2 text-sm text-gray-500">
                Product sales analysis and reports
              </p>
            </div>
            <.link
              navigate={~p"/admin"}
              class="px-4 py-2 bg-gray-800 text-white rounded-md hover:bg-gray-700 transition-colors"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4 inline mr-2" /> Back to Dashboard
            </.link>
          </div>
        </div>

        <!-- Date Range & Filters -->
        <div class="bg-white shadow rounded-lg p-6 mb-6">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <!-- Date Range Selection -->
            <div>
              <h3 class="text-lg font-medium text-gray-900 mb-4">Date Range</h3>
              <!-- Preset Buttons -->
              <div class="flex flex-wrap gap-2 mb-4">
                <button
                  phx-click="apply_preset"
                  phx-value-preset="last_7_days"
                  class={[
                    "px-3 py-2 text-sm font-medium rounded-md",
                    @preset == "last_7_days" && "bg-emerald-600 text-white",
                    @preset != "last_7_days" && "bg-gray-100 text-gray-700 hover:bg-gray-200"
                  ]}
                >
                  Last 7 days
                </button>
                <button
                  phx-click="apply_preset"
                  phx-value-preset="last_30_days"
                  class={[
                    "px-3 py-2 text-sm font-medium rounded-md",
                    @preset == "last_30_days" && "bg-emerald-600 text-white",
                    @preset != "last_30_days" && "bg-gray-100 text-gray-700 hover:bg-gray-200"
                  ]}
                >
                  Last 30 days
                </button>
                <button
                  phx-click="apply_preset"
                  phx-value-preset="last_90_days"
                  class={[
                    "px-3 py-2 text-sm font-medium rounded-md",
                    @preset == "last_90_days" && "bg-emerald-600 text-white",
                    @preset != "last_90_days" && "bg-gray-100 text-gray-700 hover:bg-gray-200"
                  ]}
                >
                  Last 90 days
                </button>
                <button
                  phx-click="apply_preset"
                  phx-value-preset="this_month"
                  class={[
                    "px-3 py-2 text-sm font-medium rounded-md",
                    @preset == "this_month" && "bg-emerald-600 text-white",
                    @preset != "this_month" && "bg-gray-100 text-gray-700 hover:bg-gray-200"
                  ]}
                >
                  This month
                </button>
                <button
                  phx-click="apply_preset"
                  phx-value-preset="last_month"
                  class={[
                    "px-3 py-2 text-sm font-medium rounded-md",
                    @preset == "last_month" && "bg-emerald-600 text-white",
                    @preset != "last_month" && "bg-gray-100 text-gray-700 hover:bg-gray-200"
                  ]}
                >
                  Last month
                </button>
                <button
                  phx-click="apply_preset"
                  phx-value-preset="this_year"
                  class={[
                    "px-3 py-2 text-sm font-medium rounded-md",
                    @preset == "this_year" && "bg-emerald-600 text-white",
                    @preset != "this_year" && "bg-gray-100 text-gray-700 hover:bg-gray-200"
                  ]}
                >
                  This year
                </button>
              </div>

              <!-- Custom Date Range -->
              <form phx-submit="update_dates" class="flex gap-3 items-end">
                <div class="flex-1">
                  <label class="block text-sm font-medium text-gray-700 mb-1">From</label>
                  <input
                    type="date"
                    name="date_from"
                    value={@date_from}
                    class="block w-full rounded-md border-gray-300 shadow-sm focus:border-emerald-500 focus:ring-emerald-500 sm:text-sm"
                  />
                </div>
                <div class="flex-1">
                  <label class="block text-sm font-medium text-gray-700 mb-1">To</label>
                  <input
                    type="date"
                    name="date_to"
                    value={@date_to}
                    class="block w-full rounded-md border-gray-300 shadow-sm focus:border-emerald-500 focus:ring-emerald-500 sm:text-sm"
                  />
                </div>
                <button
                  type="submit"
                  class="px-4 py-2 bg-emerald-600 text-white text-sm font-medium rounded-md hover:bg-emerald-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-emerald-500"
                >
                  Apply
                </button>
              </form>
            </div>

            <!-- Status Filter -->
            <div>
              <h3 class="text-lg font-medium text-gray-900 mb-4">Order Status Filter</h3>
              <form phx-change="update_status_filter" class="space-y-2">
                <div class="flex items-center">
                  <input
                    type="checkbox"
                    id="status_paid"
                    name="status[paid]"
                    value="true"
                    checked={@status_filter && "paid" in @status_filter}
                    class="h-4 w-4 text-emerald-600 focus:ring-emerald-500 border-gray-300 rounded"
                  />
                  <label for="status_paid" class="ml-2 block text-sm text-gray-900">
                    Paid orders
                  </label>
                </div>
                <div class="flex items-center">
                  <input
                    type="checkbox"
                    id="status_open"
                    name="status[open]"
                    value="true"
                    checked={@status_filter && "open" in @status_filter}
                    class="h-4 w-4 text-emerald-600 focus:ring-emerald-500 border-gray-300 rounded"
                  />
                  <label for="status_open" class="ml-2 block text-sm text-gray-900">
                    Open orders
                  </label>
                </div>
                <div class="flex items-center">
                  <input
                    type="checkbox"
                    id="status_partially_paid"
                    name="status[partially_paid]"
                    value="true"
                    checked={@status_filter && "partially_paid" in @status_filter}
                    class="h-4 w-4 text-emerald-600 focus:ring-emerald-500 border-gray-300 rounded"
                  />
                  <label for="status_partially_paid" class="ml-2 block text-sm text-gray-900">
                    Partially paid orders
                  </label>
                </div>
              </form>
            </div>
          </div>
        </div>

        <!-- Overall Statistics -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
          <div class="bg-white shadow rounded-lg p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <.icon name="hero-shopping-bag" class="h-8 w-8 text-emerald-600" />
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Total Orders</p>
                <p class="text-2xl font-semibold text-gray-900">
                  {CozyCheckoutWeb.CurrencyHelper.format_number(@overall.total_orders)}
                </p>
              </div>
            </div>
          </div>

          <div class="bg-white shadow rounded-lg p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <.icon name="hero-currency-dollar" class="h-8 w-8 text-emerald-600" />
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Total Revenue</p>
                <p class="text-2xl font-semibold text-gray-900">
                  {CozyCheckoutWeb.CurrencyHelper.format_currency(@overall.total_revenue || Decimal.new("0"))}
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Top Products -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
          <!-- Most Popular Products -->
          <div class="bg-white shadow rounded-lg overflow-hidden">
            <div class="px-6 py-4 border-b border-gray-200">
              <h3 class="text-lg font-medium text-gray-900">Most Popular Products</h3>
              <p class="mt-1 text-sm text-gray-500">By quantity sold</p>
            </div>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Product
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Category
                    </th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Quantity
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <%= for product <- @most_popular do %>
                    <tr>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        {product.product_name}
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        {product.category_name}
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right font-medium">
                        {CozyCheckoutWeb.CurrencyHelper.format_number(product.total_quantity)}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>

          <!-- Top Revenue Products -->
          <div class="bg-white shadow rounded-lg overflow-hidden">
            <div class="px-6 py-4 border-b border-gray-200">
              <h3 class="text-lg font-medium text-gray-900">Top Revenue Products</h3>
              <p class="mt-1 text-sm text-gray-500">By total revenue</p>
            </div>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Product
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Category
                    </th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Revenue
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <%= for product <- @top_revenue do %>
                    <tr>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        {product.product_name}
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        {product.category_name}
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right font-medium">
                        {CozyCheckoutWeb.CurrencyHelper.format_currency(product.total_revenue)}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- Products by Category -->
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <div class="px-6 py-4 border-b border-gray-200">
            <h3 class="text-lg font-medium text-gray-900">All Products - Sales Details</h3>
            <p class="mt-1 text-sm text-gray-500">Grouped by category</p>
          </div>

          <%= for category <- @categories_with_products do %>
            <div class="border-b border-gray-200 last:border-b-0">
              <div class="px-6 py-3 bg-gray-50">
                <h4 class="text-sm font-semibold text-gray-900 uppercase tracking-wider">
                  {category.category_name}
                </h4>
              </div>
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-gray-200">
                  <thead class="bg-gray-50">
                    <tr>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Product
                      </th>
                      <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Quantity Sold
                      </th>
                      <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Total Amount
                      </th>
                      <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Total Revenue
                      </th>
                      <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Orders
                      </th>
                    </tr>
                  </thead>
                  <tbody class="bg-white divide-y divide-gray-200">
                    <%= for product <- category.products do %>
                      <tr>
                        <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                          {product.product_name}
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                          {CozyCheckoutWeb.CurrencyHelper.format_number(product.total_quantity)}
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                          {format_unit_display(product.total_amount, product.product_unit)}
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right font-medium">
                          {CozyCheckoutWeb.CurrencyHelper.format_currency(product.total_revenue)}
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 text-right">
                          {CozyCheckoutWeb.CurrencyHelper.format_number(product.order_count)}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end

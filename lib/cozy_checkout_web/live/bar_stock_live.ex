defmodule CozyCheckoutWeb.BarStockLive do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Inventory

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    default_start_date = Date.add(today, -30) |> Date.to_iso8601()
    default_end_date = Date.to_iso8601(today)

    {:ok,
     socket
     |> assign(:product_search, "")
     |> assign(:product_search_results, [])
     |> assign(:selected_product, nil)
     |> assign(:show_product_results, false)
     |> assign(:loss_start_date, default_start_date)
     |> assign(:loss_end_date, default_end_date)
     |> assign(:movement_search, "")
     |> assign(:movement_type, "")
     |> assign(:movement_start_date, default_start_date)
     |> assign(:movement_end_date, default_end_date)
     |> assign(:movement_page, 1)
     |> load_stock()}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Bar Stock")}
  end

  @impl true
  def handle_event("add_product", %{"bar_stock" => params}, socket) do
    if socket.assigns.selected_product &&
         params["product_id"] == socket.assigns.selected_product.id do
      case Inventory.add_product_to_bar(params["product_id"], params) do
        {:ok, product} ->
          {:noreply,
           socket
           |> put_flash(:info, "#{product.name} added to bar stock")
           |> assign(:selected_product, nil)
           |> assign(:product_search, "")
           |> load_stock()}

        {:error, :already_tracked} ->
          {:noreply, put_flash(socket, :error, "This product is already tracked in bar stock")}

        {:error, :invalid_quantity} ->
          {:noreply, put_flash(socket, :error, "Enter valid non-negative amounts")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not add product to bar stock")}
      end
    else
      {:noreply, put_flash(socket, :error, "Search for and select a product first")}
    end
  end

  def handle_event("search_products", %{"search" => query}, socket) do
    query_lower = String.downcase(String.trim(query))

    results =
      if query_lower == "" do
        []
      else
        socket.assigns.bar_stock_candidates
        |> Enum.filter(fn product ->
          String.contains?(String.downcase(product.name), query_lower) ||
            (product.category &&
               String.contains?(String.downcase(product.category.name), query_lower))
        end)
        |> Enum.take(10)
      end

    {:noreply,
     socket
     |> assign(:product_search, query)
     |> assign(:product_search_results, results)
     |> assign(:selected_product, nil)
     |> assign(:show_product_results, query_lower != "")}
  end

  def handle_event("select_product", %{"id" => product_id}, socket) do
    product = Enum.find(socket.assigns.bar_stock_candidates, &(&1.id == product_id))

    if product do
      {:noreply,
       socket
       |> assign(:selected_product, product)
       |> assign(:product_search, "")
       |> assign(:product_search_results, [])
       |> assign(:show_product_results, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_product", _params, socket) do
    {:noreply, assign(socket, :selected_product, nil)}
  end

  def handle_event("clear_product_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:product_search, "")
     |> assign(:product_search_results, [])
     |> assign(:show_product_results, false)}
  end

  def handle_event("restock", %{"product_id" => product_id, "quantity" => quantity}, socket) do
    case Inventory.restock_bar_stock(product_id, quantity) do
      {:ok, _movement} ->
        {:noreply,
         socket
         |> put_flash(:info, "Bar stock replenished")
         |> load_stock()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Enter a valid positive amount")}
    end
  end

  def handle_event("count", %{"product_id" => product_id, "quantity" => quantity}, socket) do
    case Inventory.count_bar_stock(product_id, quantity) do
      {:ok, difference} ->
        item = Enum.find(socket.assigns.bar_stock_items, &(&1.product.id == product_id))

        difference =
          if item.display_unit == "L", do: Decimal.div(difference, 1000), else: difference

        message =
          cond do
            Decimal.compare(difference, 0) == :eq ->
              "Count matches expected stock"

            Decimal.compare(difference, 0) == :lt ->
              "Count saved: #{format_quantity(Decimal.abs(difference))} #{item.display_unit} missing"

            true ->
              "Count saved: #{format_quantity(difference)} #{item.display_unit} more than expected"
          end

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> load_stock()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Enter a valid non-negative count")}
    end
  end

  def handle_event(
        "update_threshold",
        %{"product_id" => product_id, "threshold" => threshold},
        socket
      ) do
    case Inventory.update_bar_stock_threshold(product_id, threshold) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Low-stock alert updated")
         |> load_stock()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Enter a valid non-negative threshold")}
    end
  end

  def handle_event(
        "log_waste",
        %{"product_id" => product_id, "quantity" => quantity, "reason" => reason},
        socket
      ) do
    case Inventory.record_bar_stock_waste(product_id, quantity, reason) do
      {:ok, _movement} ->
        {:noreply,
         socket
         |> put_flash(:info, "Loss recorded")
         |> load_stock()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Enter a valid amount and reason")}
    end
  end

  def handle_event("untrack_product", %{"product_id" => product_id}, socket) do
    case Inventory.untrack_bar_stock_product(product_id) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{product.name} is no longer tracked in the bar")
         |> load_stock()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not stop tracking this product")}
    end
  end

  def handle_event("filter_loss_summary", params, socket) do
    {:noreply,
     socket
     |> assign(:loss_start_date, params["start_date"] || "")
     |> assign(:loss_end_date, params["end_date"] || "")
     |> load_stock()}
  end

  def handle_event("clear_loss_filter", _params, socket) do
    {:noreply,
     socket
     |> assign(:loss_start_date, "")
     |> assign(:loss_end_date, "")
     |> load_stock()}
  end

  def handle_event("filter_movements", params, socket) do
    {:noreply,
     socket
     |> assign(:movement_search, params["search"] || "")
     |> assign(:movement_type, params["movement_type"] || "")
     |> assign(:movement_start_date, params["start_date"] || "")
     |> assign(:movement_end_date, params["end_date"] || "")
     |> assign(:movement_page, 1)
     |> load_stock()}
  end

  def handle_event("clear_movement_filter", _params, socket) do
    {:noreply,
     socket
     |> assign(:movement_search, "")
     |> assign(:movement_type, "")
     |> assign(:movement_start_date, "")
     |> assign(:movement_end_date, "")
     |> assign(:movement_page, 1)
     |> load_stock()}
  end

  def handle_event("movements_page", %{"page" => page_str}, socket) do
    {:noreply,
     socket
     |> assign(:movement_page, String.to_integer(page_str))
     |> load_stock()}
  end

  defp load_stock(socket) do
    movement_filters = movement_filters(socket)
    movement_page_size = 50
    movement_total_count = Inventory.count_bar_stock_movements(movement_filters)
    movement_total_pages = movement_total_pages(movement_total_count, movement_page_size)
    movement_page = clamp(socket.assigns[:movement_page] || 1, 1, movement_total_pages)

    socket
    |> assign(:bar_stock_items, Inventory.list_bar_stock_products())
    |> assign(:bar_stock_candidates, Inventory.list_bar_stock_candidates())
    |> assign(:movement_page, movement_page)
    |> assign(:movement_total_pages, movement_total_pages)
    |> assign(:movement_total_count, movement_total_count)
    |> assign(
      :recent_movements,
      Inventory.list_recent_bar_stock_movements(movement_filters,
        page: movement_page,
        page_size: movement_page_size
      )
    )
    |> assign(:loss_summary, Inventory.get_bar_stock_loss_summary(loss_filters(socket)))
    |> assign(:waste_reasons, Inventory.bar_stock_waste_reasons())
  end

  defp loss_filters(socket) do
    %{}
    |> maybe_put_filter(:start_date, parse_filter_date(socket.assigns[:loss_start_date]))
    |> maybe_put_filter(:end_date, parse_filter_date(socket.assigns[:loss_end_date]))
  end

  defp movement_filters(socket) do
    %{}
    |> maybe_put_filter(:product_search, String.trim(socket.assigns[:movement_search] || ""))
    |> maybe_put_filter(:movement_type, socket.assigns[:movement_type] || "")
    |> maybe_put_filter(:start_date, parse_filter_date(socket.assigns[:movement_start_date]))
    |> maybe_put_filter(:end_date, parse_filter_date(socket.assigns[:movement_end_date]))
  end

  defp movement_total_pages(0, _page_size), do: 1

  defp movement_total_pages(total_count, page_size),
    do: div(total_count + page_size - 1, page_size)

  defp clamp(value, min, max), do: value |> max(min) |> min(max)

  defp maybe_put_filter(filters, _key, nil), do: filters
  defp maybe_put_filter(filters, _key, ""), do: filters
  defp maybe_put_filter(filters, key, value), do: Map.put(filters, key, value)

  defp movement_type_options do
    [
      {"All types", ""},
      {"Opening stock", "opening"},
      {"Restock", "restock"},
      {"Account entry", "sale"},
      {"Account correction", "sale_reversal"},
      {"Stock count", "count_adjustment"},
      {"Loss recorded", "waste"}
    ]
  end

  defp parse_filter_date(nil), do: nil
  defp parse_filter_date(""), do: nil

  defp parse_filter_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp format_quantity(quantity), do: Decimal.to_string(Decimal.round(quantity, 2), :normal)

  defp format_percent(value), do: Decimal.to_string(Decimal.round(value, 1), :normal)

  defp format_movement_quantity(quantity, product) do
    quantity =
      if product.unit in ["ml", "L", "cl"], do: Decimal.div(quantity, 1000), else: quantity

    sign = if Decimal.compare(quantity, 0) == :gt, do: "+", else: ""
    unit = if product.unit in ["ml", "L", "cl"], do: "L", else: product.unit || "pcs"

    "#{sign}#{Decimal.to_string(Decimal.round(quantity, 3), :normal)} #{unit}"
  end

  defp movement_label("opening"), do: "Opening stock"
  defp movement_label("restock"), do: "Restock"
  defp movement_label("sale"), do: "Account entry"
  defp movement_label("sale_reversal"), do: "Account correction"
  defp movement_label("count_adjustment"), do: "Stock count"
  defp movement_label("waste"), do: "Loss recorded"

  defp non_negative(quantity) do
    if Decimal.compare(quantity, 0) == :lt, do: Decimal.new("0"), else: quantity
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      content_class="mx-auto w-full max-w-7xl space-y-6"
      main_class="p-0"
      show_header={false}
      flash_info_class="alert-success"
    >
      <div id="bar-stock-workspace" class="min-w-0 px-4 py-6 sm:px-6 lg:px-8">
        <div class="mb-8">
          <.link
            navigate={~p"/admin"}
            class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block"
          >
            ← Back to Dashboard
          </.link>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h1 class="text-3xl font-bold text-primary-500 sm:text-4xl">Bar Stock</h1>
            <.link
              navigate={~p"/admin/stock"}
              class="inline-flex flex-shrink-0 items-center gap-2 rounded-lg bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-emerald-700"
            >
              <.icon name="hero-archive-box" class="h-4 w-4" /> Stock Overview
            </.link>
          </div>
        </div>

        <section class="mb-6 rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
          <h2 class="mb-3 flex items-center gap-2 text-base font-semibold text-gray-900">
            <.icon name="hero-magnifying-glass" class="h-5 w-5 text-gray-400" />
            Add product to bar stock
          </h2>
          <form
            id="bar-stock-search-form"
            phx-change="search_products"
            phx-submit={JS.dispatch("blur", to: "#bar-stock-product-search")}
          >
            <div class="relative">
              <input
                aria-label="Search products to add to bar stock"
                id="bar-stock-product-search"
                type="text"
                name="search"
                value={@product_search}
                placeholder="Type to search..."
                autocomplete="off"
                phx-debounce="300"
                class="block w-full rounded-lg border-gray-300 pr-10 text-sm shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500"
              />
              <%= if @product_search != "" do %>
                <button
                  type="button"
                  phx-click="clear_product_search"
                  aria-label="Clear product search"
                  class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
                >
                  <.icon name="hero-x-mark" class="h-4 w-4" />
                </button>
              <% end %>
              <%= if @show_product_results do %>
                <div class="absolute z-20 mt-1 max-h-80 w-full overflow-y-auto rounded-xl border border-gray-200 bg-white shadow-xl">
                  <%= if @product_search_results == [] do %>
                    <div class="px-4 py-6 text-center text-sm text-gray-400">
                      No products found for "{@product_search}"
                    </div>
                  <% else %>
                    <ul>
                      <%= for product <- @product_search_results do %>
                        <li class="flex items-center justify-between border-b border-gray-100 px-4 py-3 transition-colors last:border-b-0 hover:bg-gray-50">
                          <div class="min-w-0 flex-1">
                            <div class="truncate text-sm font-medium text-gray-900">
                              {product.name}
                            </div>
                            <div class="mt-0.5 flex items-center gap-2">
                              <%= if product.category do %>
                                <span class="text-xs text-gray-400">{product.category.name}</span>
                              <% end %>
                              <span class="rounded bg-tertiary-100 px-1.5 py-0.5 text-xs font-semibold text-tertiary-800">
                                {if product.unit in ["ml", "L", "cl"],
                                  do: "L",
                                  else: product.unit || "pcs"}
                              </span>
                            </div>
                          </div>
                          <button
                            type="button"
                            phx-click="select_product"
                            phx-value-id={product.id}
                            class="ml-4 inline-flex flex-shrink-0 items-center gap-1 rounded-lg bg-emerald-100 px-3 py-1.5 text-xs font-semibold text-emerald-800 transition-colors hover:bg-emerald-200"
                          >
                            <.icon name="hero-plus" class="h-3.5 w-3.5" /> Select
                          </button>
                        </li>
                      <% end %>
                    </ul>
                  <% end %>
                </div>
              <% end %>
            </div>
          </form>

          <%= if @selected_product do %>
            <div class="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-emerald-200 bg-emerald-50 p-4">
              <div class="flex min-w-0 items-center gap-3">
                <.icon name="hero-check-circle" class="h-5 w-5 flex-shrink-0 text-emerald-600" />
                <div class="min-w-0">
                  <div class="truncate text-sm font-semibold text-gray-900">
                    {@selected_product.name}
                  </div>
                  <div class="text-xs text-gray-500">
                    {@selected_product.category && @selected_product.category.name} · {if @selected_product.unit in [
                                                                                            "ml",
                                                                                            "L",
                                                                                            "cl"
                                                                                          ],
                                                                                          do: "L",
                                                                                          else:
                                                                                            @selected_product.unit ||
                                                                                              "pcs"}
                  </div>
                </div>
              </div>
              <button
                type="button"
                phx-click="clear_product"
                class="text-sm font-medium text-gray-500 hover:text-gray-800"
              >
                Change
              </button>
            </div>

            <.form
              for={%{}}
              as={:bar_stock}
              id="bar-stock-add-form"
              phx-submit="add_product"
              class="mt-5 grid gap-4 border-t border-gray-100 pt-5 md:grid-cols-3 md:items-end"
            >
              <input type="hidden" name="bar_stock[product_id]" value={@selected_product.id} />
              <div>
                <label for="bar-stock-initial" class="mb-1 block text-sm font-medium text-gray-700">Current bar amount ({if @selected_product.unit in [
                                                                                                                              "ml",
                                                                                                                              "L",
                                                                                                                              "cl"
                                                                                                                            ],
                                                                                                                            do:
                                                                                                                              "L",
                                                                                                                            else:
                                                                                                                              @selected_product.unit ||
                                                                                                                                "pcs"})</label>
                <input
                  id="bar-stock-initial"
                  name="bar_stock[initial_quantity]"
                  type="number"
                  min="0"
                  inputmode="decimal"
                  step="0.01"
                  value="0"
                  required
                  class="block w-full rounded-lg border-gray-300 text-sm shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500"
                />
              </div>
              <div>
                <label for="bar-stock-threshold" class="mb-1 block text-sm font-medium text-gray-700">Alert below ({if @selected_product.unit in [
                                                                                                                         "ml",
                                                                                                                         "L",
                                                                                                                         "cl"
                                                                                                                       ],
                                                                                                                       do:
                                                                                                                         "L",
                                                                                                                       else:
                                                                                                                         @selected_product.unit ||
                                                                                                                           "pcs"})</label>
                <input
                  id="bar-stock-threshold"
                  name="bar_stock[threshold]"
                  type="number"
                  min="0"
                  inputmode="decimal"
                  step="0.01"
                  value="0"
                  required
                  class="block w-full rounded-lg border-gray-300 text-sm shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500"
                />
              </div>
              <div class="flex items-center justify-between gap-3">
                <button
                  type="submit"
                  class="bar-stock-primary w-full justify-center"
                  phx-disable-with="Adding…"
                >
                  <.icon name="hero-plus" class="h-4 w-4" /> Add to bar
                </button>
              </div>
            </.form>
          <% end %>
        </section>

        <section id="bar-stock-items" class="mb-10" aria-labelledby="bar-stock-items-heading">
          <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
            <div>
              <h2 id="bar-stock-items-heading" class="text-xl font-semibold text-gray-900">
                In the bar
              </h2>
              <p class="mt-1 text-sm text-gray-500">Count what is here. Restock only what you add.</p>
            </div>
            <span class="rounded-full bg-white px-3 py-1 text-sm font-medium text-gray-600 ring-1 ring-gray-200">
              {length(@bar_stock_items)} products
            </span>
          </div>
          <div class="grid min-w-0 items-start gap-4 lg:grid-cols-2">
            <article
              :for={item <- @bar_stock_items}
              id={"bar-stock-item-#{item.product.id}"}
              class="bar-stock-card min-w-0 rounded-2xl border border-gray-200 bg-white shadow-sm"
            >
              <div class="flex items-start justify-between gap-3 p-4 sm:p-5">
                <div class="min-w-0">
                  <p class="mb-1 text-xs font-medium text-gray-500">
                    {item.product.category && item.product.category.name}
                  </p>
                  <h3 class="break-words text-lg font-semibold leading-snug text-gray-900">
                    {item.product.name}
                  </h3>
                  <span class={[
                    "mt-2 inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold",
                    item.status == :out_of_stock && "bg-rose-50 text-rose-700",
                    item.status == :low_stock && "bg-amber-50 text-amber-800",
                    item.status == :in_stock && "bg-emerald-50 text-emerald-700"
                  ]}>
                    <span class="size-1.5 rounded-full bg-current"></span>
                    {case item.status do
                      :out_of_stock -> "Out of stock"
                      :low_stock -> "Low stock"
                      :in_stock -> "In stock"
                    end}
                  </span>
                </div>
                <div class="shrink-0 text-right">
                  <p class="text-xs text-gray-500">Expected</p>
                  <p class="mt-1 text-2xl font-bold tabular-nums text-gray-900">
                    {format_quantity(item.stock)}
                    <span class="text-sm font-normal text-gray-500">{item.display_unit}</span>
                  </p>
                </div>
              </div>
              <div class="space-y-2 border-t border-gray-100 p-4 sm:p-5">
                <details
                  id={"bar-action-count-#{item.product.id}"}
                  name={"bar-action-#{item.product.id}"}
                  class="bar-stock-action bar-stock-action--count"
                >
                  <summary>
                    <span class="bar-stock-action-icon"><.icon
                      name="hero-clipboard-document-check"
                      class="size-5"
                    /></span>
                    <span class="min-w-0 flex-1">
                      <span class="block text-sm font-semibold">Count stock</span>
                      <span class="mt-0.5 block text-xs font-normal text-gray-500">Enter what is actually in the bar</span>
                    </span>
                    <.icon name="hero-chevron-down" class="bar-stock-action-chevron size-5 shrink-0" />
                  </summary>
                  <div class="bar-stock-action-panel">
                    <.form
                      for={%{}}
                      as={:count}
                      id={"bar-count-#{item.product.id}"}
                      phx-submit="count"
                      class="min-w-0"
                    >
                      <input type="hidden" name="product_id" value={item.product.id} />
                      <label
                        for={"count-#{item.product.id}"}
                        class="mb-2 block text-sm font-semibold text-gray-800"
                      >Actual count
                      <span class="font-normal text-gray-500">({item.display_unit})</span></label>
                      <div class="flex gap-2">
                        <input
                          id={"count-#{item.product.id}"}
                          aria-label={"Counted amount for #{item.product.name}"}
                          name="quantity"
                          type="number"
                          inputmode="decimal"
                          min="0"
                          step="0.01"
                          value={format_quantity(non_negative(item.stock))}
                          required
                          class="min-w-0 flex-1"
                        />
                        <button
                          type="submit"
                          aria-label={"Save count for #{item.product.name}"}
                          phx-disable-with="Saving…"
                          class="bar-stock-primary gap-2"
                        ><.icon name="hero-check" class="size-5" /> Save count</button>
                      </div>
                    </.form>
                  </div>
                </details>
                <details
                  id={"bar-action-restock-#{item.product.id}"}
                  name={"bar-action-#{item.product.id}"}
                  class="bar-stock-action bar-stock-action--restock"
                >
                  <summary>
                    <span class="bar-stock-action-icon"><.icon name="hero-plus-circle" class="size-5" /></span>
                    <span class="min-w-0 flex-1">
                      <span class="block text-sm font-semibold">Add stock</span>
                      <span class="mt-0.5 block text-xs font-normal text-gray-500">Enter the amount you are adding</span>
                    </span>
                    <.icon name="hero-chevron-down" class="bar-stock-action-chevron size-5 shrink-0" />
                  </summary>
                  <div class="bar-stock-action-panel">
                    <.form
                      for={%{}}
                      as={:restock}
                      id={"bar-restock-#{item.product.id}"}
                      phx-submit="restock"
                      class="min-w-0"
                    >
                      <input type="hidden" name="product_id" value={item.product.id} />
                      <label
                        for={"restock-#{item.product.id}"}
                        class="mb-2 block text-sm font-semibold text-gray-800"
                      >Add to bar <span class="font-normal text-gray-500">({item.display_unit})</span></label>
                      <div class="flex gap-2">
                        <input
                          id={"restock-#{item.product.id}"}
                          aria-label={"Amount to add for #{item.product.name}"}
                          name="quantity"
                          type="number"
                          inputmode="decimal"
                          min="0.01"
                          step="0.01"
                          placeholder="0"
                          required
                          class="min-w-0 flex-1"
                        />
                        <button
                          type="submit"
                          aria-label={"Add stock for #{item.product.name}"}
                          phx-disable-with="Adding…"
                          class="bar-stock-secondary gap-2"
                        ><.icon name="hero-plus" class="size-5" /> Add stock</button>
                      </div>
                    </.form>
                  </div>
                </details>
                <details
                  id={"bar-action-loss-#{item.product.id}"}
                  name={"bar-action-#{item.product.id}"}
                  class="bar-stock-action bar-stock-action--loss"
                >
                  <summary>
                    <span class="bar-stock-action-icon"><.icon
                      name="hero-exclamation-triangle"
                      class="size-5"
                    /></span>
                    <span class="min-w-0 flex-1">
                      <span class="block text-sm font-semibold">Log loss</span>
                      <span class="mt-0.5 block text-xs font-normal text-gray-500">Record spillage, breakage or other loss</span>
                    </span>
                    <.icon name="hero-chevron-down" class="bar-stock-action-chevron size-5 shrink-0" />
                  </summary>
                  <div class="bar-stock-action-panel">
                    <.form
                      for={%{}}
                      as={:waste}
                      id={"bar-loss-#{item.product.id}"}
                      phx-submit="log_waste"
                      class="space-y-2"
                    >
                      <input type="hidden" name="product_id" value={item.product.id} />
                      <label
                        for={"loss-#{item.product.id}"}
                        class="block text-sm font-semibold text-gray-800"
                      >Log loss ({item.display_unit})</label>
                      <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,2fr)] gap-2">
                        <input
                          id={"loss-#{item.product.id}"}
                          aria-label={"Amount lost for #{item.product.name}"}
                          name="quantity"
                          type="number"
                          inputmode="decimal"
                          min="0.01"
                          step="0.01"
                          placeholder="0"
                          required
                        />
                        <select
                          aria-label={"Loss reason for #{item.product.name}"}
                          name="reason"
                          required
                        >
                          <option value="">Select reason</option>
                          <option :for={reason <- @waste_reasons} value={reason}>
                            {String.capitalize(reason)}
                          </option>
                        </select>
                      </div>
                      <button
                        type="submit"
                        aria-label={"Log loss for #{item.product.name}"}
                        phx-disable-with="Saving…"
                        class="bar-stock-loss-submit w-full gap-2"
                      ><.icon name="hero-check" class="size-5" /> Record loss</button>
                    </.form>
                  </div>
                </details>
              </div>
              <details
                id={"bar-options-#{item.product.id}"}
                class="bar-stock-settings border-t border-gray-100"
              >
                <summary class="flex min-h-14 cursor-pointer list-none items-center gap-3 px-4 py-3 text-sm font-semibold text-gray-600 hover:bg-gray-50 hover:text-gray-900 sm:px-5">
                  <.icon name="hero-cog-6-tooth" class="size-5 shrink-0" />
                  <span class="flex-1">Stock settings</span>
                  <.icon name="hero-chevron-down" class="bar-stock-settings-chevron size-5 shrink-0" />
                </summary>
                <div class="space-y-5 px-4 pb-5 sm:px-5">
                  <.form
                    for={%{}}
                    as={:threshold}
                    id={"bar-threshold-#{item.product.id}"}
                    phx-submit="update_threshold"
                  >
                    <input type="hidden" name="product_id" value={item.product.id} />
                    <label
                      for={"threshold-#{item.product.id}"}
                      class="mb-2 block text-sm font-semibold text-gray-800"
                    >Alert below ({item.display_unit})</label>
                    <div class="flex gap-2">
                      <input
                        id={"threshold-#{item.product.id}"}
                        aria-label={"Low stock threshold for #{item.product.name}"}
                        name="threshold"
                        type="number"
                        inputmode="decimal"
                        min="0"
                        step="0.01"
                        value={format_quantity(item.threshold)}
                        required
                        class="min-w-0 flex-1"
                      />
                      <button
                        type="submit"
                        aria-label={"Save threshold for #{item.product.name}"}
                        phx-disable-with="Saving…"
                        class="bar-stock-secondary"
                      >Save alert</button>
                    </div>
                  </.form>
                  <button
                    type="button"
                    phx-click="untrack_product"
                    phx-value-product_id={item.product.id}
                    data-confirm={"Stop tracking #{item.product.name} in the bar? Current stock (#{format_quantity(item.stock)} #{item.display_unit}) will no longer be monitored, but past movements are kept."}
                    aria-label={"Stop tracking #{item.product.name}"}
                    class="flex min-h-11 items-center gap-2 text-sm font-medium text-gray-500 hover:text-rose-700"
                  >
                    <.icon name="hero-eye-slash" class="size-4" /> Stop tracking product
                  </button>
                </div>
              </details>
            </article>
          </div>
          <div
            :if={@bar_stock_items == []}
            class="rounded-2xl border border-dashed border-gray-300 bg-white px-5 py-10 text-center"
          >
            <.icon name="hero-archive-box" class="mx-auto mb-3 size-8 text-gray-400" />
            <h3 class="text-base font-semibold text-gray-900">Your bar stock starts here</h3>
            <p class="mt-2 text-sm text-gray-500">
              Search for a product above and enter how much is in the bar.
            </p>
          </div>
        </section>

        <section class="mb-10">
          <div class="mb-3 flex flex-wrap items-end justify-between gap-3">
            <h2 class="text-lg font-semibold text-gray-900">
              Loss overview
              <span class="font-normal text-gray-500">
                {if @loss_start_date == "" and @loss_end_date == "",
                  do: "(all-time)",
                  else: "(selected period)"}
              </span>
            </h2>
            <form
              phx-change="filter_loss_summary"
              class="bar-stock-filters grid w-full grid-cols-2 items-end gap-2 sm:w-auto sm:grid-cols-3"
            >
              <div>
                <label class="mb-1 block text-xs font-medium text-gray-600" for="loss-start-date">
                  From
                </label>
                <input
                  id="loss-start-date"
                  type="date"
                  name="start_date"
                  value={@loss_start_date}
                  class="rounded-md border-gray-300 text-sm shadow-sm"
                />
              </div>
              <div>
                <label class="mb-1 block text-xs font-medium text-gray-600" for="loss-end-date">
                  To
                </label>
                <input
                  id="loss-end-date"
                  type="date"
                  name="end_date"
                  value={@loss_end_date}
                  class="rounded-md border-gray-300 text-sm shadow-sm"
                />
              </div>
              <button
                type="button"
                phx-click="clear_loss_filter"
                class="rounded-md bg-gray-100 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-200"
              >
                Clear
              </button>
            </form>
          </div>
          <div class="bar-stock-history overflow-hidden rounded-xl border border-gray-200">
            <table class="min-w-full divide-y divide-gray-200 text-sm">
              <thead class="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500">
                <tr>
                  <th class="px-4 py-3">Product</th>
                  <th class="whitespace-nowrap px-4 py-3">Sold</th>
                  <th class="whitespace-nowrap px-4 py-3">Loss</th>
                  <th class="whitespace-nowrap px-4 py-3">Loss rate</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 bg-white">
                <%= for row <- @loss_summary do %>
                  <tr class={Decimal.compare(row.loss_rate, 5) == :gt && "bg-rose-50"}>
                    <td data-label="Product" class="px-4 py-3 font-medium text-gray-900">
                      {row.product.name}
                    </td>
                    <td data-label="Sold" class="whitespace-nowrap px-4 py-3 text-gray-700">
                      {format_quantity(row.sold)} {row.display_unit}
                    </td>
                    <td data-label="Loss" class="whitespace-nowrap px-4 py-3 text-gray-700">
                      {format_quantity(row.loss)} {row.display_unit}
                    </td>
                    <td
                      data-label="Loss rate"
                      class={[
                        "whitespace-nowrap px-4 py-3 font-semibold",
                        Decimal.compare(row.loss_rate, 5) == :gt && "text-rose-700"
                      ]}
                    >
                      {format_percent(row.loss_rate)}%
                    </td>
                  </tr>
                <% end %>
                <%= if @loss_summary == [] do %>
                  <tr>
                    <td colspan="4" class="px-4 py-8 text-center text-gray-500">
                      No products are being tracked in the bar yet.
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </section>

        <section class="mt-10">
          <h2 class="mb-3 text-lg font-semibold text-gray-900">Recent movements</h2>

          <.form
            for={%{}}
            as={:movement_filter}
            phx-submit="filter_movements"
            class="bar-stock-filters mb-4 grid gap-3 rounded-xl border border-gray-200 bg-white p-4 sm:grid-cols-2 xl:grid-cols-4"
          >
            <div>
              <label for="movement-search" class="mb-1 block text-xs font-medium text-gray-600">
                Product
              </label>
              <input
                id="movement-search"
                type="text"
                name="search"
                value={@movement_search}
                placeholder="Search by product name..."
                class="w-full rounded-md border-gray-300 text-sm shadow-sm"
              />
            </div>
            <div>
              <label for="movement-type" class="mb-1 block text-xs font-medium text-gray-600">
                Movement type
              </label>
              <select
                id="movement-type"
                name="movement_type"
                class="rounded-md border-gray-300 text-sm shadow-sm"
              >
                <%= for {label, value} <- movement_type_options() do %>
                  <option value={value} selected={@movement_type == value}>{label}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label for="movement-start-date" class="mb-1 block text-xs font-medium text-gray-600">
                From
              </label>
              <input
                id="movement-start-date"
                type="date"
                name="start_date"
                value={@movement_start_date}
                class="rounded-md border-gray-300 text-sm shadow-sm"
              />
            </div>
            <div>
              <label for="movement-end-date" class="mb-1 block text-xs font-medium text-gray-600">
                To
              </label>
              <input
                id="movement-end-date"
                type="date"
                name="end_date"
                value={@movement_end_date}
                class="rounded-md border-gray-300 text-sm shadow-sm"
              />
            </div>
            <button
              type="submit"
              class="inline-flex items-center gap-2 rounded-lg bg-tertiary-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-tertiary-700"
            >
              <.icon name="hero-magnifying-glass" class="h-4 w-4" /> Search
            </button>
            <button
              type="button"
              phx-click="clear_movement_filter"
              class="rounded-lg bg-gray-100 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-200"
            >
              Clear
            </button>
          </.form>

          <div class="bar-stock-history overflow-hidden rounded-xl border border-gray-200">
            <table class="min-w-full divide-y divide-gray-200 text-sm">
              <thead class="bg-gray-50 text-left text-xs font-semibold uppercase text-gray-500">
                <tr>
                  <th class="px-4 py-3">When</th>
                  <th class="px-4 py-3">Product</th>
                  <th class="px-4 py-3">Change</th>
                  <th class="px-4 py-3">Movement</th>
                  <th class="px-4 py-3">Details</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 bg-white">
                <%= for movement <- @recent_movements do %>
                  <tr>
                    <td data-label="When" class="whitespace-nowrap px-4 py-3 text-gray-500">
                      {Calendar.strftime(movement.inserted_at, "%d.%m.%Y %H:%M")}
                    </td>
                    <td
                      data-label="Product"
                      class="whitespace-nowrap px-4 py-3 font-medium text-gray-900"
                    >
                      {movement.product.name}
                    </td>
                    <td data-label="Change" class="whitespace-nowrap px-4 py-3 font-semibold">
                      {format_movement_quantity(movement.quantity, movement.product)}
                    </td>
                    <td data-label="Movement" class="whitespace-nowrap px-4 py-3 text-gray-700">
                      {movement_label(movement.movement_type)}
                    </td>
                    <td data-label="Details" class="px-4 py-3 text-gray-500">
                      {if movement.order_item && movement.order_item.order,
                        do: "Order #{movement.order_item.order.order_number}",
                        else: movement.notes}
                    </td>
                  </tr>
                <% end %>
                <%= if @recent_movements == [] do %>
                  <tr>
                    <td colspan="5" class="px-4 py-8 text-center text-gray-500">
                      No bar stock movements found.
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div class="mt-3 flex flex-wrap items-center justify-between gap-3 text-sm text-gray-600">
            <span>
              Page {@movement_page} of {@movement_total_pages} · {@movement_total_count} movements
            </span>
            <div class="flex gap-2">
              <button
                type="button"
                phx-click="movements_page"
                phx-value-page={@movement_page - 1}
                disabled={@movement_page <= 1}
                class="rounded-lg bg-gray-100 px-3 py-1.5 font-medium text-gray-700 hover:bg-gray-200 disabled:cursor-not-allowed disabled:opacity-50"
              >
                ← Previous
              </button>
              <button
                type="button"
                phx-click="movements_page"
                phx-value-page={@movement_page + 1}
                disabled={@movement_page >= @movement_total_pages}
                class="rounded-lg bg-gray-100 px-3 py-1.5 font-medium text-gray-700 hover:bg-gray-200 disabled:cursor-not-allowed disabled:opacity-50"
              >
                Next →
              </button>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end

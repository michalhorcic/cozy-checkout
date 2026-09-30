defmodule CozyCheckoutWeb.BarStockLive do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Inventory

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:product_search, "")
     |> assign(:product_search_results, [])
     |> assign(:selected_product, nil)
     |> assign(:show_product_results, false)
     |> assign(:loss_start_date, "")
     |> assign(:loss_end_date, "")
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

  defp load_stock(socket) do
    socket
    |> assign(:bar_stock_items, Inventory.list_bar_stock_products())
    |> assign(:bar_stock_candidates, Inventory.list_bar_stock_candidates())
    |> assign(:recent_movements, Inventory.list_recent_bar_stock_movements())
    |> assign(:loss_summary, Inventory.get_bar_stock_loss_summary(loss_filters(socket)))
    |> assign(:waste_reasons, Inventory.bar_stock_waste_reasons())
  end

  defp loss_filters(socket) do
    %{}
    |> maybe_put_loss_date(:start_date, parse_filter_date(socket.assigns[:loss_start_date]))
    |> maybe_put_loss_date(:end_date, parse_filter_date(socket.assigns[:loss_end_date]))
  end

  defp maybe_put_loss_date(filters, _key, nil), do: filters
  defp maybe_put_loss_date(filters, key, date), do: Map.put(filters, key, date)

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
      <div class="px-4 py-8 sm:px-6 lg:px-8">
        <div class="mb-8">
          <.link
            navigate={~p"/admin"}
            class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block"
          >
            ← Back to Dashboard
          </.link>
          <div class="flex items-end justify-between gap-4">
            <h1 class="text-4xl font-bold text-primary-500">Bar Stock</h1>
            <.link
              navigate={~p"/admin/stock"}
              class="inline-flex flex-shrink-0 items-center gap-2 rounded-lg bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-emerald-700"
            >
              <.icon name="hero-archive-box" class="h-4 w-4" /> Stock Overview
            </.link>
          </div>
        </div>

        <section class="mb-6 rounded-lg bg-white p-6 shadow-lg">
          <h2 class="mb-3 flex items-center gap-2 text-base font-semibold text-gray-900">
            <.icon name="hero-magnifying-glass" class="h-5 w-5 text-gray-400" />
            Add product to bar stock
          </h2>
          <form id="bar-stock-search-form" phx-change="search_products" phx-submit="noop">
            <div class="relative">
              <input
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
                <label for="bar-stock-initial" class="mb-1 block text-sm font-medium text-gray-700">Current bar amount</label>
                <input
                  id="bar-stock-initial"
                  name="bar_stock[initial_quantity]"
                  type="number"
                  min="0"
                  step="0.01"
                  value="0"
                  required
                  class="block w-full rounded-lg border-gray-300 text-sm shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500"
                />
              </div>
              <div>
                <label for="bar-stock-threshold" class="mb-1 block text-sm font-medium text-gray-700">Alert below</label>
                <input
                  id="bar-stock-threshold"
                  name="bar_stock[threshold]"
                  type="number"
                  min="0"
                  step="0.01"
                  value="0"
                  required
                  class="block w-full rounded-lg border-gray-300 text-sm shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500"
                />
              </div>
              <div class="flex items-center justify-between gap-3">
                <span class="text-sm text-gray-500">{if @selected_product.unit in ["ml", "L", "cl"],
                  do: "L",
                  else: @selected_product.unit || "pcs"}</span>
                <button
                  type="submit"
                  class="inline-flex items-center gap-2 rounded-lg bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-emerald-700"
                >
                  <.icon name="hero-plus" class="h-4 w-4" /> Add to bar
                </button>
              </div>
            </.form>
          <% end %>
        </section>

        <div class="mb-6 rounded-lg bg-white p-4 shadow-lg">
          <div class="flex flex-wrap items-center justify-center gap-x-8 gap-y-3">
            <div class="flex items-center gap-2">
              <span class="h-4 w-4 rounded bg-rose-500"></span><span class="text-sm text-gray-700">Out of Stock</span>
            </div>
            <div class="flex items-center gap-2">
              <span class="h-4 w-4 rounded bg-amber-500"></span><span class="text-sm text-gray-700">Low Stock</span>
            </div>
            <div class="flex items-center gap-2">
              <span class="h-4 w-4 rounded bg-emerald-500"></span><span class="text-sm text-gray-700">In Stock</span>
            </div>
          </div>
        </div>

        <div class="mb-8 overflow-hidden rounded-lg bg-white shadow-lg">
          <table class="min-w-full divide-y divide-gray-200 text-sm">
            <thead class="bg-gradient-to-r from-primary-500 to-secondary-600 text-left text-xs font-medium uppercase text-white">
              <tr>
                <th class="whitespace-nowrap px-2 py-3">Status</th>
                <th class="px-2 py-3">Product</th>
                <th class="px-2 py-3">Category</th>
                <th class="whitespace-nowrap px-2 py-3">Current Stock</th>
                <th class="whitespace-nowrap px-2 py-3">Low Stock Alert</th>
                <th class="px-2 py-3">Restock</th>
                <th class="px-2 py-3">Count</th>
                <th class="px-2 py-3">Log Loss</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200 bg-white">
              <%= for item <- @bar_stock_items do %>
                <tr class={[
                  "transition-colors hover:bg-gray-50",
                  item.status == :out_of_stock && "bg-rose-50",
                  item.status == :low_stock && "bg-amber-50"
                ]}>
                  <td class="whitespace-nowrap px-2 py-3">
                    <span class={[
                      "inline-block h-3 w-3 rounded-full",
                      item.status == :out_of_stock && "bg-rose-500",
                      item.status == :low_stock && "bg-amber-500",
                      item.status == :in_stock && "bg-emerald-500"
                    ]}></span>
                  </td>
                  <td class="px-2 py-3 text-sm font-medium text-gray-900">
                    <div class="flex items-center justify-between gap-2">
                      <span class="truncate">{item.product.name}</span>
                      <button
                        type="button"
                        phx-click="untrack_product"
                        phx-value-product_id={item.product.id}
                        data-confirm={"Stop tracking #{item.product.name} in the bar? Current stock (#{format_quantity(item.stock)} #{item.display_unit}) will no longer be monitored, but past movements are kept."}
                        aria-label={"Stop tracking #{item.product.name}"}
                        title="Stop tracking this product"
                        class="flex-shrink-0 rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-rose-600"
                      >
                        <.icon name="hero-eye-slash" class="size-4" />
                      </button>
                    </div>
                  </td>
                  <td class="whitespace-nowrap px-2 py-3 text-sm text-gray-900">
                    {item.product.category && item.product.category.name}
                  </td>
                  <td class="whitespace-nowrap px-2 py-3">
                    <div class={[
                      "text-sm font-semibold",
                      item.status == :out_of_stock && "text-rose-600",
                      item.status == :low_stock && "text-amber-600",
                      item.status == :in_stock && "text-emerald-600"
                    ]}>
                      {format_quantity(item.stock)} {item.display_unit}
                    </div>
                  </td>
                  <td class="whitespace-nowrap px-2 py-3 text-sm text-gray-500">
                    <.form
                      for={%{}}
                      as={:threshold}
                      phx-submit="update_threshold"
                      class="flex items-center gap-1"
                    >
                      <input type="hidden" name="product_id" value={item.product.id} />
                      <input
                        aria-label={"Low stock threshold for #{item.product.name}"}
                        name="threshold"
                        type="number"
                        min="0"
                        step="0.01"
                        value={format_quantity(item.threshold)}
                        class="w-14 rounded-md border-gray-300 text-xs shadow-sm"
                      />
                      <span class="text-xs text-gray-500">{item.display_unit}</span>
                      <button
                        type="submit"
                        aria-label={"Save threshold for #{item.product.name}"}
                        class="rounded p-1 text-gray-500 hover:bg-gray-100 hover:text-gray-900"
                      >
                        <.icon name="hero-check" class="size-4" />
                      </button>
                    </.form>
                  </td>
                  <td class="px-2 py-3">
                    <.form
                      for={%{}}
                      as={:restock}
                      phx-submit="restock"
                      class="flex items-center gap-1"
                    >
                      <input type="hidden" name="product_id" value={item.product.id} />
                      <input
                        aria-label={"Amount to add for #{item.product.name}"}
                        name="quantity"
                        type="number"
                        min="0.01"
                        step="0.01"
                        placeholder={item.display_unit}
                        required
                        class="w-14 rounded-md border-gray-300 text-xs shadow-sm"
                      />
                      <button
                        type="submit"
                        aria-label={"Add stock for #{item.product.name}"}
                        class="rounded p-1 text-emerald-700 hover:bg-emerald-50"
                      >
                        <.icon name="hero-plus" class="size-4" />
                      </button>
                    </.form>
                  </td>
                  <td class="px-2 py-3">
                    <.form
                      for={%{}}
                      as={:count}
                      phx-submit="count"
                      class="flex items-center gap-1"
                    >
                      <input type="hidden" name="product_id" value={item.product.id} />
                      <input
                        aria-label={"Counted amount for #{item.product.name}"}
                        name="quantity"
                        type="number"
                        min="0"
                        step="0.01"
                        value={format_quantity(non_negative(item.stock))}
                        required
                        class="w-14 rounded-md border-gray-300 text-xs shadow-sm"
                      />
                      <span class="text-xs text-gray-500">{item.display_unit}</span>
                      <button
                        type="submit"
                        aria-label={"Save count for #{item.product.name}"}
                        class="rounded p-1 text-gray-500 hover:bg-gray-100 hover:text-gray-900"
                      >
                        <.icon name="hero-clipboard-document-check" class="size-4" />
                      </button>
                    </.form>
                  </td>
                  <td class="px-2 py-3">
                    <.form
                      for={%{}}
                      as={:waste}
                      phx-submit="log_waste"
                      class="flex w-40 flex-col items-stretch gap-1"
                    >
                      <input type="hidden" name="product_id" value={item.product.id} />
                      <div class="flex items-center gap-1">
                        <input
                          aria-label={"Amount lost for #{item.product.name}"}
                          name="quantity"
                          type="number"
                          min="0.01"
                          step="0.01"
                          placeholder={item.display_unit}
                          required
                          class="w-14 rounded-md border-gray-300 text-xs shadow-sm"
                        />
                        <button
                          type="submit"
                          aria-label={"Log loss for #{item.product.name}"}
                          class="rounded p-1 text-rose-700 hover:bg-rose-50"
                        >
                          <.icon name="hero-exclamation-triangle" class="size-4" />
                        </button>
                      </div>
                      <select
                        aria-label={"Loss reason for #{item.product.name}"}
                        name="reason"
                        required
                        class="w-full rounded-md border-gray-300 text-xs shadow-sm"
                      >
                        <option value="">Reason</option>
                        <%= for reason <- @waste_reasons do %>
                          <option value={reason}>{String.capitalize(reason)}</option>
                        <% end %>
                      </select>
                    </.form>
                  </td>
                </tr>
              <% end %>
              <%= if @bar_stock_items == [] do %>
                <tr>
                  <td colspan="8" class="px-4 py-10 text-center text-gray-500">
                    No products are being tracked in the bar yet.
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

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
            <form phx-change="filter_loss_summary" class="flex flex-wrap items-end gap-2">
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
          <div class="overflow-x-auto border-y border-gray-200">
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
                    <td class="px-4 py-3 font-medium text-gray-900">{row.product.name}</td>
                    <td class="whitespace-nowrap px-4 py-3 text-gray-700">
                      {format_quantity(row.sold)} {row.display_unit}
                    </td>
                    <td class="whitespace-nowrap px-4 py-3 text-gray-700">
                      {format_quantity(row.loss)} {row.display_unit}
                    </td>
                    <td class={[
                      "whitespace-nowrap px-4 py-3 font-semibold",
                      Decimal.compare(row.loss_rate, 5) == :gt && "text-rose-700"
                    ]}>
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
          <div class="overflow-x-auto border-y border-gray-200">
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
                    <td class="whitespace-nowrap px-4 py-3 text-gray-500">
                      {Calendar.strftime(movement.inserted_at, "%d.%m.%Y %H:%M")}
                    </td>
                    <td class="whitespace-nowrap px-4 py-3 font-medium text-gray-900">
                      {movement.product.name}
                    </td>
                    <td class="whitespace-nowrap px-4 py-3 font-semibold">
                      {format_movement_quantity(movement.quantity, movement.product)}
                    </td>
                    <td class="whitespace-nowrap px-4 py-3 text-gray-700">
                      {movement_label(movement.movement_type)}
                    </td>
                    <td class="px-4 py-3 text-gray-500">
                      {if movement.order_item && movement.order_item.order,
                        do: "Order #{movement.order_item.order.order_number}",
                        else: movement.notes}
                    </td>
                  </tr>
                <% end %>
                <%= if @recent_movements == [] do %>
                  <tr>
                    <td colspan="5" class="px-4 py-8 text-center text-gray-500">
                      No bar stock movements yet.
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end

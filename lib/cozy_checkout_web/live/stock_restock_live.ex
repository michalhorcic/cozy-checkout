defmodule CozyCheckoutWeb.StockRestockLive do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.{Inventory, Catalog}

  @impl true
  def mount(_params, _session, socket) do
    all_combos = build_product_combos(Catalog.list_products())

    {:ok,
     socket
     |> assign(:page_title, "Shopping Trip")
     |> assign(:all_combos, all_combos)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:show_results, false)
     |> assign(:supplier, "")
     |> assign(:cart, [])}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_supplier", %{"supplier" => supplier}, socket) do
    {:noreply, assign(socket, :supplier, supplier)}
  end

  @impl true
  def handle_event("search_changed", %{"search" => query}, socket) do
    results =
      if String.length(query) >= 1 do
        query_lower = String.downcase(query)

        socket.assigns.all_combos
        |> Enum.filter(fn combo ->
          String.contains?(String.downcase(combo.product_name), query_lower) ||
            (combo.category_name &&
               String.contains?(String.downcase(combo.category_name), query_lower))
        end)
        |> Enum.take(12)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)
     |> assign(:show_results, query != "")}
  end

  @impl true
  def handle_event(
        "add_to_cart",
        %{"product-id" => product_id, "unit-amount" => unit_amount_str},
        socket
      ) do
    unit_amount = parse_unit_amount(unit_amount_str)

    combo =
      Enum.find(socket.assigns.all_combos, fn c ->
        c.product_id == product_id && c.unit_amount == unit_amount
      end)

    if combo do
      cart = add_or_increment(socket.assigns.cart, combo)

      {:noreply,
       socket
       |> assign(:cart, cart)
       |> assign(:search_query, "")
       |> assign(:search_results, [])
       |> assign(:show_results, false)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "increment_qty",
        %{"product-id" => product_id, "unit-amount" => unit_amount_str},
        socket
      ) do
    unit_amount = parse_unit_amount(unit_amount_str)
    cart = update_cart_qty(socket.assigns.cart, product_id, unit_amount, +1)
    {:noreply, assign(socket, :cart, cart)}
  end

  @impl true
  def handle_event(
        "decrement_qty",
        %{"product-id" => product_id, "unit-amount" => unit_amount_str},
        socket
      ) do
    unit_amount = parse_unit_amount(unit_amount_str)
    cart = update_cart_qty(socket.assigns.cart, product_id, unit_amount, -1)
    {:noreply, assign(socket, :cart, cart)}
  end

  @impl true
  def handle_event(
        "set_qty",
        %{"product-id" => product_id, "unit-amount" => unit_amount_str, "qty" => qty_str},
        socket
      ) do
    unit_amount = parse_unit_amount(unit_amount_str)

    qty =
      case Integer.parse(qty_str) do
        {n, ""} when n > 0 -> n
        _ -> 1
      end

    cart = set_cart_qty(socket.assigns.cart, product_id, unit_amount, qty)
    {:noreply, assign(socket, :cart, cart)}
  end

  @impl true
  def handle_event(
        "remove_from_cart",
        %{"product-id" => product_id, "unit-amount" => unit_amount_str},
        socket
      ) do
    unit_amount = parse_unit_amount(unit_amount_str)

    cart =
      Enum.reject(socket.assigns.cart, fn item ->
        item.product_id == product_id && item.unit_amount == unit_amount
      end)

    {:noreply, assign(socket, :cart, cart)}
  end

  @impl true
  def handle_event("save_batch", _params, socket) do
    cart = socket.assigns.cart

    if cart == [] do
      {:noreply, put_flash(socket, :error, "Add at least one product before saving")}
    else
      items =
        Enum.map(cart, fn item ->
          %{
            product_id: item.product_id,
            quantity: item.quantity,
            unit_amount: item.unit_amount
          }
        end)

      case Inventory.batch_restock(%{supplier: socket.assigns.supplier, items: items}) do
        {:ok, _} ->
          total_units = Enum.sum(Enum.map(cart, & &1.quantity))

          {:noreply,
           socket
           |> put_flash(:info, "Restocked #{length(cart)} products (#{total_units} total units)")
           |> push_navigate(to: ~p"/admin/stock")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to save — please try again")}
      end
    end
  end

  @impl true
  def handle_event("close_results", _params, socket) do
    {:noreply, assign(socket, :show_results, false)}
  end

  @impl true
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp build_product_combos(products) do
    Enum.flat_map(products, fn product ->
      unit_amounts =
        if product.default_unit_amounts && product.default_unit_amounts not in ["", "[]"] do
          product.default_unit_amounts
          |> Jason.decode!()
          |> Enum.map(&normalize_unit_amount/1)
        else
          []
        end

      case unit_amounts do
        [] ->
          [
            %{
              product_id: product.id,
              product_name: product.name,
              category_name: product.category && product.category.name,
              unit: product.unit,
              unit_amount: nil
            }
          ]

        amounts ->
          Enum.map(amounts, fn amount ->
            %{
              product_id: product.id,
              product_name: product.name,
              category_name: product.category && product.category.name,
              unit: product.unit,
              unit_amount: amount
            }
          end)
      end
    end)
    |> Enum.sort_by(fn c -> {c.product_name, c.unit_amount || 0} end)
  end

  defp add_or_increment(cart, combo) do
    idx =
      Enum.find_index(cart, fn item ->
        item.product_id == combo.product_id && item.unit_amount == combo.unit_amount
      end)

    if idx do
      List.update_at(cart, idx, fn item -> %{item | quantity: item.quantity + 1} end)
    else
      cart ++
        [
          %{
            product_id: combo.product_id,
            product_name: combo.product_name,
            category_name: combo.category_name,
            unit: combo.unit,
            unit_amount: combo.unit_amount,
            quantity: 1
          }
        ]
    end
  end

  defp update_cart_qty(cart, product_id, unit_amount, delta) do
    Enum.map(cart, fn item ->
      if item.product_id == product_id && item.unit_amount == unit_amount do
        %{item | quantity: max(1, item.quantity + delta)}
      else
        item
      end
    end)
  end

  defp set_cart_qty(cart, product_id, unit_amount, qty) do
    Enum.map(cart, fn item ->
      if item.product_id == product_id && item.unit_amount == unit_amount,
        do: %{item | quantity: qty},
        else: item
    end)
  end

  # Normalize float amounts that are whole numbers to integers for consistent matching
  defp normalize_unit_amount(amount) when is_integer(amount), do: amount

  defp normalize_unit_amount(amount) when is_float(amount) do
    if Float.floor(amount) == amount, do: trunc(amount), else: amount
  end

  defp parse_unit_amount(""), do: nil

  defp parse_unit_amount(str) do
    case Integer.parse(str) do
      {i, ""} ->
        i

      _ ->
        case Float.parse(str) do
          {f, ""} -> normalize_unit_amount(f)
          _ -> nil
        end
    end
  end

  defp unit_amount_param(nil), do: ""
  defp unit_amount_param(amount), do: to_string(amount)

  defp cart_total_units(cart), do: Enum.sum(Enum.map(cart, & &1.quantity))

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-8">
      <%!-- Header --%>
      <div class="mb-6">
        <.link
          navigate={~p"/admin/stock"}
          class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block"
        >
          ← Back to Stock Overview
        </.link>
        <h1 class="text-4xl font-bold text-primary-500 flex items-center gap-3">
          <span>🛒</span> Shopping Trip
        </h1>
        <p class="text-gray-500 mt-1">
          Search and add products, then save to update stock levels.
        </p>
      </div>

      <%!-- Trip info (date + supplier) --%>
      <div class="bg-white shadow-lg rounded-xl p-6 mb-6">
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Date</label>
            <div class="px-4 py-2.5 rounded-lg bg-gray-50 border border-gray-200 text-gray-500 text-sm">
              {Date.to_string(Date.utc_today())}
            </div>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">
              Supplier <span class="text-gray-400 font-normal">(optional)</span>
            </label>
            <form phx-change="update_supplier" phx-submit="noop">
              <input
                type="text"
                name="supplier"
                value={@supplier}
                placeholder="e.g. Makro, Albert"
                phx-debounce="300"
                class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 sm:text-sm"
              />
            </form>
          </div>
        </div>
      </div>

      <%!-- Product Search --%>
      <div class="bg-white shadow-lg rounded-xl p-6 mb-6">
        <h2 class="text-base font-semibold text-gray-900 mb-3 flex items-center gap-2">
          <.icon name="hero-magnifying-glass" class="w-5 h-5 text-gray-400" /> Add Products
        </h2>
        <form phx-change="search_changed" phx-submit="noop">
          <div class="relative">
            <input
              type="text"
              name="search"
              value={@search_query}
              placeholder="Search by product name or category…"
              phx-debounce="200"
              autocomplete="off"
              class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-tertiary-500 focus:ring-tertiary-500 pr-10"
            />
          <%= if @search_query != "" do %>
            <button
              type="button"
              phx-click="close_results"
              class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          <% end %>

          <%!-- Results dropdown --%>
          <%= if @show_results do %>
            <div class="absolute z-20 mt-1 w-full bg-white rounded-xl border border-gray-200 shadow-xl max-h-80 overflow-y-auto">
              <%= if @search_results == [] do %>
                <div class="px-4 py-6 text-center text-sm text-gray-400">
                  No products found for "{@search_query}"
                </div>
              <% else %>
                <ul>
                  <%= for combo <- @search_results do %>
                    <li class="flex items-center justify-between px-4 py-3 hover:bg-gray-50 transition-colors border-b border-gray-100 last:border-b-0">
                      <div class="min-w-0 flex-1">
                        <div class="text-sm font-medium text-gray-900 truncate">
                          {combo.product_name}
                        </div>
                        <div class="flex items-center gap-2 mt-0.5">
                          <%= if combo.category_name do %>
                            <span class="text-xs text-gray-400">{combo.category_name}</span>
                          <% end %>
                          <%= if combo.unit_amount do %>
                            <span class="px-1.5 py-0.5 text-xs font-semibold bg-tertiary-100 text-tertiary-800 rounded">
                              {combo.unit_amount}{combo.unit}
                            </span>
                          <% end %>
                        </div>
                      </div>
                      <button
                        type="button"
                        phx-click="add_to_cart"
                        phx-value-product-id={combo.product_id}
                        phx-value-unit-amount={unit_amount_param(combo.unit_amount)}
                        class="ml-4 flex-shrink-0 inline-flex items-center gap-1 px-3 py-1.5 bg-emerald-100 hover:bg-emerald-200 text-emerald-800 text-xs font-semibold rounded-lg transition-colors"
                      >
                        <.icon name="hero-plus" class="w-3.5 h-3.5" /> Add
                      </button>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          <% end %>
        </div>
        </form>
      </div>

      <%!-- Cart --%>
      <div class="bg-white shadow-lg rounded-xl overflow-hidden mb-6">
        <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
          <h2 class="text-base font-semibold text-gray-900 flex items-center gap-2">
            <.icon name="hero-shopping-cart" class="w-5 h-5 text-gray-400" />
            Items to Restock
            <%= if @cart != [] do %>
              <span class="bg-emerald-100 text-emerald-800 text-xs font-semibold px-2 py-0.5 rounded-full">
                {length(@cart)}
              </span>
            <% end %>
          </h2>
          <%= if @cart != [] do %>
            <span class="text-sm text-gray-400">
              {cart_total_units(@cart)} total units
            </span>
          <% end %>
        </div>

        <%= if @cart == [] do %>
          <div class="px-6 py-14 text-center">
            <.icon name="hero-shopping-cart" class="w-12 h-12 text-gray-200 mx-auto mb-3" />
            <p class="text-gray-400 font-medium">Your cart is empty</p>
            <p class="text-sm text-gray-400 mt-1">Search for a product above to get started</p>
          </div>
        <% else %>
          <ul class="divide-y divide-gray-100">
            <%= for item <- @cart do %>
              <li class="flex items-center gap-3 px-6 py-4">
                <%!-- Product info --%>
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="text-sm font-semibold text-gray-900">{item.product_name}</span>
                    <%= if item.unit_amount do %>
                      <span class="px-1.5 py-0.5 text-xs font-semibold bg-tertiary-100 text-tertiary-800 rounded">
                        {item.unit_amount}{item.unit}
                      </span>
                    <% end %>
                  </div>
                  <%= if item.category_name do %>
                    <div class="text-xs text-gray-400 mt-0.5">{item.category_name}</div>
                  <% end %>
                </div>

                <%!-- Quantity stepper --%>
                <div class="flex items-center gap-1 flex-shrink-0">
                  <button
                    type="button"
                    phx-click="decrement_qty"
                    phx-value-product-id={item.product_id}
                    phx-value-unit-amount={unit_amount_param(item.unit_amount)}
                    disabled={item.quantity <= 1}
                    class={[
                      "w-8 h-8 rounded-lg flex items-center justify-center font-bold text-lg transition-colors",
                      if(item.quantity <= 1,
                        do: "bg-gray-50 text-gray-300 cursor-not-allowed",
                        else: "bg-gray-100 hover:bg-gray-200 text-gray-600"
                      )
                    ]}
                  >
                    −
                  </button>
                  <input
                    type="number"
                    name="qty"
                    value={item.quantity}
                    min="1"
                    phx-blur="set_qty"
                    phx-value-product-id={item.product_id}
                    phx-value-unit-amount={unit_amount_param(item.unit_amount)}
                    class="w-16 text-center text-sm font-semibold rounded-lg border-gray-300 focus:border-tertiary-500 focus:ring-tertiary-500 py-1.5"
                  />
                  <button
                    type="button"
                    phx-click="increment_qty"
                    phx-value-product-id={item.product_id}
                    phx-value-unit-amount={unit_amount_param(item.unit_amount)}
                    class="w-8 h-8 rounded-lg bg-gray-100 hover:bg-gray-200 flex items-center justify-center font-bold text-lg text-gray-600 transition-colors"
                  >
                    +
                  </button>
                </div>

                <%!-- Remove --%>
                <button
                  type="button"
                  phx-click="remove_from_cart"
                  phx-value-product-id={item.product_id}
                  phx-value-unit-amount={unit_amount_param(item.unit_amount)}
                  class="flex-shrink-0 text-gray-300 hover:text-rose-500 transition-colors"
                  title="Remove"
                >
                  <.icon name="hero-x-mark" class="w-5 h-5" />
                </button>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <%!-- Footer actions --%>
      <div class="flex justify-between items-center">
        <.link
          navigate={~p"/admin/stock"}
          class="px-6 py-2.5 text-sm font-medium text-gray-600 hover:text-gray-900 transition-colors"
        >
          Cancel
        </.link>
        <button
          type="button"
          phx-click="save_batch"
          disabled={@cart == []}
          class={[
            "inline-flex items-center gap-2 px-6 py-2.5 text-sm font-semibold rounded-lg transition-colors",
            if(@cart == [],
              do: "bg-gray-100 text-gray-400 cursor-not-allowed",
              else: "bg-emerald-600 hover:bg-emerald-700 text-white shadow-sm"
            )
          ]}
        >
          <.icon name="hero-check" class="w-4 h-4" />
          Save Shopping Trip
          <%= if @cart != [] do %>
            <span class="opacity-75">({cart_total_units(@cart)} units)</span>
          <% end %>
        </button>
      </div>
    </div>
    """
  end
end

defmodule CozyCheckoutWeb.OrderLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales

  import CozyCheckoutWeb.FlopComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Normalize params: convert indexed maps to arrays for Flop
    normalized_params = normalize_flop_params(params)

    socket =
      case Sales.list_orders_with_flop(normalized_params) do
        {:ok, {orders, meta}} ->
          socket
          |> assign(:orders, orders)
          |> assign(:meta, meta)

        {:error, meta} ->
          socket
          |> assign(:orders, [])
          |> assign(:meta, meta)
      end

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Orders")
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    order = Sales.get_order!(id)

    # Prevent deletion of paid orders - they serve as accounting history
    if order.status == "paid" do
      {:noreply,
       put_flash(socket, :error, "Cannot delete paid orders. They serve as accounting history.")}
    else
      {:ok, _} = Sales.delete_order(order)
      # Re-fetch orders after delete
      {:noreply, push_patch(socket, to: ~p"/admin/orders")}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    # Push patch to update URL with filter params
    {:noreply, push_patch(socket, to: ~p"/admin/orders?#{build_filter_params(params)}")}
  end

  # Helper to build filter params from form
  defp build_filter_params(params) do
    filters =
      case params["filters"] do
        nil ->
          []

        filters_map ->
          filters_map
          |> Enum.map(fn {_idx, filter} ->
            # Only include filters with non-empty values
            if filter["value"] && filter["value"] != "" do
              %{
                "field" => filter["field"],
                "op" => filter["op"] || "==",
                "value" => filter["value"]
              }
            else
              nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.with_index()
          |> Enum.into(%{}, fn {filter, idx} ->
            {to_string(idx), filter}
          end)
      end

    # Preserve existing params
    %{
      "filters" => filters,
      "page" => params["page"],
      "page_size" => params["page_size"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) || v == %{} end)
    |> Map.new()
  end

  # Convert Phoenix indexed map params (e.g., %{"0" => "value"}) to arrays for Flop
  defp normalize_flop_params(params) do
    params
    |> normalize_array_param("order_by")
    |> normalize_array_param("order_directions")
  end

  defp normalize_array_param(params, key) do
    case Map.get(params, key) do
      # If it's a map with string keys "0", "1", etc., convert to array
      value when is_map(value) ->
        array =
          value
          |> Enum.sort_by(fn {k, _v} -> String.to_integer(k) end)
          |> Enum.map(fn {_k, v} -> v end)

        Map.put(params, key, array)

      # Otherwise, leave it as is
      _ ->
        params
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8 flex items-center justify-between">
        <div>
          <.link navigate={~p"/admin"} class="text-blue-600 hover:text-blue-800 mb-2 inline-block">
            ← Back to Dashboard
          </.link>
          <h1 class="text-4xl font-bold text-gray-900">{@page_title}</h1>
        </div>
        <.link navigate={~p"/admin/orders/new"}>
          <.button>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Order
          </.button>
        </.link>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <!-- Filter Form -->
        <.filter_form meta={@meta} path={~p"/admin/orders"} id="orders-filter">
          <:filter>
            <input type="hidden" name="filters[0][field]" value="status" />
            <input type="hidden" name="filters[0][op]" value="==" />
            <.input
              type="select"
              name="filters[0][value]"
              label="Status"
              options={[
                {"All", ""},
                {"Open", "open"},
                {"Paid", "paid"},
                {"Partially Paid", "partially_paid"},
                {"Cancelled", "cancelled"}
              ]}
              value={get_filter_value(@meta, :status)}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[1][field]" value="inserted_at" />
            <input type="hidden" name="filters[1][op]" value=">=" />
            <.input
              type="date"
              name="filters[1][value]"
              label="Date From"
              value={get_filter_value(@meta, :inserted_at)}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[2][field]" value="inserted_at" />
            <input type="hidden" name="filters[2][op]" value="<=" />
            <.input
              type="date"
              name="filters[2][value]"
              label="Date To"
              value={get_filter_value(@meta, :inserted_at)}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[3][field]" value="order_number" />
            <input type="hidden" name="filters[3][op]" value="ilike_and" />
            <.input
              type="text"
              name="filters[3][value]"
              label="Order Number"
              value={get_filter_value(@meta, :order_number)}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[4][field]" value="name" />
            <input type="hidden" name="filters[4][op]" value="ilike_and" />
            <.input
              type="text"
              name="filters[4][value]"
              label="Order Name"
              value={get_filter_value(@meta, :name)}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[5][field]" value="guest_name" />
            <input type="hidden" name="filters[5][op]" value="ilike_and" />
            <.input
              type="text"
              name="filters[5][value]"
              label="Guest Name"
              value={get_filter_value(@meta, :guest_name)}
            />
          </:filter>
        </.filter_form>
        <!-- Table -->
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Order #
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Guest / Name
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Total
                </th>
                <.sortable_header meta={@meta} field={:status} path={~p"/admin/orders"}>
                  Status
                </.sortable_header>
                <.sortable_header meta={@meta} field={:inserted_at} path={~p"/admin/orders"}>
                  Date
                </.sortable_header>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= if @orders == [] do %>
                <tr>
                  <td colspan="6" class="px-6 py-12 text-center text-gray-500">
                    No orders found.
                  </td>
                </tr>
              <% else %>
                <tr :for={order <- @orders} class="hover:bg-gray-50">
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    {order.order_number}
                  </td>
                  <td class="px-6 py-4 text-sm text-gray-500">
                    <%= if order.booking_id do %>
                      {order.booking && order.booking.guest && order.booking.guest.name}
                    <% else %>
                      <span class="flex items-center gap-2">
                        <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-purple-100 text-purple-800">
                          Standalone
                        </span>
                        <span class="font-medium text-gray-900">{order.name}</span>
                      </span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {format_currency(order.total_amount)}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span class={[
                      "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                      case order.status do
                        "paid" -> "bg-green-100 text-green-800"
                        "partially_paid" -> "bg-yellow-100 text-yellow-800"
                        "open" -> "bg-blue-100 text-blue-800"
                        "cancelled" -> "bg-red-100 text-red-800"
                        _ -> "bg-gray-100 text-gray-800"
                      end
                    ]}>
                      {String.replace(order.status, "_", " ") |> String.capitalize()}
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {Calendar.strftime(order.inserted_at, "%Y-%m-%d %H:%M")}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <.link
                      navigate={~p"/admin/orders/#{order}"}
                      class="text-blue-600 hover:text-blue-900 mr-4"
                    >
                      View
                    </.link>
                    <%= if order.status != "paid" do %>
                      <.link
                        phx-click={JS.push("delete", value: %{id: order.id})}
                        data-confirm="Are you sure?"
                        class="text-red-600 hover:text-red-900"
                      >
                        Delete
                      </.link>
                    <% else %>
                      <span
                        class="text-gray-400 italic text-xs"
                        title="Paid orders cannot be deleted"
                      >
                        <.icon name="hero-lock-closed" class="w-4 h-4 inline" /> Locked
                      </span>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
        <!-- Pagination -->
        <.pagination meta={@meta} path={~p"/admin/orders"} />
      </div>
    </div>
    """
  end
end

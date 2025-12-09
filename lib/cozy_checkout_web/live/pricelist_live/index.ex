defmodule CozyCheckoutWeb.PricelistLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Catalog
  alias CozyCheckout.Catalog.Pricelist

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
      case Catalog.list_pricelists_with_flop(normalized_params) do
        {:ok, {pricelists, meta}} ->
          socket
          |> assign(:pricelists, pricelists)
          |> assign(:meta, meta)
          |> assign(:current_params, params)

        {:error, meta} ->
          socket
          |> assign(:pricelists, [])
          |> assign(:meta, meta)
          |> assign(:current_params, params)
      end

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Pricelist")
    |> assign(:pricelist, Catalog.get_pricelist!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Pricelist")
    |> assign(:pricelist, %Pricelist{valid_from: Date.utc_today()})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Pricelists")
    |> assign(:pricelist, nil)
  end

  @impl true
  def handle_info({CozyCheckoutWeb.PricelistLive.FormComponent, {:saved, _pricelist}}, socket) do
    # Re-fetch pricelists to show updated data, preserving current filters
    {:noreply, push_patch(socket, to: build_path_with_params(~p"/admin/pricelists", socket.assigns.current_params))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    pricelist = Catalog.get_pricelist!(id)
    {:ok, _} = Catalog.delete_pricelist(pricelist)

    # Re-fetch pricelists after delete, preserving current filters
    {:noreply, push_patch(socket, to: build_path_with_params(~p"/admin/pricelists", socket.assigns.current_params))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    # Push patch to update URL with filter params
    {:noreply, push_patch(socket, to: ~p"/admin/pricelists?#{build_filter_params(params)}")}
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

    # Preserve existing params including custom filters
    %{
      "filters" => filters,
      "page" => params["page"],
      "page_size" => params["page_size"],
      "product_name" => params["product_name"],
      "category_id" => params["category_id"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) || v == %{} || v == "" end)
    |> Map.new()
  end

  defp format_price_display(pricelist) do
    cond do
      # Has price tiers - show them
      pricelist.price_tiers && pricelist.price_tiers != [] ->
        pricelist.price_tiers
        |> Enum.map(fn tier ->
          unit_amount = tier["unit_amount"] || tier[:unit_amount]
          price = tier["price"] || tier[:price]
          # Convert to Decimal for proper formatting
          price_decimal =
            if is_struct(price, Decimal), do: price, else: Decimal.new(to_string(price))

          "#{format_number(unit_amount)}: #{format_currency(price_decimal)}"
        end)
        |> Enum.join(", ")

      # Has single price
      pricelist.price ->
        format_currency(pricelist.price)

      # No price set
      true ->
        "—"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8 flex items-center justify-between">
        <div>
          <.link navigate={~p"/admin"} class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block">
            ← Back to Dashboard
          </.link>
          <h1 class="text-4xl font-bold text-primary-500">{@page_title}</h1>
        </div>
        <div class="flex gap-3">
          <.link
            navigate={~p"/admin/pricelists/management"}
            class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-gradient-to-r from-emerald-500 to-teal-600 hover:from-emerald-600 hover:to-teal-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-emerald-500 transition-all duration-200"
          >
            <.icon name="hero-clipboard-document-check" class="w-5 h-5 mr-2" /> Price Management
          </.link>
          <.link patch={build_path_with_params(~p"/admin/pricelists/new", @current_params)}>
            <.button>
              <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Pricelist
            </.button>
          </.link>
        </div>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <!-- Filter Form -->
        <.filter_form meta={@meta} path={~p"/admin/pricelists"} id="pricelists-filter">
          <:filter>
            <.input
              type="text"
              name="product_name"
              label="Product Name"
              placeholder="Search by product name"
              value={Map.get(@meta.params, "product_name", "")}
            />
          </:filter>
          <:filter>
            <.input
              type="select"
              name="category_id"
              label="Category"
              options={[{"All", ""} | Enum.map(Catalog.list_categories(), &{&1.name, &1.id})]}
              value={Map.get(@meta.params, "category_id", "")}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[0][field]" value="active" />
            <input type="hidden" name="filters[0][op]" value="==" />
            <.input
              type="select"
              name="filters[0][value]"
              label="Status"
              options={[
                {"All", ""},
                {"Active", "true"},
                {"Inactive", "false"}
              ]}
              value={get_filter_value(@meta, :active)}
            />
          </:filter>
        </.filter_form>
        <!-- Table -->
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-secondary-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                  Product
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                  Category
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                  Price
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                  VAT Rate
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                  Valid From
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                  Valid To
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                  Status
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-primary-400 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= if @pricelists == [] do %>
                <tr>
                  <td colspan="8" class="px-6 py-12 text-center text-primary-400">
                    No pricelists found.
                  </td>
                </tr>
              <% else %>
                <tr :for={pricelist <- @pricelists} class="hover:bg-secondary-50">
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-primary-500">
                    {pricelist.product && pricelist.product.name}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-primary-400">
                    {pricelist.product && pricelist.product.category && pricelist.product.category.name}
                  </td>
                  <td class="px-6 py-4 text-sm text-primary-500">
                    {format_price_display(pricelist)}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-primary-400">
                    {pricelist.vat_rate}%
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-primary-400">
                    {pricelist.valid_from}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-primary-400">
                    {pricelist.valid_to || "—"}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span class={[
                      "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                      if(pricelist.active,
                        do: "bg-success-light text-success-dark",
                        else: "bg-secondary-100 text-primary-500"
                      )
                    ]}>
                      {if pricelist.active, do: "Active", else: "Inactive"}
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <.link
                      patch={build_path_with_params(~p"/admin/pricelists/#{pricelist}/edit", @current_params)}
                      class="text-tertiary-600 hover:text-white-900 mr-4"
                    >
                      Edit
                    </.link>
                    <.link
                      phx-click={JS.push("delete", value: %{id: pricelist.id})}
                      data-confirm="Are you sure?"
                      class="text-error hover:text-error-dark"
                    >
                      Delete
                    </.link>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
        <!-- Pagination -->
        <.pagination meta={@meta} path={~p"/admin/pricelists"} />
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="pricelist-modal"
        show
        on_cancel={JS.patch(build_path_with_params(~p"/admin/pricelists", @current_params))}
      >
        <.live_component
          module={CozyCheckoutWeb.PricelistLive.FormComponent}
          id={@pricelist.id || :new}
          title={@page_title}
          action={@live_action}
          pricelist={@pricelist}
          patch={build_path_with_params(~p"/admin/pricelists", @current_params)}
        />
      </.modal>
    </div>
    """
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
end

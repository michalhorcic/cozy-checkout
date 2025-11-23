defmodule CozyCheckoutWeb.ProductLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Catalog
  alias CozyCheckout.Catalog.Product

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
      case Catalog.list_products_with_flop(normalized_params) do
        {:ok, {products, meta}} ->
          socket
          |> assign(:products, products)
          |> assign(:meta, meta)
          |> assign(:current_params, params)

        {:error, meta} ->
          socket
          |> assign(:products, [])
          |> assign(:meta, meta)
          |> assign(:current_params, params)
      end

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Product")
    |> assign(:product, Catalog.get_product!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Product")
    |> assign(:product, %Product{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Products")
    |> assign(:product, nil)
  end

  @impl true
  def handle_info({CozyCheckoutWeb.ProductLive.FormComponent, {:saved, _product}}, socket) do
    # Re-fetch products to show updated data, preserving current filters
    {:noreply, push_patch(socket, to: build_path_with_params(~p"/admin/products", socket.assigns.current_params))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product = Catalog.get_product!(id)
    {:ok, _} = Catalog.delete_product(product)

    # Re-fetch products after delete, preserving current filters
    {:noreply, push_patch(socket, to: build_path_with_params(~p"/admin/products", socket.assigns.current_params))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    # Push patch to update URL with filter params
    {:noreply, push_patch(socket, to: ~p"/admin/products?#{build_filter_params(params)}")}
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
      "product_name" => params["product_name"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) || v == %{} || v == "" end)
    |> Map.new()
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
        <.link patch={build_path_with_params(~p"/admin/products/new", @current_params)}>
          <.button>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Product
          </.button>
        </.link>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <!-- Filter Form -->
        <.filter_form meta={@meta} path={~p"/admin/products"} id="products-filter">
          <:filter>
            <.input
              type="text"
              name="product_name"
              label="Product Name"
              placeholder="Search by name"
              value={Map.get(@meta.params, "product_name", "")}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[0][field]" value="category_id" />
            <input type="hidden" name="filters[0][op]" value="==" />
            <.input
              type="select"
              name="filters[0][value]"
              label="Category"
              options={[{"All", ""} | Enum.map(Catalog.list_categories(), &{&1.name, &1.id})]}
              value={get_filter_value(@meta, :category_id)}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[1][field]" value="active" />
            <input type="hidden" name="filters[1][op]" value="==" />
            <.input
              type="select"
              name="filters[1][value]"
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
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Name
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Category
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Unit Tracking
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Description
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= if @products == [] do %>
                <tr>
                  <td colspan="6" class="px-6 py-12 text-center text-gray-500">
                    No products found.
                  </td>
                </tr>
              <% else %>
                <tr :for={product <- @products} class="hover:bg-gray-50">
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    {product.name}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {product.category && product.category.name}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {product.unit || "—"}
                  </td>
                  <td class="px-6 py-4 text-sm text-gray-500">
                    {product.description}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span class={[
                      "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                      if(product.active,
                        do: "bg-green-100 text-green-800",
                        else: "bg-gray-100 text-gray-800"
                      )
                    ]}>
                      {if product.active, do: "Active", else: "Inactive"}
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <.link
                      patch={build_path_with_params(~p"/admin/products/#{product}/edit", @current_params)}
                      class="text-indigo-600 hover:text-indigo-900 mr-4"
                    >
                      Edit
                    </.link>
                    <.link
                      phx-click={JS.push("delete", value: %{id: product.id})}
                      data-confirm="Are you sure?"
                      class="text-red-600 hover:text-red-900"
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
        <.pagination meta={@meta} path={~p"/admin/products"} />
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="product-modal"
        show
        on_cancel={JS.patch(build_path_with_params(~p"/admin/products", @current_params))}
      >
        <.live_component
          module={CozyCheckoutWeb.ProductLive.FormComponent}
          id={@product.id || :new}
          title={@page_title}
          action={@live_action}
          product={@product}
          patch={build_path_with_params(~p"/admin/products", @current_params)}
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

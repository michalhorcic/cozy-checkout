defmodule CozyCheckoutWeb.PricelistLive.FormComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Catalog

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form
        for={@form}
        id="pricelist-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.product_autocomplete
          form={@form}
          field={:product_id}
          label="Product"
          products={@filtered_products}
          selected_product={@selected_product}
          search_query={@search_query}
          show_dropdown={@show_dropdown}
          is_editing={@action == :edit}
          target={@myself}
        />
        
    <!-- Price tiers for products with default_unit_amounts -->
        <div :if={@selected_product && @selected_product.default_unit_amounts} class="mb-6">
          <label class="block text-sm font-semibold text-gray-700 mb-4">
            Price Tiers for {@selected_product.name}
            <span :if={@selected_product.unit} class="text-sm font-normal text-gray-500">
              ({@selected_product.unit})
            </span>
          </label>

          <div class="space-y-3">
            <div
              :for={{tier, idx} <- Enum.with_index(@price_tiers)}
              class="flex items-center gap-4 p-4 bg-gray-50 rounded-lg"
            >
              <div class="flex-1">
                <span class="text-lg font-medium text-gray-900">
                  {format_tier_amount(tier["unit_amount"])} {@selected_product.unit}
                </span>
              </div>

              <div class="flex items-center gap-2">
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={tier["price"]}
                  phx-blur="update_price_tier"
                  phx-target={@myself}
                  phx-value-index={idx}
                  name="price"
                  class="w-32 px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  placeholder="0.00"
                  required
                />
                <span class="text-gray-600 font-medium">CZK</span>
              </div>
            </div>
          </div>

          <p class="mt-3 text-sm text-gray-500">
            Set prices for each predefined size. These will be used when adding items in the POS system.
          </p>
        </div>
        
    <!-- Single price for products without default_unit_amounts -->
        <div :if={@selected_product && !@selected_product.default_unit_amounts}>
          <.input field={@form[:price]} type="number" label="Price" step="0.01" required />
          <p class="mt-2 text-sm text-gray-500">
            This product has no predefined amounts, so a single price will be used.
          </p>
        </div>

        <.input field={@form[:vat_rate]} type="number" label="VAT Rate (%)" step="0.01" required />

        <.input field={@form[:valid_from]} type="date" label="Valid From" required />

        <.input field={@form[:valid_to]} type="date" label="Valid To" />

        <.input field={@form[:active]} type="checkbox" label="Active" />

        <div class="mt-6 flex items-center justify-end gap-x-6">
          <.button type="submit" phx-disable-with="Saving...">Save Pricelist</.button>
        </div>
      </.form>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :products, :list, required: true
  attr :selected_product, :map, default: nil
  attr :search_query, :string, default: ""
  attr :show_dropdown, :boolean, default: false
  attr :is_editing, :boolean, default: false
  attr :target, :any, required: true

  defp product_autocomplete(assigns) do
    ~H"""
    <div class="form-control w-full mb-4">
      <label class="label">
        <span class="label-text font-medium">{@label}</span>
        <span class="label-text-alt text-error">*</span>
      </label>

      <div class="relative">
        <!-- Hidden input to store the actual product_id -->
        <input type="hidden" name={"#{@form.name}[#{@field}]"} value={@form[@field].value} />
        
    <!-- Search input (disabled when editing) -->
        <div :if={!@is_editing} class="relative">
          <input
            type="text"
            name="search_query"
            id={"#{@form.id}_#{@field}_search"}
            class="input input-bordered w-full pr-10"
            placeholder="Search products..."
            value={@search_query}
            phx-change="search_product"
            phx-target={@target}
            phx-debounce="300"
            autocomplete="off"
          />
          <.icon
            name="hero-magnifying-glass"
            class="absolute right-3 top-1/2 -translate-y-1/2 w-5 h-5 text-base-content/40"
          />
        </div>
        
    <!-- Selected product display -->
        <div
          :if={@selected_product}
          class="mt-2 flex items-center justify-between p-3 bg-base-200 rounded-lg"
        >
          <div class="flex items-center gap-2">
            <.icon name="hero-check-circle" class="w-5 h-5 text-success" />
            <div>
              <p class="font-medium">{@selected_product.name}</p>
              <p
                :if={@selected_product.category && Ecto.assoc_loaded?(@selected_product.category)}
                class="text-sm text-base-content/60"
              >
                {@selected_product.category.name}
              </p>
            </div>
          </div>
          <button
            :if={!@is_editing}
            type="button"
            class="btn btn-ghost btn-sm btn-circle"
            phx-click="clear_product"
            phx-target={@target}
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>
        
    <!-- Dropdown with results -->
        <div
          :if={@show_dropdown && @products != []}
          class="absolute z-50 w-full mt-2 bg-base-100 border border-base-300 rounded-lg shadow-lg max-h-96 overflow-y-auto"
        >
          <ul class="menu p-2">
            <li :for={product <- @products}>
              <button
                type="button"
                class="flex flex-col items-start gap-1 hover:bg-base-200 active:bg-base-300"
                phx-click="select_product"
                phx-value-id={product.id}
                phx-target={@target}
              >
                <span class="font-medium">{product.name}</span>
                <div class="flex items-center gap-2 text-sm text-base-content/60">
                  <span :if={product.category && Ecto.assoc_loaded?(product.category)}>
                    {product.category.name}
                  </span>
                  <span :if={product.unit} class="badge badge-sm">
                    {product.unit}
                  </span>
                </div>
              </button>
            </li>
          </ul>
        </div>
        
    <!-- No results message -->
        <div
          :if={@show_dropdown && @products == [] && @search_query != ""}
          class="absolute z-50 w-full mt-2 bg-base-100 border border-base-300 rounded-lg shadow-lg p-4"
        >
          <p class="text-center text-base-content/60">No products found</p>
        </div>
      </div>

      <label :if={@form[@field].errors != []} class="label">
        <span class="label-text-alt text-error">
          {translate_errors(@form[@field].errors)}
        </span>
      </label>
    </div>
    """
  end

  defp translate_errors([{msg, _opts} | _]), do: msg
  defp translate_errors([msg | _]) when is_binary(msg), do: msg
  defp translate_errors(_), do: ""

  @impl true
  def update(%{pricelist: pricelist} = assigns, socket) do
    all_products = Catalog.list_products()
    selected_product = get_selected_product(pricelist, all_products)

    # Initialize price tiers from product's default amounts
    price_tiers = initialize_price_tiers(pricelist, selected_product)

    # Only show dropdown when creating (not editing)
    show_dropdown = assigns.action == :new

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:all_products, all_products)
     |> assign(:filtered_products, Enum.take(all_products, 20))
     |> assign(:selected_product, selected_product)
     |> assign(:price_tiers, price_tiers)
     |> assign(:search_query, (selected_product && selected_product.name) || "")
     |> assign(:show_dropdown, show_dropdown)
     |> assign_new(:form, fn ->
       to_form(Catalog.change_pricelist(pricelist))
     end)}
  end

  defp initialize_price_tiers(%{price_tiers: existing_tiers}, _product)
       when is_list(existing_tiers) and length(existing_tiers) > 0 do
    # Use existing price tiers if they exist
    existing_tiers
  end

  defp initialize_price_tiers(_pricelist, nil), do: []
  defp initialize_price_tiers(_pricelist, %{default_unit_amounts: nil}), do: []
  defp initialize_price_tiers(_pricelist, %{default_unit_amounts: ""}), do: []

  defp initialize_price_tiers(_pricelist, product) do
    # Create price tiers from product's default amounts
    case Jason.decode(product.default_unit_amounts) do
      {:ok, amounts} when is_list(amounts) ->
        Enum.map(amounts, fn amount ->
          %{"unit_amount" => amount, "price" => 0}
        end)

      _ ->
        []
    end
  end

  defp format_tier_amount(num) when is_integer(num), do: Integer.to_string(num)
  defp format_tier_amount(num) when is_float(num), do: :erlang.float_to_binary(num, decimals: 2)
  defp format_tier_amount(num), do: to_string(num)

  defp get_selected_product(%{product: %Ecto.Association.NotLoaded{}}, _products), do: nil
  defp get_selected_product(%{product: product}, _products) when not is_nil(product), do: product

  defp get_selected_product(%{product_id: product_id}, products) when not is_nil(product_id) do
    Enum.find(products, &(&1.id == product_id))
  end

  defp get_selected_product(_, _), do: nil

  @impl true
  def handle_event("search_product", %{"search_query" => query}, socket) do
    filtered_products = filter_products(socket.assigns.all_products, query)

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:filtered_products, filtered_products)
     |> assign(:show_dropdown, true)}
  end

  @impl true
  def handle_event("select_product", %{"id" => product_id}, socket) do
    product = Enum.find(socket.assigns.all_products, &(&1.id == product_id))

    if product do
      # Initialize price tiers for the newly selected product
      price_tiers = initialize_price_tiers(%{price_tiers: []}, product)

      changeset =
        Catalog.change_pricelist(socket.assigns.pricelist, %{"product_id" => product_id})

      {:noreply,
       socket
       |> assign(:selected_product, product)
       |> assign(:price_tiers, price_tiers)
       |> assign(:search_query, product.name)
       |> assign(:show_dropdown, false)
       |> assign(:form, to_form(changeset))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_product", _params, socket) do
    changeset = Catalog.change_pricelist(socket.assigns.pricelist, %{"product_id" => nil})

    {:noreply,
     socket
     |> assign(:selected_product, nil)
     |> assign(:search_query, "")
     |> assign(:show_dropdown, false)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("update_price_tier", %{"index" => idx, "value" => price}, socket) do
    update_price_tier_at_index(socket, String.to_integer(idx), price)
  end

  @impl true
  def handle_event("update_price_tier", %{"index" => idx, "price" => price}, socket) do
    update_price_tier_at_index(socket, String.to_integer(idx), price)
  end

  @impl true
  def handle_event("validate", %{"pricelist" => pricelist_params}, socket) do
    changeset = Catalog.change_pricelist(socket.assigns.pricelist, pricelist_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("save", %{"pricelist" => pricelist_params}, socket) do
    # Add price_tiers to params if product has default_unit_amounts
    pricelist_params =
      if socket.assigns.selected_product && socket.assigns.selected_product.default_unit_amounts do
        Map.put(pricelist_params, "price_tiers", socket.assigns.price_tiers)
      else
        # Remove price_tiers for products without default_unit_amounts
        Map.delete(pricelist_params, "price_tiers")
      end

    save_pricelist(socket, socket.assigns.action, pricelist_params)
  end

  defp update_price_tier_at_index(socket, index, price) do
    updated_tiers =
      List.update_at(socket.assigns.price_tiers, index, fn tier ->
        Map.put(tier, "price", parse_price(price))
      end)

    {:noreply, assign(socket, :price_tiers, updated_tiers)}
  end

  defp parse_price(""), do: 0

  defp parse_price(price) when is_binary(price) do
    case Float.parse(price) do
      {num, _} -> num
      :error -> 0
    end
  end

  defp parse_price(price) when is_number(price), do: price
  defp parse_price(_), do: 0

  defp filter_products(products, query) when query == "" do
    # Show first 20 products when no search query
    Enum.take(products, 20)
  end

  defp filter_products(products, query) do
    query_lower = String.downcase(query)

    products
    |> Enum.filter(fn product ->
      String.contains?(String.downcase(product.name), query_lower) ||
        (product.category && String.contains?(String.downcase(product.category.name), query_lower))
    end)
    |> Enum.take(10)
  end

  defp save_pricelist(socket, :edit, pricelist_params) do
    case Catalog.update_pricelist(socket.assigns.pricelist, pricelist_params) do
      {:ok, pricelist} ->
        notify_parent({:saved, pricelist})

        {:noreply,
         socket
         |> put_flash(:info, "Pricelist updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_pricelist(socket, :new, pricelist_params) do
    case Catalog.create_pricelist(pricelist_params) do
      {:ok, pricelist} ->
        notify_parent({:saved, pricelist})

        {:noreply,
         socket
         |> put_flash(:info, "Pricelist created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end

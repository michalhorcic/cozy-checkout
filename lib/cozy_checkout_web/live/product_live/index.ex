defmodule CozyCheckoutWeb.ProductLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Catalog
  alias CozyCheckout.Catalog.Product

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :products, Catalog.list_products())}
  end

  @impl true
  def handle_params(params, _url, socket) do
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
  def handle_info({CozyCheckoutWeb.ProductLive.FormComponent, {:saved, product}}, socket) do
    {:noreply, stream_insert(socket, :products, Catalog.get_product!(product.id))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product = Catalog.get_product!(id)
    {:ok, _} = Catalog.delete_product(product)

    {:noreply, stream_delete(socket, :products, product)}
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
        <.link patch={~p"/admin/products/new"}>
          <.button>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Product
          </.button>
        </.link>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
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
          <tbody id="products" phx-update="stream" class="bg-white divide-y divide-gray-200">
            <tr :for={{id, product} <- @streams.products} id={id} class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                {product.name}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {product.category && product.category.name}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {product.unit || "-"}
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
                  patch={~p"/admin/products/#{product}/edit"}
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
          </tbody>
        </table>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="product-modal"
        show
        on_cancel={JS.patch(~p"/admin/products")}
      >
        <.live_component
          module={CozyCheckoutWeb.ProductLive.FormComponent}
          id={@product.id || :new}
          title={@page_title}
          action={@live_action}
          product={@product}
          patch={~p"/admin/products"}
        />
      </.modal>
    </div>
    """
  end
end

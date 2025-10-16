defmodule CozyCheckoutWeb.CategoryLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Catalog
  alias CozyCheckout.Catalog.Category

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :categories, Catalog.list_categories())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Category")
    |> assign(:category, Catalog.get_category!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Category")
    |> assign(:category, %Category{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Categories")
    |> assign(:category, nil)
  end

  @impl true
  def handle_info({CozyCheckoutWeb.CategoryLive.FormComponent, {:saved, category}}, socket) do
    {:noreply, stream_insert(socket, :categories, category)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    category = Catalog.get_category!(id)
    {:ok, _} = Catalog.delete_category(category)

    {:noreply, stream_delete(socket, :categories, category)}
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
        <.link patch={~p"/admin/categories/new"}>
          <.button>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Category
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
                Description
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody id="categories" phx-update="stream" class="bg-white divide-y divide-gray-200">
            <tr :for={{id, category} <- @streams.categories} id={id} class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                {category.name}
              </td>
              <td class="px-6 py-4 text-sm text-gray-500">
                {category.description}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <.link
                  patch={~p"/admin/categories/#{category}/edit"}
                  class="text-indigo-600 hover:text-indigo-900 mr-4"
                >
                  Edit
                </.link>
                <.link
                  phx-click={JS.push("delete", value: %{id: category.id})}
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
        id="category-modal"
        show
        on_cancel={JS.patch(~p"/admin/categories")}
      >
        <.live_component
          module={CozyCheckoutWeb.CategoryLive.FormComponent}
          id={@category.id || :new}
          title={@page_title}
          action={@live_action}
          category={@category}
          patch={~p"/admin/categories"}
        />
      </.modal>
    </div>
    """
  end
end

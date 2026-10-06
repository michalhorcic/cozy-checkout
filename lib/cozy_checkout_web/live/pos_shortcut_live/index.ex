defmodule CozyCheckoutWeb.PosShortcutLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Catalog
  alias CozyCheckout.Catalog.PosProductShortcut

  @impl true
  def mount(_params, _session, socket) do
    shortcuts = Catalog.list_pos_shortcuts_for_admin()

    {:ok,
     socket
     |> assign(:products, Catalog.list_pos_products())
     |> assign(:shortcut_count, length(shortcuts))
     |> stream(:shortcuts, shortcuts)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    shortcut = Catalog.get_pos_shortcut!(id)
    products = socket.assigns.products

    products =
      if Enum.any?(products, &(&1.id == shortcut.product_id)) do
        products
      else
        [shortcut.product | products]
      end

    socket
    |> assign(:page_title, "Edit POS shortcut")
    |> assign(:products, products)
    |> assign(:shortcut, shortcut)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New POS shortcut")
    |> assign(:shortcut, %PosProductShortcut{position: Catalog.next_pos_shortcut_position()})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "POS shortcuts")
    |> assign(:shortcut, nil)
  end

  @impl true
  def handle_info({CozyCheckoutWeb.PosShortcutLive.FormComponent, {:saved, _shortcut}}, socket) do
    shortcuts = Catalog.list_pos_shortcuts_for_admin()

    {:noreply,
     socket
     |> assign(:shortcut_count, length(shortcuts))
     |> stream(:shortcuts, shortcuts, reset: true)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    shortcut = Catalog.get_pos_shortcut!(id)

    case Catalog.delete_pos_shortcut(shortcut) do
      {:ok, _deleted} ->
        {:noreply,
         socket
         |> update(:shortcut_count, &max(&1 - 1, 0))
         |> stream_delete(:shortcuts, shortcut)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not remove POS shortcut.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl px-4 py-8">
      <div class="mb-8 flex items-center justify-between gap-4">
        <div>
          <.link
            navigate={~p"/admin"}
            class="mb-2 inline-block text-tertiary-600 hover:text-tertiary-800"
          >
            ← Back to Dashboard
          </.link>
          <h1 class="text-3xl font-bold text-primary-500">{@page_title}</h1>
          <p class="mt-2 text-primary-400">
            Choose the products and serving sizes shown on the POS Popular tab. Lower positions appear first.
          </p>
        </div>
        <.link patch={~p"/admin/pos-shortcuts/new"} id="new-pos-shortcut">
          <.button><.icon name="hero-plus" class="mr-2 h-5 w-5" /> Add shortcut</.button>
        </.link>
      </div>

      <div class="overflow-hidden rounded-xl bg-white shadow-lg">
        <p :if={@shortcut_count == 0} class="px-5 py-8 text-center text-primary-400">
          No shortcuts yet. Add one to configure the Popular tab in the POS.
        </p>
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-secondary-50">
            <tr>
              <th class="px-5 py-3 text-left text-xs font-semibold uppercase text-primary-400">
                Position
              </th>
              <th class="px-5 py-3 text-left text-xs font-semibold uppercase text-primary-400">
                Product
              </th>
              <th class="px-5 py-3 text-left text-xs font-semibold uppercase text-primary-400">
                Shortcut size
              </th>
              <th class="px-5 py-3 text-right text-xs font-semibold uppercase text-primary-400">
                Actions
              </th>
            </tr>
          </thead>
          <tbody id="pos-shortcuts" phx-update="stream" class="divide-y divide-gray-100">
            <tr :for={{id, shortcut} <- @streams.shortcuts} id={id}>
              <td class="whitespace-nowrap px-5 py-4 text-sm text-primary-500">
                {shortcut.position}
              </td>
              <td class="px-5 py-4 text-sm font-semibold text-primary-500">
                {shortcut.product.name}
                <span
                  :if={
                    !shortcut.product.active || !shortcut.product.visible_in_pos ||
                      shortcut.product.deleted_at
                  }
                  class="ml-2 rounded-full bg-amber-100 px-2 py-1 text-xs font-medium text-amber-800"
                >
                  Hidden in POS
                </span>
              </td>
              <td class="whitespace-nowrap px-5 py-4 text-sm text-primary-400">
                <%= if shortcut.unit_amount do %>
                  {Decimal.to_string(Decimal.normalize(shortcut.unit_amount), :normal)} {shortcut.product.unit}
                <% else %>
                  Choose when adding
                <% end %>
              </td>
              <td class="whitespace-nowrap px-5 py-4 text-right text-sm">
                <.link
                  patch={~p"/admin/pos-shortcuts/#{shortcut}/edit"}
                  class="mr-4 font-medium text-tertiary-600 hover:text-tertiary-800"
                >
                  Edit
                </.link>
                <.link
                  phx-click={JS.push("delete", value: %{id: shortcut.id})}
                  data-confirm="Remove this POS shortcut?"
                  class="font-medium text-error hover:text-error-dark"
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
        id="pos-shortcut-modal"
        show
        on_cancel={JS.patch(~p"/admin/pos-shortcuts")}
      >
        <.live_component
          module={CozyCheckoutWeb.PosShortcutLive.FormComponent}
          id={@shortcut.id || :new}
          title={@page_title}
          action={@live_action}
          shortcut={@shortcut}
          products={@products}
          patch={~p"/admin/pos-shortcuts"}
        />
      </.modal>
    </div>
    """
  end
end

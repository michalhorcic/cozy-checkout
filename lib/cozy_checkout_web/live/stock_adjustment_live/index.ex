defmodule CozyCheckoutWeb.StockAdjustmentLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Inventory

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :stock_adjustments, Inventory.list_stock_adjustments())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Stock Adjustment")
    |> assign(:stock_adjustment, Inventory.get_stock_adjustment!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Stock Adjustment")
    |> assign(:stock_adjustment, %CozyCheckout.Inventory.StockAdjustment{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Stock Adjustments")
    |> assign(:stock_adjustment, nil)
  end

  @impl true
  def handle_info({CozyCheckoutWeb.StockAdjustmentLive.FormComponent, {:saved, stock_adjustment}}, socket) do
    {:noreply, stream_insert(socket, :stock_adjustments, stock_adjustment, at: 0)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    stock_adjustment = Inventory.get_stock_adjustment!(id)
    {:ok, _} = Inventory.delete_stock_adjustment(stock_adjustment)

    {:noreply, stream_delete(socket, :stock_adjustments, stock_adjustment)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="mb-8">
        <.link navigate={~p"/admin"} class="text-tertiary-600 hover:text-tertiary-800 mb-2 inline-block">
          ← Back to Dashboard
        </.link>
        <div class="flex justify-between items-center">
          <h1 class="text-4xl font-bold text-primary-500">{@page_title}</h1>
          <.link patch={~p"/admin/stock-adjustments/new"}>
            <button class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-lg text-white bg-gradient-to-r from-tertiary-500 to-secondary-600 hover:from-tertiary-600 hover:to-secondary-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-tertiary-500 transition-all shadow-lg">
              <.icon name="hero-plus" class="w-5 h-5 mr-2" />
              New Adjustment
            </button>
          </.link>
        </div>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gradient-to-r from-primary-500 to-secondary-600">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                Date
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                Product
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                Type
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                Quantity
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-white uppercase tracking-wider">
                Reason
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-white uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody id="stock_adjustments" phx-update="stream" class="bg-white divide-y divide-gray-200">
            <tr
              :for={{id, adjustment} <- @streams.stock_adjustments}
              id={id}
              class="hover:bg-gray-50 transition-colors"
            >
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                {Calendar.strftime(adjustment.inserted_at, "%b %d, %Y %H:%M")}
              </td>
              <td class="px-6 py-4">
                <div class="text-sm font-medium text-gray-900">{adjustment.product.name}</div>
                <div class="text-sm text-gray-500">{adjustment.product.category.name}</div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class={[
                  "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                  type_badge_class(adjustment.adjustment_type)
                ]}>
                  {adjustment.adjustment_type}
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class={[
                  "text-sm font-semibold",
                  quantity_color(adjustment.quantity)
                ]}>
                  {format_quantity(adjustment.quantity)} {adjustment.unit_amount && "× #{adjustment.unit_amount}"} {adjustment.product.unit || "pcs"}
                </span>
              </td>
              <td class="px-6 py-4">
                <div class="text-sm text-gray-900">{adjustment.reason}</div>
                <%= if adjustment.notes do %>
                  <div class="text-xs text-gray-500 mt-1">{adjustment.notes}</div>
                <% end %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <.link
                  patch={~p"/admin/stock-adjustments/#{adjustment}/edit"}
                  class="text-tertiary-600 hover:text-tertiary-900 mr-4"
                >
                  Edit
                </.link>
                <.link
                  phx-click={JS.push("delete", value: %{id: adjustment.id}) |> hide("##{id}")}
                  data-confirm="Are you sure?"
                  class="text-rose-600 hover:text-rose-900"
                >
                  Delete
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <.modal
      :if={@live_action in [:new, :edit]}
      id="stock-adjustment-modal"
      show
      on_cancel={JS.patch(~p"/admin/stock-adjustments")}
    >
      <.live_component
        module={CozyCheckoutWeb.StockAdjustmentLive.FormComponent}
        id={@stock_adjustment.id || :new}
        title={@page_title}
        action={@live_action}
        stock_adjustment={@stock_adjustment}
        patch={~p"/admin/stock-adjustments"}
      />
    </.modal>
    """
  end

  defp type_badge_class("increase"), do: "bg-emerald-100 text-emerald-800"
  defp type_badge_class("decrease"), do: "bg-rose-100 text-rose-800"
  defp type_badge_class("spillage"), do: "bg-amber-100 text-amber-800"
  defp type_badge_class("breakage"), do: "bg-orange-100 text-orange-800"
  defp type_badge_class("theft"), do: "bg-red-100 text-red-800"
  defp type_badge_class("spoilage"), do: "bg-purple-100 text-purple-800"
  defp type_badge_class("expired"), do: "bg-gray-100 text-gray-800"
  defp type_badge_class("correction"), do: "bg-blue-100 text-blue-800"
  defp type_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp quantity_color(quantity) when quantity > 0, do: "text-emerald-600"
  defp quantity_color(quantity) when quantity < 0, do: "text-rose-600"
  defp quantity_color(_), do: "text-gray-900"

  defp format_quantity(quantity) when quantity > 0, do: "+#{quantity}"
  defp format_quantity(quantity), do: to_string(quantity)
end

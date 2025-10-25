defmodule CozyCheckoutWeb.PricelistLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Catalog
  alias CozyCheckout.Catalog.Pricelist

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :pricelists, Catalog.list_pricelists())}
  end

  @impl true
  def handle_params(params, _url, socket) do
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
  def handle_info({CozyCheckoutWeb.PricelistLive.FormComponent, {:saved, pricelist}}, socket) do
    {:noreply, stream_insert(socket, :pricelists, Catalog.get_pricelist!(pricelist.id))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    pricelist = Catalog.get_pricelist!(id)
    {:ok, _} = Catalog.delete_pricelist(pricelist)

    {:noreply, stream_delete(socket, :pricelists, pricelist)}
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
          price_decimal = if is_struct(price, Decimal), do: price, else: Decimal.new(to_string(price))
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
          <.link navigate={~p"/admin"} class="text-blue-600 hover:text-blue-800 mb-2 inline-block">
            ← Back to Dashboard
          </.link>
          <h1 class="text-4xl font-bold text-gray-900">{@page_title}</h1>
        </div>
        <div class="flex gap-3">
          <.link
            navigate={~p"/admin/pricelists/management"}
            class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-gradient-to-r from-emerald-500 to-teal-600 hover:from-emerald-600 hover:to-teal-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-emerald-500 transition-all duration-200"
          >
            <.icon name="hero-clipboard-document-check" class="w-5 h-5 mr-2" />
            Price Management
          </.link>
          <.link patch={~p"/admin/pricelists/new"}>
            <.button>
              <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Pricelist
            </.button>
          </.link>
        </div>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Product
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Price
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                VAT Rate
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Valid From
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Valid To
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Status
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody id="pricelists" phx-update="stream" class="bg-white divide-y divide-gray-200">
            <tr :for={{id, pricelist} <- @streams.pricelists} id={id} class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                {pricelist.product && pricelist.product.name}
              </td>
              <td class="px-6 py-4 text-sm text-gray-900">
                {format_price_display(pricelist)}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {pricelist.vat_rate}%
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {pricelist.valid_from}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {pricelist.valid_to || "—"}
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class={[
                  "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                  if(pricelist.active,
                    do: "bg-green-100 text-green-800",
                    else: "bg-gray-100 text-gray-800"
                  )
                ]}>
                  {if pricelist.active, do: "Active", else: "Inactive"}
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <.link
                  patch={~p"/admin/pricelists/#{pricelist}/edit"}
                  class="text-indigo-600 hover:text-indigo-900 mr-4"
                >
                  Edit
                </.link>
                <.link
                  phx-click={JS.push("delete", value: %{id: pricelist.id})}
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
        id="pricelist-modal"
        show
        on_cancel={JS.patch(~p"/admin/pricelists")}
      >
        <.live_component
          module={CozyCheckoutWeb.PricelistLive.FormComponent}
          id={@pricelist.id || :new}
          title={@page_title}
          action={@live_action}
          pricelist={@pricelist}
          patch={~p"/admin/pricelists"}
        />
      </.modal>
    </div>
    """
  end
end

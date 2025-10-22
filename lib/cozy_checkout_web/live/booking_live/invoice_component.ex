defmodule CozyCheckoutWeb.BookingLive.InvoiceComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Bookings
  alias CozyCheckout.Bookings.{BookingInvoice, BookingInvoiceItem}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow-lg rounded-lg p-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-2xl font-bold text-gray-900">Invoice Details</h2>
        <div class="flex space-x-2">
          <%= if @invoice && @invoice.invoice_number do %>
            <span class="px-3 py-1 bg-green-100 text-green-800 rounded-full text-sm font-medium">
              {@invoice.invoice_number}
            </span>
          <% end %>
          <%= if @invoice do %>
            <button
              type="button"
              phx-click="recalculate"
              phx-target={@myself}
              class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white text-sm font-medium rounded-lg transition-colors"
            >
              <.icon name="hero-calculator" class="w-4 h-4 inline mr-1" /> Recalculate
            </button>
            <%= if !@invoice.invoice_number do %>
              <button
                type="button"
                phx-click="generate_invoice"
                phx-target={@myself}
                class="px-4 py-2 bg-green-600 hover:bg-green-700 text-white text-sm font-medium rounded-lg transition-colors"
              >
                <.icon name="hero-document-text" class="w-4 h-4 inline mr-1" /> Generate Invoice
              </button>
            <% end %>
          <% end %>
        </div>
      </div>

      <%= if @invoice do %>
        <%!-- Invoice Items Table --%>
        <div class="mb-6">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-lg font-semibold text-gray-900">Line Items</h3>
            <%= if !@editing_item_id do %>
              <button
                type="button"
                phx-click="add_item"
                phx-target={@myself}
                class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-medium rounded-lg transition-colors"
              >
                <.icon name="hero-plus" class="w-4 h-4 inline mr-1" /> Add Item
              </button>
            <% end %>
          </div>

          <div class="overflow-hidden border border-gray-200 rounded-lg">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Name
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Type
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase whitespace-nowrap">
                    Qty
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase whitespace-nowrap">
                    Price/Night
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase whitespace-nowrap">
                    VAT %
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase whitespace-nowrap">
                    Subtotal
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase whitespace-nowrap">
                    Total
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase whitespace-nowrap">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= if @invoice.items == [] && @editing_item_id != :new do %>
                  <tr>
                    <td colspan="8" class="px-4 py-8 text-center text-gray-500">
                      No items yet. Click "Add Item" to create one.
                    </td>
                  </tr>
                <% end %>

                <%= for item <- @invoice.items do %>
                  <%= if @editing_item_id == item.id do %>
                    <%!-- Edit Mode --%>
                    <tr class="bg-blue-50">
                      <td colspan="8" class="px-4 py-3">
                        <.form
                          for={@item_form}
                          id={"item-form-#{item.id}"}
                          phx-target={@myself}
                          phx-submit="save_item"
                        >
                          <div class="grid grid-cols-7 gap-3">
                            <div class="col-span-2">
                              <.input field={@item_form[:name]} type="text" placeholder="Item name" />
                            </div>
                            <div>
                              <.input
                                field={@item_form[:item_type]}
                                type="select"
                                options={[{"Person", "person"}, {"Extra", "extra"}]}
                              />
                            </div>
                            <div>
                              <.input
                                field={@item_form[:quantity]}
                                type="number"
                                min="0"
                                placeholder="Qty"
                              />
                            </div>
                            <div>
                              <.input
                                field={@item_form[:price_per_night]}
                                type="number"
                                step="0.01"
                                min="0"
                                placeholder="Price"
                              />
                            </div>
                            <div>
                              <.input
                                field={@item_form[:vat_rate]}
                                type="number"
                                step="0.01"
                                min="0"
                                max="100"
                                placeholder="VAT %"
                              />
                            </div>
                            <div class="flex space-x-2">
                              <button
                                type="submit"
                                class="px-3 py-2 bg-green-600 hover:bg-green-700 text-white text-sm rounded transition-colors"
                              >
                                Save
                              </button>
                              <button
                                type="button"
                                phx-click="cancel_edit"
                                phx-target={@myself}
                                class="px-3 py-2 bg-gray-300 hover:bg-gray-400 text-gray-800 text-sm rounded transition-colors"
                              >
                                Cancel
                              </button>
                            </div>
                          </div>
                        </.form>
                      </td>
                    </tr>
                  <% else %>
                    <%!-- Display Mode --%>
                    <tr class="hover:bg-gray-50">
                      <td class="px-4 py-3 text-sm text-gray-900">{item.name}</td>
                      <td class="px-4 py-3 text-sm text-gray-700">
                        <span class={[
                          "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium",
                          item.item_type == "person" && "bg-blue-100 text-blue-800",
                          item.item_type == "extra" && "bg-purple-100 text-purple-800"
                        ]}>
                          {if item.item_type == "person", do: "Person", else: "Extra"}
                        </span>
                      </td>
                      <td class="px-4 py-3 text-sm text-gray-900 text-right whitespace-nowrap">
                        {CozyCheckoutWeb.CurrencyHelper.format_number(item.quantity)}
                      </td>
                      <td class="px-4 py-3 text-sm text-gray-900 text-right whitespace-nowrap">
                        {CozyCheckoutWeb.CurrencyHelper.format_currency(item.price_per_night)}
                      </td>
                      <td class="px-4 py-3 text-sm text-gray-900 text-right whitespace-nowrap">
                        {CozyCheckoutWeb.CurrencyHelper.format_number(item.vat_rate)}%
                      </td>
                      <td class="px-4 py-3 text-sm text-gray-900 text-right whitespace-nowrap">
                        <%= if item.subtotal do %>
                          {CozyCheckoutWeb.CurrencyHelper.format_currency(item.subtotal)}
                        <% else %>
                          <span class="text-gray-400">—</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-sm font-medium text-gray-900 text-right whitespace-nowrap">
                        <%= if item.total do %>
                          {CozyCheckoutWeb.CurrencyHelper.format_currency(item.total)}
                        <% else %>
                          <span class="text-gray-400">—</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-right text-sm whitespace-nowrap">
                        <button
                          type="button"
                          phx-click="edit_item"
                          phx-value-item-id={item.id}
                          phx-target={@myself}
                          class="text-indigo-600 hover:text-indigo-900 mr-3"
                        >
                          Edit
                        </button>
                        <button
                          type="button"
                          phx-click="delete_item"
                          phx-value-item-id={item.id}
                          phx-target={@myself}
                          class="text-red-600 hover:text-red-900"
                          data-confirm="Are you sure you want to delete this item?"
                        >
                          Delete
                        </button>
                      </td>
                    </tr>
                  <% end %>
                <% end %>

                <%!-- New Item Form --%>
                <%= if @editing_item_id == :new do %>
                  <tr class="bg-green-50">
                    <td colspan="8" class="px-4 py-3">
                      <.form
                        for={@item_form}
                        id="new-item-form"
                        phx-target={@myself}
                        phx-submit="save_item"
                      >
                        <div class="grid grid-cols-7 gap-3">
                          <div class="col-span-2">
                            <.input
                              field={@item_form[:name]}
                              type="text"
                              placeholder="Item name"
                              required
                            />
                          </div>
                          <div>
                            <.input
                              field={@item_form[:item_type]}
                              type="select"
                              options={[{"Person", "person"}, {"Extra", "extra"}]}
                              required
                            />
                          </div>
                          <div>
                            <.input
                              field={@item_form[:quantity]}
                              type="number"
                              min="0"
                              placeholder="Qty"
                              required
                            />
                          </div>
                          <div>
                            <.input
                              field={@item_form[:price_per_night]}
                              type="number"
                              step="0.01"
                              min="0"
                              placeholder="Price"
                              required
                            />
                          </div>
                          <div>
                            <.input
                              field={@item_form[:vat_rate]}
                              type="number"
                              step="0.01"
                              min="0"
                              max="100"
                              placeholder="VAT %"
                              required
                            />
                          </div>
                          <div class="flex space-x-2">
                            <button
                              type="submit"
                              class="px-3 py-2 bg-green-600 hover:bg-green-700 text-white text-sm rounded transition-colors"
                            >
                              Add
                            </button>
                            <button
                              type="button"
                              phx-click="cancel_edit"
                              phx-target={@myself}
                              class="px-3 py-2 bg-gray-300 hover:bg-gray-400 text-gray-800 text-sm rounded transition-colors"
                            >
                              Cancel
                            </button>
                          </div>
                        </div>
                      </.form>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Invoice Summary --%>
        <div class="bg-gray-50 p-4 rounded-lg">
          <div class="max-w-md ml-auto space-y-2">
            <div class="flex justify-between text-sm">
              <span class="text-gray-600">Number of Nights</span>
              <span class="font-medium text-gray-900">
                {CozyCheckoutWeb.CurrencyHelper.format_number(calculate_nights(@booking))}
              </span>
            </div>
            <hr class="border-gray-300" />
            <%= if @invoice.subtotal do %>
              <div class="flex justify-between text-sm">
                <span class="text-gray-600">Subtotal (excl. VAT)</span>
                <span class="font-medium text-gray-900">
                  {CozyCheckoutWeb.CurrencyHelper.format_currency(@invoice.subtotal)}
                </span>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-gray-600">Total VAT</span>
                <span class="font-medium text-gray-900">
                  {CozyCheckoutWeb.CurrencyHelper.format_currency(@invoice.vat_amount)}
                </span>
              </div>
              <hr class="border-gray-300" />
              <div class="flex justify-between">
                <span class="text-lg font-bold text-gray-900">Total Price</span>
                <span class="text-2xl font-bold text-green-600">
                  {CozyCheckoutWeb.CurrencyHelper.format_currency(@invoice.total_price)}
                </span>
              </div>
            <% else %>
              <p class="text-sm text-gray-500 italic">Click "Recalculate" to compute totals</p>
            <% end %>
          </div>

          <%= if @invoice.invoice_generated_at do %>
            <div class="mt-4 pt-4 border-t border-gray-300">
              <p class="text-sm text-gray-600">
                Invoice generated on
                <span class="font-medium text-gray-900">
                  {Calendar.strftime(@invoice.invoice_generated_at, "%B %d, %Y at %I:%M %p")}
                </span>
              </p>
            </div>
          <% end %>
        </div>
      <% else %>
        <%!-- No Invoice Yet --%>
        <div class="text-center py-8">
          <.icon name="hero-document-text" class="w-16 h-16 mx-auto text-gray-400 mb-4" />
          <p class="text-gray-500 mb-4">No invoice details yet for this booking.</p>
          <button
            type="button"
            phx-click="create_invoice"
            phx-target={@myself}
            class="px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors"
          >
            <.icon name="hero-plus" class="w-5 h-5 inline mr-1" /> Create Invoice
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    booking = assigns.booking
    invoice = Bookings.get_invoice_by_booking_id(booking.id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:invoice, invoice)
     |> assign(:editing_item_id, nil)
     |> assign(:item_form, nil)}
  end

  @impl true
  def handle_event("create_invoice", _params, socket) do
    case Bookings.create_default_invoice(socket.assigns.booking) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> put_flash(:info, "Invoice created with default items")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create invoice")}
    end
  end

  @impl true
  def handle_event("add_item", _params, socket) do
    next_position = length(socket.assigns.invoice.items) + 1

    form =
      Bookings.change_invoice_item(%BookingInvoiceItem{}, %{
        position: next_position,
        quantity: 1,
        price_per_night: Decimal.new("0.00"),
        vat_rate: Decimal.new("21.00"),
        item_type: "person"
      })
      |> to_form()

    {:noreply,
     socket
     |> assign(:editing_item_id, :new)
     |> assign(:item_form, form)}
  end

  @impl true
  def handle_event("edit_item", %{"item-id" => item_id}, socket) do
    item = Bookings.get_invoice_item!(item_id)
    form = Bookings.change_invoice_item(item) |> to_form()

    {:noreply,
     socket
     |> assign(:editing_item_id, item.id)
     |> assign(:item_form, form)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_item_id, nil)
     |> assign(:item_form, nil)}
  end

  @impl true
  def handle_event("save_item", %{"booking_invoice_item" => item_params}, socket) do
    result =
      if socket.assigns.editing_item_id == :new do
        Bookings.create_invoice_item(socket.assigns.invoice.id, item_params)
      else
        item = Bookings.get_invoice_item!(socket.assigns.editing_item_id)
        Bookings.update_invoice_item(item, item_params)
      end

    case result do
      {:ok, _item} ->
        invoice = Bookings.get_invoice_by_booking_id(socket.assigns.booking.id)

        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> assign(:editing_item_id, nil)
         |> assign(:item_form, nil)
         |> put_flash(:info, "Item saved successfully")}

      {:error, changeset} ->
        {:noreply, assign(socket, :item_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete_item", %{"item-id" => item_id}, socket) do
    item = Bookings.get_invoice_item!(item_id)

    case Bookings.delete_invoice_item(item) do
      {:ok, _} ->
        invoice = Bookings.get_invoice_by_booking_id(socket.assigns.booking.id)

        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> put_flash(:info, "Item deleted successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete item")}
    end
  end

  @impl true
  def handle_event("recalculate", _params, socket) do
    case Bookings.recalculate_invoice_totals(socket.assigns.invoice) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> put_flash(:info, "Invoice totals recalculated")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to recalculate totals")}
    end
  end

  @impl true
  def handle_event("generate_invoice", _params, socket) do
    case Bookings.generate_invoice_number(socket.assigns.invoice) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> put_flash(:info, "Invoice #{invoice.invoice_number} generated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to generate invoice number")}
    end
  end

  defp calculate_nights(booking) do
    BookingInvoice.calculate_nights(booking)
  end
end

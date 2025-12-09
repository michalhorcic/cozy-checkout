defmodule CozyCheckoutWeb.BookingLive.InvoiceComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Bookings
  alias CozyCheckout.Bookings.{BookingInvoice, BookingInvoiceItem}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow-lg rounded-lg p-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-2xl font-bold text-primary-500">Invoice Details</h2>
        <div class="flex space-x-2">
          <%= if @invoice && @invoice.invoice_number do %>
            <span class="px-3 py-1 bg-success-light text-success-dark rounded-full text-sm font-medium">
              {@invoice.invoice_number}
            </span>
          <% end %>
          <%= if @invoice do %>
            <span class={[
              "px-3 py-1 rounded-full text-sm font-semibold",
              state_badge_class(@invoice.state)
            ]}>
              {state_label(@invoice.state)}
            </span>
            <button
              type="button"
              phx-click="recalculate"
              phx-target={@myself}
              class="px-4 py-2 bg-tertiary-600 hover:bg-tertiary-700 text-white text-sm font-medium rounded-lg transition-colors"
            >
              <.icon name="hero-calculator" class="w-4 h-4 inline mr-1" /> Recalculate
            </button>
          <% end %>
        </div>
      </div>

      <%= if @invoice do %>
        <%!-- State Transition Buttons --%>
        <div class="mb-6 flex items-center justify-end space-x-2">
          <%= if @invoice.state == "draft" do %>
            <button
              type="button"
              phx-click="transition_to_personal"
              phx-target={@myself}
              class="px-4 py-2 bg-warning hover:bg-warning-dark text-white text-sm font-medium rounded-lg transition-colors"
            >
              <.icon name="hero-user" class="w-4 h-4 inline mr-1" /> Mark as Personal
            </button>
            <button
              type="button"
              phx-click="transition_to_generated"
              phx-target={@myself}
              class="px-4 py-2 bg-success hover:bg-success-dark text-white text-sm font-medium rounded-lg transition-colors"
            >
              <.icon name="hero-check-circle" class="w-4 h-4 inline mr-1" /> Generate Invoice
            </button>
          <% end %>
          <%= if @invoice.state == "personal" do %>
            <button
              type="button"
              phx-click="transition_to_draft"
              phx-target={@myself}
              class="px-4 py-2 bg-gray-600 hover:bg-gray-700 text-white text-sm font-medium rounded-lg transition-colors"
            >
              <.icon name="hero-arrow-uturn-left" class="w-4 h-4 inline mr-1" /> Back to Draft
            </button>
            <button
              type="button"
              phx-click="transition_to_generated"
              phx-target={@myself}
              class="px-4 py-2 bg-success hover:bg-success-dark text-white text-sm font-medium rounded-lg transition-colors"
            >
              <.icon name="hero-check-circle" class="w-4 h-4 inline mr-1" /> Generate Invoice
            </button>
          <% end %>
          <%= if @invoice.state in ["generated", "sent", "advance_paid"] do %>
            <%= if @invoice.state == "generated" do %>
              <button
                type="button"
                phx-click="transition_to_sent"
                phx-target={@myself}
                class="px-4 py-2 bg-tertiary-500 hover:bg-tertiary-600 text-white text-sm font-medium rounded-lg transition-colors"
              >
                <.icon name="hero-paper-airplane" class="w-4 h-4 inline mr-1" /> Mark as Sent
              </button>
            <% end %>
            <%= if @invoice.state in ["sent", "generated"] do %>
              <button
                type="button"
                phx-click="transition_to_advance_paid"
                phx-target={@myself}
                class="px-4 py-2 bg-yellow-600 hover:bg-yellow-700 text-white text-sm font-medium rounded-lg transition-colors"
              >
                <.icon name="hero-currency-dollar" class="w-4 h-4 inline mr-1" />
                Mark as Advance Paid (50%)
              </button>
            <% end %>
            <button
              type="button"
              phx-click="transition_to_paid"
              phx-target={@myself}
              class="px-4 py-2 bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-medium rounded-lg transition-colors"
            >
              <.icon name="hero-banknotes" class="w-4 h-4 inline mr-1" /> Mark as Paid
            </button>
          <% end %>
        </div>
        <%!-- Invoice Items Table --%>
        <div class="mb-6">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-lg font-semibold text-primary-500">Line Items</h3>
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

          <div class="overflow-hidden border border-secondary-200 rounded-lg">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-secondary-50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-primary-400 uppercase">
                    Name
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-primary-400 uppercase">
                    Type
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-primary-400 uppercase whitespace-nowrap">
                    Qty
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-primary-400 uppercase whitespace-nowrap">
                    Nights
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-primary-400 uppercase whitespace-nowrap">
                    Price/Night
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-primary-400 uppercase whitespace-nowrap">
                    VAT %
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-primary-400 uppercase whitespace-nowrap">
                    Subtotal
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-primary-400 uppercase whitespace-nowrap">
                    Total
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-primary-400 uppercase whitespace-nowrap">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= if @invoice.items == [] && @editing_item_id != :new do %>
                  <tr>
                    <td colspan="9" class="px-4 py-8 text-center text-primary-400">
                      No items yet. Click "Add Item" to create one.
                    </td>
                  </tr>
                <% end %>

                <%= for item <- @invoice.items do %>
                  <%= if @editing_item_id == item.id do %>
                    <%!-- Edit Mode --%>
                    <tr class="bg-tertiary-50">
                      <td colspan="9" class="px-4 py-3">
                        <.form
                          for={@item_form}
                          id={"item-form-#{item.id}"}
                          phx-target={@myself}
                          phx-submit="save_item"
                        >
                          <div class="grid grid-cols-8 gap-3">
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
                                field={@item_form[:nights]}
                                type="number"
                                min="1"
                                placeholder="Nights"
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
                                class="px-3 py-2 bg-success hover:bg-success-dark text-white text-sm rounded transition-colors"
                              >
                                Save
                              </button>
                              <button
                                type="button"
                                phx-click="cancel_edit"
                                phx-target={@myself}
                                class="px-3 py-2 bg-secondary-300 hover:bg-secondary-400 text-primary-500 text-sm rounded transition-colors"
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
                    <tr class="hover:bg-secondary-50">
                      <td class="px-4 py-3 text-sm text-primary-500">{item.name}</td>
                      <td class="px-4 py-3 text-sm text-primary-500">
                        <span class={[
                          "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium",
                          item.item_type == "person" && "bg-tertiary-100 text-tertiary-800",
                          item.item_type == "extra" && "bg-info-light text-info-dark"
                        ]}>
                          {if item.item_type == "person", do: "Person", else: "Extra"}
                        </span>
                      </td>
                      <td class="px-4 py-3 text-sm text-primary-500 text-right whitespace-nowrap">
                        {CozyCheckoutWeb.CurrencyHelper.format_number(item.quantity)}
                      </td>
                      <td class="px-4 py-3 text-sm text-primary-500 text-right whitespace-nowrap">
                        {CozyCheckoutWeb.CurrencyHelper.format_number(item.nights || 1)}
                      </td>
                      <td class="px-4 py-3 text-sm text-primary-500 text-right whitespace-nowrap">
                        {CozyCheckoutWeb.CurrencyHelper.format_currency(item.price_per_night)}
                      </td>
                      <td class="px-4 py-3 text-sm text-primary-500 text-right whitespace-nowrap">
                        {CozyCheckoutWeb.CurrencyHelper.format_number(item.vat_rate)}%
                      </td>
                      <td class="px-4 py-3 text-sm text-primary-500 text-right whitespace-nowrap">
                        <%= if item.subtotal do %>
                          {CozyCheckoutWeb.CurrencyHelper.format_currency(item.subtotal)}
                        <% else %>
                          <span class="text-primary-300">—</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-sm font-medium text-primary-500 text-right whitespace-nowrap">
                        <%= if item.total do %>
                          {CozyCheckoutWeb.CurrencyHelper.format_currency(item.total)}
                        <% else %>
                          <span class="text-primary-300">—</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-3 text-right text-sm whitespace-nowrap">
                        <button
                          type="button"
                          phx-click="edit_item"
                          phx-value-item-id={item.id}
                          phx-target={@myself}
                          class="text-tertiary-600 hover:text-white-900 mr-3"
                        >
                          Edit
                        </button>
                        <button
                          type="button"
                          phx-click="delete_item"
                          phx-value-item-id={item.id}
                          phx-target={@myself}
                          class="text-error hover:text-error-dark"
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
                  <tr class="bg-success-light">
                    <td colspan="9" class="px-4 py-3">
                      <.form
                        for={@item_form}
                        id="new-item-form"
                        phx-target={@myself}
                        phx-submit="save_item"
                      >
                        <div class="grid grid-cols-8 gap-3">
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
                              field={@item_form[:nights]}
                              type="number"
                              min="1"
                              placeholder="Nights"
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
                              class="px-3 py-2 bg-success hover:bg-success-dark text-white text-sm rounded transition-colors"
                            >
                              Add
                            </button>
                            <button
                              type="button"
                              phx-click="cancel_edit"
                              phx-target={@myself}
                              class="px-3 py-2 bg-secondary-300 hover:bg-secondary-400 text-primary-500 text-sm rounded transition-colors"
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
        <div class="bg-secondary-50 p-4 rounded-lg">
          <div class="max-w-md ml-auto space-y-2">
            <div class="flex justify-between text-sm">
              <span class="text-primary-400">Number of Nights</span>
              <span class="font-medium text-primary-500">
                {CozyCheckoutWeb.CurrencyHelper.format_number(calculate_nights(@booking))}
              </span>
            </div>
            <hr class="border-secondary-300" />
            <%= if @invoice.subtotal do %>
              <div class="flex justify-between text-sm">
                <span class="text-primary-400">Subtotal (excl. VAT)</span>
                <span class="font-medium text-primary-500">
                  {CozyCheckoutWeb.CurrencyHelper.format_currency(@invoice.subtotal)}
                </span>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-primary-400">Total VAT</span>
                <span class="font-medium text-primary-500">
                  {CozyCheckoutWeb.CurrencyHelper.format_currency(@invoice.vat_amount)}
                </span>
              </div>
              <hr class="border-secondary-300" />
              <div class="flex justify-between">
                <span class="text-lg font-bold text-primary-500">Total Price</span>
                <span class="text-2xl font-bold text-success-dark">
                  {CozyCheckoutWeb.CurrencyHelper.format_currency(@invoice.total_price)}
                </span>
              </div>
              <div class="flex justify-between text-sm mt-2">
                <span class="text-primary-400 font-medium">Advance Payment (50%)</span>
                <span class="font-semibold text-yellow-600">
                  {CozyCheckoutWeb.CurrencyHelper.format_currency(Decimal.div(@invoice.total_price, 2))}
                </span>
              </div>
            <% else %>
              <p class="text-sm text-primary-400 italic">Click "Recalculate" to compute totals</p>
            <% end %>
          </div>

          <%= if @invoice.invoice_generated_at do %>
            <div class="mt-4 pt-4 border-t border-secondary-300">
              <p class="text-sm text-primary-400">
                Invoice generated on
                <span class="font-medium text-primary-500">
                  {Calendar.strftime(@invoice.invoice_generated_at, "%B %d, %Y at %I:%M %p")}
                </span>
              </p>
            </div>
          <% end %>
        </div>
      <% else %>
        <%!-- No Invoice Yet --%>
        <div class="text-center py-8">
          <.icon name="hero-document-text" class="w-16 h-16 mx-auto text-primary-300 mb-4" />
          <p class="text-primary-400 mb-4">No invoice details yet for this booking.</p>
          <button
            type="button"
            phx-click="create_invoice"
            phx-target={@myself}
            class="px-6 py-3 bg-tertiary-600 hover:bg-tertiary-700 text-white font-medium rounded-lg transition-colors"
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

    # Calculate default nights from booking
    nights = BookingInvoice.calculate_nights(socket.assigns.booking)

    form =
      Bookings.change_invoice_item(%BookingInvoiceItem{}, %{
        position: next_position,
        quantity: 1,
        nights: nights,
        price_per_night: Decimal.new("0.00"),
        vat_rate: Decimal.new("0.00"),
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

  @impl true
  def handle_event("transition_to_generated", _params, socket) do
    case Bookings.transition_to_generated(socket.assigns.invoice) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> put_flash(:info, "Invoice #{invoice.invoice_number} generated successfully")}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to generate invoice")}
    end
  end

  @impl true
  def handle_event("transition_to_sent", _params, socket) do
    case Bookings.transition_to_sent(socket.assigns.invoice) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> put_flash(:info, "Invoice marked as sent")}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to mark invoice as sent")}
    end
  end

  @impl true
  def handle_event("transition_to_advance_paid", _params, socket) do
    case Bookings.transition_to_advance_paid(socket.assigns.invoice) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> put_flash(:info, "Invoice marked as advance paid (50%)")}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to mark invoice as advance paid")}
    end
  end

  @impl true
  def handle_event("transition_to_paid", _params, socket) do
    case Bookings.transition_to_paid(socket.assigns.invoice) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> put_flash(:info, "Invoice marked as paid")}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to mark invoice as paid")}
    end
  end

  @impl true
  def handle_event("transition_to_personal", _params, socket) do
    case Bookings.transition_to_personal(socket.assigns.invoice) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> put_flash(:info, "Invoice marked as personal")}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to mark invoice as personal")}
    end
  end

  @impl true
  def handle_event("transition_to_draft", _params, socket) do
    case Bookings.update_booking_invoice(socket.assigns.invoice, %{state: "draft"}) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> put_flash(:info, "Invoice returned to draft")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to return invoice to draft")}
    end
  end

  defp calculate_nights(booking) do
    BookingInvoice.calculate_nights(booking)
  end

  defp state_badge_class("draft"), do: "bg-secondary-100 text-primary-500"
  defp state_badge_class("personal"), do: "bg-warning-light text-warning-dark"
  defp state_badge_class("generated"), do: "bg-tertiary-100 text-tertiary-800"
  defp state_badge_class("sent"), do: "bg-info-light text-info-dark"
  defp state_badge_class("advance_paid"), do: "bg-warning-light text-warning-dark"
  defp state_badge_class("paid"), do: "bg-success-light text-success-dark"
  defp state_badge_class(_), do: "bg-secondary-100 text-primary-500"

  defp state_label("draft"), do: "Draft"
  defp state_label("personal"), do: "Personal"
  defp state_label("generated"), do: "Generated"
  defp state_label("sent"), do: "Sent"
  defp state_label("advance_paid"), do: "Advance Paid (50%)"
  defp state_label("paid"), do: "Paid"
  defp state_label(state), do: String.capitalize(state)
end

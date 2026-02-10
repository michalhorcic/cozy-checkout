defmodule CozyCheckoutWeb.BookingLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Bookings
  alias CozyCheckout.Bookings.Booking

  import CozyCheckoutWeb.FlopComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  # Apply default filter to show only current and future bookings
  defp apply_default_filters(params) do
    # Only apply default if no "show_all" param and no existing filter on check_out_date
    if Map.get(params, "show_all") == "true" || has_custom_filters?(params) do
      params
    else
      # Add default filter: show_current_and_future = true
      Map.put(params, "show_current_and_future", "true")
    end
  end

  # Check if user has applied custom filters
  defp has_custom_filters?(params) do
    # If there are any filters in params, don't apply default
    Map.has_key?(params, "filters") ||
    Map.has_key?(params, "invoice_state") ||
    Map.has_key?(params, "guest_search")
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Apply default filter to show only current and future bookings if no filters are set
    params_with_defaults = apply_default_filters(params)

    # Normalize params: convert indexed maps to arrays for Flop
    normalized_params = normalize_flop_params(params_with_defaults)

    socket =
      case Bookings.list_bookings_with_flop(normalized_params) do
        {:ok, {bookings, meta}} ->
          # Add rooms and invoice to each booking
          bookings_with_rooms =
            Enum.map(bookings, fn booking ->
              rooms = Bookings.list_booking_rooms(booking.id)
              invoice = Bookings.get_invoice_by_booking_id(booking.id)

              booking
              |> Map.put(:rooms_list, rooms)
              |> Map.put(:invoice, invoice)
            end)

          socket
          |> assign(:bookings, bookings_with_rooms)
          |> assign(:meta, meta)
          |> assign(:current_params, params)

        {:error, meta} ->
          socket
          |> assign(:bookings, [])
          |> assign(:meta, meta)
          |> assign(:current_params, params)
      end

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Booking")
    |> assign(:booking, Bookings.get_booking!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Booking")
    |> assign(:booking, %Booking{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Bookings")
    |> assign(:booking, nil)
  end

  @impl true
  def handle_info({CozyCheckoutWeb.BookingLive.FormComponent, {:saved, _booking}}, socket) do
    # Re-fetch bookings to show updated data, preserving current filters
    {:noreply, push_patch(socket, to: build_path_with_params(~p"/admin/bookings", socket.assigns.current_params))}
  end

  @impl true
  def handle_info({:guest_created, guest}, socket) do
    # Forward the message to the FormComponent
    send_update(CozyCheckoutWeb.BookingLive.FormComponent,
      id: socket.assigns.booking.id || :new,
      guest_created: guest
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    booking = Bookings.get_booking!(id)
    {:ok, _} = Bookings.delete_booking(booking)

    # Re-fetch bookings after delete, preserving current filters
    {:noreply, push_patch(socket, to: build_path_with_params(~p"/admin/bookings", socket.assigns.current_params))}
  end

  @impl true
  def handle_event("update_booking_status", %{"id" => id, "status" => status}, socket) do
    booking = Bookings.get_booking!(id)

    case Bookings.update_booking(booking, %{status: status}) do
      {:ok, _booking} ->
        {:noreply,
         socket
         |> put_flash(:info, "Booking status updated successfully")
         |> push_patch(to: build_path_with_params(~p"/admin/bookings", socket.assigns.current_params))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update booking status")}
    end
  end

  @impl true
  def handle_event("update_invoice_status", %{"id" => id, "state" => state}, socket) do
    invoice = Bookings.get_booking_invoice!(id)

    case Bookings.update_invoice_state(invoice, state) do
      {:ok, _invoice} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invoice status updated successfully")
         |> push_patch(to: build_path_with_params(~p"/admin/bookings", socket.assigns.current_params))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update invoice status")}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    # Preserve show_all parameter when filtering
    filter_params = build_filter_params(params, socket.assigns.current_params)
    {:noreply, push_patch(socket, to: ~p"/admin/bookings?#{filter_params}")}
  end

  # Helper to build filter params from form
  defp build_filter_params(params, current_params) do
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
    result = %{
      "filters" => filters,
      "page" => params["page"],
      "page_size" => params["page_size"],
      "invoice_state" => params["invoice_state"],
      "guest_search" => params["guest_search"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) || v == %{} || v == "" end)
    |> Map.new()

    # Preserve show_all from current params if it exists
    if Map.get(current_params, "show_all") == "true" do
      Map.put(result, "show_all", "true")
    else
      result
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
        <div class="flex gap-2">
          <.link navigate={~p"/admin/bookings/calendar"}>
            <.button>
              <.icon name="hero-calendar" class="w-5 h-5 mr-2" /> Calendar
            </.button>
          </.link>
          <.link navigate={~p"/admin/bookings/timeline"}>
            <.button>
              <.icon name="hero-bars-3" class="w-5 h-5 mr-2" /> Timeline
            </.button>
          </.link>
          <.link patch={build_path_with_params(~p"/admin/bookings/new", @current_params)}>
            <.button>
              <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Booking
            </.button>
          </.link>
        </div>
      </div>

      <div class="bg-white shadow-lg rounded-lg overflow-hidden">
        <!-- Filter Form -->
        <.filter_form meta={@meta} path={~p"/admin/bookings"} id="bookings-filter">
          <:filter>
            <.input
              type="select"
              name="invoice_state"
              label="Invoice State"
              options={[
                {"All", ""},
                {"No Invoice", "no_invoice"},
                {"Draft", "draft"},
                {"Personal", "personal"},
                {"Generated", "generated"},
                {"Sent", "sent"},
                {"Advance Paid (50%)", "advance_paid"},
                {"Paid", "paid"}
              ]}
              value={Map.get(@meta.params, "invoice_state", "")}
            />
          </:filter>
          <:filter>
            <.input
              type="text"
              name="guest_search"
              label="Guest Name/Email"
              placeholder="Search by name or email"
              value={Map.get(@meta.params, "guest_search", "")}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[0][field]" value="status" />
            <input type="hidden" name="filters[0][op]" value="==" />
            <.input
              type="select"
              name="filters[0][value]"
              label="Status"
              options={[
                {"All", ""},
                {"Upcoming", "upcoming"},
                {"Active", "active"},
                {"Completed", "completed"},
                {"Cancelled", "cancelled"}
              ]}
              value={get_filter_value(@meta, :status)}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[1][field]" value="check_in_date" />
            <input type="hidden" name="filters[1][op]" value=">=" />
            <.input
              type="date"
              name="filters[1][value]"
              label="Check-in From"
              value={get_filter_value(@meta, :check_in_date)}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[2][field]" value="check_in_date" />
            <input type="hidden" name="filters[2][op]" value="<=" />
            <.input
              type="date"
              name="filters[2][value]"
              label="Check-in To"
              value={get_filter_value(@meta, :check_in_date)}
            />
          </:filter>
          <:filter>
            <input type="hidden" name="filters[3][field]" value="short_note" />
            <input type="hidden" name="filters[3][op]" value="==" />
            <.input
              type="text"
              name="filters[3][value]"
              label="Group/Tag"
              placeholder="Filter by short note"
              value={get_filter_value(@meta, :short_note)}
            />
          </:filter>
        </.filter_form>

        <!-- View toggle -->
        <div class="px-6 py-3 bg-secondary-50 border-t border-secondary-200 flex items-center justify-between">
          <div class="flex items-center gap-2">
            <%= if Map.get(@current_params, "show_all") == "true" do %>
              <span class="text-sm text-primary-500">
                <.icon name="hero-eye" class="w-4 h-4 inline-block" />
                Showing all bookings (including past)
              </span>
              <.link
                navigate={~p"/admin/bookings"}
                class="text-sm text-tertiary-600 hover:text-tertiary-800 underline"
              >
                Show only current & future
              </.link>
            <% else %>
              <span class="text-sm text-primary-500">
                <.icon name="hero-eye" class="w-4 h-4 inline-block" />
                Showing current and future bookings
              </span>
              <.link
                navigate={~p"/admin/bookings?show_all=true"}
                class="text-sm text-tertiary-600 hover:text-tertiary-800 underline"
              >
                Show all bookings
              </.link>
            <% end %>
          </div>
        </div>

        <!-- Table -->
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-secondary-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                  Guest
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                  Room
                </th>
                <.sortable_header meta={@meta} field={:check_in_date} path={~p"/admin/bookings"}>
                  Check-in
                </.sortable_header>
                <.sortable_header meta={@meta} field={:check_out_date} path={~p"/admin/bookings"}>
                  Check-out
                </.sortable_header>
                <.sortable_header meta={@meta} field={:status} path={~p"/admin/bookings"}>
                  Status
                </.sortable_header>
                <th class="px-6 py-3 text-left text-xs font-medium text-primary-400 uppercase tracking-wider">
                  Invoice
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-primary-400 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= if @bookings == [] do %>
                <tr>
                  <td colspan="7" class="px-6 py-12 text-center text-primary-400">
                    No bookings found.
                  </td>
                </tr>
              <% else %>
                <tr :for={booking <- @bookings} class="hover:bg-secondary-50">
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-primary-500">
                    <div class="flex items-center gap-2">
                      <span>{booking.guest.name}</span>
                      <%= if booking.short_note do %>
                        <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-info-light text-tertiary-800">
                          {booking.short_note}
                        </span>
                      <% end %>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-primary-400">
                    <%= if Map.get(booking, :rooms_list) && booking.rooms_list != [] do %>
                      {Enum.map_join(booking.rooms_list, ", ", & &1.room_number)}
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-primary-400">
                    {Calendar.strftime(booking.check_in_date, "%b %d, %Y")}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-primary-400">
                    {if booking.check_out_date,
                      do: Calendar.strftime(booking.check_out_date, "%b %d, %Y"),
                      else: "—"}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="relative" id={"booking-status-#{booking.id}"} phx-click-away={JS.hide(to: "#status-menu-#{booking.id}")}>
                      <button
                        type="button"
                        phx-click={JS.toggle(to: "#status-menu-#{booking.id}")}
                        class="w-full text-left inline-flex items-center justify-between gap-2 hover:opacity-80 transition-opacity"
                      >
                        <span class={[
                          "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                          status_badge_class(booking.status)
                        ]}>
                          {String.capitalize(booking.status)}
                        </span>
                        <.icon name="hero-chevron-down" class="w-3 h-3 text-primary-400" />
                      </button>

                      <div
                        id={"status-menu-#{booking.id}"}
                        class="hidden absolute z-10 mt-1 w-40 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5"
                      >
                        <div class="py-1" role="menu">
                          <button
                            type="button"
                            phx-click="update_booking_status"
                            phx-value-id={booking.id}
                            phx-value-status="upcoming"
                            class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                          >
                            <span class={["px-2 inline-flex text-xs leading-5 font-semibold rounded-full", status_badge_class("upcoming")]}>
                              Upcoming
                            </span>
                          </button>
                          <button
                            type="button"
                            phx-click="update_booking_status"
                            phx-value-id={booking.id}
                            phx-value-status="active"
                            class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                          >
                            <span class={["px-2 inline-flex text-xs leading-5 font-semibold rounded-full", status_badge_class("active")]}>
                              Active
                            </span>
                          </button>
                          <button
                            type="button"
                            phx-click="update_booking_status"
                            phx-value-id={booking.id}
                            phx-value-status="completed"
                            class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                          >
                            <span class={["px-2 inline-flex text-xs leading-5 font-semibold rounded-full", status_badge_class("completed")]}>
                              Completed
                            </span>
                          </button>
                          <button
                            type="button"
                            phx-click="update_booking_status"
                            phx-value-id={booking.id}
                            phx-value-status="cancelled"
                            class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                          >
                            <span class={["px-2 inline-flex text-xs leading-5 font-semibold rounded-full", status_badge_class("cancelled")]}>
                              Cancelled
                            </span>
                          </button>
                        </div>
                      </div>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <%= if Map.get(booking, :invoice) do %>
                      <div class="relative" id={"invoice-status-#{booking.id}"} phx-click-away={JS.hide(to: "#invoice-menu-#{booking.id}")}>
                        <button
                          type="button"
                          phx-click={JS.toggle(to: "#invoice-menu-#{booking.id}")}
                          class="w-full text-left inline-flex items-center justify-between gap-2 hover:opacity-80 transition-opacity"
                        >
                          <span class={[
                            "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                            invoice_state_badge_class(booking.invoice.state)
                          ]}>
                            {invoice_state_label(booking.invoice.state)}
                          </span>
                          <.icon name="hero-chevron-down" class="w-3 h-3 text-primary-400" />
                        </button>

                        <div
                          id={"invoice-menu-#{booking.id}"}
                          class="hidden absolute z-10 mt-1 w-48 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5"
                        >
                          <div class="py-1" role="menu">
                            <button
                              type="button"
                              phx-click="update_invoice_status"
                              phx-value-id={booking.invoice.id}
                              phx-value-state="draft"
                              class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                            >
                              <span class={["px-2 inline-flex text-xs leading-5 font-semibold rounded-full", invoice_state_badge_class("draft")]}>
                                Draft
                              </span>
                            </button>
                            <button
                              type="button"
                              phx-click="update_invoice_status"
                              phx-value-id={booking.invoice.id}
                              phx-value-state="personal"
                              class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                            >
                              <span class={["px-2 inline-flex text-xs leading-5 font-semibold rounded-full", invoice_state_badge_class("personal")]}>
                                Personal
                              </span>
                            </button>
                            <button
                              type="button"
                              phx-click="update_invoice_status"
                              phx-value-id={booking.invoice.id}
                              phx-value-state="generated"
                              class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                            >
                              <span class={["px-2 inline-flex text-xs leading-5 font-semibold rounded-full", invoice_state_badge_class("generated")]}>
                                Generated
                              </span>
                            </button>
                            <button
                              type="button"
                              phx-click="update_invoice_status"
                              phx-value-id={booking.invoice.id}
                              phx-value-state="sent"
                              class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                            >
                              <span class={["px-2 inline-flex text-xs leading-5 font-semibold rounded-full", invoice_state_badge_class("sent")]}>
                                Sent
                              </span>
                            </button>
                            <button
                              type="button"
                              phx-click="update_invoice_status"
                              phx-value-id={booking.invoice.id}
                              phx-value-state="advance_paid"
                              class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                            >
                              <span class={["px-2 inline-flex text-xs leading-5 font-semibold rounded-full", invoice_state_badge_class("advance_paid")]}>
                                Advance Paid (50%)
                              </span>
                            </button>
                            <button
                              type="button"
                              phx-click="update_invoice_status"
                              phx-value-id={booking.invoice.id}
                              phx-value-state="paid"
                              class="block w-full text-left px-4 py-2 text-sm hover:bg-secondary-50 transition-colors"
                            >
                              <span class={["px-2 inline-flex text-xs leading-5 font-semibold rounded-full", invoice_state_badge_class("paid")]}>
                                Paid
                              </span>
                            </button>
                          </div>
                        </div>
                      </div>
                    <% else %>
                      <span class="text-primary-300 text-sm">—</span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <.link
                      navigate={build_path_with_params(~p"/admin/bookings/#{booking}", @current_params)}
                      class="text-tertiary-600 hover:text-blue-900 mr-4"
                    >
                      View
                    </.link>
                    <.link
                      patch={build_path_with_params(~p"/admin/bookings/#{booking}/edit", @current_params)}
                      class="text-tertiary-600 hover:text-white-900 mr-4"
                    >
                      Edit
                    </.link>
                    <.link
                      phx-click={JS.push("delete", value: %{id: booking.id})}
                      data-confirm="Are you sure? This will not delete associated orders."
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
        <.pagination meta={@meta} path={~p"/admin/bookings"} />
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="booking-modal"
        show
        on_cancel={JS.patch(build_path_with_params(~p"/admin/bookings", @current_params))}
      >
        <.live_component
          module={CozyCheckoutWeb.BookingLive.FormComponent}
          id={@booking.id || :new}
          title={@page_title}
          action={@live_action}
          booking={@booking}
          patch={build_path_with_params(~p"/admin/bookings", @current_params)}
        />
      </.modal>
    </div>
    """
  end

  defp status_badge_class("upcoming"), do: "bg-tertiary-100 text-tertiary-800"
  defp status_badge_class("active"), do: "bg-success-light text-success-dark"
  defp status_badge_class("completed"), do: "bg-secondary-100 text-primary-500"
  defp status_badge_class("cancelled"), do: "bg-error-light text-error-dark"
  defp status_badge_class(_), do: "bg-secondary-100 text-primary-500"

  defp invoice_state_badge_class("draft"), do: "bg-secondary-100 text-primary-500"
  defp invoice_state_badge_class("personal"), do: "bg-warning-light text-warning-dark"
  defp invoice_state_badge_class("generated"), do: "bg-tertiary-100 text-tertiary-800"
  defp invoice_state_badge_class("sent"), do: "bg-info-light text-info-dark"
  defp invoice_state_badge_class("advance_paid"), do: "bg-warning-light text-warning-dark"
  defp invoice_state_badge_class("paid"), do: "bg-success-light text-success-dark"
  defp invoice_state_badge_class(_), do: "bg-secondary-100 text-primary-500"

  defp invoice_state_label("draft"), do: "Draft"
  defp invoice_state_label("personal"), do: "Personal"
  defp invoice_state_label("generated"), do: "Generated"
  defp invoice_state_label("sent"), do: "Sent"
  defp invoice_state_label("advance_paid"), do: "Advance Paid (50%)"
  defp invoice_state_label("paid"), do: "Paid"
  defp invoice_state_label(state), do: String.capitalize(state)

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

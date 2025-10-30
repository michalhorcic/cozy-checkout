defmodule CozyCheckoutWeb.BookingLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Bookings
  alias CozyCheckout.Bookings.Booking

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
  def handle_event("filter", params, socket) do
    # Push patch to update URL with filter params
    {:noreply, push_patch(socket, to: ~p"/admin/bookings?#{build_filter_params(params)}")}
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
      "invoice_state" => params["invoice_state"],
      "guest_search" => params["guest_search"]
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
        <.link patch={build_path_with_params(~p"/admin/bookings/new", @current_params)}>
          <.button>
            <.icon name="hero-plus" class="w-5 h-5 mr-2" /> New Booking
          </.button>
        </.link>
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
        <!-- Table -->
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Guest
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
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
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Invoice
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= if @bookings == [] do %>
                <tr>
                  <td colspan="7" class="px-6 py-12 text-center text-gray-500">
                    No bookings found.
                  </td>
                </tr>
              <% else %>
                <tr :for={booking <- @bookings} class="hover:bg-gray-50">
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    <div class="flex items-center gap-2">
                      <span>{booking.guest.name}</span>
                      <%= if booking.short_note do %>
                        <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-indigo-100 text-indigo-800">
                          {booking.short_note}
                        </span>
                      <% end %>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= if Map.get(booking, :rooms_list) && booking.rooms_list != [] do %>
                      {Enum.map_join(booking.rooms_list, ", ", & &1.room_number)}
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {Calendar.strftime(booking.check_in_date, "%b %d, %Y")}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {if booking.check_out_date,
                      do: Calendar.strftime(booking.check_out_date, "%b %d, %Y"),
                      else: "—"}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span class={[
                      "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                      status_badge_class(booking.status)
                    ]}>
                      {String.capitalize(booking.status)}
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <%= if Map.get(booking, :invoice) do %>
                      <span class={[
                        "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                        invoice_state_badge_class(booking.invoice.state)
                      ]}>
                        {invoice_state_label(booking.invoice.state)}
                      </span>
                    <% else %>
                      <span class="text-gray-400 text-sm">—</span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <.link
                      navigate={build_path_with_params(~p"/admin/bookings/#{booking}", @current_params)}
                      class="text-blue-600 hover:text-blue-900 mr-4"
                    >
                      View
                    </.link>
                    <.link
                      patch={build_path_with_params(~p"/admin/bookings/#{booking}/edit", @current_params)}
                      class="text-indigo-600 hover:text-indigo-900 mr-4"
                    >
                      Edit
                    </.link>
                    <.link
                      phx-click={JS.push("delete", value: %{id: booking.id})}
                      data-confirm="Are you sure? This will not delete associated orders."
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

  defp status_badge_class("upcoming"), do: "bg-blue-100 text-blue-800"
  defp status_badge_class("active"), do: "bg-green-100 text-green-800"
  defp status_badge_class("completed"), do: "bg-gray-100 text-gray-800"
  defp status_badge_class("cancelled"), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp invoice_state_badge_class("draft"), do: "bg-gray-100 text-gray-800"
  defp invoice_state_badge_class("personal"), do: "bg-amber-100 text-amber-800"
  defp invoice_state_badge_class("generated"), do: "bg-blue-100 text-blue-800"
  defp invoice_state_badge_class("sent"), do: "bg-purple-100 text-purple-800"
  defp invoice_state_badge_class("advance_paid"), do: "bg-yellow-100 text-yellow-800"
  defp invoice_state_badge_class("paid"), do: "bg-green-100 text-green-800"
  defp invoice_state_badge_class(_), do: "bg-gray-100 text-gray-800"

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

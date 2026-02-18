defmodule CozyCheckoutWeb.BookingLive.Calendar do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Bookings
  alias CozyCheckoutWeb.BookingLive.CalendarHelpers

  # Make CalendarHelpers available in templates
  defp assign_helpers(socket) do
    assign(socket, :CalendarHelpers, CalendarHelpers)
  end

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    socket =
      socket
      |> assign(:year, today.year)
      |> assign(:month, today.month)
      |> assign(:modal_date, nil)
      |> assign(:modal_bookings, [])
      |> assign(:modal_categorized, %{arriving: [], staying: [], leaving: []})
      |> assign_helpers()
      |> load_calendar_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_month", _params, socket) do
    {year, month} = CalendarHelpers.previous_month(socket.assigns.year, socket.assigns.month)

    socket =
      socket
      |> assign(:year, year)
      |> assign(:month, month)
      |> load_calendar_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("next_month", _params, socket) do
    {year, month} = CalendarHelpers.next_month(socket.assigns.year, socket.assigns.month)

    socket =
      socket
      |> assign(:year, year)
      |> assign(:month, month)
      |> load_calendar_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("today", _params, socket) do
    today = Date.utc_today()

    socket =
      socket
      |> assign(:year, today.year)
      |> assign(:month, today.month)
      |> load_calendar_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_day_bookings", %{"date" => date_string}, socket) do
    date = Date.from_iso8601!(date_string)
    bookings = CalendarHelpers.bookings_for_date(socket.assigns.bookings, date)
    categorized = CalendarHelpers.categorize_bookings_for_date(socket.assigns.bookings, date)

    {:noreply, assign(socket, modal_date: date, modal_bookings: bookings, modal_categorized: categorized)}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal_date: nil, modal_bookings: [], modal_categorized: %{arriving: [], staying: [], leaving: []})}
  end

  defp load_calendar_data(socket) do
    year = socket.assigns.year
    month = socket.assigns.month

    bookings = Bookings.list_bookings_for_month(year, month)
    weeks = CalendarHelpers.generate_calendar_grid(year, month)

    # Get occupancy data for the entire calendar range
    first_day = Date.new!(year, month, 1)
    last_day = Date.end_of_month(first_day)
    calendar_start = Date.beginning_of_week(first_day, :monday)
    calendar_end = Date.end_of_week(last_day, :monday)

    occupancy_map = Bookings.get_occupancy_for_range(calendar_start, calendar_end)
    occupancy_breakdown_map = Bookings.get_occupancy_breakdown_for_range(calendar_start, calendar_end)
    arrivals_departures_map = Bookings.get_arrivals_departures_for_range(calendar_start, calendar_end)
    capacity = Bookings.cottage_capacity()

    socket
    |> assign(:bookings, bookings)
    |> assign(:weeks, weeks)
    |> assign(:occupancy_map, occupancy_map)
    |> assign(:occupancy_breakdown_map, occupancy_breakdown_map)
    |> assign(:arrivals_departures_map, arrivals_departures_map)
    |> assign(:capacity, capacity)
    |> assign(:page_title, "Calendar - #{CalendarHelpers.month_name(month)} #{year}")
  end

  defp status_color(status) do
    case status do
      "upcoming" -> "bg-tertiary-100 border-tertiary-300 text-tertiary-800"
      "active" -> "bg-success-light border-success text-success-dark"
      "completed" -> "bg-secondary-100 border-secondary-300 text-primary-400"
      "cancelled" -> "bg-error-light border-error text-error"
      _ -> "bg-secondary-100 border-secondary-300 text-primary-400"
    end
  end

  defp occupancy_badge_class(count) do
    level = Bookings.occupancy_level(count)

    base_classes =
      "absolute top-1 left-1 text-xs font-semibold px-2 py-0.5 rounded-full shadow-sm"

    color_classes =
      case level do
        :full -> "bg-error text-white"
        :high -> "bg-warning text-white"
        :medium -> "bg-warning text-primary-500"
        :low -> "bg-success text-white"
      end

    "#{base_classes} #{color_classes}"
  end

  defp day_cell(assigns) do
    ~H"""
    <div class={[
      "min-h-[120px] border-r border-b border-secondary-200 p-2 relative",
      @is_today && "bg-tertiary-50"
    ]}>
      <%!-- Day number --%>
      <div class="text-right mb-1">
        <span class={[
          "text-sm font-semibold",
          @is_today &&
            "inline-flex items-center justify-center w-7 h-7 rounded-full bg-tertiary-600 text-white",
          !@is_today && "text-primary-500"
        ]}>
          {@date.day}
        </span>
      </div>

      <%!-- Occupancy badge (top-left) --%>
      <%= if occupancy = Map.get(@occupancy_map, @date, 0) do %>
        <%= if occupancy > 0 do %>
          <button
            type="button"
            phx-click="show_day_bookings"
            phx-value-date={@date}
            class={[occupancy_badge_class(occupancy), "cursor-pointer hover:shadow-md transition-shadow"]}
          >
            <span>{occupancy}/{@capacity}</span>
            <%!-- Breakdown rows --%>
            <%= if breakdown = Map.get(@occupancy_breakdown_map, @date) do %>
              <div class="mt-0.5 space-y-0.5 text-[10px] font-normal leading-tight">
                <%= if breakdown.adults > 0 do %>
                  <div>👤 {breakdown.adults}</div>
                <% end %>
                <%= if breakdown.kids_under_12 > 0 or breakdown.kids_under_2 > 0 do %>
                  <div>
                    🧒 {breakdown.kids_under_12 + breakdown.kids_under_2}
                    <%= if breakdown.kids_under_2 > 0 do %>
                      <span class="opacity-75">(👶{breakdown.kids_under_2})</span>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </button>
        <% end %>
      <% end %>

      <%!-- Activity badges (right side) --%>
      <%= if stats = Map.get(@arrivals_departures_map, @date) do %>
        <div class="absolute top-1 right-1 flex flex-col gap-1 items-end">
          <%= if stats.arrivals > 0 do %>
            <button
              type="button"
              phx-click="show_day_bookings"
              phx-value-date={@date}
              class="text-xs font-semibold px-2 py-0.5 rounded-full shadow-sm bg-success text-white cursor-pointer hover:shadow-md transition-shadow"
              title={"#{stats.arrivals} arriving"}
            >
              ▶ {stats.arrivals}
            </button>
          <% end %>
          <%= if stats.departures > 0 do %>
            <button
              type="button"
              phx-click="show_day_bookings"
              phx-value-date={@date}
              class="text-xs font-semibold px-2 py-0.5 rounded-full shadow-sm bg-error text-white cursor-pointer hover:shadow-md transition-shadow"
              title={"#{stats.departures} leaving"}
            >
              ◀ {stats.departures}
            </button>
          <% end %>
        </div>
      <% end %>

      <%!-- Bookings for this day --%>
      <div class="space-y-1 mt-6">
        <%= for booking <- Enum.take(@bookings, 3) do %>
          <.link
            navigate={~p"/admin/bookings/#{booking}"}
            class={[
              "block px-2 py-1 rounded text-xs font-medium border-l-2 hover:shadow-sm transition-shadow",
              status_color(booking.status)
            ]}
          >
            <div class="truncate font-semibold flex items-center gap-1">
              <span class="text-[10px]">{CalendarHelpers.booking_icon_for_date(booking, @date)}</span>
              {booking.guest.name}
            </div>
            <%= if booking.room_number do %>
              <div class="truncate text-[10px] opacity-75">Room {booking.room_number}</div>
            <% end %>
          </.link>
        <% end %>

        <%!-- Show count if more than 3 bookings --%>
        <%= if length(@bookings) > 3 do %>
          <button
            type="button"
            phx-click="show_day_bookings"
            phx-value-date={@date}
            class="text-[10px] text-tertiary-600 hover:text-tertiary-800 font-medium text-center pt-1 w-full hover:underline cursor-pointer"
          >
            +{length(@bookings) - 3} more
          </button>
        <% end %>
      </div>
    </div>
    """
  end
end

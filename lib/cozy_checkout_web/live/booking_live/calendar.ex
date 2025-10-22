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
    capacity = Bookings.cottage_capacity()

    socket
    |> assign(:bookings, bookings)
    |> assign(:weeks, weeks)
    |> assign(:occupancy_map, occupancy_map)
    |> assign(:capacity, capacity)
    |> assign(:page_title, "Calendar - #{CalendarHelpers.month_name(month)} #{year}")
  end

  defp status_color(status) do
    case status do
      "upcoming" -> "bg-blue-100 border-blue-300 text-blue-800"
      "active" -> "bg-green-100 border-green-300 text-green-800"
      "completed" -> "bg-gray-100 border-gray-300 text-gray-600"
      "cancelled" -> "bg-red-100 border-red-300 text-red-600"
      _ -> "bg-gray-100 border-gray-300 text-gray-600"
    end
  end

  defp occupancy_badge_class(count) do
    level = Bookings.occupancy_level(count)

    base_classes =
      "absolute top-1 right-1 text-xs font-semibold px-2 py-0.5 rounded-full shadow-sm"

    color_classes =
      case level do
        :full -> "bg-red-500 text-white"
        :high -> "bg-orange-500 text-white"
        :medium -> "bg-yellow-500 text-gray-900"
        :low -> "bg-green-500 text-white"
      end

    "#{base_classes} #{color_classes}"
  end

  defp day_cell(assigns) do
    ~H"""
    <div class={[
      "min-h-[120px] border-r border-b border-gray-200 p-2 relative",
      @is_today && "bg-blue-50"
    ]}>
      <%!-- Day number --%>
      <div class="text-right mb-1">
        <span class={[
          "text-sm font-semibold",
          @is_today &&
            "inline-flex items-center justify-center w-7 h-7 rounded-full bg-blue-600 text-white",
          !@is_today && "text-gray-700"
        ]}>
          {@date.day}
        </span>
      </div>

      <%!-- Occupancy badge --%>
      <%= if occupancy = Map.get(@occupancy_map, @date, 0) do %>
        <%= if occupancy > 0 do %>
          <div class={occupancy_badge_class(occupancy)}>
            {occupancy}/{@capacity}
          </div>
        <% end %>
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
            <div class="truncate font-semibold">{booking.guest.name}</div>
            <%= if booking.room_number do %>
              <div class="truncate text-[10px] opacity-75">Room {booking.room_number}</div>
            <% end %>
          </.link>
        <% end %>

        <%!-- Show count if more than 3 bookings --%>
        <%= if length(@bookings) > 3 do %>
          <div class="text-[10px] text-gray-500 text-center pt-1">
            +{length(@bookings) - 3} more
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end

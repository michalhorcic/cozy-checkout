defmodule CozyCheckoutWeb.BookingLive.Timeline do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Bookings
  alias CozyCheckoutWeb.BookingLive.CalendarHelpers

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    # Calculate the Monday of the current week
    start_of_week = Date.beginning_of_week(today, :monday)

    socket =
      socket
      |> assign(:start_date, start_of_week)
      |> assign(:weeks_shown, 2)
      |> load_timeline_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_week", _params, socket) do
    new_start_date = Date.add(socket.assigns.start_date, -7)

    socket =
      socket
      |> assign(:start_date, new_start_date)
      |> load_timeline_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("next_week", _params, socket) do
    new_start_date = Date.add(socket.assigns.start_date, 7)

    socket =
      socket
      |> assign(:start_date, new_start_date)
      |> load_timeline_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("today", _params, socket) do
    today = Date.utc_today()
    start_of_week = Date.beginning_of_week(today, :monday)

    socket =
      socket
      |> assign(:start_date, start_of_week)
      |> load_timeline_data()

    {:noreply, socket}
  end

  defp load_timeline_data(socket) do
    start_date = socket.assigns.start_date
    weeks_shown = socket.assigns.weeks_shown
    end_date = Date.add(start_date, weeks_shown * 7 - 1)

    bookings =
      Bookings.list_bookings_for_date_range(start_date, end_date)
      |> Enum.sort_by(& &1.check_in_date)
      |> Enum.map(fn booking ->
        # Load invoice and calculate people count
        invoice = Bookings.get_invoice_by_booking_id(booking.id)

        people_count =
          if invoice do
            Bookings.get_invoice_people_count(invoice.id)
          else
            0
          end

        # Load rooms
        rooms = Bookings.list_booking_rooms(booking.id)

        booking
        |> Map.put(:invoice, invoice)
        |> Map.put(:people_count, people_count)
        |> Map.put(:rooms_list, rooms)
      end)

    dates = Date.range(start_date, end_date) |> Enum.to_list()
    capacity = Bookings.cottage_capacity()
    occupancy_map = Bookings.get_occupancy_for_range(start_date, end_date)

    socket
    |> assign(:bookings, bookings)
    |> assign(:dates, dates)
    |> assign(:end_date, end_date)
    |> assign(:capacity, capacity)
    |> assign(:occupancy_map, occupancy_map)
    |> assign(:page_title, "Timeline - Week of #{Calendar.strftime(start_date, "%b %d, %Y")}")
  end

  defp booking_spans_date?(booking, date) do
    check_in_ok = Date.compare(date, booking.check_in_date) in [:eq, :gt]

    check_out_ok =
      if booking.check_out_date do
        Date.compare(date, booking.check_out_date) in [:eq, :lt]
      else
        true
      end

    check_in_ok and check_out_ok
  end

  defp is_check_in_date?(booking, date) do
    Date.compare(date, booking.check_in_date) == :eq
  end

  defp is_check_out_date?(booking, date) do
    booking.check_out_date && Date.compare(date, booking.check_out_date) == :eq
  end

  defp cell_class(booking, date) do
    base = "border-t border-b border-gray-200 text-xs px-1 py-2"

    cond do
      is_check_in_date?(booking, date) ->
        "#{base} border-l-2 border-l-success bg-success-light font-semibold rounded-l"

      is_check_out_date?(booking, date) ->
        "#{base} border-r-2 border-r-error bg-error-light font-semibold rounded-r"

      booking_spans_date?(booking, date) ->
        "#{base} bg-tertiary-50"

      true ->
        "#{base} bg-white"
    end
  end

  defp cell_content(booking, date) do
    cond do
      is_check_in_date?(booking, date) ->
        "▶ In"

      is_check_out_date?(booking, date) ->
        "Out ◀"

      booking_spans_date?(booking, date) ->
        "→"

      true ->
        ""
    end
  end

  defp status_indicator(status) do
    case status do
      "upcoming" -> "🔵"
      "active" -> "🟢"
      "completed" -> "⚪"
      "cancelled" -> "🔴"
      _ -> "⚪"
    end
  end

  defp occupancy_color(count, _capacity) do
    level = Bookings.occupancy_level(count)

    case level do
      :full -> "bg-error text-white"
      :high -> "bg-warning text-white"
      :medium -> "bg-warning text-primary-500"
      :low -> "bg-success text-white"
    end
  end
end

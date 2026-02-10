defmodule CozyCheckoutWeb.BookingLive.CalendarHelpers do
  @moduledoc """
  Helper functions for generating calendar views.
  """

  @doc """
  Generates a list of weeks for a given month.
  Each week is a list of 7 days (starting Monday).
  Days outside the current month are nil.
  """
  def generate_calendar_grid(year, month) do
    first_day = Date.new!(year, month, 1)
    last_day = Date.end_of_month(first_day)

    # Find the Monday of the week containing the first day
    start_offset = Date.day_of_week(first_day) - 1
    calendar_start = Date.add(first_day, -start_offset)

    # Find the Sunday of the week containing the last day
    end_offset = 7 - Date.day_of_week(last_day)
    calendar_end = Date.add(last_day, end_offset)

    # Generate all dates in the calendar grid
    calendar_start
    |> Date.range(calendar_end)
    |> Enum.map(fn date ->
      if date.month == month do
        date
      else
        nil
      end
    end)
    |> Enum.chunk_every(7)
  end

  @doc """
  Returns the name of the month.
  """
  def month_name(month) do
    case month do
      1 -> "January"
      2 -> "February"
      3 -> "March"
      4 -> "April"
      5 -> "May"
      6 -> "June"
      7 -> "July"
      8 -> "August"
      9 -> "September"
      10 -> "October"
      11 -> "November"
      12 -> "December"
    end
  end

  @doc """
  Returns the short name of a day of week (1 = Monday, 7 = Sunday).
  """
  def day_name(day_of_week) do
    case day_of_week do
      1 -> "Mon"
      2 -> "Tue"
      3 -> "Wed"
      4 -> "Thu"
      5 -> "Fri"
      6 -> "Sat"
      7 -> "Sun"
    end
  end

  @doc """
  Gets bookings that overlap with a specific date.
  """
  def bookings_for_date(bookings, date) do
    Enum.filter(bookings, fn booking ->
      date_in_range?(date, booking.check_in_date, booking.check_out_date)
    end)
  end

  @doc """
  Checks if a date falls within a booking range.
  """
  def date_in_range?(date, check_in, check_out) do
    check_in_ok = Date.compare(date, check_in) in [:eq, :gt]

    check_out_ok =
      if check_out do
        Date.compare(date, check_out) in [:eq, :lt]
      else
        true
      end

    check_in_ok and check_out_ok
  end

  @doc """
  Navigates to the previous month.
  """
  def previous_month(year, month) do
    if month == 1 do
      {year - 1, 12}
    else
      {year, month - 1}
    end
  end

  @doc """
  Navigates to the next month.
  """
  def next_month(year, month) do
    if month == 12 do
      {year + 1, 1}
    else
      {year, month + 1}
    end
  end

  @doc """
  Returns true if the date is today.
  """
  def today?(date) do
    Date.compare(date, Date.utc_today()) == :eq
  end

  @doc """
  Categorizes bookings for a specific date into arriving, staying, and leaving.
  Returns a map with keys: :arriving, :staying, :leaving
  """
  def categorize_bookings_for_date(bookings, date) do
    bookings
    |> Enum.filter(&date_in_range?(date, &1.check_in_date, &1.check_out_date))
    |> Enum.group_by(&booking_status_for_date(&1, date))
    |> then(fn grouped ->
      %{
        arriving: Map.get(grouped, :arriving, []),
        staying: Map.get(grouped, :staying, []),
        leaving: Map.get(grouped, :leaving, [])
      }
    end)
  end

  @doc """
  Determines if a booking is arriving, staying, or leaving on a specific date.
  """
  def booking_status_for_date(booking, date) do
    is_check_in = Date.compare(date, booking.check_in_date) == :eq
    is_check_out = booking.check_out_date && Date.compare(date, booking.check_out_date) == :eq

    cond do
      is_check_in -> :arriving
      is_check_out -> :leaving
      true -> :staying
    end
  end

  @doc """
  Returns the icon for a booking based on its status for a date.
  """
  def booking_icon_for_date(booking, date) do
    case booking_status_for_date(booking, date) do
      :arriving -> "▶"
      :leaving -> "◀"
      :staying -> "→"
    end
  end
end

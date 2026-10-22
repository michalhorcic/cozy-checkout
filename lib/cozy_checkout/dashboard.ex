defmodule CozyCheckout.Dashboard do
  @moduledoc "Read-only operational overview using the calendar and kitchen calculations."

  import Ecto.Query
  alias CozyCheckout.{Bookings, Meals, Repo}
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Meals.{MenuPlanning, PortionCounts}

  def overview(today \\ Date.utc_today()) do
    last_date = month_ahead(today)

    bookings =
      Booking
      |> where([b], is_nil(b.deleted_at) and b.status in ["upcoming", "active"])
      |> where([b], b.check_in_date <= ^last_date)
      |> where([b], is_nil(b.check_out_date) or b.check_out_date >= ^today)
      |> order_by([b], asc: b.check_in_date, asc: b.id)
      |> preload([:guest, :rooms])
      |> Repo.all()

    portions = Meals.get_portion_counts_for_range(today, today) |> Map.fetch!(today)
    incomplete = PortionCounts.for_range(bookings, today, last_date)

    missing_details =
      incomplete
      |> Map.values()
      |> Enum.flat_map(& &1.incomplete_bookings)
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(&%{booking: &1, kind: :details, reason: "Doplnit údaje o stravování"})

    booking_ids = MapSet.new(bookings, & &1.id)

    menu_issues =
      MenuPlanning.kitchen_for_range(today, last_date).issues
      |> Enum.filter(&MapSet.member?(booking_ids, &1.booking.id))
      |> Enum.map(&Map.put(&1, :kind, :menu))

    %{
      today: today,
      last_date: last_date,
      bookings: bookings,
      arrivals: Enum.count(bookings, &(&1.check_in_date == today)),
      departures: Enum.count(bookings, &(&1.check_out_date == today)),
      occupancy: Map.fetch!(Bookings.get_occupancy_for_range(today, today), today),
      capacity: Bookings.cottage_capacity(),
      portions: portions,
      issues: Enum.sort_by(missing_details ++ menu_issues, & &1.booking.check_in_date, Date)
    }
  end

  @doc "Same day of the following month, clamped to its last day."
  def month_ahead(%Date{year: year, month: month, day: day}) do
    first = if month == 12, do: Date.new!(year + 1, 1, 1), else: Date.new!(year, month + 1, 1)
    Date.new!(first.year, first.month, min(day, Date.days_in_month(first)))
  end
end

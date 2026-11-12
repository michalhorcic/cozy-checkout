defmodule CozyCheckout.Adventure.Sources.Operation do
  @moduledoc "Ephemeral, PII-free projection of the shared operational dashboard."
  alias CozyCheckout.{Adventure, Dashboard}

  # Europe/Prague follows EU summer time: last Sunday in March/October at 01:00 UTC.
  # Keep the clock in memory: a SQL timezone lookup would exceed the source budget.
  def today(now \\ DateTime.utc_now()) do
    boundary = fn month ->
      last = Date.new!(now.year, month, 1) |> Date.end_of_month()
      sunday = Date.add(last, -rem(Date.day_of_week(last), 7))
      DateTime.new!(sunday, ~T[01:00:00], "Etc/UTC")
    end

    summer =
      DateTime.compare(now, boundary.(3)) != :lt and DateTime.compare(now, boundary.(10)) == :lt

    now |> DateTime.add(if(summer, do: 7200, else: 3600), :second) |> DateTime.to_date()
  end

  def load do
    if Adventure.enabled?() do
      now = DateTime.utc_now()
      {:ok, Dashboard.overview(today(now)) |> project(now)}
    else
      {:error, :disabled}
    end
  rescue
    _error in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, :unavailable}
  end

  def project(overview, now) do
    %{
      today: overview.today,
      through: overview.last_date,
      loaded_at: now,
      arrivals: overview.arrivals,
      departures: overview.departures,
      occupancy: overview.occupancy,
      capacity: overview.capacity,
      portions: Map.take(overview.portions, ["breakfast", "lunch", "dinner"]),
      incomplete: length(overview.portions.incomplete_bookings),
      issues:
        Enum.map(overview.issues, fn issue ->
          %{
            booking_id: issue.booking.id,
            on: issue.booking.check_in_date,
            kind: issue.kind,
            reason: issue.reason
          }
        end)
    }
  end

  def stale?(snapshot, now \\ DateTime.utc_now()) do
    snapshot.today != today(now) or DateTime.diff(now, snapshot.loaded_at) >= 900
  end
end

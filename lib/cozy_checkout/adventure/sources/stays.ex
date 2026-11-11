defmodule CozyCheckout.Adventure.Sources.Stays do
  @moduledoc """
  One read-only aggregate over bookings, without guest/room joins or operational
  context calls. No status refreshes, writes, remote calls, or guest payloads.
  Dates follow the calendar's inclusive arrival / exclusive departure rule.
  """
  alias CozyCheckout.Repo

  def today, do: local_date(DateTime.utc_now())

  def local_date(at) do
    %{rows: [[date]]} =
      Repo.query!("SELECT timezone('Europe/Prague', $1::timestamptz)::date", [at])

    date
  end

  # Campaign cutoff is frozen on closure; as_of always describes the current
  # source read, not a claim that historical versions of bookings are available.
  def snapshot(campaign, as_of \\ DateTime.utc_now()) do
    cutoff = campaign.closed_at || as_of

    %{columns: columns, rows: [values]} =
      Repo.query!(
        ~S"""
        WITH bounds AS (
          SELECT $1::date AS starts_on, $2::date AS ends_on,
                 timezone('Europe/Prague', $3::timestamptz)::date AS cutoff_on,
                 timezone('Europe/Prague', $4::timestamptz)::date AS activated_on
        ), stays AS (
          SELECT b.check_in_date, b.check_out_date, b.status,
                 (COALESCE(b.adults, 0)::bigint + COALESCE(b.children, 0) +
                  COALESCE(b.infants, 0) + COALESCE(b.unclassified_guests, 0)) AS people,
                 b.check_in_date IS NOT NULL AND b.check_out_date > b.check_in_date AS valid_dates,
                 b.adults IS NOT NULL AND b.children IS NOT NULL AND b.infants IS NOT NULL
                   AND b.unclassified_guests IS NOT NULL AND b.adults >= 0 AND b.children >= 0
                   AND b.infants >= 0 AND b.unclassified_guests >= 0 AS valid_people,
                 bounds.*
          FROM bookings b CROSS JOIN bounds
          WHERE b.deleted_at IS NULL AND b.status IS DISTINCT FROM 'cancelled'
            AND (b.check_in_date IS NULL OR b.check_in_date <= bounds.ends_on)
            AND (b.check_out_date IS NULL OR b.check_out_date >= bounds.starts_on
                 OR (b.check_out_date <= b.check_in_date AND b.check_in_date >= bounds.starts_on))
        )
        SELECT
          count(*) FILTER (WHERE valid_dates AND status = 'completed'
            AND check_out_date BETWEEN starts_on AND ends_on AND check_out_date < cutoff_on) AS completed_stays,
          count(*) FILTER (WHERE valid_dates AND status = 'completed'
            AND check_out_date BETWEEN starts_on AND ends_on AND check_out_date < cutoff_on
            AND check_out_date > activated_on) AS eligible_completed_stays,
          COALESCE(sum(CASE WHEN valid_dates AND valid_people AND status IN ('active', 'completed')
            THEN people * GREATEST(0, LEAST(check_out_date, ends_on + 1, cutoff_on) - GREATEST(check_in_date, starts_on))
            ELSE 0 END), 0)::bigint AS realized_bednights,
          COALESCE(sum(CASE WHEN valid_dates AND valid_people AND status IN ('upcoming', 'active')
            THEN people * GREATEST(0, LEAST(check_out_date, ends_on + 1) - GREATEST(check_in_date, starts_on, cutoff_on))
            ELSE 0 END), 0)::bigint AS reserved_bednights,
          count(*) FILTER (WHERE valid_dates IS NOT TRUE OR valid_people IS NOT TRUE OR people <= 0
            OR status IS NULL OR status NOT IN ('upcoming', 'active', 'completed')
            OR (status = 'upcoming' AND check_in_date < cutoff_on)
            OR (status = 'active' AND check_out_date < cutoff_on)
            OR (status = 'completed' AND check_out_date >= cutoff_on)) AS uncertain_stays,
          (SELECT cutoff_on FROM bounds) AS cutoff_on
        FROM stays
        """,
        [campaign.starts_on, campaign.ends_on, cutoff, campaign.activated_at]
      )

    metrics = Map.new(Enum.zip(columns, values))

    closed_nights =
      max(
        0,
        Date.diff(
          min_date(Date.add(campaign.ends_on, 1), metrics["cutoff_on"]),
          campaign.starts_on
        )
      )

    capacity_nights = campaign.capacity * closed_nights

    percent =
      if capacity_nights > 0,
        do:
          Decimal.div(
            Decimal.new(metrics["realized_bednights"] * 100),
            Decimal.new(capacity_nights)
          )

    over_capacity = not is_nil(percent) and Decimal.compare(percent, 100) == :gt

    metrics
    |> Map.put("cutoff_on", Date.to_iso8601(metrics["cutoff_on"]))
    |> Map.merge(%{
      "as_of" => DateTime.to_iso8601(as_of),
      "rules_version" => campaign.rules_version,
      "source" => "bookings",
      "timezone" => "Europe/Prague",
      "starts_on" => Date.to_iso8601(campaign.starts_on),
      "ends_on" => Date.to_iso8601(campaign.ends_on),
      "closed_nights" => closed_nights,
      "capacity_bednights" => capacity_nights,
      "capacity" => campaign.capacity,
      "capacity_source" => "self_confirmed_constant",
      "occupancy_percent" =>
        if(percent, do: percent |> Decimal.round(2) |> Decimal.to_string(:normal)),
      "occupancy_status" => if(capacity_nights == 0, do: "unavailable", else: "available"),
      "completeness" =>
        if(metrics["uncertain_stays"] == 0 and not over_capacity, do: "complete", else: "partial"),
      "definition" =>
        "Příjezd včetně, odjezd bez noci. Realizované noci: active/completed před cutoff_on; rezervované: upcoming/active od cutoff_on. Počty osob včetně dětí a kojenců. Dokončené pobyty: odjezd v kampani před cutoff_on; milníky navíc až den po aktivaci."
    })
  end

  defp min_date(a, b), do: if(Date.compare(a, b) == :gt, do: b, else: a)
end

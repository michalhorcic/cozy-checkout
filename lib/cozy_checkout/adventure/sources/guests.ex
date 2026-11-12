defmodule CozyCheckout.Adventure.Sources.Guests do
  @moduledoc "One aggregate for the current Prague day, shared by all due guest-scoped templates."
  alias CozyCheckout.Repo

  def snapshot(day) do
    %{rows: [[present, uncertain]]} =
      Repo.query!(
        """
        SELECT
          count(*) FILTER (WHERE status = 'active'
            AND check_in_date <= $1::date AND check_out_date > $1::date
            AND adults IS NOT NULL AND children IS NOT NULL AND infants IS NOT NULL
            AND unclassified_guests IS NOT NULL
            AND adults >= 0 AND children >= 0 AND infants >= 0 AND unclassified_guests >= 0
            AND adults + children + infants + unclassified_guests > 0),
          count(*) FILTER (WHERE
            check_in_date IS NULL OR check_out_date IS NULL OR check_out_date <= check_in_date
            OR status IS NULL OR status NOT IN ('upcoming','active','completed')
            OR (check_in_date <= $1::date AND check_out_date > $1::date
              AND (status != 'active' OR adults IS NULL OR children IS NULL OR infants IS NULL
                OR unclassified_guests IS NULL OR adults < 0 OR children < 0 OR infants < 0
                OR unclassified_guests < 0 OR adults + children + infants + unclassified_guests <= 0))
            OR (status = 'active' AND check_out_date < $1::date))
        FROM bookings
        WHERE deleted_at IS NULL AND status IS DISTINCT FROM 'cancelled'
          AND (check_in_date IS NULL OR check_in_date <= $1::date)
          AND (check_out_date IS NULL OR check_out_date >= $1::date OR status = 'active')
        """,
        [day]
      )

    cond do
      present > 0 -> "present"
      uncertain > 0 -> "unknown"
      true -> "empty"
    end
  end
end

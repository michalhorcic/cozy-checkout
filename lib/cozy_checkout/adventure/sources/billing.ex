defmodule CozyCheckout.Adventure.Sources.Billing do
  @moduledoc "Read-only period cash flow and departure-cohort settlement, aggregated per payer."

  alias CozyCheckout.{Adventure, Repo}

  def evaluate(campaign, opts \\ []) do
    if Adventure.enabled?(),
      do: read_evaluation(campaign, opts),
      else: {:error, :disabled}
  end

  defp read_evaluation(campaign, opts) do
    as_of = Keyword.get(opts, :as_of, DateTime.utc_now())

    %{columns: columns, rows: [values]} =
      Repo.query!(
        ~S"""
        WITH bounds AS (
          SELECT $1::date AS starts_on, $2::date AS ends_on,
                 timezone('Europe/Prague', $3::timestamptz)::date AS as_of_on
        ), cohort AS (
          SELECT b.id, b.allocation_completed_at FROM bookings b CROSS JOIN bounds
          WHERE b.check_out_date BETWEEN bounds.starts_on AND LEAST(bounds.ends_on, bounds.as_of_on)
            AND (b.check_in_date IS NULL OR b.check_out_date >= b.check_in_date)
        ), period_history AS (
          SELECT d.booking_id FROM billing_documents d CROSS JOIN bounds
          WHERE d.issued_on BETWEEN bounds.starts_on AND LEAST(bounds.ends_on, bounds.as_of_on)
          UNION
          SELECT p.booking_id FROM billing_payments p CROSS JOIN bounds
          WHERE p.paid_on BETWEEN bounds.starts_on AND LEAST(bounds.ends_on, bounds.as_of_on)
            AND p.kind IN ('receipt', 'refund')
        ), departure_quality AS (
          SELECT count(*) AS uncertain_departure_bookings
          FROM bookings b CROSS JOIN bounds
          LEFT JOIN period_history h ON h.booking_id = b.id
          WHERE (b.check_out_date IS NULL OR b.check_out_date < b.check_in_date)
            AND (b.check_in_date BETWEEN bounds.starts_on AND LEAST(bounds.ends_on, bounds.as_of_on)
              OR b.check_out_date BETWEEN bounds.starts_on AND LEAST(bounds.ends_on, bounds.as_of_on)
              OR h.booking_id IS NOT NULL)
        ), documents AS (
          SELECT d.billing_account_id, count(*) AS document_count,
                 count(*) FILTER (WHERE d.kind = 'final') AS final_count,
                 COALESCE(sum(d.total) FILTER (WHERE d.kind = 'final'
                   OR (d.kind = 'correction' AND parent.kind = 'final'
                     AND parent.issued_on <= bounds.as_of_on)), 0) AS billed
          FROM billing_documents d JOIN cohort c ON c.id = d.booking_id CROSS JOIN bounds
          LEFT JOIN billing_documents parent ON parent.id = d.parent_id
            AND parent.billing_account_id = d.billing_account_id
          WHERE d.issued_on <= bounds.as_of_on
          GROUP BY d.billing_account_id
        ), payments AS (
          SELECT p.billing_account_id, count(*) AS payment_count,
                 sum(CASE WHEN p.kind = 'refund' THEN -p.amount ELSE p.amount END) AS paid
          FROM billing_payments p JOIN cohort c ON c.id = p.booking_id CROSS JOIN bounds
          WHERE p.paid_on <= bounds.as_of_on AND p.kind IN ('receipt', 'refund')
          GROUP BY p.billing_account_id
        ), accounts AS (
          SELECT a.id, a.booking_id, COALESCE(i.state = 'personal', false) AS personal,
                 COALESCE(d.final_count, 0) AS final_count, COALESCE(d.billed, 0) AS billed,
                 COALESCE(p.paid, 0) AS paid
          FROM billing_accounts a JOIN cohort c ON c.id = a.booking_id
          LEFT JOIN booking_invoices i ON i.billing_account_id = a.id
          LEFT JOIN documents d ON d.billing_account_id = a.id
          LEFT JOIN payments p ON p.billing_account_id = a.id
          WHERE a.deleted_at IS NULL OR COALESCE(d.document_count, 0) > 0
            OR COALESCE(p.payment_count, 0) > 0
        ), account_totals AS (
          SELECT count(*) AS settlement_accounts_count,
                 count(*) FILTER (WHERE final_count > 0) AS settlement_final_accounts_count,
                 count(*) FILTER (WHERE personal) AS personal_accounts_count,
                 count(*) FILTER (WHERE final_count = 0 AND NOT personal) AS missing_final_accounts,
                 count(*) FILTER (WHERE final_count = 0 AND personal) AS personal_accounts_missing_final,
                 COALESCE(sum(billed) FILTER (WHERE final_count > 0), 0)::numeric AS settlement_billed_amount,
                 COALESCE(sum(paid), 0)::numeric AS settlement_paid_amount,
                 COALESCE(sum(GREATEST(billed - paid, 0)) FILTER (WHERE final_count > 0), 0)::numeric AS settlement_remaining_amount,
                 COALESCE(sum(GREATEST(paid - billed, 0)) FILTER (WHERE final_count > 0), 0)::numeric AS settlement_overpayment_amount
          FROM accounts
        ), booking_accounts AS (
          SELECT booking_id, count(*) AS account_count FROM accounts GROUP BY booking_id
        ), booking_totals AS (
          SELECT count(*) AS settlement_bookings_count,
                 count(*) FILTER (WHERE a.account_count IS NULL) AS bookings_without_accounts,
                 count(*) FILTER (WHERE allocation_completed_at IS NULL) AS incomplete_allocation_bookings
          FROM cohort c LEFT JOIN booking_accounts a ON a.booking_id = c.id
        ), period_totals AS (
          SELECT COALESCE(sum(p.amount) FILTER (WHERE p.kind = 'receipt'), 0)::numeric AS period_receipts_amount,
                 COALESCE(sum(p.amount) FILTER (WHERE p.kind = 'refund'), 0)::numeric AS period_refunds_amount,
                 COALESCE(sum(CASE WHEN p.kind = 'refund' THEN -p.amount ELSE p.amount END), 0)::numeric AS period_net_amount
          FROM billing_payments p CROSS JOIN bounds
          WHERE p.paid_on BETWEEN bounds.starts_on AND LEAST(bounds.ends_on, bounds.as_of_on)
            AND p.kind IN ('receipt', 'refund')
        )
        SELECT account_totals.*, booking_totals.*, period_totals.*, departure_quality.*, bounds.as_of_on
        FROM account_totals CROSS JOIN booking_totals CROSS JOIN period_totals
          CROSS JOIN departure_quality CROSS JOIN bounds
        """,
        [campaign.starts_on, campaign.ends_on, as_of]
      )

    row =
      Map.new(Enum.zip(columns, values), fn
        {key, %Decimal{} = value} ->
          {key, value |> Decimal.round(2) |> Decimal.to_string(:normal)}

        pair ->
          pair
      end)

    quality =
      Map.take(row, [
        "missing_final_accounts",
        "personal_accounts_missing_final",
        "bookings_without_accounts",
        "incomplete_allocation_bookings",
        "uncertain_departure_bookings"
      ])

    incomplete = Enum.any?(quality, fn {_key, count} -> count > 0 end)

    unavailable =
      (row["settlement_bookings_count"] > 0 or row["uncertain_departure_bookings"] > 0) and
        row["settlement_final_accounts_count"] == 0

    departure_status =
      cond do
        row["uncertain_departure_bookings"] == 0 -> "complete"
        row["settlement_bookings_count"] == 0 -> "unavailable"
        true -> "partial"
      end

    metrics = Map.drop(row, Map.keys(quality) ++ ["as_of_on"])

    # Missing documents never become a verified zero. Mixed cohorts expose only
    # known issued amounts; quality preserves the unknown remainder separately.
    metrics =
      if unavailable do
        Map.merge(metrics, %{
          "settlement_billed_amount" => nil,
          "settlement_remaining_amount" => nil,
          "settlement_overpayment_amount" => nil
        })
      else
        metrics
      end

    metrics =
      if departure_status == "unavailable",
        do: Map.put(metrics, "settlement_paid_amount", nil),
        else: metrics

    settlement_status =
      cond do
        unavailable -> "unavailable"
        incomplete -> "partial"
        true -> "complete"
      end

    metric_quality =
      Map.new(metrics, fn {key, _} ->
        completeness =
          cond do
            key in [
              "settlement_billed_amount",
              "settlement_remaining_amount",
              "settlement_overpayment_amount"
            ] ->
              settlement_status

            String.starts_with?(key, "settlement_") or key == "personal_accounts_count" ->
              departure_status

            true ->
              "complete"
          end

        {key, %{"completeness" => completeness}}
      end)

    %{
      "source" => "billing",
      "definition_version" => 1,
      "as_of" => DateTime.to_iso8601(as_of),
      "metrics" => metrics,
      "quality" =>
        Map.merge(quality, %{
          "completeness" => if(incomplete, do: "partial", else: "complete"),
          "settlement_amounts_status" => settlement_status,
          "metrics" => metric_quality
        }),
      "evidence" => %{
        "currency" => "CZK",
        "timezone" => "Europe/Prague",
        "starts_on" => Date.to_iso8601(campaign.starts_on),
        "ends_on" => Date.to_iso8601(campaign.ends_on),
        "as_of_on" => Date.to_iso8601(row["as_of_on"]),
        "source_state" => "current_records",
        "period_date_field" => "billing_payments.paid_on",
        "cohort_date_field" => "bookings.check_out_date",
        "boundaries" => "inclusive_campaign_dates_through_as_of_on",
        "settlement_amounts_scope" => "accounts_with_final",
        "settlement_paid_scope" => "all_cohort_accounts_all_dates_through_as_of_on",
        "uncertain_departure_scope" =>
          "Missing or reversed departure with arrival/departure or issued-document/payment date in the capped campaign period. These are candidates, not assigned season stays; unrelated undated records are not attributed to this season.",
        "definition" =>
          "Period receipts minus refunds are separate from settlement. Settlement uses the common booking departure, including cancelled/deleted bookings and issued history on deleted accounts. Final totals plus signed corrections directly parented to finals, less all payer receipts minus refunds through as_of_on. Advances, tax receipts and deduction snapshots are not additional billed amounts. Personal calculations are counts, never inferred amounts."
      }
    }
  end
end

defmodule CozyCheckout.Adventure.Sources.Bar do
  @moduledoc "Read-only current payment records, not order sales or a historical bank audit."

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
        )
        SELECT
          COALESCE(sum(p.amount) FILTER (WHERE NOT o.is_service_order), 0)::numeric AS received_amount,
          count(p.id) FILTER (WHERE NOT o.is_service_order) AS payment_count,
          COALESCE(sum(p.amount) FILTER (WHERE NOT o.is_service_order AND p.payment_method = 'cash'), 0)::numeric AS cash_received_amount,
          COALESCE(sum(p.amount) FILTER (WHERE NOT o.is_service_order AND p.payment_method = 'qr_code'), 0)::numeric AS qr_received_amount,
          COALESCE(sum(p.amount) FILTER (WHERE o.is_service_order), 0)::numeric AS service_received_amount,
          count(p.id) FILTER (WHERE o.is_service_order) AS service_payment_count,
          COALESCE(sum(p.amount) FILTER (WHERE o.is_service_order AND p.payment_method = 'cash'), 0)::numeric AS service_cash_received_amount,
          COALESCE(sum(p.amount) FILTER (WHERE o.is_service_order AND p.payment_method = 'qr_code'), 0)::numeric AS service_qr_received_amount,
          COALESCE(sum(p.amount), 0)::numeric AS total_received_amount,
          (SELECT as_of_on FROM bounds) AS as_of_on
        FROM payments p JOIN orders o ON o.id = p.order_id CROSS JOIN bounds
        WHERE p.deleted_at IS NULL
          AND p.payment_date BETWEEN bounds.starts_on AND LEAST(bounds.ends_on, bounds.as_of_on)
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

    metrics = Map.delete(row, "as_of_on")

    %{
      "source" => "bar",
      "definition_version" => 1,
      "as_of" => DateTime.to_iso8601(as_of),
      "metrics" => metrics,
      "quality" => %{
        "completeness" => "complete",
        "metrics" => Map.new(metrics, fn {key, _} -> {key, %{"completeness" => "complete"}} end)
      },
      "evidence" => %{
        "currency" => "CZK",
        "timezone" => "Europe/Prague",
        "starts_on" => Date.to_iso8601(campaign.starts_on),
        "ends_on" => Date.to_iso8601(campaign.ends_on),
        "as_of_on" => Date.to_iso8601(row["as_of_on"]),
        "source_state" => "current_records",
        "date_field" => "payments.payment_date",
        "boundaries" => "inclusive_campaign_dates_through_as_of_on",
        "headline_scope" => "non_service_orders",
        "definition" =>
          "Nondeleted payment amounts, including partial payments and tips actually paid. Service orders are separate. Deleted orders remain included. No allocation to goods, discounts or tips is inferred."
      }
    }
  end
end

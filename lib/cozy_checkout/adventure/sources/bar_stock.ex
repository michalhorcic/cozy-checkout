defmodule CozyCheckout.Adventure.Sources.BarStock do
  @moduledoc "Ephemeral read-only bar stock evidence; never a physical inventory or seasonal metric."
  alias CozyCheckout.{Adventure, Repo}

  def load do
    if Adventure.enabled?() do
      %{rows: rows} =
        Repo.query!("""
        SELECT p.name, p.unit, p.bar_stock_threshold, sum(m.quantity), count(m.id)
        FROM products p
        LEFT JOIN bar_stock_movements m ON m.product_id = p.id
        WHERE p.deleted_at IS NULL AND p.track_bar_stock = true
        GROUP BY p.id
        ORDER BY p.name, p.id
        """)

      products = Enum.map(rows, &project/1)
      {:ok, %{loaded_at: DateTime.utc_now(), products: products, tracked_count: length(products)}}
    else
      {:error, :disabled}
    end
  rescue
    _ in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, :unavailable}
  end

  def stale?(snapshot, now \\ DateTime.utc_now()),
    do: DateTime.diff(now, snapshot.loaded_at) >= 900

  defp project([name, unit, threshold, raw_stock, count]) do
    stock =
      cond do
        count == 0 -> nil
        unit in ["ml", "L", "cl"] -> Decimal.div(raw_stock, 1000)
        true -> raw_stock
      end

    threshold = if threshold && Decimal.compare(threshold, 0) == :gt, do: threshold

    status =
      cond do
        is_nil(stock) -> :unknown
        Decimal.compare(stock, 0) != :gt -> :out_of_stock
        threshold && Decimal.compare(stock, threshold) != :gt -> :low_stock
        is_nil(threshold) -> :no_limit
        true -> :in_stock
      end

    %{
      name: name,
      stock: stock,
      unit: if(unit in ["ml", "L", "cl"], do: "L", else: unit || "pcs"),
      threshold: threshold,
      status: status
    }
  end
end

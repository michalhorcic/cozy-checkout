defmodule CozyCheckout.Workers.AbraSyncWorker do
  @moduledoc """
  Oban worker that syncs a paid order to ABRA Flexi.
  Retries up to 5 times with exponential backoff. After final failure,
  marks the order as failed so staff can retry manually from the admin UI.
  """

  use Oban.Worker, queue: :abra_sync, max_attempts: 5

  alias CozyCheckout.{Abra, Sales}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}, attempt: attempt, max_attempts: max}) do
    Sales.increment_abra_sync_attempts(order_id)

    case Abra.sync_order(order_id) do
      {:ok, _abra_id} ->
        :ok

      {:error, reason} when attempt >= max ->
        Sales.mark_order_abra_failed(order_id, reason)
        {:cancel, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

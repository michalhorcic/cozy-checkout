defmodule CozyCheckout.Workers.IncomingBatchReconcileWorker do
  @moduledoc "Recover batch completion and terminated extraction jobs without calling AI."
  use Oban.Worker, queue: :incoming_extraction, max_attempts: 3, unique: [period: 60]

  @impl Oban.Worker
  def perform(_job), do: CozyCheckout.IncomingDocuments.Batches.reconcile()
end

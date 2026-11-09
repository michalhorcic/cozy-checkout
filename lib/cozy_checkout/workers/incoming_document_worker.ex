defmodule CozyCheckout.Workers.IncomingDocumentWorker do
  @moduledoc "Background extraction and reviewed delivery; retries of a write only verify its external ID."
  use Oban.Worker,
    queue: :billing,
    max_attempts: 3,
    unique: [
      period: :infinity,
      keys: [:document_id, :operation, :run_id],
      states: [:available, :scheduled, :retryable]
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"document_id" => id, "operation" => operation} = args,
        attempt: attempt,
        max_attempts: max
      }) do
    if operation == "extract",
      do: CozyCheckout.IncomingDocuments.perform_extraction(id, args["run_id"], attempt),
      else: CozyCheckout.IncomingDocuments.perform(id, operation)
  rescue
    exception ->
      record_failure(id, operation, args["run_id"], exception, attempt, max)
      # Do not place XML, original data, provider responses or credentials into Oban error logs.
      {:error, "Operace přijatého dokladu byla přerušena"}
  end

  defp record_failure(id, "extract", run_id, exception, _attempt, _max) when is_binary(run_id) do
    CozyCheckout.IncomingDocuments.ExtractionRuns.worker_exception(id, run_id, exception)
  rescue
    # A database outage may also prevent recording the failure. Keep Oban errors private;
    # its retry will inspect the persisted reservation before any further paid call.
    _ -> :ok
  end

  defp record_failure(id, operation, _run_id, _exception, attempt, max) do
    if attempt >= max, do: CozyCheckout.IncomingDocuments.worker_failed(id, operation)
  rescue
    _ -> :ok
  end
end

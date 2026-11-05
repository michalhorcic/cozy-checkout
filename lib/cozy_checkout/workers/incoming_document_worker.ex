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
    _ ->
      if attempt >= max do
        if operation == "extract" and is_binary(args["run_id"]),
          do: CozyCheckout.IncomingDocuments.ExtractionRuns.interrupt(id, args["run_id"]),
          else: CozyCheckout.IncomingDocuments.worker_failed(id, operation)
      end

      # Do not place XML, original data, provider responses or credentials into Oban error logs.
      {:error, "Operace přijatého dokladu byla přerušena"}
  end
end

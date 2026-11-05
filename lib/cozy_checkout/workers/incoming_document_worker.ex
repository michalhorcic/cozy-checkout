defmodule CozyCheckout.Workers.IncomingDocumentWorker do
  @moduledoc "Background extraction and reviewed delivery; retries of a write only verify its external ID."
  use Oban.Worker,
    queue: :billing,
    max_attempts: 3,
    unique: [
      period: :infinity,
      keys: [:document_id, :operation],
      states: [:available, :scheduled, :retryable]
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"document_id" => id, "operation" => operation},
        attempt: attempt,
        max_attempts: max
      }) do
    CozyCheckout.IncomingDocuments.perform(id, operation)
  rescue
    _ ->
      if attempt >= max, do: CozyCheckout.IncomingDocuments.worker_failed(id, operation)
      # Do not place XML, original data, provider responses or credentials into Oban error logs.
      {:error, "Operace přijatého dokladu byla přerušena"}
  end
end

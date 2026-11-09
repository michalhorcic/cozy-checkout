defmodule CozyCheckout.Workers.IncomingDocumentAttachmentWorker do
  @moduledoc "Upload or reconcile a source attachment; never writes an accounting document."
  use Oban.Worker,
    queue: :abra_pdf,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:document_id, :delivery_id],
      states: [:available, :scheduled, :retryable, :executing]
    ]

  @impl Oban.Worker
  def perform(
        %Oban.Job{args: %{"document_id" => id, "delivery_id" => delivery_id}, attempt: attempt} =
          job
      ) do
    CozyCheckout.IncomingDocuments.SourceAttachments.deliver(job)
  rescue
    _ ->
      record_failure(id, delivery_id, attempt)
      {:error, "Přenos přílohy přijatého dokladu byl přerušen"}
  end

  defp record_failure(id, delivery_id, attempt) do
    CozyCheckout.IncomingDocuments.SourceAttachments.worker_failed(id, delivery_id, attempt)
  rescue
    _ -> :ok
  end
end

defmodule CozyCheckout.Workers.BillingPdfWorker do
  use Oban.Worker,
    queue: :billing,
    max_attempts: 5,
    unique: [period: 60, fields: [:worker, :args]]

  def perform(%Oban.Job{args: %{"document_id" => id}}) do
    case CozyCheckout.Billing.ensure_pdf(id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end

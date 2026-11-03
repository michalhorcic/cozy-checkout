defmodule CozyCheckout.Workers.AbraPdfWorker do
  use Oban.Worker,
    queue: :abra_pdf,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:transfer_id], states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"transfer_id" => id}}),
    do: CozyCheckout.Abra.PdfAttachments.deliver(id)
end

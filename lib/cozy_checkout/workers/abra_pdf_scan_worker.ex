defmodule CozyCheckout.Workers.AbraPdfScanWorker do
  use Oban.Worker, queue: :abra_pdf, max_attempts: 3, unique: [period: 60, fields: [:worker]]

  @impl Oban.Worker
  def perform(_job), do: CozyCheckout.Abra.PdfAttachments.scan()
end

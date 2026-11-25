defmodule CozyCheckout.Workers.AbraPaymentStatusWorker do
  use Oban.Worker,
    queue: :abra_sync,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :args], states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}),
    do: CozyCheckout.Abra.PaymentStatus.sync(args["booking_id"])
end

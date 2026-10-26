defmodule CozyCheckout.Workers.AbraBankPaymentWorker do
  use Oban.Worker,
    queue: :abra_sync,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:confirmation_id], states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"confirmation_id" => id}, attempt: attempt, max_attempts: max}) do
    CozyCheckout.Abra.BankPaymentSync.sync(id, attempt >= max)
  end
end

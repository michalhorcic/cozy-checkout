defmodule CozyCheckout.Workers.AbraAccommodationWorker do
  @moduledoc "Retryable delivery of immutable accommodation exports, independent of bar orders."
  use Oban.Worker,
    queue: :abra_sync,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:export_id],
      states: :incomplete
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"export_id" => id}, attempt: attempt, max_attempts: max}) do
    CozyCheckout.Abra.Accommodation.sync(id, attempt >= max)
  rescue
    exception ->
      CozyCheckout.Abra.Accommodation.worker_failed(id, attempt >= max)
      reraise exception, __STACKTRACE__
  end
end

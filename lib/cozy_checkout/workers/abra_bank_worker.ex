defmodule CozyCheckout.Workers.AbraBankWorker do
  @moduledoc "Periodic and manually requested read-only bank import."
  use Oban.Worker,
    queue: :abra_sync,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: CozyCheckout.Abra.Bank.sync()
end

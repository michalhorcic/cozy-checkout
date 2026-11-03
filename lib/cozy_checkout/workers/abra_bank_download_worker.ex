defmodule CozyCheckout.Workers.AbraBankDownloadWorker do
  @moduledoc "Hourly online statement download, followed by a bank mirror refresh."
  use Oban.Worker,
    queue: :abra_sync,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  alias CozyCheckout.Abra.Bank

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Bank.enabled?() do
      with :ok <- Bank.download_statements(),
           {:ok, _job} <- Bank.enqueue() do
        :ok
      end
    else
      :ok
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{}), do: 15 * 60
end

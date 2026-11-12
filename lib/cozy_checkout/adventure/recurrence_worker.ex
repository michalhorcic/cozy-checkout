defmodule CozyCheckout.Adventure.RecurrenceWorker do
  @moduledoc "Hourly recurrence refresh; disabled Adventure performs no reads or writes."
  use Oban.Worker, queue: :adventure, max_attempts: 3, unique: [period: 60]

  @impl Oban.Worker
  def perform(_job) do
    case CozyCheckout.Adventure.Templates.generate() do
      {:ok, _} -> :ok
      {:error, :disabled} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

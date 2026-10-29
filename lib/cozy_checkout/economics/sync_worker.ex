defmodule CozyCheckout.Economics.SyncWorker do
  @moduledoc "Independent daily and manual reporting imports. Disabled configuration performs no HTTP."
  use Oban.Worker,
    queue: :economics_sync,
    max_attempts: 5,
    unique: [period: :infinity, states: :incomplete, keys: [:source_key, :period]]

  alias CozyCheckout.Economics.{Config, Sync}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    if Config.enabled?() do
      with {:ok, cfg} <- Config.connection() do
        key =
          cfg
          |> Config.identity()
          |> :erlang.term_to_binary()
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)

        if args["source_key"] && args["source_key"] != key do
          {:cancel, "Reporting source changed"}
        else
          result = if args["period"], do: Sync.run(args["period"]), else: Sync.scheduled()

          case result do
            {:ok, _} -> :ok
            other -> other
          end
        end
      end
    else
      :ok
    end
  end
end

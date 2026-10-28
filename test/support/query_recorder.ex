defmodule CozyCheckout.QueryRecorder do
  @moduledoc false

  def record(fun, caller \\ self()) do
    {:ok, recorder} = Agent.start_link(fn -> [] end)
    id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        id,
        [:cozy_checkout, :repo, :query],
        &__MODULE__.handle_query/4,
        {caller, recorder}
      )

    try do
      result = fun.()
      {result, Agent.get(recorder, &Enum.reverse/1)}
    after
      :telemetry.detach(id)
      Agent.stop(recorder)
    end
  end

  def handle_query(_, _, metadata, {caller, recorder}) do
    if self() == caller, do: Agent.update(recorder, &[metadata.query | &1])
  end
end

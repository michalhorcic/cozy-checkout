defmodule CozyCheckoutWeb.AdminAuthRateLimiter do
  use GenServer

  @max_attempts 5
  @attempt_window_seconds 300
  @lockout_seconds 60
  @retain_seconds 3_600

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  def allowed?(key), do: GenServer.call(__MODULE__, {:allowed?, key})
  def record_failure(key), do: GenServer.call(__MODULE__, {:record_failure, key})
  def reset(key), do: GenServer.call(__MODULE__, {:reset, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:allowed?, key}, _from, state) do
    now = System.system_time(:second)
    entry = Map.get(state, key)
    state = prune(state, now)
    {:reply, is_nil(entry) or entry.locked_until <= now, state}
  end

  def handle_call({:record_failure, key}, _from, state) do
    now = System.system_time(:second)
    state = prune(state, now)
    entry = Map.get(state, key)

    entry =
      if is_nil(entry) or now - entry.window_started_at >= @attempt_window_seconds do
        %{failures: 1, window_started_at: now, locked_until: 0, updated_at: now}
      else
        failures = entry.failures + 1

        %{
          entry
          | failures: failures,
            locked_until: if(failures >= @max_attempts, do: now + @lockout_seconds, else: 0),
            updated_at: now
        }
      end

    {:reply, :ok, Map.put(state, key, entry)}
  end

  def handle_call({:reset, key}, _from, state) do
    {:reply, :ok, Map.delete(state, key)}
  end

  defp prune(state, now) do
    Map.reject(state, fn {_key, entry} -> now - entry.updated_at > @retain_seconds end)
  end
end

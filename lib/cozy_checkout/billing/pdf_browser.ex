defmodule CozyCheckout.Billing.PdfBrowser do
  @moduledoc "Lazy Chrome lifecycle with a dedicated profile, separate from the user's open browser."
  use GenServer
  require Logger

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def print_to_pdf(source, opts) do
    GenServer.call(__MODULE__, {:print, source, opts}, 55_000)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    profile = Path.join(System.tmp_dir!(), "cozy-checkout-pdf-#{Ecto.UUID.generate()}")
    File.mkdir_p!(profile)
    File.chmod!(profile, 0o700)
    # Chrome 136+ requires a non-default profile for remote-debugging-pipe.
    # A single browser owns this profile; requests are serialized through this server.
    args = "--user-data-dir=" <> shell_quote(profile)

    config =
      opts
      |> Keyword.put(:on_demand, false)
      |> Keyword.put(:chrome_args, append: args)
      |> Keyword.put(:session_pool,
        size: 1,
        init_timeout: 15_000,
        timeout: 30_000,
        checkout_timeout: 15_000
      )

    {:ok, %{profile: profile, config: config, browser: nil}}
  end

  @impl true
  def handle_call({:print, source, opts}, _from, state) do
    case start_browser(state) do
      {:ok, state} ->
        result = protect(fn -> ChromicPDF.print_to_pdf(source, opts) end)
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{browser: pid} = state) do
    Logger.warning("Billing Chrome stopped: #{Exception.format_exit(reason)}")
    {:noreply, %{state | browser: nil}}
  end

  # Includes partial browser startups that returned an error instead of a child PID.
  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.browser && Process.alive?(state.browser) do
      protect(fn -> Supervisor.stop(state.browser, :normal, 4_000) end)
    end

    File.rm_rf(state.profile)
    :ok
  end

  defp start_browser(%{browser: pid} = state) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, state}, else: start_browser(%{state | browser: nil})
  end

  defp start_browser(state) do
    case protect(fn -> ChromicPDF.start_link(state.config) end) do
      {:ok, pid} -> {:ok, %{state | browser: pid}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp protect(fun) do
    try do
      fun.()
    rescue
      exception -> {:error, Exception.message(exception)}
    catch
      :exit, reason -> {:error, Exception.format_exit(reason)}
    end
  end

  defp shell_quote(path), do: "'" <> String.replace(path, "'", "'\\''") <> "'"
end

defmodule CozyCheckout.Economics.Sync do
  @moduledoc "Build off-line, reconcile each month, then atomically replace the active report."
  import Ecto.Query
  alias CozyCheckout.Repo
  alias CozyCheckout.Economics.{AbraClient, Config, Reports, Source, ImportRun, Snapshot}

  def run(code \\ "current") do
    with {:ok, cfg} <- Config.connection(),
         {:ok, source} <- source(cfg) do
      started = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, run} =
        Repo.transaction(fn ->
          locked = Repo.one!(from s in Source, where: s.id == ^source.id, lock: "FOR UPDATE")

          Repo.update_all(
            from(r in ImportRun, where: r.source_id == ^source.id and r.state == "running"),
            set: [
              state: "failed",
              error: "superseded_import",
              completed_at: started,
              updated_at: started
            ]
          )

          generation = locked.generation + 1
          locked |> Ecto.Changeset.change(generation: generation) |> Repo.update!()

          Repo.insert!(%ImportRun{
            source_id: source.id,
            period_code: code,
            state: "running",
            generation: generation,
            started_at: started
          })
        end)

      result =
        try do
          build(code)
        rescue
          _ -> {:error, :import_failed}
        end

      case result do
        {:ok, payload} -> publish(source, run, cfg, payload)
        {:error, reason} -> fail(run, reason)
      end
    end
  end

  def scheduled do
    with {:ok, cfg} <- Config.connection() do
      {base, company} = Config.identity(cfg)

      codes =
        Repo.all(
          from s in Snapshot,
            join: src in Source,
            on: src.id == s.source_id,
            where:
              src.base_url == ^base and src.company_id == ^company and is_nil(src.deleted_at) and
                s.active,
            select: s.period_code
        )

      with {:ok, current} <- run("current") do
        Enum.reduce_while(Enum.reject(codes, &(&1 == current.period_code)), :ok, fn code, _ ->
          case run(code) do
            {:ok, _} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      end
    end
  end

  defp source(cfg) do
    {base, company} = Config.identity(cfg)

    Repo.insert(%Source{base_url: base, company_id: company},
      on_conflict: :nothing,
      conflict_target: [:base_url, :company_id]
    )

    case Repo.one(
           from s in Source,
             where: s.base_url == ^base and s.company_id == ^company and is_nil(s.deleted_at)
         ) do
      nil -> {:error, :source_unavailable}
      source -> {:ok, source}
    end
  end

  defp build(code) do
    with {:ok, rows} <- AbraClient.periods(),
         {:ok, periods} <- Reports.periods(rows),
         {:ok, period} <- choose_period(periods, code),
         {:ok, catalog} <- AbraClient.accounts(),
         {:ok, months} <- months(period, catalog) do
      {:ok,
       %{
         "period" => period,
         "months" => months,
         "posting_state" => "posted",
         "mapping_version" => CozyCheckout.Economics.AccountMapping.version()
       }}
    end
  end

  defp choose_period(periods, code) do
    today = Date.to_iso8601(Date.utc_today())

    period =
      Enum.find(periods, fn p ->
        if code == "current", do: p["from"] <= today and p["to"] >= today, else: p["code"] == code
      end)

    cond do
      is_nil(period) ->
        {:error, :period_unavailable}

      period["from"] < "2026-07-01" or period["from"] > today ->
        {:error, :unsupported_period}

      Date.diff(Date.from_iso8601!(period["to"]), Date.from_iso8601!(period["from"])) > 730 ->
        {:error, :unsupported_period}

      true ->
        {:ok, period}
    end
  end

  defp months(period, catalog) do
    first = Date.from_iso8601!(period["from"])
    last = Date.from_iso8601!(period["to"])

    cutoff =
      min(Date.to_iso8601(last), Date.utc_today() |> Date.end_of_month() |> Date.to_iso8601())

    Stream.iterate(first, &Date.shift(&1, month: 1))
    |> Enum.take_while(&(Date.to_iso8601(&1) <= cutoff))
    |> Enum.reduce_while({:ok, []}, fn first, {:ok, acc} ->
      last = Date.end_of_month(first)

      with {:ok, posted} <- AbraClient.movements(first, last),
           {:ok, unposted} <- AbraClient.movements(first, last, "unposted"),
           {:ok, trial} <- AbraClient.trial_balance(period["code"], last, 1),
           {:ok, saldo} <- AbraClient.open_items(last),
           {:ok, month} <-
             Reports.month(period, first, last, catalog, posted, unposted, trial, saldo) do
        {:cont, {:ok, acc ++ [month]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp publish(source, run, cfg, payload) do
    # Prevent a configuration change during the HTTP phase from publishing under another source.
    with {:ok, current} <- Config.connection(),
         true <- Config.identity(current) == Config.identity(cfg) do
      result =
        Repo.transaction(fn ->
          locked = Repo.one!(from s in Source, where: s.id == ^source.id, lock: "FOR UPDATE")

          if locked.generation != run.generation or not is_nil(locked.deleted_at),
            do: Repo.rollback(:superseded_import)

          code = payload["period"]["code"]

          active =
            Repo.one(
              from s in Snapshot,
                where: s.source_id == ^source.id and s.period_code == ^code and s.active
            )

          if active && DateTime.compare(active.started_at, run.started_at) == :gt,
            do: Repo.rollback(:superseded_import)

          now = DateTime.utc_now() |> DateTime.truncate(:second)
          fingerprint = Reports.fingerprint(payload)

          snapshot =
            if active && active.fingerprint == fingerprint do
              active |> Ecto.Changeset.change(checked_at: now) |> Repo.update!()
            else
              Repo.update_all(
                from(s in Snapshot,
                  where: s.source_id == ^source.id and s.period_code == ^code and s.active
                ),
                set: [active: false, updated_at: now]
              )

              Repo.insert!(%Snapshot{
                source_id: source.id,
                import_run_id: run.id,
                period_code: code,
                payload: payload,
                fingerprint: fingerprint,
                started_at: run.started_at,
                checked_at: now
              })
            end

          run |> Ecto.Changeset.change(state: "succeeded", completed_at: now) |> Repo.update!()
          snapshot
        end)

      case result do
        {:ok, snapshot} -> {:ok, snapshot}
        {:error, reason} -> fail(run, reason)
      end
    else
      _ -> fail(run, :source_changed)
    end
  end

  defp fail(run, reason) do
    error =
      case reason do
        {:http, code} -> "http_#{code}"
        reason when is_atom(reason) -> to_string(reason)
        _ -> "import_failed"
      end

    run
    |> Ecto.Changeset.change(
      state: "failed",
      error: error,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    {:error, reason}
  end
end

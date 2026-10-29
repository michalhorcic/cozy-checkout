defmodule CozyCheckout.Economics do
  @moduledoc "Public entry point for isolated company reporting. UI reads local snapshots only."
  import Ecto.Query
  alias CozyCheckout.Repo

  alias CozyCheckout.Economics.{
    Config,
    Reports,
    Source,
    Snapshot,
    ImportRun,
    Confirmation,
    SyncWorker
  }

  @zero Decimal.new(0)

  def enabled?, do: Config.enabled?()
  def mapping, do: CozyCheckout.Economics.AccountMapping.entries()

  def home_summary(today \\ Date.utc_today()) do
    with {:ok, source} <- current_source() do
      snapshots = Repo.all(from s in Snapshot, where: s.source_id == ^source.id and s.active)
      confirmations = Repo.all(from c in Confirmation, where: c.source_id == ^source.id)

      latest_run =
        Repo.one(
          from r in ImportRun,
            where: r.source_id == ^source.id,
            order_by: [desc: r.generation],
            limit: 1
        )

      {:ok, CozyCheckout.Economics.Attention.build(snapshots, confirmations, latest_run, today)}
    end
  end

  def connection_info do
    cfg = Config.get()
    uri = URI.parse(cfg[:base_url] || "")

    %{
      enabled: enabled?(),
      host: uri.host,
      company: cfg[:company_id],
      configured: match?({:ok, _}, Config.connection())
    }
  end

  def request_sync(code \\ "current") do
    with {:ok, cfg} <- Config.connection(),
         true <- is_binary(code) and byte_size(code) in 1..100 do
      key =
        cfg
        |> Config.identity()
        |> :erlang.term_to_binary()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      %{source_key: key, period: code} |> SyncWorker.new() |> Oban.insert()
    else
      false -> {:error, :invalid_period}
      error -> error
    end
  end

  def overview(params \\ %{}) do
    if Enum.all?(["period", "from", "to"], &(is_nil(params[&1]) or is_binary(params[&1]))) do
      do_overview(params)
    else
      {:error, :invalid_range}
    end
  end

  defp do_overview(params) do
    with {:ok, source} <- current_source() do
      periods =
        Repo.all(
          from s in Snapshot,
            where: s.source_id == ^source.id and s.active,
            order_by: [desc: fragment("?->'period'->>'from'", s.payload)],
            select: %{code: s.period_code, id: s.id}
        )

      code = params["period"] || (List.first(periods) || %{})[:code]

      snapshot =
        if code,
          do:
            Repo.one(
              from s in Snapshot,
                where: s.source_id == ^source.id and s.active and s.period_code == ^code
            )

      latest_run =
        Repo.one(
          from r in ImportRun,
            where: r.source_id == ^source.id,
            order_by: [desc: r.inserted_at, desc: r.generation],
            limit: 1
        )

      confirmations = Repo.all(from c in Confirmation, where: c.source_id == ^source.id)

      current_saldo =
        Repo.one(
          from s in Snapshot,
            where:
              s.source_id == ^source.id and s.active and
                not is_nil(fragment("?->'current_saldo'", s.payload)),
            order_by: [
              desc: fragment("?->'current_saldo'->>'date'", s.payload),
              desc: s.checked_at
            ],
            select: fragment("?->'current_saldo'", s.payload),
            limit: 1
        )

      report =
        if snapshot do
          select_report(snapshot, params, confirmations)
          |> Map.put(
            :current_saldo,
            CozyCheckout.Economics.Attention.saldo(current_saldo, Date.utc_today())
          )
        end

      {:ok,
       %{
         source: source,
         periods: periods,
         snapshot: snapshot,
         latest_run: latest_run,
         report: report
       }}
    end
  end

  def confirm_month(snapshot_id, month, evidence)
      when is_binary(snapshot_id) and is_binary(month) and is_binary(evidence) do
    with {:ok, source} <- current_source(),
         {:ok, date} <- Date.from_iso8601(month),
         true <- date.day == 1 and Date.compare(Date.end_of_month(date), Date.utc_today()) == :lt,
         true <- String.length(String.trim(evidence)) in 10..1000 do
      Repo.transaction(fn ->
        Repo.one!(from s in Source, where: s.id == ^source.id, lock: "FOR UPDATE")

        snapshot =
          Repo.one(
            from s in Snapshot,
              where: s.id == ^snapshot_id and s.source_id == ^source.id and s.active
          )

        if is_nil(snapshot), do: Repo.rollback(:snapshot_changed)
        data = Enum.find(snapshot.payload["months"], &(&1["from"] == month))
        if is_nil(data), do: Repo.rollback(:invalid_month)

        Repo.insert!(
          %Confirmation{
            source_id: source.id,
            snapshot_id: snapshot.id,
            month: date,
            fingerprint: Reports.fingerprint(data),
            evidence: String.trim(evidence)
          },
          on_conflict: :nothing,
          conflict_target: [:source_id, :month, :fingerprint]
        )
      end)
    else
      _ -> {:error, :invalid_confirmation}
    end
  end

  def confirm_month(_, _, _), do: {:error, :invalid_confirmation}

  def account_detail(params, code) do
    with {:ok, %{report: %{months: months} = report}} <- overview(params),
         rows when rows != [] <-
           Enum.flat_map(months, & &1["movements"]) |> Enum.filter(&(&1["account"] == code)) do
      {:ok, %{report: report, rows: rows, account: hd(rows)["name"], code: code}}
    else
      _ -> {:error, :account_unavailable}
    end
  end

  defp current_source do
    with {:ok, cfg} <- Config.connection() do
      {base, company} = Config.identity(cfg)

      case Repo.one(
             from s in Source,
               where: s.base_url == ^base and s.company_id == ^company and is_nil(s.deleted_at)
           ) do
        nil -> {:error, :not_imported}
        source -> {:ok, source}
      end
    end
  end

  defp select_report(snapshot, params, confirmations) do
    months = snapshot.payload["months"]
    first = params["from"] || String.slice(hd(months)["from"], 0, 7)
    last = params["to"] || String.slice(List.last(months)["from"], 0, 7)
    available = Enum.map(months, &String.slice(&1["from"], 0, 7))

    if first not in available or last not in available or first > last do
      %{error: :invalid_range, available: available}
    else
      selected =
        Enum.filter(
          months,
          &(String.slice(&1["from"], 0, 7) >= first and String.slice(&1["from"], 0, 7) <= last)
        )

      movements = Enum.flat_map(selected, & &1["movements"])

      accounts =
        movements
        |> Enum.filter(&(&1["kind"] in ["expense", "revenue"]))
        |> Enum.group_by(& &1["account"])
        |> Enum.map(fn {code, rows} ->
          meta = hd(rows)

          %{
            code: code,
            name: meta["name"],
            category: meta["category"],
            kind: meta["kind"],
            totals: Reports.totals(rows)
          }
        end)
        |> Enum.sort_by(& &1.code)

      confirmed =
        Enum.map(selected, fn data ->
          confirmation =
            Enum.find(
              confirmations,
              &(to_string(&1.month) == data["from"] and
                  &1.fingerprint == Reports.fingerprint(data))
            )

          %{
            month: data["from"],
            confirmed: not is_nil(confirmation),
            evidence: confirmation && confirmation.evidence,
            confirmed_at: confirmation && confirmation.inserted_at
          }
        end)

      closing = List.last(selected)

      balances =
        Enum.filter(closing["balances"], &String.starts_with?(&1["account"], ["211", "221"]))

      items = closing["open_items"]

      %{
        months: selected,
        available: available,
        from: first,
        to: last,
        accounts: accounts,
        totals: Reports.totals(movements),
        balances: balances,
        ledger_totals:
          Map.new(["211", "221"], fn prefix ->
            rows = Enum.filter(balances, &String.starts_with?(&1["account"], prefix))

            value =
              if rows != [],
                do:
                  Enum.reduce(rows, @zero, &Decimal.add(Reports.number!(&1["closing"]), &2))
                  |> Decimal.to_string(:normal)

            {prefix, value}
          end),
        open_items: items,
        open_totals: open_totals(items, closing["to"]),
        confirmations: confirmed,
        warnings: selected |> Enum.flat_map(& &1["warnings"]) |> Enum.uniq(),
        period: snapshot.payload["period"],
        snapshot_id: snapshot.id,
        checked_at: snapshot.checked_at,
        cost_categories: cost_categories(accounts)
      }
    end
  end

  defp cost_categories(accounts) do
    accounts
    |> Enum.filter(&(&1.kind == "expense"))
    |> Enum.group_by(& &1.category)
    |> Enum.map(fn {category, rows} ->
      amount = Enum.reduce(rows, @zero, &Decimal.add(Reports.number!(&1.totals["expense"]), &2))
      %{category: category, amount: Decimal.to_string(amount, :normal), accounts: rows}
    end)
    |> Enum.sort(fn a, b ->
      Decimal.compare(Reports.number!(a.amount), Reports.number!(b.amount)) != :lt
    end)
  end

  defp open_totals(items, date) do
    if Enum.any?(items, &is_nil(&1["amount"])) do
      nil
    else
      for kind <- ["receivable", "payable"], into: %{} do
        selected = Enum.filter(items, &(&1["kind"] == kind))
        # Credits remain separate; unrelated debts are never netted against one another.
        {kind,
         %{
           "due" =>
             sum_items(
               selected,
               &(Decimal.positive?(Reports.number!(&1["amount"])) and not is_nil(&1["due"]) and
                   &1["due"] < date)
             ),
           "total" => sum_items(selected, &Decimal.positive?(Reports.number!(&1["amount"]))),
           "credits" => sum_items(selected, &Decimal.negative?(Reports.number!(&1["amount"])))
         }}
      end
    end
  end

  defp sum_items(items, predicate),
    do:
      items
      |> Enum.filter(predicate)
      |> Enum.reduce(@zero, &Decimal.add(Reports.number!(&1["amount"]), &2))
      |> Decimal.to_string(:normal)
end

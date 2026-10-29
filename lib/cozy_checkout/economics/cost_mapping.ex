defmodule CozyCheckout.Economics.CostMapping do
  @moduledoc false
  import Ecto.Query
  alias CozyCheckout.{Economics, Repo}

  alias CozyCheckout.Economics.{
    CostMappingVersion,
    CostRule,
    CostOverride,
    Costs,
    Source,
    Snapshot
  }

  @salt "economics-cost-preview-v1"
  @rule_fields ~w(account partner_id description_contains valid_from valid_to behavior extraordinary fixed_percent reason)a
  @override_fields ~w(account module document_id month fingerprint behavior extraordinary fixed_percent reason)a

  def workspace(params) do
    if Enum.all?(
         ["snapshot", "period", "version", "from", "to"],
         &(is_nil(params[&1]) or is_binary(params[&1]))
       ) do
      do_workspace(params)
    else
      {:error, :invalid_range}
    end
  end

  defp do_workspace(params) do
    with {:ok, source} <- Economics.current_source() do
      snapshots =
        Repo.all(
          from s in Snapshot,
            where: s.source_id == ^source.id,
            order_by: [desc: s.checked_at, desc: s.id],
            select: %{
              id: s.id,
              period_code: s.period_code,
              active: s.active,
              checked_at: s.checked_at
            }
        )

      versions =
        Repo.all(
          from v in CostMappingVersion,
            where: v.source_id == ^source.id and v.state != "draft",
            order_by: [desc: v.number]
        )

      active = Enum.find(versions, &(&1.state == "active"))

      selected_version =
        case params["version"] do
          value when value in [nil, ""] -> active
          "none" -> nil
          id -> Enum.find(versions, &(&1.id == id))
        end

      selected =
        if params["snapshot"] in [nil, ""],
          do:
            Enum.find(
              snapshots,
              &(&1.active and (is_nil(params["period"]) or &1.period_code == params["period"]))
            ),
          else: Enum.find(snapshots, &(&1.id == params["snapshot"]))

      cond do
        params["version"] not in [nil, "", "none"] and is_nil(selected_version) ->
          {:error, :invalid_version}

        is_nil(selected) ->
          {:error, :not_imported}

        true ->
          snapshot = Repo.get!(Snapshot, selected.id)
          report = Economics.report_for_snapshot(snapshot, params)

          if report[:error] do
            {:error, :invalid_range}
          else
            {rules, overrides} = entries(selected_version)
            # Include other fiscal periods when checking whether an override target
            # disappeared. A valid target in another snapshot is not an orphan.
            reference =
              active_snapshots(source.id)
              |> Enum.reject(&(&1.period_code == snapshot.period_code))

            months =
              snapshot.payload["months"] ++ Enum.flat_map(reference, & &1.payload["months"])

            result = Costs.classify(months, rules, overrides)

            items =
              Enum.filter(
                result.items,
                &(String.slice(&1.month, 0, 7) >= report.from and
                    String.slice(&1.month, 0, 7) <= report.to)
              )

            {:ok,
             %{
               source: source,
               snapshots: snapshots,
               snapshot: snapshot,
               versions: versions,
               version: selected_version,
               active_version: active,
               rules: rules,
               overrides: overrides,
               report: report,
               items: items,
               totals: Costs.totals(items),
               monthly:
                 Enum.map(report.months, fn month ->
                   %{
                     month: month["from"],
                     totals: Costs.totals(Enum.filter(items, &(&1.month == month["from"])))
                   }
                 end),
               categories: categories(items),
               accounts: accounts([snapshot]),
               missing_overrides:
                 Enum.filter(result.missing_overrides, fn override ->
                   month = to_string(override.month)

                   (month >= snapshot.payload["period"]["from"] and
                      month <= snapshot.payload["period"]["to"]) or
                     Enum.any?(
                       items,
                       &({&1.module, &1.document_id, &1.account} ==
                           {override.module, override.document_id, override.account})
                     )
                 end)
             }}
          end
      end
    end
  end

  defp categories(items) do
    items
    |> Enum.group_by(& &1.category)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {category, rows} ->
      firms =
        rows
        |> Enum.group_by(fn item ->
          ids = Enum.map(item.rows, &get_in(&1, ["identification", "partner_id"])) |> Enum.uniq()
          if length(ids) == 1 and hd(ids), do: {:partner, hd(ids)}, else: {:document, item.key}
        end)
        |> Enum.map(fn {_, docs} ->
          %{
            name: get_in(hd(hd(docs).rows), ["identification", "company"]) || "Firma neuvedena",
            totals: Costs.totals(docs),
            count: length(docs)
          }
        end)
        |> Enum.sort_by(& &1.name)

      %{name: category, totals: Costs.totals(rows), firms: firms}
    end)
  end

  def entries(nil), do: {[], []}

  def entries(version) do
    # Two bounded queries for the complete version, independent of document count.
    {Repo.all(
       from r in CostRule,
         where: r.version_id == ^version.id and is_nil(r.deleted_at),
         order_by: r.id
     ),
     Repo.all(
       from o in CostOverride,
         where: o.version_id == ^version.id and is_nil(o.deleted_at),
         order_by: o.id
     )}
  end

  def rule_attrs(rule), do: attrs(rule, @rule_fields)
  def override_attrs(override), do: attrs(override, @override_fields)

  defp attrs(struct, fields) do
    Map.new(fields, fn field ->
      value = Map.fetch!(struct, field)

      value =
        case value do
          %Date{} -> to_string(value)
          %Decimal{} -> Decimal.to_string(value, :normal)
          other -> other
        end

      {to_string(field), value}
    end)
  end

  def preview(rule_attrs, override_attrs, note, expected_base)
      when is_list(rule_attrs) and is_list(override_attrs) and is_binary(note) do
    with {:ok, source} <- Economics.current_source(),
         {:ok, rules} <- validate(rule_attrs, CostRule),
         {:ok, overrides} <- validate(override_attrs, CostOverride),
         true <- String.length(String.trim(note)) in 1..1000 do
      active = active_version(source.id)

      if %{source_id: source.id, version_id: version_id(active)} != expected_base do
        {:error, :stale_preview}
      else
        snapshots = active_snapshots(source.id)

        {old_rules, old_overrides} = entries(active)

        with :ok <- validate_targets(snapshots, rules, overrides, old_rules, old_overrides) do
          months = Enum.flat_map(snapshots, & &1.payload["months"])
          previous = Costs.classify(months, old_rules, old_overrides)
          proposed = Costs.classify(months, rules, overrides)
          previous_by_month = Enum.group_by(previous.items, & &1.month)
          proposed_by_month = Enum.group_by(proposed.items, & &1.month)

          impacts =
            Enum.map(snapshots, fn snapshot ->
              dates = Enum.map(snapshot.payload["months"], & &1["from"])
              before = %{items: Enum.flat_map(dates, &Map.get(previous_by_month, &1, []))}
              after_result = %{items: Enum.flat_map(dates, &Map.get(proposed_by_month, &1, []))}
              before_items = Map.new(before.items, &{&1.key, &1})

              changed =
                Enum.filter(after_result.items, fn item ->
                  interpretation(item) != interpretation(before_items[item.key])
                end)

              %{
                snapshot_id: snapshot.id,
                period: snapshot.period_code,
                before: Costs.totals(before.items),
                after: Costs.totals(after_result.items),
                changed: changed,
                months:
                  Enum.map(snapshot.payload["months"], fn month ->
                    rows_before = Map.get(previous_by_month, month["from"], [])
                    rows_after = Map.get(proposed_by_month, month["from"], [])

                    %{
                      month: month["from"],
                      before: Costs.totals(rows_before),
                      after: Costs.totals(rows_after)
                    }
                  end),
                conflicts: Enum.count(after_result.items, &(&1.status == :conflict))
              }
            end)

          payload = %{
            source_id: source.id,
            base: version_id(active),
            snapshots: snapshot_signature(snapshots),
            rules: Enum.map(rules, &rule_attrs/1),
            overrides: Enum.map(overrides, &override_attrs/1),
            note: String.trim(note)
          }

          token = Phoenix.Token.sign(CozyCheckoutWeb.Endpoint, @salt, payload)
          {:ok, %{token: token, impacts: impacts, base: version_id(active)}}
        end
      end
    else
      false -> {:error, :invalid_note}
      error -> error
    end
  end

  def preview(_, _, _, _), do: {:error, :invalid_mapping}

  def publish(token) when is_binary(token) do
    with {:ok, payload} <-
           Phoenix.Token.verify(CozyCheckoutWeb.Endpoint, @salt, token, max_age: 3600),
         {:ok, source} <- Economics.current_source(),
         true <- payload.source_id == source.id do
      Repo.transaction(fn ->
        locked = Repo.one!(from s in Source, where: s.id == ^source.id, lock: "FOR UPDATE")
        if locked.deleted_at, do: Repo.rollback(:stale_preview)
        active = active_version(source.id)
        snapshots = active_snapshots(source.id)

        if version_id(active) != payload.base or
             snapshot_signature(snapshots) != payload.snapshots,
           do: Repo.rollback(:stale_preview)

        {:ok, rules} = validate(payload.rules, CostRule)
        {:ok, overrides} = validate(payload.overrides, CostOverride)

        {old_rules, old_overrides} = entries(active)

        case validate_targets(snapshots, rules, overrides, old_rules, old_overrides) do
          :ok -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end

        number =
          (Repo.one(
             from v in CostMappingVersion, where: v.source_id == ^source.id, select: max(v.number)
           ) || 0) + 1

        now = DateTime.utc_now() |> DateTime.truncate(:second)

        version =
          Repo.insert!(%CostMappingVersion{
            source_id: source.id,
            number: number,
            note: payload.note
          })

        insert_entries(rules, CostRule, version.id, now)
        insert_entries(overrides, CostOverride, version.id, now)
        if active, do: active |> Ecto.Changeset.change(state: "superseded") |> Repo.update!()
        version |> Ecto.Changeset.change(state: "active", published_at: now) |> Repo.update!()
      end)
    else
      _ -> {:error, :stale_preview}
    end
  end

  def publish(_), do: {:error, :stale_preview}

  def suggestions(months) do
    accounts = Costs.bundles(months) |> Enum.map(& &1.account) |> MapSet.new()

    for {account, behavior, reason} <- [
          {"501100", "variable",
           "Potraviny: návrh variabilního nákladu; nákup nemusí odpovídat spotřebě zásob."},
          {"502001", "mixed", "Energie: smíšené bez odhadu podílu."},
          {"501300", "variable", "Úklid a praní: ověřit, zda část není paušál."},
          {"518400", "variable", "Úklid a praní: ověřit, zda část není paušál."}
        ],
        MapSet.member?(accounts, account) do
      %{
        "account" => account,
        "behavior" => behavior,
        "reason" => reason,
        "extraordinary" => false,
        "valid_from" => hd(months)["from"]
      }
    end
  end

  defp validate(rows, schema) do
    Enum.reduce_while(rows, {:ok, []}, fn attrs, {:ok, acc} ->
      case schema.changeset(struct(schema), attrs) |> Ecto.Changeset.apply_action(:insert) do
        {:ok, row} -> {:cont, {:ok, [row | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp accounts(snapshots) do
    snapshots
    |> Enum.flat_map(fn snapshot ->
      snapshot.payload["cost_accounts"] ||
        Enum.map(
          Costs.bundles(snapshot.payload["months"]),
          &%{"account" => &1.account, "name" => &1.name, "category" => &1.category}
        )
    end)
    |> Enum.uniq_by(& &1["account"])
    |> Enum.sort_by(& &1["account"])
  end

  defp validate_targets(snapshots, rules, overrides, old_rules, old_overrides) do
    bundles = Enum.flat_map(snapshots, &Costs.bundles(&1.payload["months"]))
    accounts = MapSet.new(accounts(snapshots), & &1["account"])
    old_targets = MapSet.new(old_overrides, &{Costs.override_key(&1), &1.fingerprint})
    targets = MapSet.new(bundles, &{&1.key, &1.fingerprint})
    old_rule_targets = MapSet.new(old_rules, &{&1.account, &1.partner_id})

    partners =
      Enum.flat_map(bundles, fn b ->
        Enum.map(b.rows, &get_in(&1, ["identification", "partner_id"]))
      end)
      |> MapSet.new()

    keys = Enum.map(overrides, &Costs.override_key/1)

    cond do
      Enum.any?(
        rules,
        &(not MapSet.member?(accounts, &1.account) and
              not MapSet.member?(old_rule_targets, {&1.account, &1.partner_id}))
      ) ->
        {:error, :invalid_account}

      Enum.any?(
        rules,
        &((&1.partner_id && not MapSet.member?(partners, &1.partner_id)) and
              not MapSet.member?(old_rule_targets, {&1.account, &1.partner_id}))
      ) ->
        {:error, :invalid_partner}

      length(Enum.uniq(keys)) != length(keys) ->
        {:error, :duplicate_override}

      Enum.any?(overrides, fn override ->
        target = {Costs.override_key(override), override.fingerprint}
        not MapSet.member?(targets, target) and not MapSet.member?(old_targets, target)
      end) ->
        {:error, :invalid_override}

      # Existing stale/missing overrides are deliberately retained until explicitly reviewed.
      true ->
        :ok
    end
  end

  defp insert_entries(rows, schema, version, now) do
    fields = schema.__schema__(:fields) -- [:__meta__]

    values =
      Enum.map(rows, fn row ->
        row
        |> Map.from_struct()
        |> Map.take(fields)
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          version_id: version,
          inserted_at: now,
          updated_at: now
        })
      end)

    if values != [], do: Repo.insert_all(schema, values)
  end

  defp interpretation(item),
    do:
      {item.behavior, item.extraordinary, item.status, item.estimated, item.fixed, item.variable,
       Enum.map(item.matches, & &1.reason)}

  defp active_snapshots(source),
    do: Repo.all(from s in Snapshot, where: s.source_id == ^source and s.active, order_by: s.id)

  defp snapshot_signature(snapshots), do: Enum.map(snapshots, &{&1.id, &1.fingerprint})

  defp active_version(source),
    do:
      Repo.one(
        from v in CostMappingVersion, where: v.source_id == ^source and v.state == "active"
      )

  defp version_id(nil), do: nil
  defp version_id(version), do: version.id
end

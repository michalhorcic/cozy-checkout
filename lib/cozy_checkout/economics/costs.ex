defmodule CozyCheckout.Economics.Costs do
  @moduledoc "Pure classification of expense postings; never reads the database or ABRA."
  alias CozyCheckout.Economics.Reports
  @zero Decimal.new(0)
  @buckets [:fixed, :variable, :mixed, :unclassified]

  def bundles(months) do
    months
    |> Enum.flat_map(fn month ->
      month["movements"]
      |> Enum.filter(&(&1["kind"] == "expense"))
      |> Enum.group_by(&{&1["module"], &1["document_id"], &1["account"]})
      |> Enum.map(fn {{module, document, account}, rows} ->
        rows = Enum.sort(rows)

        %{
          key: {module, document, account, month["from"]},
          module: module,
          document_id: document,
          account: account,
          month: month["from"],
          name: hd(rows)["name"],
          category: hd(rows)["category"],
          rows: rows,
          amount: Enum.reduce(rows, @zero, &Decimal.add(amount(&1), &2)),
          fingerprint:
            Reports.fingerprint(
              Enum.map(
                rows,
                &Map.take(&1, [
                  "module",
                  "document_id",
                  "account",
                  "journal_id",
                  "date",
                  "md",
                  "dal",
                  "currency"
                ])
              )
              |> Enum.sort()
            ),
          noncash: String.starts_with?(account, "551")
        }
      end)
    end)
    |> Enum.sort_by(& &1.key)
  end

  def classify(months, rules, overrides) do
    bundles = bundles(months)
    keys = MapSet.new(bundles, & &1.key)
    overrides = Enum.reject(overrides, & &1.deleted_at)
    by_key = Map.new(overrides, &{override_key(&1), &1})
    missing = Enum.reject(overrides, &MapSet.member?(keys, override_key(&1)))
    moved = Enum.group_by(missing, &{&1.module, &1.document_id})
    rules = Enum.reject(rules, & &1.deleted_at) |> Enum.group_by(& &1.account)

    items =
      Enum.map(bundles, fn bundle ->
        override = by_key[bundle.key]

        cond do
          override && override.fingerprint != bundle.fingerprint ->
            unresolved(bundle, :stale_override, [override])

          override ->
            assigned(bundle, override, :override, [override])

          Map.has_key?(moved, {bundle.module, bundle.document_id}) ->
            unresolved(
              bundle,
              :moved_override,
              moved[{bundle.module, bundle.document_id}]
            )

          true ->
            apply_rules(bundle, Map.get(rules, bundle.account, []))
        end
      end)

    %{items: items, missing_overrides: missing, totals: totals(items)}
  end

  def override_key(override),
    do: {override.module, override.document_id, override.account, to_string(override.month)}

  defp apply_rules(bundle, rules) do
    matching = Enum.filter(rules, &matches?(&1, bundle))
    highest = Enum.map(matching, &priority/1) |> Enum.max(fn -> 0 end)

    winners =
      Enum.filter(matching, &(priority(&1) == highest)) |> Enum.sort_by(&{&1.reason, &1.id})

    case Enum.uniq_by(winners, &result/1) do
      [] -> unresolved(bundle, :unclassified, [])
      [rule] -> assigned(bundle, rule, :rule, winners)
      _ -> unresolved(bundle, :conflict, winners)
    end
  end

  defp matches?(rule, bundle) do
    month = Date.from_iso8601!(bundle.month)
    infos = Enum.map(bundle.rows, &(&1["identification"] || %{}))

    Date.compare(month, rule.valid_from) != :lt and
      (is_nil(rule.valid_to) or Date.compare(month, rule.valid_to) != :gt) and
      (is_nil(rule.partner_id) or
         Enum.uniq(Enum.map(infos, & &1["partner_id"])) == [rule.partner_id]) and
      (is_nil(rule.description_contains) or
         Enum.any?(infos, fn info ->
           String.contains?(
             String.downcase(info["description"] || ""),
             String.downcase(rule.description_contains)
           )
         end))
  end

  defp priority(%{partner_id: p, description_contains: d}) do
    case {not is_nil(p), not is_nil(d)} do
      {true, true} -> 4
      {true, false} -> 3
      {false, true} -> 2
      _ -> 1
    end
  end

  defp result(rule),
    do:
      {rule.behavior, rule.extraordinary,
       rule.fixed_percent && Decimal.to_string(Decimal.normalize(rule.fixed_percent), :normal)}

  defp assigned(bundle, rule, via, matches) do
    {fixed, variable, mixed, unclassified} =
      case {rule.behavior, rule.fixed_percent} do
        {"fixed", _} ->
          {bundle.amount, @zero, @zero, @zero}

        {"variable", _} ->
          {@zero, bundle.amount, @zero, @zero}

        {"mixed", nil} ->
          {@zero, @zero, bundle.amount, @zero}

        {"mixed", percent} ->
          fixed = Decimal.div(Decimal.mult(bundle.amount, percent), 100)
          {fixed, Decimal.sub(bundle.amount, fixed), @zero, @zero}

        _ ->
          {@zero, @zero, @zero, bundle.amount}
      end

    Map.merge(bundle, %{
      behavior: rule.behavior,
      extraordinary: rule.extraordinary,
      estimated: rule.behavior == "mixed" and not is_nil(rule.fixed_percent),
      status: if(rule.behavior == "unclassified", do: :unclassified, else: :classified),
      via: via,
      matches: matches,
      fixed: fixed,
      variable: variable,
      mixed: mixed,
      unclassified: unclassified
    })
  end

  defp unresolved(bundle, status, matches) do
    Map.merge(bundle, %{
      behavior: "unclassified",
      extraordinary: false,
      estimated: false,
      status: status,
      via: nil,
      matches: matches,
      fixed: @zero,
      variable: @zero,
      mixed: @zero,
      unclassified: bundle.amount
    })
  end

  def totals(items) do
    sums =
      Map.new(
        @buckets ++ [:total, :extraordinary, :estimated, :absolute, :unresolved_volume],
        &{&1, @zero}
      )

    sums =
      Enum.reduce(items, sums, fn item, sums ->
        sums =
          Enum.reduce(@buckets, sums, fn bucket, acc ->
            Map.update!(acc, bucket, &Decimal.add(&1, item[bucket]))
          end)

        sums
        |> Map.update!(:total, &Decimal.add(&1, item.amount))
        |> Map.update!(:absolute, &Decimal.add(&1, Decimal.abs(item.amount)))
        |> Map.update!(
          :extraordinary,
          &Decimal.add(&1, if(item.extraordinary, do: item.amount, else: @zero))
        )
        |> Map.update!(
          :estimated,
          &Decimal.add(&1, if(item.estimated, do: item.amount, else: @zero))
        )
        |> Map.update!(
          :unresolved_volume,
          &Decimal.add(
            &1,
            if(item.status != :classified, do: Decimal.abs(item.amount), else: @zero)
          )
        )
      end)

    unresolved = Enum.count(items, &(&1.status != :classified))

    coverage =
      if Decimal.equal?(sums.absolute, 0),
        do: nil,
        else:
          Decimal.mult(
            Decimal.div(Decimal.sub(sums.absolute, sums.unresolved_volume), sums.absolute),
            100
          )

    Map.merge(sums, %{
      unresolved_count: unresolved,
      coverage: coverage,
      display: balanced_round(sums)
    })
  end

  # Rounding cumulative amounts allocates the remainder once, including negative credits.
  defp balanced_round(sums) do
    {display, _, _} =
      Enum.reduce(@buckets, {%{}, @zero, @zero}, fn bucket, {acc, exact, shown} ->
        exact = Decimal.add(exact, sums[bucket])
        rounded = Decimal.round(exact, 2)
        {Map.put(acc, bucket, Decimal.sub(rounded, shown)), exact, rounded}
      end)

    display
  end

  defp amount(row), do: Decimal.sub(Reports.number!(row["md"]), Reports.number!(row["dal"]))
end

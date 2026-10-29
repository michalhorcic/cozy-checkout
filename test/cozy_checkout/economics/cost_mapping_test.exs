defmodule CozyCheckout.Economics.CostMappingTest do
  use CozyCheckout.DataCase, async: false
  import CozyCheckout.EconomicsFixtures
  alias CozyCheckout.{Economics, Repo}

  alias CozyCheckout.Economics.{
    CostMappingVersion,
    CostRule,
    CostOverride,
    Costs,
    Config,
    Source,
    Snapshot,
    ImportRun,
    Reports
  }

  setup do
    previous = Application.get_env(:cozy_checkout, :economics)

    Application.put_env(:cozy_checkout, :economics,
      enabled: true,
      base_url: "https://accounting.test",
      company_id: "costs",
      username: "reader",
      password: "synthetic"
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cozy_checkout, :economics, previous),
        else: Application.delete_env(:cozy_checkout, :economics)
    end)

    source = Repo.insert!(%Source{base_url: "https://accounting.test", company_id: "costs"})
    snapshot = insert_snapshot(source)
    %{source: source, snapshot: snapshot, base: %{source_id: source.id, version_id: nil}}
  end

  defp insert_snapshot(source, active \\ true) do
    at = DateTime.utc_now() |> DateTime.truncate(:second)

    run =
      Repo.insert!(%ImportRun{
        source_id: source.id,
        period_code: "FY-TEST",
        state: "succeeded",
        generation: 0,
        started_at: at,
        completed_at: at
      })

    {:ok, month} =
      Reports.month(
        period(),
        ~D[2026-07-01],
        ~D[2026-07-31],
        catalog(),
        posted(),
        [],
        trial(),
        []
      )

    payload = %{
      "period" => period(),
      "months" => [month],
      "cost_accounts" => Reports.cost_accounts(catalog())
    }

    Repo.insert!(%Snapshot{
      source_id: source.id,
      import_run_id: run.id,
      period_code: "FY-TEST",
      active: active,
      payload: payload,
      fingerprint: Reports.fingerprint(payload),
      started_at: at,
      checked_at: at
    })
  end

  defp rule(attrs \\ %{}),
    do:
      Map.merge(
        %{
          "account" => "501100",
          "behavior" => "variable",
          "extraordinary" => false,
          "valid_from" => "2026-07-01",
          "reason" => "Potvrzené potraviny"
        },
        attrs
      )

  defp preview(base, rules \\ [rule()], overrides \\ []),
    do: Economics.preview_cost_mapping(rules, overrides, "Kontrola mapování s majitelem", base)

  defp equal(a, b), do: assert(Decimal.equal?(a, b))

  @tag :cost_preview_regression
  test "account rules without a partner can be previewed and published", %{base: base} do
    for partner <- [nil, ""] do
      assert {:ok, result} = preview(base, [rule(%{"partner_id" => partner})])
      assert [%{changed: [%{behavior: "variable"}]}] = result.impacts
    end

    assert {:ok, result} = preview(base, [rule()])
    assert {:ok, version} = Economics.publish_cost_mapping(result.token)
    assert version.state == "active"
    assert {:ok, %{rules: [%{partner_id: nil}]}} = Economics.costs()
  end

  test "preview is inactive; publication is atomic and repeatable only against its baseline", %{
    base: base,
    snapshot: snapshot
  } do
    assert {:ok, data} = Economics.costs()
    assert is_nil(data.version)
    equal(data.totals.unclassified, "45.50")
    assert {:ok, preview} = preview(base)
    assert Repo.aggregate(CostMappingVersion, :count) == 0
    assert [%{snapshot_id: id, changed: [changed]}] = preview.impacts
    assert id == snapshot.id and changed.account == "501100"
    assert {:ok, version} = Economics.publish_cost_mapping(preview.token)
    assert version.number == 1 and version.state == "active"
    assert {:ok, data} = Economics.costs()
    equal(data.totals.variable, "45.50")
    equal(data.totals.total, data.report.totals["expense"])
    assert {:error, :stale_preview} = Economics.publish_cost_mapping(preview.token)
    assert Repo.aggregate(CostMappingVersion, :count) == 1
  end

  test "competing editors cannot publish over each other, and old interpretations remain reproducible",
       %{base: base, snapshot: snapshot} do
    {:ok, a} = preview(base)
    {:ok, b} = preview(base, [rule(%{"behavior" => "fixed"})])
    {:ok, v1} = Economics.publish_cost_mapping(a.token)
    assert {:error, :stale_preview} = Economics.publish_cost_mapping(b.token)
    assert {:error, :stale_preview} = preview(base)
    {:ok, next} = preview(%{base | version_id: v1.id}, [rule(%{"behavior" => "fixed"})])
    {:ok, v2} = Economics.publish_cost_mapping(next.token)
    assert v2.number == 2
    assert Repo.get!(CostMappingVersion, v1.id).state == "superseded"
    assert {:ok, old} = Economics.costs(%{"snapshot" => snapshot.id, "version" => v1.id})
    equal(old.totals.variable, "45.50")
    assert {:ok, current} = Economics.costs()
    equal(current.totals.fixed, "45.50")
    assert {:ok, original} = Economics.costs(%{"snapshot" => snapshot.id, "version" => "none"})
    equal(original.totals.unclassified, "45.50")
  end

  test "new snapshot or metadata invalidates a preview without modifying accounting confirmations",
       %{base: base, snapshot: snapshot, source: source} do
    assert {:ok, _} =
             Economics.confirm_month(snapshot.id, "2026-07-01", "Odsouhlaseno podle předvahy.")

    {:ok, preview} = preview(base)
    snapshot |> Ecto.Changeset.change(active: false) |> Repo.update!()
    newer = insert_snapshot(source)
    assert {:error, :stale_preview} = Economics.publish_cost_mapping(preview.token)
    assert {:ok, data} = Economics.costs(%{"snapshot" => snapshot.id})
    assert hd(data.report.confirmations).confirmed
    assert data.snapshot.id != newer.id
    {:ok, fresh} = preview(base)
    {:ok, _} = Economics.publish_cost_mapping(fresh.token)
    assert {:ok, data} = Economics.costs()
    assert hd(data.report.confirmations).confirmed
    assert Repo.get!(Snapshot, snapshot.id).payload == snapshot.payload
  end

  test "source changes cannot transfer previews, rules, overrides or history", %{
    base: base,
    source: source,
    snapshot: snapshot
  } do
    {:ok, preview} = preview(base)
    other = Repo.insert!(%Source{base_url: source.base_url, company_id: "other"})
    insert_snapshot(other)

    Application.put_env(
      :cozy_checkout,
      :economics,
      Keyword.put(Config.get(), :company_id, "other")
    )

    assert {:error, :stale_preview} = Economics.publish_cost_mapping(preview.token)
    assert {:error, :stale_preview} = preview(base)
    assert {:error, :not_imported} = Economics.costs(%{"snapshot" => snapshot.id})
    {:ok, own} = preview(%{source_id: other.id, version_id: nil})
    {:ok, version} = Economics.publish_cost_mapping(own.token)

    Application.put_env(
      :cozy_checkout,
      :economics,
      Keyword.put(Config.get(), :company_id, source.company_id)
    )

    assert {:error, :invalid_version} = Economics.costs(%{"version" => version.id})
    assert {:ok, %{rules: []}} = Economics.costs()
  end

  test "rejects invented accounts, unverified partners, invalid targets and duplicate overrides",
       %{base: base, snapshot: snapshot} do
    assert {:error, :invalid_account} = preview(base, [rule(%{"account" => "602001"})])
    assert {:error, :invalid_partner} = preview(base, [rule(%{"partner_id" => "42"})])
    [bundle] = Costs.bundles(snapshot.payload["months"])

    attrs = %{
      "account" => bundle.account,
      "module" => bundle.module,
      "document_id" => bundle.document_id,
      "month" => bundle.month,
      "fingerprint" => bundle.fingerprint,
      "behavior" => "fixed",
      "reason" => "Ruční kontrola"
    }

    assert {:error, :invalid_override} =
             preview(base, [], [Map.put(attrs, "document_id", "foreign")])

    assert {:error, :duplicate_override} = preview(base, [], [attrs, attrs])
    assert {:ok, p} = preview(base, [], [attrs])
    assert {:ok, version} = Economics.publish_cost_mapping(p.token)
    assert [%{behavior: "fixed"}] = Repo.all(CostOverride)
    # Removing an exception creates a new version, preserving the original business record.
    {:ok, p} = preview(%{base | version_id: version.id}, [], [])
    {:ok, _} = Economics.publish_cost_mapping(p.token)
    assert Repo.aggregate(CostOverride, :count) == 1
  end

  test "stale and missing exceptions survive later versions without falling back to a general rule",
       %{base: base, snapshot: snapshot} do
    [bundle] = Costs.bundles(snapshot.payload["months"])

    attrs = %{
      "account" => bundle.account,
      "module" => bundle.module,
      "document_id" => bundle.document_id,
      "month" => bundle.month,
      "fingerprint" => bundle.fingerprint,
      "behavior" => "fixed",
      "reason" => "Původní kontrola"
    }

    {:ok, p} = preview(base, [rule()], [attrs])
    {:ok, v1} = Economics.publish_cost_mapping(p.token)

    payload =
      update_in(snapshot.payload, ["months"], fn [month] ->
        [
          Map.update!(
            month,
            "movements",
            &Enum.map(&1, fn row ->
              if row["kind"] == "expense", do: Map.put(row, "md", "90"), else: row
            end)
          )
        ]
      end)

    changed =
      snapshot
      |> Ecto.Changeset.change(payload: payload, fingerprint: Reports.fingerprint(payload))
      |> Repo.update!()

    assert {:ok, %{items: [%{status: :stale_override}]} = data} = Economics.costs()
    equal(data.totals.unclassified, "90")
    {:ok, p} = preview(%{base | version_id: v1.id}, [rule()], [attrs])
    {:ok, v2} = Economics.publish_cost_mapping(p.token)

    payload =
      update_in(payload, ["months"], fn [month] ->
        [
          Map.update!(
            month,
            "movements",
            &Enum.reject(&1, fn row -> row["kind"] == "expense" end)
          )
        ]
      end)

    changed
    |> Ecto.Changeset.change(payload: payload, fingerprint: Reports.fingerprint(payload))
    |> Repo.update!()

    assert {:ok, %{items: [], missing_overrides: [_]}} = Economics.costs()
    assert {:ok, p} = preview(%{base | version_id: v2.id}, [rule()], [attrs])
    assert {:ok, _} = Economics.publish_cost_mapping(p.token)
  end

  test "published records are immutable even to direct database writes", %{base: base} do
    {:ok, p} = preview(base)
    {:ok, version} = Economics.publish_cost_mapping(p.token)
    rule = Repo.one!(CostRule)
    reject_write(fn -> rule |> Ecto.Changeset.change(reason: "Přepsáno") |> Repo.update!() end)
    reject_write(fn -> Repo.delete!(rule) end)

    reject_write(fn ->
      Repo.insert!(%CostRule{
        version_id: version.id,
        account: "501100",
        valid_from: ~D[2026-07-01],
        behavior: "fixed",
        reason: "Dodatečný zápis"
      })
    end)

    reject_write(fn -> version |> Ecto.Changeset.change(note: "Přepsáno") |> Repo.update!() end)
    assert Repo.get!(CostRule, rule.id).reason == rule.reason
  end

  defp reject_write(fun) do
    Repo.query!("SAVEPOINT check_immutable", [], sandbox_subtransaction: false)

    try do
      assert_raise Postgrex.Error, fun
    after
      Repo.query!("ROLLBACK TO SAVEPOINT check_immutable", [], sandbox_subtransaction: false)
    end
  end

  test "failed publication rolls back all entries and retains the active version", %{base: base} do
    {:ok, p} = preview(base)
    {:ok, first} = Economics.publish_cost_mapping(p.token)
    {:ok, p} = preview(%{base | version_id: first.id})

    Repo.query!("""
    CREATE FUNCTION pg_temp.reject_cost_publication() RETURNS trigger AS $$
    BEGIN RAISE EXCEPTION 'synthetic publication failure'; END;
    $$ LANGUAGE plpgsql;
    """)

    Repo.query!(
      "CREATE TRIGGER reject_cost_publication BEFORE INSERT ON economics_cost_rules FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_cost_publication()"
    )

    reject_write(fn -> Economics.publish_cost_mapping(p.token) end)
    assert Repo.aggregate(CostMappingVersion, :count) == 1
    assert Repo.aggregate(CostRule, :count) == 1
    assert Repo.get!(CostMappingVersion, first.id).state == "active"
  end

  test "classification query count remains constant for many postings and disabled feature performs no queries",
       %{base: base, snapshot: snapshot} do
    {:ok, p} = preview(base)
    {:ok, _} = Economics.publish_cost_mapping(p.token)
    {:ok, _} = Economics.costs()
    one_count = count_queries(fn -> Economics.costs() end)

    payload =
      update_in(snapshot.payload, ["months"], fn [month] ->
        [
          Map.update!(month, "movements", fn rows ->
            for i <- 1..150,
                row <- rows,
                do:
                  Map.merge(row, %{
                    "document_id" => "#{row["document_id"]}-#{i}",
                    "journal_id" => "#{row["journal_id"]}-#{i}"
                  })
          end)
        ]
      end)

    snapshot
    |> Ecto.Changeset.change(payload: payload, fingerprint: Reports.fingerprint(payload))
    |> Repo.update!()

    assert count_queries(fn -> Economics.costs() end) == one_count
    Application.put_env(:cozy_checkout, :economics, enabled: false)
    assert count_queries(fn -> assert {:error, :disabled} = Economics.costs() end) == 0
  end

  defp count_queries(fun) do
    key = {__MODULE__, make_ref()}
    Process.put(key, 0)
    id = "cost-queries-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      id,
      [:cozy_checkout, :repo, :query],
      fn _, _, _, _ -> Process.put(key, Process.get(key, 0) + 1) end,
      nil
    )

    try do
      fun.()
      Process.get(key)
    after
      :telemetry.detach(id)
      Process.delete(key)
    end
  end

  test "draft classification uses loaded data without queries or changing the active mapping" do
    assert {:ok, data} = Economics.costs()

    assert count_queries(fn ->
             assert {:ok, [%{status: :classified, behavior: "fixed"}]} =
                      Economics.cost_draft_items(data, [rule(%{"behavior" => "fixed"})], [])

             assert {:ok, [%{status: :conflict}]} =
                      Economics.cost_draft_items(
                        data,
                        [rule(), rule(%{"behavior" => "fixed"})],
                        []
                      )

             assert {:ok, [%{status: :unclassified}]} = Economics.cost_draft_items(data, [], [])

             assert {:error, %Ecto.Changeset{}} =
                      Economics.cost_draft_items(data, [rule(%{"reason" => ""})], [])
           end) == 0

    assert {:ok, %{version: nil, items: [%{status: :unclassified}]}} = Economics.costs()
  end

  test "invalid range and invalid version input are rejected without UUID casts" do
    assert {:error, :invalid_range} = Economics.costs(%{"from" => "2020-01"})
    assert {:error, :invalid_version} = Economics.costs(%{"version" => "bad-uuid"})
    assert {:error, :stale_preview} = Economics.publish_cost_mapping("forged")
  end
end

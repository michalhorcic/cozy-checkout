defmodule CozyCheckout.Adventure.ChronicleTest do
  use CozyCheckout.DataCase, async: false
  import CozyCheckout.AdventureFixtures
  import Ecto.Changeset
  alias CozyCheckout.{QueryRecorder, Repo}
  alias CozyCheckout.Adventure.{Campaign, Campaigns, Evaluation, Quest, Unlock, XpTransaction}
  alias CozyCheckout.Adventure.Sources.Stays

  setup do
    Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ", [],
      sandbox_subtransaction: false
    )

    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    {:ok, profile: adventure_profile(), today: Stays.today()}
  end

  test "season capacity and goals are opt-in while legacy requirements remain", %{today: today} do
    attrs = season_attrs(today)
    assert {:ok, season} = Campaigns.create(attrs)
    assert season.rules_version == "season_v1"
    assert season.capacity == nil
    assert season.completed_goal == nil
    assert season.reserved_goal == nil
    assert season.occupancy_goal == nil
    assert {:error, %Ecto.Changeset{}} = Campaigns.create(Map.delete(attrs, :rules_version))

    for invalid <- [
          %{capacity: 0},
          %{completed_goal: 0},
          %{reserved_goal: -1},
          %{occupancy_goal: 101}
        ] do
      assert {:error, %Ecto.Changeset{}} = Campaigns.create(Map.merge(attrs, invalid))
    end

    assert {:ok, legacy} = Campaigns.create(campaign_attrs())
    assert legacy.rules_version == "stays_v1"
  end

  test "database allows null goals only for season rules and still enforces ranges", %{
    today: today
  } do
    for {attrs, constraint} <- [
          {season_attrs(today) |> Map.put(:capacity, 0), :adventure_campaign_goals},
          {season_attrs(today) |> Map.put(:completed_goal, -1), :adventure_campaign_goals},
          {season_attrs(today) |> Map.put(:rules_version, "stays_v1"), :adventure_campaign_goals},
          {campaign_attrs(%{rules_version: "unknown"}), :adventure_campaign_rules}
        ] do
      changeset =
        struct(Campaign, attrs) |> change() |> check_constraint(:capacity, name: constraint)

      assert {:error, %Ecto.Changeset{}} = Repo.insert(changeset, mode: :savepoint)
    end
  end

  test "historical creation is directly closed and does not occupy the active slot or generate tasks",
       %{
         profile: p,
         today: today
       } do
    active = active_campaign(p)
    booking = past_booking(today)
    tasks_before = Repo.aggregate(Quest, :count)

    {{:ok, historical}, queries} =
      QueryRecorder.record(fn -> Campaigns.create_historical(past_attrs(today), p.id) end)

    assert historical.rules_version == "season_v1"
    assert historical.status == "closed"
    assert historical.historical
    assert historical.activated_at == nil
    assert historical.activated_by_id == nil
    assert historical.closed_at
    assert Repo.get!(Campaign, active.id).status == "active"
    assert historical.last_evaluation.version == 1
    assert historical.last_evaluation.previous_evaluation_id == nil
    assert historical.last_evaluation.snapshot["completed_stays"] == 1
    assert historical.last_evaluation.snapshot["realized_bednights"] == 4
    assert historical.last_evaluation.campaign_metadata["historical"] == true
    assert Repo.aggregate(Quest, :count) == tasks_before
    assert Repo.aggregate(Unlock, :count) == 0
    assert Repo.aggregate(XpTransaction, :count) == 0
    assert Repo.reload!(booking).status == "completed"
    assert_adventure_writes_only(queries)
    refute inspect(historical.last_evaluation.snapshot) =~ "Soukromé"
    refute inspect(historical.last_evaluation.snapshot) =~ "@example.test"
  end

  test "historical entry rejects nonpast seasons and invalid actors atomically", %{
    profile: p,
    today: today
  } do
    assert {:error, :not_past_campaign} = Campaigns.create_historical(season_attrs(today), p.id)
    assert {:error, :invalid_profile} = Campaigns.create_historical(past_attrs(today), "invalid")
    assert Repo.aggregate(Campaign, :count) == 0
    assert Repo.aggregate(Evaluation, :count) == 0
  end

  test "a past draft can be archived explicitly and replaying the archive is idempotent", %{
    profile: p,
    today: today
  } do
    assert {:ok, draft} = Campaigns.create(past_attrs(today))
    assert {:error, :past_campaign} = Campaigns.activate(draft.id, p.id, true)
    assert {:error, :confirmation_required} = Campaigns.archive_historical(draft.id, p.id, false)
    assert {:ok, archived} = Campaigns.archive_historical(draft.id, p.id, true)
    assert archived.status == "closed"
    assert archived.historical
    assert {:ok, repeated} = Campaigns.archive_historical(draft.id, p.id, true)
    assert repeated.last_evaluation_id == archived.last_evaluation_id
    assert Repo.aggregate(Evaluation, :count) == 1
  end

  test "closed corrections require a reason and append numbered linked immutable snapshots", %{
    profile: p,
    today: today
  } do
    booking = past_booking(today)
    {:ok, season} = Campaigns.create_historical(past_attrs(today), p.id)
    first = season.last_evaluation
    before = Repo.aggregate(Evaluation, :count)
    assert {:error, :correction_reason_required} = Campaigns.evaluate(season.id, p.id)

    assert {:error, :correction_reason_required} =
             Campaigns.evaluate(season.id, p.id, correction_reason: " \n ")

    {_, invalid_queries} =
      QueryRecorder.record(fn ->
        assert {:error, :correction_reason_too_long} =
                 Campaigns.evaluate(season.id, p.id,
                   correction_reason: String.duplicate("x", 1001)
                 )
      end)

    refute Enum.any?(invalid_queries, &String.contains?(&1, "WITH bounds AS"))

    assert Repo.aggregate(Evaluation, :count) == before
    booking |> change(adults: 3) |> Repo.update!()

    assert {:ok, corrected} =
             Campaigns.evaluate(season.id, p.id, correction_reason: "  Oprava počtu osob  ")

    second = corrected.last_evaluation
    assert second.version == 2
    assert second.previous_evaluation_id == first.id
    assert second.correction_reason == "Oprava počtu osob"
    assert second.snapshot["realized_bednights"] == 6
    assert second.campaign_metadata["starts_on"] == Date.to_iso8601(season.starts_on)
    assert second.campaign_metadata["capacity"] == nil
    assert second.campaign_metadata["rules_version"] == "season_v1"
    assert Repo.get!(Evaluation, first.id) == first

    assert {:ok, third} = Campaigns.evaluate(season.id, p.id, reason: "Doplnění úhrad")
    assert third.last_evaluation.version == 3
    assert third.last_evaluation.previous_evaluation_id == second.id
    assert {:ok, ^third} = Campaigns.close(season.id, p.id)
    assert Repo.aggregate(Evaluation, :count) == 3
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "database rejects rewriting or deleting a chronicle evaluation", %{
    profile: p,
    today: today
  } do
    {:ok, season} = Campaigns.create_historical(past_attrs(today), p.id)
    evaluation = season.last_evaluation

    changeset =
      evaluation
      |> change(snapshot: %{})
      |> check_constraint(:snapshot, name: :adventure_evaluation_immutable)

    assert {:error, _} = Repo.update(changeset, mode: :savepoint)

    changeset =
      evaluation |> change() |> check_constraint(:snapshot, name: :adventure_evaluation_immutable)

    assert {:error, _} = Repo.delete(changeset, mode: :savepoint)
    assert Repo.get!(Evaluation, evaluation.id) == evaluation
  end

  test "database rejects invalid revision numbers, cross-season links and duplicate versions", %{
    profile: p,
    today: today
  } do
    {:ok, first} = Campaigns.create_historical(past_attrs(today), p.id)
    {:ok, other} = Campaigns.create_historical(past_attrs(today), p.id)

    for {attrs, constraint} <- [
          {%{version: 0}, :adventure_evaluation_version},
          {%{
             version: 2,
             previous_evaluation_id: other.last_evaluation_id,
             correction_reason: "Oprava"
           }, :adventure_evaluation_previous},
          {%{version: 2, previous_evaluation_id: first.last_evaluation_id},
           :adventure_evaluation_reason},
          {%{
             version: 2,
             previous_evaluation_id: first.last_evaluation_id,
             correction_reason: String.duplicate("x", 1001)
           }, :adventure_evaluation_reason}
        ] do
      changeset =
        %Evaluation{
          campaign_id: first.id,
          actor_id: p.id,
          version: 1,
          campaign_metadata: first.last_evaluation.campaign_metadata,
          snapshot: %{},
          as_of: DateTime.utc_now()
        }
        |> change(attrs)
        |> check_constraint(:version, name: constraint)

      assert {:error, %Ecto.Changeset{}} = Repo.insert(changeset, mode: :savepoint)
    end

    duplicate =
      first.last_evaluation
      |> Map.from_struct()
      |> Map.take(Evaluation.__schema__(:fields))
      |> Map.delete(:id)
      |> then(&struct(Evaluation, &1))
      |> change()
      |> unique_constraint([:campaign_id, :version])

    assert {:error, %Ecto.Changeset{}} = Repo.insert(duplicate, mode: :savepoint)
  end

  test "active seasons never auto award XP and retain the single active slot", %{
    profile: p,
    today: today
  } do
    active = active_campaign(p, %{rules_version: "season_v1"})
    for _ <- 1..10, do: past_booking(today)
    assert Stays.snapshot(active)["eligible_completed_stays"] == 10
    tasks_before = Repo.aggregate(Quest, :count)
    assert {:ok, evaluated} = Campaigns.evaluate(active.id, p.id)
    assert evaluated.last_evaluation.version == 1
    assert {:ok, again} = Campaigns.evaluate(active.id, p.id)
    assert again.last_evaluation.version == 2
    assert {:ok, another} = Campaigns.create(season_attrs(today))
    assert {:error, %Ecto.Changeset{}} = Campaigns.activate(another.id, p.id, true)
    assert {:ok, closed} = Campaigns.close(active.id, p.id)
    assert closed.last_evaluation.version == 3
    assert Repo.aggregate(Unlock, :count) == 0
    assert Repo.aggregate(XpTransaction, :count) == 0
    assert Repo.aggregate(Quest, :count) == tasks_before
  end

  test "period and capacity cannot change after activation, including direct database writes", %{
    profile: p,
    today: today
  } do
    {:ok, draft} = Campaigns.create(season_attrs(today))
    {:ok, active} = Campaigns.activate(draft.id, p.id, true)
    assert {:error, :immutable_campaign} = Campaigns.update(active.id, %{capacity: 10})

    for attrs <- [
          %{capacity: 10},
          %{starts_on: Date.add(today, -20)},
          %{ends_on: Date.add(today, 20)},
          %{completed_goal: 5},
          %{reserved_goal: 100},
          %{occupancy_goal: 50},
          %{rules_version: "stays_v1"}
        ] do
      changeset =
        active
        |> change(attrs)
        |> check_constraint(:starts_on, name: :adventure_campaign_immutable_period)

      assert {:error, %Ecto.Changeset{}} = Repo.update(changeset, mode: :savepoint)
    end
  end

  test "snapshot contains all three sources and per-metric provenance without guest data", %{
    profile: p,
    today: today
  } do
    past_booking(today)
    as_of = DateTime.utc_now()
    {:ok, season} = Campaigns.create_historical(past_attrs(today), p.id, as_of: as_of)
    snapshot = season.last_evaluation.snapshot
    assert Enum.sort(Map.keys(snapshot["sources"])) == ["bar", "billing", "stays"]
    assert snapshot["source_consistency"] == "transaction_snapshot"

    for {name, source} <- snapshot["sources"] do
      assert source["source"] == name
      assert source["as_of"] == DateTime.to_iso8601(as_of)

      for {metric, _} <- source["metrics"] do
        metadata = source["metric_metadata"][metric]
        assert metadata["source"] == name
        assert metadata["as_of"] == source["as_of"]
        assert metadata["definition_version"] == source["definition_version"]
        assert metadata["completeness"] in ["complete", "partial", "unavailable"]
        assert metadata["unit"] in ["CZK", "count", "percent", "bednights"]
        assert metadata["period"]["starts_on"] == Date.to_iso8601(season.starts_on)
      end
    end

    assert get_in(snapshot, [
             "sources",
             "stays",
             "metric_metadata",
             "occupancy_percent",
             "completeness"
           ]) == "unavailable"

    paid_metadata = snapshot["sources"]["billing"]["metric_metadata"]["settlement_paid_amount"]
    assert paid_metadata["time_basis"] == "departure_cohort"
    assert paid_metadata["cohort_period"]["starts_on"] == Date.to_iso8601(season.starts_on)
    assert paid_metadata["source_date_range"]["starts_on"] == nil
    assert paid_metadata["source_date_range"]["ends_on"] == paid_metadata["recorded_through_on"]

    refute inspect(snapshot) =~ "Soukromé"
  end

  test "overview reads saved snapshots only and recalculation has a bounded aggregate read count",
       %{profile: p, today: today} do
    {:ok, season} = Campaigns.create_historical(past_attrs(today), p.id)

    {_, empty_queries} =
      QueryRecorder.record(fn -> Campaigns.evaluate(season.id, p.id, reason: "Kontrola") end)

    for _ <- 1..10, do: past_booking(today)

    {{:ok, _}, more_queries} =
      QueryRecorder.record(fn -> Campaigns.evaluate(season.id, p.id, reason: "Nová data") end)

    assert length(empty_queries) == length(more_queries)
    assert_adventure_writes_only(more_queries)
    assert Enum.count(more_queries, &String.contains?(&1, "FROM bookings b")) == 2
    assert Enum.count(more_queries, &String.contains?(&1, "WITH bounds AS")) == 3

    {_, queries} = QueryRecorder.record(fn -> Campaigns.overview() end)

    refute Enum.any?(
             queries,
             &Regex.match?(
               ~r/\b(bookings|payments|billing_documents|booking_invoices|purchases)\b/,
               &1
             )
           )
  end

  test "disabled season API performs no reads or writes", %{profile: p, today: today} do
    attrs = past_attrs(today)
    id = Ecto.UUID.generate()
    Application.put_env(:cozy_checkout, :adventure_enabled, false)

    {_, queries} =
      QueryRecorder.record(fn ->
        assert {:error, :disabled} = Campaigns.create_historical(attrs, p.id)
        assert {:error, :disabled} = Campaigns.archive_historical(id, p.id, true)
        assert {:error, :disabled} = Campaigns.evaluate(id, p.id, correction_reason: "Oprava")
      end)

    assert queries == []
  end

  defp season_attrs(today) do
    %{
      name: "Sezonní kronika",
      starts_on: Date.add(today, -30),
      ends_on: Date.add(today, 30),
      rules_version: "season_v1"
    }
  end

  defp past_attrs(today), do: Map.put(season_attrs(today), :ends_on, Date.add(today, -1))

  defp past_booking(today) do
    adventure_booking(%{check_in_date: Date.add(today, -5), check_out_date: Date.add(today, -3)})
  end

  defp assert_adventure_writes_only(queries) do
    writes = Enum.filter(queries, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM)/, &1))
    assert writes != []
    assert Enum.all?(writes, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM) "adventure_/, &1))
  end
end

defmodule CozyCheckout.Adventure.ChronicleIsolationTest do
  use ExUnit.Case, async: false
  import CozyCheckout.AdventureFixtures
  alias Ecto.Adapters.SQL.Sandbox
  alias CozyCheckout.{QueryRecorder, Repo}
  alias CozyCheckout.Adventure.{Campaign, Campaigns, Profile}

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)

    {profile, campaign, booking} =
      Sandbox.unboxed_run(Repo, fn ->
        profile =
          Repo.insert!(%Profile{
            slug: "chronicle-isolation-#{Ecto.UUID.generate()}",
            display_name: "Isolation"
          })

        campaign =
          Repo.insert!(%Campaign{
            name: "Isolation season",
            rules_version: "season_v1",
            starts_on: ~D[2026-10-01],
            ends_on: ~D[2026-10-10],
            status: "active",
            activated_at: ~U[2026-09-30 12:00:00Z],
            activated_by_id: profile.id
          })

        {profile, campaign, adventure_booking()}
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        # The reader owns a rollback-only sandbox transaction, so no immutable
        # evaluation survives and no trigger bypass is needed for cleanup.
        Repo.delete!(Repo.get!(Campaign, campaign.id))
        Repo.delete!(Repo.get!(CozyCheckout.Bookings.Booking, booking.id))
        Repo.delete!(Repo.get!(CozyCheckout.Guests.Guest, booking.guest_id))
        Repo.delete!(profile)
      end)
    end)

    {:ok, profile: profile, campaign: campaign, booking: booking}
  end

  test "root snapshot actions establish repeatable read and nested read committed is rejected", %{
    profile: profile,
    campaign: campaign
  } do
    Sandbox.unboxed_run(Repo, fn ->
      {{:error, :not_found}, queries} =
        QueryRecorder.record(fn ->
          Campaigns.evaluate(Ecto.UUID.generate(), profile.id)
        end)

      isolation_index =
        Enum.find_index(queries, &(&1 == "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ"))

      campaign_index =
        Enum.find_index(queries, &String.contains?(&1, "FROM \"adventure_campaigns\""))

      assert is_integer(isolation_index)
      assert is_integer(campaign_index)
      assert isolation_index < campaign_index

      assert {:ok, {:error, :snapshot_isolation_required}} =
               Repo.transaction(fn ->
                 Repo.query!("SELECT 1")
                 Campaigns.evaluate(campaign.id, profile.id)
               end)

      assert Repo.get!(Campaign, campaign.id).last_evaluation_id == nil
    end)
  end

  test "a concurrent committed departure change cannot mix stays and billing source versions", %{
    profile: profile,
    campaign: campaign,
    booking: booking
  } do
    parent = self()
    reference = make_ref()

    reader =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, isolation: "REPEATABLE READ")

        try do
          receive do
            :read -> Campaigns.evaluate(campaign.id, profile.id, as_of: ~U[2026-11-12 12:00:00Z])
          after
            5000 -> raise "Reader was not released"
          end
        after
          Sandbox.checkin(Repo)
        end
      end)

    handler = {__MODULE__, reference}

    :ok =
      :telemetry.attach(
        handler,
        [:cozy_checkout, :repo, :query],
        &__MODULE__.pause_after_stays/4,
        {parent, reader.pid, reference}
      )

    try do
      send(reader.pid, :read)
      assert_receive {:stays_read, ^reference}, 5000

      Sandbox.unboxed_run(Repo, fn ->
        booking
        |> Ecto.Changeset.change(check_out_date: ~D[2026-10-20], adults: 7)
        |> Repo.update!()
      end)

      send(reader.pid, {:continue, reference})
      assert {:ok, evaluated} = Task.await(reader, 10_000)
      snapshot = evaluated.last_evaluation.snapshot
      assert snapshot["sources"]["stays"]["metrics"]["completed_stays"] == 1
      assert snapshot["sources"]["stays"]["metrics"]["realized_bednights"] == 4
      assert snapshot["sources"]["billing"]["metrics"]["settlement_bookings_count"] == 1

      Sandbox.unboxed_run(Repo, fn ->
        source =
          CozyCheckout.Adventure.Sources.Billing.evaluate(campaign,
            as_of: ~U[2026-11-12 12:00:00Z]
          )

        assert source["metrics"]["settlement_bookings_count"] == 0
        assert Repo.get!(Campaign, campaign.id).last_evaluation_id == nil
      end)
    after
      send(reader.pid, {:continue, reference})
      if Process.alive?(reader.pid), do: Task.shutdown(reader, :brutal_kill)
      :telemetry.detach(handler)
    end
  end

  def pause_after_stays(_event, _measurements, metadata, {parent, reader, reference}) do
    if self() == reader and String.contains?(metadata.query, "AS eligible_completed_stays") do
      send(parent, {:stays_read, reference})

      receive do
        {:continue, ^reference} -> :ok
      after
        5000 -> raise "Concurrent writer did not release reader"
      end
    end
  end
end

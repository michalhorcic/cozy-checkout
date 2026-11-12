defmodule CozyCheckout.Adventure.CampaignsTest do
  use CozyCheckout.DataCase, async: false
  import CozyCheckout.AdventureFixtures
  alias CozyCheckout.{Adventure, QueryRecorder, Repo}
  alias CozyCheckout.Adventure.{Campaign, Campaigns, Evaluation, Unlock, XpTransaction}
  alias CozyCheckout.Adventure.Sources.Stays

  setup do
    Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ", [],
      sandbox_subtransaction: false
    )

    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    {:ok, profile: adventure_profile()}
  end

  test "draft validates goals, dates and capacity; activation requires confirmation and locks rules",
       %{profile: p} do
    for attrs <- [
          %{capacity: 0},
          %{occupancy_goal: 101},
          %{completed_goal: -1},
          %{ends_on: Date.add(Stays.today(), -100)},
          %{name: ""}
        ] do
      assert {:error, %Ecto.Changeset{}} = Campaigns.create(campaign_attrs(attrs))
    end

    {:ok, draft} = Campaigns.create(campaign_attrs())
    assert draft.status == "draft"
    assert {:error, :confirmation_required} = Campaigns.activate(draft.id, p.id, false)
    assert {:error, :invalid_profile} = Campaigns.activate(draft.id, "invalid", true)
    assert {:error, :inactive_campaign} = Campaigns.evaluate(draft.id, p.id)
    assert {:ok, active} = Campaigns.activate(draft.id, p.id, true)
    assert active.status == "active"
    assert active.activated_by_id == p.id
    assert {:ok, ^active} = Campaigns.activate(draft.id, p.id, true)
    assert {:error, :immutable_campaign} = Campaigns.update(draft.id, %{capacity: 1})
    {:ok, another} = Campaigns.create(campaign_attrs())
    assert {:error, %Ecto.Changeset{}} = Campaigns.activate(another.id, p.id, true)
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "two milestones award the cottage once; personal XP stay unchanged and audit is retained",
       %{profile: p} do
    c = active_campaign(p)
    stays = completed_stays(10)
    {{:ok, _}, queries} = QueryRecorder.record(fn -> Campaigns.evaluate(c.id, p.id) end)
    writes = Enum.filter(queries, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM)/, &1))
    assert Enum.all?(writes, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM) "adventure_/, &1))
    assert {:ok, _} = Campaigns.evaluate(c.id, p.id)
    assert Repo.aggregate(Unlock, :count) == 2
    assert Repo.aggregate(XpTransaction, :count) == 2
    assert Repo.aggregate(Evaluation, :count) == 2
    assert {:ok, %{total_xp: 350}} = Campaigns.overview()
    assert {:ok, %{total_xp: 0}} = Adventure.dashboard(p.id)

    assert Enum.all?(
             Repo.all(XpTransaction),
             &(&1.profile_id == nil and &1.attribution == "automatic")
           )

    evaluation = Repo.get!(Evaluation, Repo.get!(Campaign, c.id).last_evaluation_id)
    assert evaluation.actor_id == p.id
    assert evaluation.snapshot["eligible_completed_stays"] == length(stays)
    refute inspect(evaluation.snapshot) =~ "Soukromé jméno"
  end

  test "reconciliation compensates revoked milestones only once without farming re-awards", %{
    profile: p
  } do
    c = active_campaign(p)
    [first | rest] = completed_stays(10)
    {:ok, _} = Campaigns.evaluate(c.id, p.id)
    first |> Ecto.Changeset.change(status: "cancelled") |> Repo.update!()
    {:ok, _} = Campaigns.evaluate(c.id, p.id)
    assert {:ok, %{total_xp: 100}} = Campaigns.overview()
    assert Repo.get_by!(Unlock, code: "ten_stays").status == "revoked"
    assert {:ok, _} = Campaigns.evaluate(c.id, p.id)
    assert Repo.aggregate(XpTransaction, :count) == 3

    for booking <- rest,
        do:
          booking
          |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
          |> Repo.update!()

    {:ok, _} = Campaigns.evaluate(c.id, p.id)
    assert {:ok, %{total_xp: 0}} = Campaigns.overview()
    first |> Ecto.Changeset.change(status: "completed") |> Repo.update!()
    {:ok, _} = Campaigns.evaluate(c.id, p.id)
    assert Repo.aggregate(XpTransaction, :count) == 4
    assert {:ok, %{total_xp: 0}} = Campaigns.overview()
  end

  test "partial data cannot grant or revoke automatic XP", %{profile: p} do
    c = active_campaign(p)
    [booking] = completed_stays(1)

    uncertain =
      adventure_booking(%{check_in_date: Date.add(Stays.today(), -5), check_out_date: nil})

    {:ok, _} = Campaigns.evaluate(c.id, p.id)
    assert Repo.aggregate(Unlock, :count) == 0
    uncertain |> Ecto.Changeset.change(status: "cancelled") |> Repo.update!()
    {:ok, _} = Campaigns.evaluate(c.id, p.id)
    assert Repo.aggregate(Unlock, :count) == 1
    booking |> Ecto.Changeset.change(status: "cancelled") |> Repo.update!()
    uncertain |> Ecto.Changeset.change(status: "active") |> Repo.update!()
    {:ok, _} = Campaigns.evaluate(c.id, p.id)
    assert Repo.get_by!(Unlock, code: "first_stay").status == "unlocked"
    assert Repo.aggregate(XpTransaction, :count) == 1
  end

  test "a failure writing shared XP rolls back evaluation, unlock and last snapshot", %{
    profile: p
  } do
    c = active_campaign(p)
    completed_stays(1)

    Repo.query!("""
    CREATE FUNCTION pg_temp.reject_shared_award() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.recipient_type = 'shared' THEN
        RAISE EXCEPTION 'synthetic shared XP failure';
      END IF;
      RETURN NEW;
    END $$
    """)

    Repo.query!(
      "CREATE TRIGGER reject_shared_award BEFORE INSERT ON adventure_xp_transactions FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_shared_award()"
    )

    assert_raise Postgrex.Error, fn -> Campaigns.evaluate(c.id, p.id) end
    assert Repo.aggregate(Evaluation, :count) == 0
    assert Repo.aggregate(Unlock, :count) == 0
    assert Repo.aggregate(XpTransaction, :count) == 0
    assert Repo.get!(Campaign, c.id).last_evaluation_id == nil
  end

  test "rendering overview never reads operational records or awards XP", %{profile: p} do
    _campaign = active_campaign(p)
    completed_stays(10)
    {_, queries} = QueryRecorder.record(fn -> Campaigns.overview() end)
    refute Enum.any?(queries, &String.contains?(&1, "bookings"))
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "legacy history and awards remain unchanged when a season chronicle is added", %{
    profile: p
  } do
    campaign = active_campaign(p)
    completed_stays(1)

    {{:ok, evaluated}, queries} =
      QueryRecorder.record(fn -> Campaigns.evaluate(campaign.id, p.id) end)

    legacy_evaluation = Repo.get!(Evaluation, evaluated.last_evaluation_id)
    legacy_unlocks = Repo.all(Unlock)
    legacy_awards = Repo.all(XpTransaction)
    assert legacy_evaluation.version == nil
    assert legacy_evaluation.campaign_metadata == nil

    refute Enum.any?(
             queries,
             &Regex.match?(~r/\b(billing_payments|billing_documents|payments)\b/, &1)
           )

    attrs = campaign_attrs(%{ends_on: Date.add(Stays.today(), -1)})
    assert {:ok, historical} = Campaigns.create_historical(attrs, p.id)

    assert {:ok, _} =
             Campaigns.evaluate(historical.id, p.id, correction_reason: "Doplnění sezony")

    assert Repo.get!(Evaluation, legacy_evaluation.id) == legacy_evaluation
    assert Repo.all(Unlock) == legacy_unlocks
    assert Repo.all(XpTransaction) == legacy_awards
    assert Repo.get!(Campaign, campaign.id).last_evaluation_id == legacy_evaluation.id
  end

  test "overview query count is bounded independently of campaign history" do
    {:ok, _} = Campaigns.create(campaign_attrs())
    {_, first_queries} = QueryRecorder.record(fn -> Campaigns.overview() end)
    for _ <- 1..10, do: Campaigns.create(campaign_attrs())
    {_, more_queries} = QueryRecorder.record(fn -> Campaigns.overview() end)
    assert length(first_queries) == length(more_queries)
    assert length(more_queries) <= 6
  end

  test "closure reconciles and freezes a date cutoff; disabled module blocks every mutation", %{
    profile: p
  } do
    c = active_campaign(p)
    completed_stays(1)
    assert {:ok, closed} = Campaigns.close(c.id, p.id)
    assert closed.status == "closed"
    assert closed.closed_at
    assert {:ok, _} = Campaigns.evaluate(c.id, p.id)
    assert Repo.aggregate(XpTransaction, :count) == 1
    Application.put_env(:cozy_checkout, :adventure_enabled, false)

    {_, queries} =
      QueryRecorder.record(fn ->
        assert {:error, :disabled} = Campaigns.create(campaign_attrs())
        assert {:error, :disabled} = Campaigns.update(c.id, %{capacity: 1})
        assert {:error, :disabled} = Campaigns.activate(c.id, p.id, true)
        assert {:error, :disabled} = Campaigns.evaluate(c.id, p.id)
        assert {:error, :disabled} = Campaigns.close(c.id, p.id)
        assert {:error, :disabled} = Campaigns.overview()
      end)

    # campaign_attrs reads Prague's current date for the test fixture only.
    assert Enum.all?(queries, &String.starts_with?(&1, "SELECT timezone"))
  end

  defp completed_stays(count) do
    today = Stays.today()

    for i <- 1..count do
      adventure_booking(%{
        check_in_date: Date.add(today, -i - 2),
        check_out_date: Date.add(today, -i - 1)
      })
    end
  end
end

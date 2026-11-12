defmodule CozyCheckout.Adventure.TemplatesTest do
  use CozyCheckout.DataCase, async: false
  import Ecto.Query
  import CozyCheckout.AdventureFixtures
  alias CozyCheckout.{Adventure, QueryRecorder, Repo}

  alias CozyCheckout.Adventure.{
    Campaigns,
    Quest,
    TaskTemplate,
    TemplateVersion,
    Templates,
    Tasks,
    XpTransaction
  }

  alias CozyCheckout.Adventure.Sources.{Guests, Stays}

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    p = adventure_profile()
    %{p: p, today: Stays.today()}
  end

  defp at(day), do: DateTime.new!(day, ~T[12:00:00], "Etc/UTC")

  test "compact pages batch open work and hide irreversible archives with two selects", %{
    p: p,
    today: day
  } do
    template = active(p, day)
    {:ok, _} = Templates.generate(at(day))
    {:ok, _} = Templates.set_status(p.id, template.id, "archived", "keep")
    {current, current_queries} = QueryRecorder.record(fn -> Templates.page() end)
    refute Enum.any?(current.templates, &(&1.id == template.id))
    assert length(Enum.filter(current_queries, &String.starts_with?(&1, "SELECT"))) == 2
    {archive, archive_queries} = QueryRecorder.record(fn -> Templates.page("archive") end)
    assert [saved] = archive.templates
    assert saved.id == template.id
    assert [%{status: "waiting"}] = archive.open[template.id]
    assert length(Enum.filter(archive_queries, &String.starts_with?(&1, "SELECT"))) == 2

    assert {:error, :immutable_template} =
             Templates.set_status(p.id, template.id, "active", "keep")

    for i <- 1..33,
        do:
          Templates.create(p.id, %{"title" => "Šablona #{i}", "starts_on" => Date.to_iso8601(day)})

    {many, many_queries} = QueryRecorder.record(fn -> Templates.page() end)
    assert length(many.templates) == 30
    assert many.more?
    assert length(Enum.filter(many_queries, &String.starts_with?(&1, "SELECT"))) == 2
    next = Templates.page("current", 1)

    assert MapSet.disjoint?(
             MapSet.new(many.templates, & &1.id),
             MapSet.new(next.templates, & &1.id)
           )

    assert Enum.all?(many_queries ++ archive_queries, &String.starts_with?(&1, "SELECT"))
    Application.put_env(:cozy_checkout, :adventure_enabled, false)

    assert {%{templates: [], open: %{}, more?: false}, []} =
             QueryRecorder.record(fn -> Templates.page() end)
  end

  defp active(p, day, attrs \\ %{}) do
    {:ok, template} =
      Templates.create(
        p.id,
        Map.merge(%{"title" => "Práce", "starts_on" => Date.to_iso8601(day)}, attrs)
      )

    template |> Ecto.Changeset.change(status: "active", next_due_on: day) |> Repo.update!()
  end

  test "initialization seeds four paused definitions per hero exactly once", %{p: p} do
    assert Repo.aggregate(TaskTemplate, :count) == 8
    assert Repo.aggregate(TemplateVersion, :count) == 8
    assert {:ok, :ok} = Adventure.initialize()
    assert Repo.aggregate(TaskTemplate, :count) == 8
    assert Repo.aggregate(TemplateVersion, :count) == 8
    assert {:ok, _} = Templates.generate()
    assert Repo.aggregate(Quest, :count) == 0
    assert {:ok, :ok} = Templates.add_examples(p.id)
    assert {:ok, :ok} = Templates.add_examples(p.id)
    assert Repo.aggregate(TaskTemplate, :count) == 15
    assert Enum.all?(Templates.list(), &(&1.status == "paused"))
  end

  test "seven missed dates yield one occurrence, preserve first due and never award XP", %{
    p: p,
    today: day
  } do
    first = Date.add(day, -7)
    template = active(p, first)
    assert {:ok, [%{result: :created}]} = Templates.generate(at(day))
    task = Repo.one!(Quest)
    assert task.template_id == template.id
    assert task.first_due_on == first
    assert task.due_on == day
    assert [%{"from" => first_string, "to" => due_string}] = task.schedule_history["shifts"]
    assert first_string == Date.to_iso8601(first)
    assert due_string == Date.to_iso8601(day)
    assert {:ok, []} = Templates.generate(at(day))
    assert Repo.aggregate(Quest, :count) == 1
    assert Repo.aggregate(XpTransaction, :count) == 0
    assert {:ok, [%{result: :rolled}]} = Templates.generate(at(Date.add(day, 1)))
    rolled = Repo.get!(Quest, task.id)
    assert rolled.first_due_on == first
    assert rolled.due_on == Date.add(day, 1)
    assert length(rolled.schedule_history["shifts"]) == 2
  end

  test "completion consumes today's schedule and next day gets one new occurrence", %{
    p: p,
    today: day
  } do
    template = active(p, Date.add(day, -7))
    {:ok, _} = Templates.generate(at(Date.add(day, -1)))
    task = Repo.one!(Quest)
    {:ok, _} = Tasks.start(p.id, task.id)
    {:ok, completed} = Tasks.complete(p.id, task.id)
    assert {:ok, [%{result: :already_closed}]} = Templates.generate(at(day))
    assert Repo.aggregate(Quest, :count) == 1
    assert Repo.aggregate(XpTransaction, :count) == 1
    assert {:ok, [%{result: :created}]} = Templates.generate(at(Date.add(day, 1)))
    assert Repo.aggregate(Quest, :count) == 2
    assert Repo.get!(Quest, task.id).definition_snapshot == completed.definition_snapshot
    assert Repo.get!(TaskTemplate, template.id).next_due_on == Date.add(day, 2)
  end

  test "cancellation also consumes its local day with a typed UTC aggregate", %{p: p, today: day} do
    template = active(p, day)
    {:ok, _} = Templates.generate(at(day))
    task = Repo.one!(Quest)
    {:ok, _} = Tasks.archive(p.id, task.id)
    {:ok, _} = Templates.set_status(p.id, template.id, "active", "keep")
    assert {:ok, [%{result: :already_closed}]} = Templates.generate(at(day))
    assert Repo.aggregate(Quest, :count) == 1
    assert Repo.aggregate(XpTransaction, :count) == 0
    assert {:ok, [%{result: :created}]} = Templates.generate(at(Date.add(day, 1)))
    assert Repo.aggregate(Quest, :count) == 2
  end

  test "version edits apply to future tasks; pause requires an explicit open-task decision", %{
    p: p,
    today: day
  } do
    template = active(p, day)
    {:ok, _} = Templates.generate(at(day))
    task = Repo.one!(Quest)
    assert {:error, :immutable_task} = Tasks.update(p.id, task.id, %{"title" => "Přepsat výskyt"})

    assert {:ok, updated} =
             Templates.update(p.id, template.id, %{"title" => "Nové zadání", "xp" => 250})

    assert updated.version == 2
    assert Repo.get!(Quest, task.id).definition_snapshot["xp"] == 50

    assert {:error, :open_choice_required} =
             Templates.set_status(p.id, template.id, "paused", nil)

    assert {:ok, _} = Templates.set_status(p.id, template.id, "paused", "keep")
    assert {:ok, []} = Templates.generate(at(Date.add(day, 1)))
    assert Repo.get!(Quest, task.id).status == "waiting"
    assert {:ok, _} = Templates.set_status(p.id, template.id, "active", "keep")
    {:ok, _} = Tasks.start(p.id, task.id)
    {:ok, _} = Tasks.complete(p.id, task.id)
    assert {:ok, [%{result: :created}]} = Templates.generate(at(Date.add(day, 1)))
    next = Repo.one!(from q in Quest, where: q.id != ^task.id)
    assert next.definition_snapshot["xp"] == 250
    assert next.definition_snapshot["title"] == "Nové zadání"
    assert next.definition_snapshot["template_version"] == 4
    assert {:ok, _} = Templates.set_status(p.id, template.id, "archived", "cancel")
    assert Repo.get!(Quest, next.id).status == "cancelled"
    assert Repo.get!(Quest, task.id).status == "completed"
    assert Repo.aggregate(XpTransaction, :count) == 1

    assert {:error, :immutable_template} =
             Templates.set_status(p.id, template.id, "active", "keep")
  end

  test "weekly days are validated and XP follow size when no override is given", %{
    p: p,
    today: day
  } do
    attrs = %{
      "title" => "Týdenní",
      "starts_on" => Date.to_iso8601(day),
      "cadence" => "weekly",
      "weekdays" => [""]
    }

    assert {:error, %Ecto.Changeset{}} = Templates.create(p.id, attrs)

    assert {:ok, template} =
             Templates.create(
               p.id,
               Map.merge(attrs, %{"weekdays" => ["", "1", "4"], "size" => "large"})
             )

    assert template.weekdays == [1, 4]
    assert template.xp == 250

    assert {:error, %Ecto.Changeset{}} =
             Templates.create(p.id, Map.merge(attrs, %{"weekdays" => ["8"]}))
  end

  test "campaign applicability retries after activation and leaves open tasks after closure", %{
    p: p,
    today: day
  } do
    {:ok, campaign} = Campaigns.create(campaign_attrs())
    template = active(p, day, %{"applicability" => "campaign", "campaign_id" => campaign.id})
    assert {:ok, [%{state: "outside_campaign"}]} = Templates.generate(at(day))
    assert Repo.aggregate(Quest, :count) == 0
    assert {:ok, _} = Campaigns.activate(campaign.id, p.id, true)
    assert {:ok, [%{result: :created}]} = Templates.generate(at(day))
    task = Repo.one!(Quest)
    campaign = Repo.get!(CozyCheckout.Adventure.Campaign, campaign.id)

    campaign
    |> Ecto.Changeset.change(
      status: "closed",
      closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:ok, [%{state: "outside_campaign"}]} = Templates.generate(at(Date.add(day, 1)))
    assert Repo.get!(Quest, task.id).status == "waiting"
    assert Repo.get!(TaskTemplate, template.id).last_check["state"] == "outside_campaign"
  end

  test "first campaign due is a scheduled weekday inside the campaign", %{p: p, today: day} do
    monday = day |> Date.beginning_of_week() |> Date.add(-14)
    campaign = active_campaign(p, %{starts_on: Date.add(monday, 3)})

    active(p, monday, %{
      "cadence" => "weekly",
      "applicability" => "campaign",
      "campaign_id" => campaign.id
    })

    assert {:ok, [%{result: :created}]} = Templates.generate(at(day))
    task = Repo.one!(Quest)
    assert task.first_due_on == Date.add(monday, 7)
    assert Date.day_of_week(task.first_due_on) == 1
  end

  test "guest applicability batches one read and retries later on the same day", %{
    p: p,
    today: day
  } do
    for i <- 1..5, do: active(p, day, %{"title" => "Hosté #{i}", "applicability" => "guests"})
    {{:ok, results}, queries} = QueryRecorder.record(fn -> Templates.generate(at(day)) end)
    assert Enum.all?(results, &(&1.state == "empty"))
    assert Enum.count(queries, &String.contains?(&1, "FROM bookings")) == 1
    assert Repo.aggregate(Quest, :count) == 0

    booking =
      adventure_booking(%{
        check_in_date: day,
        check_out_date: Date.add(day, 1),
        status: "upcoming"
      })

    assert Guests.snapshot(day) == "unknown"
    assert {:ok, results} = Templates.generate(at(day))
    assert Enum.all?(results, &(&1.state == "unknown"))
    booking |> Ecto.Changeset.change(status: "active") |> Repo.update!()
    assert {:ok, results} = Templates.generate(at(day))
    assert Enum.all?(results, &(&1.result == :created))
    assert Repo.aggregate(Quest, :count) == 5
    assert Guests.snapshot(Date.add(day, 1)) == "empty"
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "legacy completed week is not reoffered and original award identity survives", %{
    p: p,
    today: day
  } do
    {:ok, task} = Adventure.activate_quest(p.id, "prepare_stay")
    {:ok, done} = Adventure.complete_manual_quest(p.id, task.id)
    award = Repo.one!(XpTransaction)
    monday = Date.beginning_of_week(day)
    template = Repo.get_by!(TaskTemplate, seed_key: "legacy:#{p.id}:prepare_stay")

    template
    |> Ecto.Changeset.change(status: "active", starts_on: monday, next_due_on: monday)
    |> Repo.update!()

    assert {:ok, [%{result: :already_recorded}]} = Templates.generate(at(day))
    assert Repo.aggregate(Quest, :count) == 1
    assert Repo.get!(Quest, task.id).definition_snapshot == done.definition_snapshot
    assert Repo.one!(XpTransaction) == award
    assert {:ok, _} = Adventure.activate_quest(p.id, "prepare_stay")
    assert Repo.aggregate(Quest, :count) == 1
  end

  test "legacy active instance is adopted without rewriting UUID, snapshot or ownership", %{
    p: p,
    today: day
  } do
    {:ok, old} = Adventure.activate_quest(p.id, "prepare_stay")
    template = Repo.get_by!(TaskTemplate, seed_key: "legacy:#{p.id}:prepare_stay")

    template
    |> Ecto.Changeset.change(
      status: "active",
      starts_on: Date.beginning_of_week(day),
      next_due_on: Date.beginning_of_week(day)
    )
    |> Repo.update!()

    assert {:ok, [%{result: :rolled}]} = Templates.generate(at(day))
    adopted = Repo.get!(Quest, old.id)
    assert adopted.template_id == template.id
    assert adopted.profile_id == old.profile_id
    assert adopted.definition_snapshot == old.definition_snapshot
    assert Repo.aggregate(Quest, :count) == 1
    assert {:ok, _} = Templates.set_status(p.id, template.id, "paused", "cancel")
    assert {:error, :immutable_task} = Adventure.complete_manual_quest(p.id, old.id)
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "Prague DST changes do not duplicate occurrences or drift the due date", %{p: p} do
    first = ~D[2026-10-25]
    active(p, first)
    assert {:ok, [%{result: :created}]} = Templates.generate(~U[2026-10-24 22:00:00Z])
    assert {:ok, []} = Templates.generate(~U[2026-10-25 00:30:00Z])
    assert {:ok, []} = Templates.generate(~U[2026-10-25 01:30:00Z])
    assert {:ok, [%{result: :rolled}]} = Templates.generate(~U[2026-10-25 23:00:00Z])
    task = Repo.one!(Quest)
    assert task.first_due_on == first
    assert task.due_on == ~D[2026-10-26]
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "recurrence writes only game tables", %{p: p, today: day} do
    {_, queries} =
      QueryRecorder.record(fn ->
        template = active(p, day)
        {:ok, _} = Templates.generate(at(day))
        {:ok, _} = Templates.update(p.id, template.id, %{"title" => "Nová verze"})
        {:ok, _} = Templates.set_status(p.id, template.id, "paused", "cancel")
      end)

    writes = Enum.filter(queries, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM)/, &1))
    assert writes != []
    assert Enum.all?(writes, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM) "adventure_/, &1))
  end

  test "disabled worker and all template entry points perform no database work", %{
    p: p,
    today: day
  } do
    t = active(p, day)
    Application.put_env(:cozy_checkout, :adventure_enabled, false)

    {_, queries} =
      QueryRecorder.record(fn ->
        assert Templates.list() == []
        assert Templates.history() == []
        assert {:error, :disabled} = Templates.seed_legacy([p])
        assert {:error, :disabled} = Templates.generate()
        assert {:error, :disabled} = Templates.refresh(p.id)
        assert {:error, :disabled} = Templates.create(p.id, %{})
        assert {:error, :disabled} = Templates.update(p.id, t.id, %{})
        assert {:error, :disabled} = Templates.set_status(p.id, t.id, "paused", "keep")
        assert {:error, :disabled} = Templates.add_examples(p.id)
        assert :ok = CozyCheckout.Adventure.RecurrenceWorker.perform(%Oban.Job{})
      end)

    assert queries == []
  end
end

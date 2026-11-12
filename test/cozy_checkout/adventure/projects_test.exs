defmodule CozyCheckout.Adventure.ProjectsTest do
  use CozyCheckout.DataCase, async: false
  alias CozyCheckout.{Adventure, QueryRecorder, Repo}

  alias CozyCheckout.Adventure.{
    Profile,
    Project,
    ProjectEvent,
    ProjectStage,
    Projects,
    Quest,
    Tasks,
    XpTransaction
  }

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    {:ok, :ok} = Adventure.initialize()
    %{actor: Repo.get_by!(Profile, slug: "michal"), other: Repo.get_by!(Profile, slug: "lucka")}
  end

  test "only a title is required; budgets remain optional plans and create retries keep history",
       %{actor: actor} do
    key = Ecto.UUID.generate()

    assert {:ok, project} =
             Projects.create(
               actor.id,
               %{"title" => "Vlastní nápad", "purpose" => "", "reference" => ""},
               key
             )

    assert project.status == "idea"
    assert project.budget == nil
    assert project.purpose == ""
    assert project.reference == ""
    assert {:ok, same} = Projects.create(actor.id, %{"title" => "Přepsat"}, key)
    assert same.id == project.id
    assert same.title == "Vlastní nápad"
    assert [%{action: "created", version: 1, actor_id: id}] = Projects.history(project.id)
    assert id == actor.id
    assert Repo.aggregate(Project, :count) == 1
    assert Repo.aggregate(Quest, :count) == 0
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "validation rejects bad plans and edits without modifying audit", %{actor: actor} do
    for attrs <- [
          %{"title" => ""},
          %{"title" => "X", "budget" => "-1"},
          %{"title" => "X", "budget" => "1.234"},
          %{"title" => "X", "currency" => "cash"},
          %{"title" => "X", "area" => "bank"}
        ] do
      assert {:error, %Ecto.Changeset{}} = Projects.create(actor.id, attrs, Ecto.UUID.generate())
    end

    project = project(actor)

    assert {:error, %Ecto.Changeset{}} =
             Projects.update(actor.id, project.id, %{"budget" => "invalid"})

    assert {:error, %Ecto.Changeset{}} = Projects.update(actor.id, project.id, %{"title" => ""})

    assert {:ok, updated} =
             Projects.update(actor.id, project.id, %{
               "budget" => "25000.50",
               "currency" => "EUR",
               "price_basis" => "excluding_vat"
             })

    assert Decimal.equal?(updated.budget, Decimal.new("25000.50"))
    assert length(Projects.history(project.id)) == 2

    assert {:error, :invalid_profile} =
             Projects.create("bad", %{"title" => "X"}, Ecto.UUID.generate())

    assert {:error, :not_found} = Projects.update(actor.id, "bad", %{})
    assert {:error, :invalid_request} = Projects.create(actor.id, %{"title" => "X"}, "bad")
  end

  test "stages reuse quests and can be detached without losing their original snapshot", %{
    actor: actor
  } do
    project = project(actor)
    {:ok, quest} = Tasks.create(actor.id, %{"title" => "Skutečný úkol"})
    assert {:ok, _} = Projects.add_stage(actor.id, project.id, quest.id, "Jasný výstup")
    assert {:ok, _} = Projects.add_stage(actor.id, project.id, quest.id, "Opakovaný klik")
    assert Repo.aggregate(ProjectStage, :count) == 1
    assert [%{stages: [{stage, _}]}] = Projects.list()
    assert stage.quest_snapshot["title"] == "Skutečný úkol"
    assert stage.output == "Jasný výstup"
    assert {:ok, _} = Tasks.update(actor.id, quest.id, %{"title" => "Upravené zadání"})
    assert {:ok, _} = Projects.remove_stage(actor.id, project.id, stage.id)
    assert [%{stages: []}] = Projects.list()
    assert Repo.get!(ProjectStage, stage.id).archived_at
    assert {:ok, _} = Projects.add_stage(actor.id, project.id, quest.id, "Restore")
    assert [%{stages: [{restored, _}]}] = Projects.list()
    assert restored.id == stage.id
    assert restored.quest_snapshot == stage.quest_snapshot

    assert Enum.map(Projects.history(project.id), & &1.action) == [
             "stage_restored",
             "stage_removed",
             "stage_added",
             "created"
           ]

    assert {:ok, _} = Projects.update_stage(actor.id, project.id, stage.id, "Upřesněný výstup")
    assert Repo.get!(ProjectStage, stage.id).output == "Upřesněný výstup"
    assert hd(Projects.history(project.id)).snapshot["previous_output"] == "Jasný výstup"
    assert {:error, %Ecto.Changeset{}} = Projects.update_stage(actor.id, project.id, stage.id, "")
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "state machine freezes approved plans, supports pause and never auto accepts", %{
    actor: actor
  } do
    {project, quest} = prepared(actor)
    assert {:error, :invalid_transition} = Projects.transition(actor.id, project.id, "accepted")

    assert {:error, :immutable_project} =
             Projects.update(actor.id, project.id, %{"title" => "Rewrite"})

    assert {:error, :immutable_project} =
             Projects.add_stage(actor.id, project.id, quest.id, "More")

    assert {:ok, _} = Projects.transition(actor.id, project.id, "paused")
    assert {:ok, _} = Projects.transition(actor.id, project.id, "approved")
    assert {:ok, _} = Projects.transition(actor.id, project.id, "active")
    {:ok, _} = Tasks.start(actor.id, quest.id)
    {:ok, _} = Tasks.complete(actor.id, quest.id)
    assert Repo.get!(Project, project.id).status == "active"

    assert {:error, :confirmation_required} =
             Projects.accept(actor.id, project.id, %{"contributors" => [actor.id]})

    assert Repo.get!(Project, project.id).acceptance == %{}
  end

  test "one explicit approval starts a draft and locks its plan and stages", %{actor: actor} do
    p = project(actor)
    {:ok, q} = Tasks.create(actor.id, %{"title" => "První krok"})
    {:ok, _} = Projects.add_stage(actor.id, p.id, q.id, nil)
    stage = Repo.get_by!(ProjectStage, project_id: p.id)
    assert stage.output == "První krok"
    assert {:ok, active} = Projects.transition(actor.id, p.id, "active")
    assert active.status == "active"
    assert Enum.map(Projects.history(p.id), & &1.snapshot["status"]) == ["active", "idea", "idea"]
    assert Repo.get!(Quest, q.id).status == "waiting"

    for target <- ["active", "paused"] do
      assert {:ok, _} = Projects.transition(actor.id, p.id, target)
      assert {:error, :immutable_project} = Projects.update(actor.id, p.id, %{"title" => "Jiné"})

      assert {:error, :immutable_project} =
               Projects.update_stage(actor.id, p.id, stage.id, "Jiné")

      assert {:error, :immutable_project} = Projects.remove_stage(actor.id, p.id, stage.id)

      assert {:error, :immutable_project} =
               Projects.create_stage(actor.id, p.id, %{"title" => "Navíc"})
    end

    assert {:ok, resumed} = Projects.transition(actor.id, p.id, "active")
    assert resumed.status == "active"
    assert Repo.aggregate(Quest, :count) == 1
    assert Repo.aggregate(XpTransaction, :count) == 0
    assert {:error, :invalid_transition} = Projects.transition(actor.id, p.id, "idea")
  end

  test "historic ready and approved states and their audit remain usable", %{actor: actor} do
    for legacy <- ["ready", "approved"] do
      p = project(actor, "Historický #{legacy}")
      {:ok, _} = Projects.transition(actor.id, p.id, "ready")
      if legacy == "approved", do: Projects.transition(actor.id, p.id, "approved")
      assert Repo.get!(Project, p.id).status == legacy
      assert {:ok, %{status: "active"}} = Projects.transition(actor.id, p.id, "active")
      assert Enum.any?(Projects.history(p.id), &(&1.snapshot["status"] == legacy))
    end
  end

  test "inline steps use genuine waiting Tasks, optional settings and one quest reward", %{
    actor: actor,
    other: other
  } do
    p = project(actor)
    assert {:ok, _} = Projects.create_stage(actor.id, p.id, %{"title" => "  Nová práce  "})
    assert [%{stages: [{stage, q}]}] = Projects.list()
    assert stage.output == "Nová práce"
    assert stage.quest_snapshot == q.definition_snapshot
    assert q.managed
    assert q.status == "waiting"
    assert q.created_by_id == actor.id
    assert q.assigned_profile_id == nil
    assert q.due_on == nil
    assert q.definition_snapshot["xp"] == 50

    assert {:ok, _} =
             Projects.create_stage(actor.id, p.id, %{
               "title" => "Společná práce",
               "scope" => "shared",
               "assigned_profile_id" => other.id,
               "size" => "large",
               "xp" => "125",
               "category" => "Údržba",
               "priority" => "high",
               "due_on" => "2026-11-12",
               "output" => "Funkční výsledek"
             })

    shared = Repo.one!(from q in Quest, where: q.scope == "shared")
    assert shared.assigned_profile_id == nil
    assert shared.definition_snapshot["xp"] == 125
    assert shared.category == "Údržba"
    assert shared.priority == "high"
    assert shared.due_on == ~D[2026-11-12]
    assert Repo.get_by!(ProjectStage, quest_id: shared.id).output == "Funkční výsledek"
    assert Repo.aggregate(XpTransaction, :count) == 0
    {:ok, _} = Tasks.start(actor.id, shared.id)
    {:ok, _} = Tasks.complete(actor.id, shared.id, %{"contributors" => [actor.id, other.id]})
    assert [%{amount: 125, recipient_type: "shared"}] = Repo.all(XpTransaction)
  end

  test "inline creation rolls back quest, stage and audit on validation failures", %{actor: actor} do
    p = project(actor)

    for attrs <- [
          %{"title" => ""},
          %{"title" => "X", "xp" => "0"},
          %{"title" => "X", "due_on" => "invalid"},
          %{"title" => "X", "scope" => "invalid"},
          %{"title" => "X", "output" => String.duplicate("x", 2001)}
        ] do
      assert {:error, %Ecto.Changeset{}} = Projects.create_stage(actor.id, p.id, attrs)
      assert Repo.aggregate(Quest, :count) == 0
      assert Repo.aggregate(ProjectStage, :count) == 0
      assert [%{action: "created"}] = Projects.history(p.id)
    end

    assert {:error, :invalid_profile} =
             Projects.create_stage(actor.id, p.id, %{
               "title" => "X",
               "assigned_profile_id" => Ecto.UUID.generate()
             })

    assert {:error, :not_found} = Projects.create_stage(actor.id, "bad", %{"title" => "X"})
    assert Repo.aggregate(Quest, :count) == 0
    assert {:ok, _} = Projects.create_stage(actor.id, p.id, %{"title" => "Po chybě"})
    assert Repo.aggregate(Quest, :count) == 1
  end

  test "inline mutation SELECT count stays bounded as stages grow and writes only Adventure", %{
    actor: actor
  } do
    p = project(actor)

    for i <- 1..8 do
      {{:ok, _}, queries} =
        QueryRecorder.record(fn ->
          Projects.create_stage(actor.id, p.id, %{"title" => "Krok #{i}"})
        end)

      assert length(selects(queries)) == 7
      writes = Enum.filter(queries, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM)/, &1))

      assert Enum.all?(
               writes,
               &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM) "adventure_/, &1)
             )
    end

    {{:ok, _}, assigned_queries} =
      QueryRecorder.record(fn ->
        Projects.create_stage(actor.id, p.id, %{
          "title" => "Přiřazený krok",
          "assigned_profile_id" => actor.id
        })
      end)

    assert length(selects(assigned_queries)) == 8
    assert Repo.aggregate(Quest, :count) == 9
    assert Repo.aggregate(ProjectStage, :count) == 9
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "acceptance is human, atomic, idempotent and adds no XP; independent of seasons", %{
    actor: actor,
    other: other
  } do
    {project, quest} = prepared(actor)

    attrs = %{
      "confirmed" => "true",
      "contributors" => [actor.id, other.id],
      "result" => "Funkční výsledek"
    }

    assert {:error, :unfinished_stages} = Projects.accept(actor.id, project.id, attrs)
    {:ok, _} = Tasks.start(actor.id, quest.id)
    {:ok, _} = Tasks.complete(other.id, quest.id)

    assert {:error, :contributors_required} =
             Projects.accept(actor.id, project.id, Map.put(attrs, "contributors", []))

    assert {:error, :contributors_required} =
             Projects.accept(
               actor.id,
               project.id,
               Map.put(attrs, "contributors", [Ecto.UUID.generate()])
             )

    assert {:error, :invalid_result} =
             Projects.accept(
               actor.id,
               project.id,
               Map.put(attrs, "result", String.duplicate("x", 5001))
             )

    assert Repo.get!(Project, project.id).status == "active"
    awards = Repo.all(XpTransaction)

    {{:ok, accepted}, queries} =
      QueryRecorder.record(fn -> Projects.accept(actor.id, project.id, attrs) end)

    assert length(selects(queries)) == 4
    assert accepted.status == "accepted"
    assert accepted.acceptance["actor_id"] == actor.id
    assert accepted.acceptance["contributors"] == Enum.sort([actor.id, other.id])

    assert [%{"quest_id" => quest_id, "evidence" => %{"actor_profile_id" => completer}}] =
             accepted.acceptance["stages"]

    assert quest_id == quest.id
    assert completer == other.id

    assert {:ok, replay} =
             Projects.accept(other.id, project.id, %{"confirmed" => "true", "result" => "Rewrite"})

    assert replay.acceptance == accepted.acceptance
    assert Repo.all(XpTransaction) == awards
    assert {:error, :invalid_transition} = Projects.transition(actor.id, project.id, "active")
    assert {:ok, archived} = Projects.archive(actor.id, project.id)
    assert archived.acceptance == accepted.acceptance
    assert {:ok, _} = Projects.archive(actor.id, project.id)
    {:ok, _} = Tasks.archive(actor.id, quest.id)
    assert [%{project: saved, stages: [{_, linked}]}] = Projects.list()
    assert saved.id == project.id
    assert saved.acceptance == accepted.acceptance
    assert linked.id == quest.id
    refute Map.has_key?(saved, :campaign_id)

    for {name, first, last} <- [
          {"První sezóna", ~D[2026-12-01], ~D[2027-03-31]},
          {"Další sezóna", ~D[2027-12-01], ~D[2028-03-31]}
        ] do
      assert {:ok, _} =
               CozyCheckout.Adventure.Campaigns.create(%{
                 name: name,
                 starts_on: first,
                 ends_on: last,
                 rules_version: "season_v1"
               })

      assert [%{project: same, stages: [{_, same_quest}]}] = Projects.list()
      assert same.id == saved.id
      assert same.acceptance == saved.acceptance
      assert same_quest.id == quest.id
      assert Projects.world().counts == [{"workshop", "accepted", 1}]
      assert [chronicle_entry] = Projects.chronicle()
      assert chronicle_entry.acceptance == accepted.acceptance
    end

    assert Enum.count(Projects.history(project.id), &(&1.action == "accepted")) == 1
    assert Repo.all(XpTransaction) == awards
  end

  test "cancel and archive preserve history and never alter linked work", %{actor: actor} do
    {project, quest} = prepared(actor)
    assert {:ok, _} = Projects.transition(actor.id, project.id, "cancelled")
    assert {:ok, _} = Projects.archive(actor.id, project.id)
    assert {:error, :invalid_transition} = Projects.transition(actor.id, project.id, "idea")
    assert Repo.get!(Quest, quest.id).status == "waiting"
    assert Repo.aggregate(XpTransaction, :count) == 0
    assert length(Projects.history(project.id)) == 7
  end

  test "acceptance query budget stays four with many completed stages", %{actor: actor} do
    p = project(actor)

    for i <- 1..8 do
      {:ok, quest} = Tasks.create(actor.id, %{"title" => "Práce #{i}"})
      {:ok, _} = Projects.add_stage(actor.id, p.id, quest.id, "Výstup #{i}")
      {:ok, _} = Tasks.start(actor.id, quest.id)
      {:ok, _} = Tasks.complete(actor.id, quest.id)
    end

    for status <- ~w(ready approved active),
        do: assert({:ok, _} = Projects.transition(actor.id, p.id, status))

    {{:ok, accepted}, queries} =
      QueryRecorder.record(fn ->
        Projects.accept(actor.id, p.id, %{"confirmed" => "true", "contributors" => [actor.id]})
      end)

    assert length(selects(queries)) == 4
    assert length(accepted.acceptance["stages"]) == 8
    assert Repo.aggregate(XpTransaction, :count) == 8
  end

  test "list and audit budgets are independent of projects and stages; writes only Adventure", %{
    actor: actor
  } do
    {[], empty} = QueryRecorder.record(&Projects.list/0)
    assert length(selects(empty)) == 2

    {_, writes} =
      QueryRecorder.record(fn ->
        for i <- 1..7 do
          p = project(actor, "Plán #{i}")

          for j <- 1..5 do
            {:ok, q} = Tasks.create(actor.id, %{"title" => "Quest #{i}/#{j}"})
            {:ok, _} = Projects.add_stage(actor.id, p.id, q.id, "Výstup #{j}")
          end
        end
      end)

    writes = Enum.filter(writes, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM)/, &1))
    assert writes != []
    assert Enum.all?(writes, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM) "adventure_/, &1))
    {rows, populated} = QueryRecorder.record(&Projects.list/0)
    assert length(rows) == 7
    assert Enum.all?(rows, &(length(&1.stages) == 5))
    assert length(selects(populated)) == 2
    {_, audit} = QueryRecorder.record(fn -> Projects.history(hd(rows).project.id) end)
    assert length(selects(audit)) == 1
    {results, search} = QueryRecorder.record(fn -> Projects.search_quests("Quest") end)
    assert length(results) == 30
    assert length(selects(search)) == 1
    assert {[], []} = QueryRecorder.record(fn -> Projects.search_quests("") end)
  end

  test "project list is capped, selected audit keeps the latest fifty events", %{actor: actor} do
    for i <- 1..101, do: project(actor, "Plán #{i}")
    assert length(Projects.list()) == 100
    assert [%{project: %{title: "Plán 101"}}] = Projects.list("Plán 101")
    p = project(actor)

    for i <- 1..55,
        do: assert({:ok, _} = Projects.update(actor.id, p.id, %{"title" => "Verze #{i}"}))

    events = Projects.history(p.id)
    assert length(events) == 50
    assert hd(events).version == 56
    assert List.last(events).version == 7
    assert Repo.aggregate(ProjectEvent, :count) == 157
  end

  test "project audit rows reject SQL rewrites and deletes", %{actor: actor} do
    p = project(actor)

    for statement <- [
          "UPDATE adventure_project_events SET action = 'rewrite' WHERE project_id = $1",
          "DELETE FROM adventure_project_events WHERE project_id = $1"
        ] do
      # Let Sandbox manage query savepoints; its release also removes nested SQL savepoints.
      assert_raise Postgrex.Error, ~r/Adventure project history is immutable/, fn ->
        Repo.query!(statement, [Ecto.UUID.dump!(p.id)], mode: :savepoint)
      end

      assert [%{action: "created"}] = Projects.history(p.id)
    end
  end

  test "disabled module blocks new queries and writes", %{actor: actor} do
    p = project(actor)
    Application.put_env(:cozy_checkout, :adventure_enabled, false)

    {_, queries} =
      QueryRecorder.record(fn ->
        assert Projects.list() == []
        assert Projects.history(p.id) == []
        assert Projects.search_quests("Quest") == []
        assert Projects.world() == %{counts: [], projects: []}
        assert Projects.chronicle() == []

        assert {:error, :disabled} =
                 Projects.create(actor.id, %{"title" => "X"}, Ecto.UUID.generate())

        assert {:error, :disabled} = Projects.update(actor.id, p.id, %{})
        assert {:error, :disabled} = Projects.transition(actor.id, p.id, "ready")
        assert {:error, :disabled} = Projects.accept(actor.id, p.id, %{})
        assert {:error, :disabled} = Projects.archive(actor.id, p.id)
        assert {:error, :disabled} = Projects.add_stage(actor.id, p.id, Ecto.UUID.generate(), "X")
        assert {:error, :disabled} = Projects.create_stage(actor.id, p.id, %{"title" => "X"})
        assert {:error, :disabled} = Projects.remove_stage(actor.id, p.id, Ecto.UUID.generate())

        assert {:error, :disabled} =
                 Projects.update_stage(actor.id, p.id, Ecto.UUID.generate(), "X")
      end)

    assert queries == []
  end

  test "world milestones come only from human acceptance and survive archive and seasons", %{
    actor: actor
  } do
    {%{counts: [], projects: []}, empty_queries} = QueryRecorder.record(&Projects.world/0)
    assert length(selects(empty_queries)) == 2
    {p, quest} = prepared(actor)
    {:ok, _} = Tasks.start(actor.id, quest.id)
    {:ok, _} = Tasks.complete(actor.id, quest.id)
    assert Projects.world().counts == [{"workshop", "active", 1}]
    assert Projects.chronicle() == []

    {:ok, accepted} =
      Projects.accept(actor.id, p.id, %{
        "confirmed" => "true",
        "contributors" => [actor.id],
        "result" => "Trvalý výsledek"
      })

    awards = Repo.all(XpTransaction)
    {:ok, _} = Projects.archive(actor.id, p.id)
    {world, queries} = QueryRecorder.record(&Projects.world/0)
    assert world.counts == [{"workshop", "accepted", 1}]
    assert [saved] = world.projects
    assert saved.archived_at
    assert saved.acceptance == accepted.acceptance
    assert length(selects(queries)) == 2
    assert Enum.all?(queries, &String.starts_with?(&1, "SELECT"))
    assert [entry] = Projects.chronicle()
    assert entry.acceptance["result"] == "Trvalý výsledek"
    assert Repo.all(XpTransaction) == awards
  end

  test "world aggregate is complete beyond bounded projects; chronicle pages include old archived outcomes",
       %{actor: actor} do
    old = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-86_400)

    for i <- 1..22 do
      Repo.insert!(%Project{
        title: "Historický výsledek #{i}",
        area: Enum.at(Project.areas(), rem(i, 6)),
        request_key: Ecto.UUID.generate(),
        status: "accepted",
        acceptance: %{
          "confirmed_at" => DateTime.to_iso8601(DateTime.add(old, i)),
          "actor_id" => actor.id,
          "contributors" => [actor.id],
          "result" => "Převzato #{i}"
        },
        archived_at: old,
        inserted_at: old,
        updated_at: old
      })
    end

    for i <- 1..101, do: project(actor, "Novější plán #{i}")
    {world, queries} = QueryRecorder.record(&Projects.world/0)
    assert length(selects(queries)) == 2
    assert length(world.projects) == 100
    assert Enum.all?(world.projects, &(&1.status == "idea"))

    assert world.counts
           |> Enum.filter(&(elem(&1, 1) == "accepted"))
           |> Enum.map(&elem(&1, 2))
           |> Enum.sum() == 22

    {first, first_queries} = QueryRecorder.record(fn -> Projects.chronicle(0) end)
    {second, second_queries} = QueryRecorder.record(fn -> Projects.chronicle(1) end)
    assert length(first) == 21
    assert length(second) == 2
    assert length(selects(first_queries)) == 1
    assert length(selects(second_queries)) == 1

    assert MapSet.disjoint?(
             MapSet.new(Enum.take(first, 20), & &1.id),
             MapSet.new(second, & &1.id)
           )

    assert Enum.all?(first ++ second, & &1.archived_at)
    assert [%{project: focused}] = Projects.list("", List.last(second).id)
    assert focused.id == List.last(second).id
  end

  defp project(actor, title \\ "Dlouhodobý plán") do
    {:ok, project} = Projects.create(actor.id, %{"title" => title}, Ecto.UUID.generate())
    project
  end

  defp prepared(actor) do
    p = project(actor)
    {:ok, quest} = Tasks.create(actor.id, %{"title" => "Skutečná práce"})
    {:ok, _} = Projects.add_stage(actor.id, p.id, quest.id, "Funkční výsledek")

    for status <- ~w(ready approved active),
        do: assert({:ok, _} = Projects.transition(actor.id, p.id, status))

    {Repo.get!(Project, p.id), quest}
  end

  defp selects(queries), do: Enum.filter(queries, &String.starts_with?(&1, "SELECT"))
end

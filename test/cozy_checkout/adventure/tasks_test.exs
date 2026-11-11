defmodule CozyCheckout.Adventure.TasksTest do
  use CozyCheckout.DataCase, async: false
  alias CozyCheckout.{Adventure, QueryRecorder, Repo}
  alias CozyCheckout.Adventure.{Profile, Quest, Tasks, XpTransaction}

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    {:ok, :ok} = Adventure.initialize()
    %{michal: Repo.get_by!(Profile, slug: "michal"), lucka: Repo.get_by!(Profile, slug: "lucka")}
  end

  test "quick creation needs only title; backlog does not consume active slots", %{michal: p} do
    for i <- 1..5 do
      assert {:ok, task} = Tasks.create(p.id, %{"title" => "Práce #{i}"})
      assert task.status == "waiting"
      assert task.definition_snapshot["xp"] == 50
      assert task.profile_id == nil
      assert task.assigned_profile_id == nil
    end

    assert length(Tasks.list(p.id)) == 5
    assert {:ok, _} = Adventure.activate_quest(p.id, "improvement")
    assert {:ok, %{total_xp: 0}} = Adventure.dashboard(p.id)
  end

  test "managed and catalog quests share a limit in both directions", %{michal: p} do
    {:ok, _} = Adventure.activate_quest(p.id, "prepare_stay")
    {:ok, first} = Tasks.create(p.id, %{"title" => "První"})
    {:ok, second} = Tasks.create(p.id, %{"title" => "Druhý"})
    {:ok, third} = Tasks.create(p.id, %{"title" => "Třetí"})
    assert {:ok, _} = Tasks.start(p.id, first.id)
    assert {:ok, _} = Tasks.start(p.id, second.id)
    assert {:error, :active_limit} = Tasks.start(p.id, third.id)
    assert {:error, :active_limit} = Adventure.activate_quest(p.id, "improvement")
    assert {:ok, _} = Tasks.archive(p.id, first.id)
    assert {:ok, _} = Tasks.start(p.id, third.id)
  end

  test "assignment is independent of actual completer and replay cannot redirect XP", %{
    michal: p,
    lucka: other
  } do
    {:ok, task} =
      Tasks.create(p.id, %{
        "title" => "Uklidit",
        "size" => "medium",
        "assigned_profile_id" => p.id
      })

    {:ok, _} = Tasks.start(p.id, task.id)
    assert {:ok, done} = Tasks.complete(other.id, task.id)
    assert done.evidence["assigned_profile_id"] == p.id
    assert done.evidence["actor_profile_id"] == other.id
    assert {:ok, _} = Tasks.complete(p.id, task.id, %{"note" => "Změnit historii"})
    award = Repo.one!(XpTransaction)
    assert award.profile_id == other.id
    assert award.amount == 100
    assert Repo.get!(Quest, task.id).evidence == done.evidence
    assert {:ok, %{total_xp: 100, quests: [%{id: id}]}} = Adventure.dashboard(other.id)
    assert id == task.id
    assert {:ok, %{total_xp: 0}} = Adventure.dashboard(p.id)
  end

  test "free task can be taken by another hero without changing the original assignment audit", %{
    michal: p,
    lucka: other
  } do
    {:ok, task} = Tasks.create(p.id, %{"title" => "Převzít práci", "assigned_profile_id" => p.id})
    assert {:ok, started} = Tasks.start(other.id, task.id)
    assert started.assigned_profile_id == other.id
    assert started.evidence["assignment_before_start"] == p.id
  end

  test "shared completion requires explicit contributors and gives only one shared reward", %{
    michal: p,
    lucka: other
  } do
    {:ok, task} =
      Tasks.create(p.id, %{"title" => "Opravit terasu", "scope" => "shared", "size" => "large"})

    assert {:error, :immutable_task} = Tasks.complete(p.id, task.id)
    {:ok, _} = Tasks.start(p.id, task.id)
    assert {:error, :contributors_required} = Tasks.complete(p.id, task.id)

    assert {:error, :contributors_required} =
             Tasks.complete(p.id, task.id, %{"contributors" => ["bad"]})

    assert Repo.get!(Quest, task.id).status == "active"

    assert {:ok, done} =
             Tasks.complete(p.id, task.id, %{"contributors" => [p.id, other.id, p.id]})

    assert done.evidence["contributor_profile_ids"] == Enum.sort([p.id, other.id])
    assert {:ok, _} = Tasks.complete(other.id, task.id, %{"contributors" => [other.id]})

    assert %XpTransaction{recipient_type: "shared", profile_id: nil, amount: 250} =
             Repo.one!(XpTransaction)

    assert {:ok, %{total_xp: 250}} = CozyCheckout.Adventure.Campaigns.overview()
    assert {:ok, %{total_xp: 0}} = Adventure.dashboard(p.id)
    assert {:ok, %{total_xp: 0}} = Adventure.dashboard(other.id)
  end

  test "definition edits stop at activation; archive preserves reward and evidence", %{michal: p} do
    {:ok, task} = Tasks.create(p.id, %{"title" => "Původní", "xp" => 75})
    assert {:ok, edited} = Tasks.update(p.id, task.id, %{"title" => "Nový název", "xp" => 90})
    assert edited.definition_snapshot["xp"] == 90
    {:ok, _} = Tasks.start(p.id, task.id)
    assert {:error, :immutable_task} = Tasks.update(p.id, task.id, %{"xp" => 1000})
    {:ok, completed} = Tasks.complete(p.id, task.id, %{"note" => "OK"})
    award = Repo.one!(XpTransaction)
    {:ok, archived} = Tasks.archive(p.id, task.id)
    assert archived.status == "completed"
    assert archived.completed_at == completed.completed_at
    assert archived.evidence["note"] == "OK"
    assert Repo.one!(XpTransaction) == award
    assert Tasks.list(p.id) == []
    assert [%{id: id}] = Tasks.list(p.id, %{"status" => "archived"})
    assert id == task.id
    assert {:error, :immutable_task} = Tasks.start(p.id, task.id)
  end

  test "failed award rolls back completion, including evidence", %{michal: p} do
    {:ok, task} = Tasks.create(p.id, %{"title" => "Úkol"})
    {:ok, started} = Tasks.start(p.id, task.id)

    started
    |> Ecto.Changeset.change(definition_snapshot: %{"title" => "Vadný", "xp" => 0})
    |> Repo.update!()

    assert {:error, %Ecto.Changeset{}} = Tasks.complete(p.id, task.id)
    unchanged = Repo.get!(Quest, task.id)
    assert unchanged.status == "active"
    assert unchanged.completed_at == nil
    assert unchanged.evidence == started.evidence
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "validation, filters, disabled module and malformed IDs", %{michal: p} do
    assert {:error, %Ecto.Changeset{}} = Tasks.create(p.id, %{"title" => "  "})
    assert {:error, %Ecto.Changeset{}} = Tasks.create(p.id, %{"title" => "X", "xp" => -1})
    assert {:error, :invalid_profile} = Tasks.create("bad", %{"title" => "X"})
    assert {:error, :not_found} = Tasks.start(p.id, "bad")
    {:ok, task} = Tasks.create(p.id, %{"title" => "Doplnit bar", "category" => "Bar"})

    assert [%{id: id}] =
             Tasks.list(p.id, %{
               "scope" => "free",
               "search" => "BAR",
               "category" => "Bar",
               "due" => "none"
             })

    assert id == task.id
    assert Tasks.list(p.id, %{"scope" => "mine"}) == []
    assert Tasks.list(p.id, %{"search" => "%"}) == []
    Application.put_env(:cozy_checkout, :adventure_enabled, false)
    assert Tasks.list(p.id) == []
    assert {:error, :disabled} = Tasks.create(p.id, %{"title" => "X"})
    assert {:error, :disabled} = Tasks.update(p.id, task.id, %{})
    assert {:error, :disabled} = Tasks.start(p.id, task.id)
    assert {:error, :disabled} = Tasks.complete(p.id, task.id)
    assert {:error, :disabled} = Tasks.archive(p.id, task.id)
  end

  test "query count is constant and all writes stay in Adventure", %{michal: p} do
    {_, empty} = QueryRecorder.record(fn -> Tasks.list(p.id) end)

    {_, queries} =
      QueryRecorder.record(fn ->
        for _ <- 1..4 do
          {:ok, task} = Tasks.create(p.id, %{"title" => "Práce"})
          {:ok, _} = Tasks.start(p.id, task.id)
          {:ok, _} = Tasks.complete(p.id, task.id)
        end
      end)

    writes = Enum.filter(queries, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM)/, &1))
    assert writes != []
    assert Enum.all?(writes, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM) "adventure_/, &1))
    {_, populated} = QueryRecorder.record(fn -> Tasks.list(p.id, %{"status" => "all"}) end)
    assert length(empty) == 1
    assert length(populated) == 1
  end
end

defmodule CozyCheckout.Adventure.QuickTasksTest do
  use CozyCheckout.DataCase, async: false
  alias CozyCheckout.{Adventure, QueryRecorder, Repo}
  alias CozyCheckout.Adventure.{Profile, Quest, Tasks, XpTransaction}

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    {:ok, _} = Adventure.initialize()
    %{actor: Repo.get_by!(Profile, slug: "michal"), other: Repo.get_by!(Profile, slug: "lucka")}
  end

  test "personal quick creation is atomic, pins the actor and preserves chosen size and category",
       %{actor: actor, other: other} do
    id = Ecto.UUID.generate()

    {{:ok, task}, queries} =
      QueryRecorder.record(fn ->
        Tasks.quick_create(
          actor.id,
          %{
            "title" => "Opravit lavici",
            "size" => "medium",
            "category" => "Údržba",
            "scope" => "shared",
            "assigned_profile_id" => other.id,
            "xp" => 9999
          },
          id,
          "mine"
        )
      end)

    assert Enum.count(queries, &String.starts_with?(&1, "SELECT")) == 4
    assert task.id == id
    assert task.status == "active"
    assert task.scope == "personal"
    assert task.assigned_profile_id == actor.id
    assert task.category == "Údržba"
    assert task.definition_snapshot["xp"] == 100
    assert Repo.aggregate(XpTransaction, :count) == 0
    assert {:ok, replay} = Tasks.quick_create(actor.id, %{"title" => "Změněné"}, id, "free")
    assert replay.id == id
    assert replay.definition_snapshot == task.definition_snapshot
    assert Repo.aggregate(Quest, :count) == 1
  end

  test "free tasks and assigned backlog consume no active slot", %{actor: actor, other: other} do
    for mode <- ["free", "later"] do
      assert {:ok, task} =
               Tasks.quick_create(actor.id, %{"title" => "Na potom"}, Ecto.UUID.generate(), mode)

      assert task.status == "waiting"
      assert task.assigned_profile_id == if(mode == "free", do: nil, else: actor.id)
      assert task.definition_snapshot["xp"] == 50
      assert task.category == "Provoz"

      if mode == "free" do
        assert {:ok, started} = Tasks.start(other.id, task.id)
        assert started.assigned_profile_id == other.id
      end
    end

    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "slot failure rolls back the draft and permits an explicit backlog retry", %{actor: actor} do
    for code <- ~w(prepare_stay review_deposits shopping_plan),
        do: Adventure.activate_quest(actor.id, code)

    id = Ecto.UUID.generate()

    assert {:error, :active_limit} =
             Tasks.quick_create(actor.id, %{"title" => "Čtvrtá"}, id, "mine")

    refute Repo.get(Quest, id)
    assert {:ok, task} = Tasks.quick_create(actor.id, %{"title" => "Čtvrtá"}, id, "later")
    assert task.status == "waiting"
    assert task.assigned_profile_id == actor.id
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "invalid requests, another creator and disabled game cannot create or modify work", %{
    actor: actor,
    other: other
  } do
    id = Ecto.UUID.generate()

    assert {:error, %Ecto.Changeset{}} =
             Tasks.quick_create(actor.id, %{"title" => ""}, id, "free")

    refute Repo.get(Quest, id)
    assert {:error, :invalid_request} = Tasks.quick_create(actor.id, %{}, "bad-id", "mine")
    assert {:error, :invalid_request} = Tasks.quick_create(actor.id, %{}, id, "shared")
    assert {:ok, task} = Tasks.quick_create(actor.id, %{"title" => "Původní"}, id, "free")

    assert {:error, :invalid_request} =
             Tasks.quick_create(other.id, %{"title" => "Přepsat"}, id, "mine")

    assert Repo.get!(Quest, id).definition_snapshot == task.definition_snapshot
    Application.put_env(:cozy_checkout, :adventure_enabled, false)

    assert {{:error, :disabled}, []} =
             QueryRecorder.record(fn ->
               Tasks.quick_create(actor.id, %{}, Ecto.UUID.generate(), "mine")
             end)
  end
end

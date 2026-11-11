defmodule CozyCheckout.AdventureTest do
  use CozyCheckout.DataCase, async: false
  alias CozyCheckout.{Adventure, QueryRecorder, Repo}
  alias CozyCheckout.Adventure.{Profile, Quest, XpTransaction}

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    {:ok, :ok} = Adventure.initialize()

    {:ok,
     profile: Repo.get_by!(Profile, slug: "michal"), other: Repo.get_by!(Profile, slug: "lucka")}
  end

  test "level thresholds use exact integer arithmetic" do
    for {xp, level} <- [{0, 1}, {99, 1}, {100, 2}, {299, 2}, {300, 3}, {-100, 1}] do
      assert Adventure.level(xp) == level
    end

    huge_level = 10_000_000_000
    threshold = div(100 * (huge_level - 1) * huge_level, 2)
    assert Adventure.level(threshold) == huge_level
    assert Adventure.level(threshold - 1) == huge_level - 1
  end

  test "setup is idempotent and reading the dashboard creates no rewards", %{profile: p} do
    assert {:ok, :ok} = Adventure.initialize()
    assert Repo.aggregate(Profile, :count) == 2
    assert {:ok, %{quests: [], total_xp: 0}} = Adventure.dashboard(p.id)
    assert {:ok, _} = Adventure.dashboard(p.id)
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "Prague ISO weeks cross local midnight, DST and ISO year boundaries" do
    assert Adventure.weekly_period(~U[2026-11-01 22:59:59Z]) == "week:2026-10-26"
    assert Adventure.weekly_period(~U[2026-11-01 23:00:00Z]) == "week:2026-11-02"
    assert Adventure.weekly_period(~U[2026-03-29 21:59:59Z]) == "week:2026-03-23"
    assert Adventure.weekly_period(~U[2026-03-29 22:00:00Z]) == "week:2026-03-30"
    assert Adventure.weekly_period(~U[2027-01-01 12:00:00Z]) == "week:2026-12-28"
  end

  test "three active quests are allowed per profile and duplicate activation is harmless", %{
    profile: p,
    other: other
  } do
    for code <- ["prepare_stay", "review_deposits", "shopping_plan"] do
      assert {:ok, _} = Adventure.activate_quest(p.id, code)
    end

    assert {:ok, _} = Adventure.activate_quest(p.id, "prepare_stay")
    assert {:error, :active_limit} = Adventure.activate_quest(p.id, "improvement")
    assert {:ok, _} = Adventure.activate_quest(other.id, "improvement")
    assert Repo.aggregate(Quest, :count) == 4
  end

  test "completion is audited, immutable and awarded once, only to its owner", %{
    profile: p,
    other: other
  } do
    {:ok, quest} = Adventure.activate_quest(p.id, "improvement")

    assert {:error, :not_found} =
             Adventure.complete_manual_quest(other.id, quest.id, "Dokončeno a ověřeno.")

    assert {:error, :evidence_required} = Adventure.complete_manual_quest(p.id, quest.id, "")

    assert {:ok, completed} =
             Adventure.complete_manual_quest(p.id, quest.id, "Zlepšení bylo dokončeno.")

    assert completed.status == "completed"
    assert completed.evidence["actor_profile_id"] == p.id
    assert completed.evidence["attribution"] == "self_selected"

    assert {:ok, ^completed} =
             Adventure.complete_manual_quest(p.id, quest.id, "Jiná poznámka nezmění historii.")

    assert Repo.aggregate(XpTransaction, :count) == 1
    assert {:ok, %{total_xp: 250, level: 2}} = Adventure.dashboard(p.id)
    assert {:ok, %{total_xp: 0}} = Adventure.dashboard(other.id)
    assert {:ok, same} = Adventure.activate_quest(p.id, "improvement")
    assert same.id == quest.id
  end

  test "award failure rolls back quest completion", %{profile: p} do
    {:ok, quest} = Adventure.activate_quest(p.id, "improvement")

    quest
    |> Ecto.Changeset.change(definition_snapshot: Map.put(quest.definition_snapshot, "xp", 0))
    |> Repo.update!()

    assert {:error, %Ecto.Changeset{} = changeset} =
             Adventure.complete_manual_quest(p.id, quest.id, "Dokončeno a ověřeno.")

    assert "must be greater than 0" in errors_on(changeset).amount
    unchanged = Repo.get!(Quest, quest.id)
    assert unchanged.status == "active"
    assert unchanged.completed_at == nil
    assert unchanged.evidence == %{}
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "correction appends exactly one inverse record without rewriting the reward", %{profile: p} do
    {:ok, quest} = Adventure.activate_quest(p.id, "improvement")
    {:ok, _} = Adventure.complete_manual_quest(p.id, quest.id, "Dokončeno a ověřeno.")
    original = Repo.one!(XpTransaction)

    assert {:ok, correction} =
             Adventure.reverse_award(p.id, original.id, "Chybně potvrzené dokončení.")

    assert correction.amount == -250
    assert correction.reverses_id == original.id

    assert {:ok, ^correction} =
             Adventure.reverse_award(p.id, original.id, "Opakovaný požadavek na opravu.")

    assert Repo.get!(XpTransaction, original.id) == original

    assert {:ok, _} =
             Adventure.complete_manual_quest(p.id, quest.id, "Znovu potvrzeno bez nové odměny.")

    assert {:ok, %{total_xp: 0, level: 1}} = Adventure.dashboard(p.id)
    assert Repo.aggregate(XpTransaction, :count) == 2
  end

  test "disabled module refuses all entry points", %{profile: p} do
    Application.put_env(:cozy_checkout, :adventure_enabled, false)
    assert Adventure.list_profiles() == []
    assert {:error, :disabled} = Adventure.initialize()
    assert {:error, :disabled} = Adventure.dashboard(p.id)
    assert {:error, :disabled} = Adventure.activate_quest(p.id, "improvement")

    assert {:error, :disabled} =
             Adventure.complete_manual_quest(p.id, Ecto.UUID.generate(), "Dokončeno a ověřeno.")

    assert {:error, _} =
             Adventure.reverse_award(p.id, Ecto.UUID.generate(), "Oprava chyby ve hře.")

    assert Repo.aggregate(Quest, :count) == 0
  end

  test "untrusted IDs and unknown definitions cannot mutate game state" do
    assert {:error, :invalid_profile} = Adventure.activate_quest("bad-id", "improvement")
    assert {:error, :unknown_quest} = Adventure.activate_quest(Ecto.UUID.generate(), "unknown")

    assert {:error, :not_found} =
             Adventure.complete_manual_quest("bad-id", "bad-id", "Dokončeno a ověřeno.")

    assert Repo.aggregate(Quest, :count) == 0
  end

  test "game mutations issue writes only to adventure tables", %{profile: p} do
    {_, queries} =
      QueryRecorder.record(fn ->
        {:ok, quest} = Adventure.activate_quest(p.id, "improvement")
        {:ok, _} = Adventure.complete_manual_quest(p.id, quest.id, "Dokončeno a ověřeno.")
        original = Repo.one!(XpTransaction)
        Adventure.reverse_award(p.id, original.id, "Chybně potvrzené dokončení.")
      end)

    writes = Enum.filter(queries, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM)/, &1))
    assert length(writes) == 4
    assert Enum.all?(writes, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM) "adventure_/, &1))
  end

  test "dashboard query count stays constant as quest history grows", %{profile: p} do
    {{:ok, _}, empty_queries} = QueryRecorder.record(fn -> Adventure.dashboard(p.id) end)

    for definition <- Adventure.catalog() do
      {:ok, quest} = Adventure.activate_quest(p.id, definition.code)

      {:ok, _} =
        Adventure.complete_manual_quest(p.id, quest.id, "Dokončeno a ověřeno pro historii.")
    end

    {{:ok, data}, populated_queries} = QueryRecorder.record(fn -> Adventure.dashboard(p.id) end)
    assert length(data.quests) == 4
    assert length(empty_queries) == 4
    assert length(populated_queries) == 4
  end
end

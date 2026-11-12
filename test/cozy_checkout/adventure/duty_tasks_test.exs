defmodule CozyCheckout.Adventure.DutyTasksTest do
  use CozyCheckout.DataCase, async: false

  alias CozyCheckout.{Adventure, QueryRecorder, Repo}
  alias CozyCheckout.Adventure.{Profile, Quest, Tasks, XpTransaction}

  @source_fields [
    :source_namespace,
    :source_ref,
    :source_type,
    :source_context,
    :source_request_key,
    :source_previous_id,
    :source_attempt
  ]

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    {:ok, :ok} = Adventure.initialize()
    issue = issue()

    %{
      michal: Repo.get_by!(Profile, slug: "michal"),
      lucka: Repo.get_by!(Profile, slug: "lucka"),
      issue: issue,
      snapshot: snapshot([issue]),
      key: Tasks.duty_key(issue)
    }
  end

  test "create and start pins the actor, is idempotent and never awards XP", %{
    michal: actor,
    lucka: other,
    snapshot: snapshot,
    key: key
  } do
    request = Ecto.UUID.generate()
    attrs = %{"title" => "Moje výprava", "scope" => "shared", "assigned_profile_id" => other.id}

    {{:ok, quest}, queries} =
      QueryRecorder.record(fn ->
        Tasks.create_from_duty(actor.id, snapshot, key, attrs, request, nil, start: true)
      end)

    assert Enum.count(queries, &Regex.match?(~r/^SELECT/i, &1)) == 7
    refute Enum.any?(queries, &String.contains?(&1, "FROM \"bookings\""))

    assert quest.status == "active"
    assert quest.scope == "personal"
    assert quest.assigned_profile_id == actor.id

    assert {:ok, replay} =
             Tasks.create_from_duty(actor.id, snapshot, key, attrs, request, nil, start: true)

    assert replay.id == quest.id
    assert Repo.aggregate(Quest, :count) == 1
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "full expedition slots roll back creation, preserving the request for a retry", %{
    michal: actor,
    snapshot: snapshot,
    key: key
  } do
    for code <- ~w(prepare_stay review_deposits shopping_plan),
        do: Adventure.activate_quest(actor.id, code)

    request = Ecto.UUID.generate()

    assert {:error, :active_limit} =
             Tasks.create_from_duty(actor.id, snapshot, key, %{}, request, nil, start: true)

    refute Repo.get_by(Quest, source_request_key: request)
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "mine cannot take over another request's existing open work", %{
    michal: actor,
    lucka: other,
    snapshot: snapshot,
    key: key
  } do
    assert {:ok, existing} =
             Tasks.create_from_duty(other.id, snapshot, key, %{}, Ecto.UUID.generate())

    assert {:ok, same} =
             Tasks.create_from_duty(actor.id, snapshot, key, %{}, Ecto.UUID.generate(), nil,
               start: true
             )

    assert same.id == existing.id
    assert same.status == "waiting"
    assert same.assigned_profile_id == nil
  end

  test "only supported source kinds with UUID references have stable keys", %{issue: issue} do
    assert Tasks.duty_key(issue) == {issue.booking_id, "details"}
    assert Tasks.duty_key(%{issue | kind: :menu}) == {issue.booking_id, "menu"}

    assert Tasks.duty_key(%{issue | reason: "Changed text", on: ~D[2027-01-02]}) ==
             Tasks.duty_key(issue)

    for invalid <- [nil, %{}, %{issue | booking_id: "bad"}, %{issue | kind: :arrival}] do
      assert Tasks.duty_key(invalid) == nil
    end
  end

  test "creation stores one complete Adventure quest with safe defaults and no booking FK", %{
    michal: actor,
    snapshot: snapshot,
    key: {booking_id, type} = key,
    issue: issue
  } do
    request = Ecto.UUID.generate()

    {{:ok, quest}, queries} =
      QueryRecorder.record(fn ->
        Tasks.create_from_duty(actor.id, snapshot, key, %{"title" => "Confirm meals"}, request)
      end)

    assert quest.managed
    assert quest.status == "waiting"
    assert quest.scope == "personal"
    assert quest.category == "Kuchyně"
    assert quest.definition_snapshot["title"] == "Confirm meals"
    assert quest.definition_snapshot["size"] == "small"
    assert quest.definition_snapshot["xp"] == 50
    assert quest.created_by_id == actor.id
    assert quest.assigned_profile_id == nil
    assert quest.profile_id == nil
    assert quest.due_on == nil
    assert quest.completed_at == nil
    assert quest.archived_at == nil
    assert quest.source_namespace == "operation_v1"
    assert quest.source_ref == booking_id
    assert quest.source_type == type
    assert quest.source_request_key == request
    assert quest.source_previous_id == nil
    assert quest.source_attempt == 1

    assert quest.source_context == %{
             "version" => 1,
             "reason" => issue.reason,
             "on" => Date.to_iso8601(issue.on),
             "loaded_at" => DateTime.to_iso8601(snapshot.loaded_at),
             "today" => Date.to_iso8601(snapshot.today),
             "through" => Date.to_iso8601(snapshot.through)
           }

    assert Map.take(Repo.get!(Quest, quest.id), @source_fields) ==
             Map.take(quest, @source_fields)

    assert Repo.aggregate(XpTransaction, :count) == 0
    assert length(selects(queries)) <= 4
    assert [insert] = writes(queries)
    assert String.starts_with?(insert, ~s(INSERT INTO "adventure_quests"))

    for field <- @source_fields -- [:source_previous_id] do
      assert insert =~ Atom.to_string(field)
    end

    assert_adventure_only(queries)
  end

  test "optional assignment and size cost at most one additional SELECT", %{
    michal: actor,
    lucka: assigned,
    snapshot: snapshot,
    key: key
  } do
    {{:ok, quest}, queries} =
      QueryRecorder.record(fn ->
        Tasks.create_from_duty(
          actor.id,
          snapshot,
          key,
          %{"title" => "Prepare menu", "size" => "medium", "assigned_profile_id" => assigned.id},
          Ecto.UUID.generate()
        )
      end)

    assert quest.assigned_profile_id == assigned.id
    assert quest.definition_snapshot["xp"] == 100
    assert quest.status == "waiting"
    assert quest.profile_id == nil
    assert length(selects(queries)) <= 5
    assert Repo.aggregate(XpTransaction, :count) == 0
    assert_adventure_only(queries)
  end

  test "changed reason and dates and different actors still identify one open quest", %{
    michal: actor,
    lucka: other,
    snapshot: snapshot,
    issue: issue,
    key: key
  } do
    {:ok, original} = create(actor, snapshot, key)
    changed_issue = %{issue | reason: "Menu is now stale", on: ~D[2026-11-18]}
    changed = %{snapshot | issues: [changed_issue], loaded_at: ~U[2026-11-13 12:00:00Z]}
    {:ok, duplicate} = create(other, changed, key)
    assert duplicate.id == original.id
    assert duplicate.source_context == original.source_context
    assert duplicate.created_by_id == actor.id
    assert Repo.aggregate(Quest, :count) == 1

    {:ok, _} = Tasks.start(actor.id, original.id)
    assert {:ok, %{id: id, status: "active"}} = create(other, changed, key)
    assert id == original.id
    assert %{^key => %{quest: linked, count: 1}} = Tasks.duty_links([changed_issue])
    assert linked.id == original.id
    assert linked.status == "active"
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "the same booking can have independent details and menu work", %{
    michal: actor,
    issue: details
  } do
    menu = %{details | kind: :menu, reason: "Missing menu"}
    snapshot = snapshot([details, menu])
    {:ok, first} = create(actor, snapshot, Tasks.duty_key(details))
    {:ok, second} = create(actor, snapshot, Tasks.duty_key(menu))
    refute first.id == second.id
    assert map_size(Tasks.duty_links([details, menu])) == 2
  end

  test "request retry returns original completed quest even after a newer attempt exists", %{
    michal: actor,
    lucka: other,
    snapshot: snapshot,
    key: key
  } do
    request = Ecto.UUID.generate()
    {:ok, original} = Tasks.create_from_duty(actor.id, snapshot, key, %{}, request)
    assert original.definition_snapshot["title"] == hd(snapshot.issues).reason
    {:ok, _} = Tasks.start(actor.id, original.id)
    {:ok, completed} = Tasks.complete(actor.id, original.id)
    award = Repo.one!(XpTransaction)

    assert {:error, :history_confirmation_required} = create(other, snapshot, key)

    {:ok, next} =
      Tasks.create_from_duty(other.id, snapshot, key, %{}, Ecto.UUID.generate(), original.id)

    assert next.source_previous_id == original.id
    assert next.source_attempt == 2

    {{:ok, replay}, queries} =
      QueryRecorder.record(fn ->
        Tasks.create_from_duty(other.id, snapshot, key, %{"title" => "Do not rewrite"}, request)
      end)

    assert replay.id == original.id
    assert replay.status == "completed"
    assert replay.completed_at == completed.completed_at
    assert replay.evidence == completed.evidence
    assert length(selects(queries)) <= 4
    assert writes(queries) == []
    assert_adventure_only(queries)
    assert Repo.one!(XpTransaction) == award
    assert Repo.aggregate(Quest, :count) == 2
  end

  test "archived work requires explicit latest confirmation and stale confirmations fail", %{
    michal: actor,
    snapshot: snapshot,
    key: key
  } do
    {:ok, first} = create(actor, snapshot, key)
    {:ok, archived} = Tasks.archive(actor.id, first.id)
    assert archived.status == "cancelled"

    assert {:ok, replay} =
             Tasks.create_from_duty(actor.id, snapshot, key, %{}, first.source_request_key)

    assert replay.id == first.id
    assert replay.status == "cancelled"
    assert replay.archived_at == archived.archived_at
    assert {:error, :history_confirmation_required} = create(actor, snapshot, key)

    assert {:error, :history_confirmation_required} =
             Tasks.create_from_duty(
               actor.id,
               snapshot,
               key,
               %{},
               Ecto.UUID.generate(),
               Ecto.UUID.generate()
             )

    {:ok, second} =
      Tasks.create_from_duty(actor.id, snapshot, key, %{}, Ecto.UUID.generate(), first.id)

    {:ok, _} = Tasks.archive(actor.id, second.id)

    assert {:error, :history_confirmation_required} =
             Tasks.create_from_duty(actor.id, snapshot, key, %{}, Ecto.UUID.generate(), first.id)

    {:ok, third} =
      Tasks.create_from_duty(actor.id, snapshot, key, %{}, Ecto.UUID.generate(), second.id)

    assert third.source_attempt == 3
    assert third.source_previous_id == second.id
    assert Repo.aggregate(Quest, :count) == 3
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "request keys cannot be reused for another source", %{michal: actor, issue: issue} do
    other = issue()
    snapshot = snapshot([issue, other])
    request = Ecto.UUID.generate()
    {:ok, _} = Tasks.create_from_duty(actor.id, snapshot, Tasks.duty_key(issue), %{}, request)

    assert {:error, :invalid_request} =
             Tasks.create_from_duty(actor.id, snapshot, Tasks.duty_key(other), %{}, request)

    assert Repo.aggregate(Quest, :count) == 1
  end

  test "unknown sources and malformed snapshots never create quests", %{
    michal: actor,
    snapshot: snapshot,
    key: key
  } do
    for invalid_snapshot <- [
          nil,
          %{},
          %{snapshot | issues: []},
          %{snapshot | loaded_at: "forged"},
          %{snapshot | today: nil},
          %{snapshot | through: nil},
          %{snapshot | issues: [%{hd(snapshot.issues) | reason: nil}]},
          %{snapshot | issues: [%{hd(snapshot.issues) | on: "2026-11-12"}]}
        ] do
      assert {:error, :invalid_duty_source} = create(actor, invalid_snapshot, key)
    end

    for invalid_key <- [
          nil,
          {"bad", "details"},
          {Ecto.UUID.generate(), "details"},
          {elem(key, 0), "arrival"}
        ] do
      assert {:error, :invalid_duty_source} = create(actor, snapshot, invalid_key)
    end

    assert Repo.aggregate(Quest, :count) == 0
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "invalid requests, profiles and validation roll back all source work", %{
    michal: actor,
    snapshot: snapshot,
    key: key
  } do
    assert {:error, :invalid_request} =
             Tasks.create_from_duty(actor.id, snapshot, key, %{}, "bad")

    assert {:error, :invalid_request} =
             Tasks.create_from_duty(actor.id, snapshot, key, %{}, Ecto.UUID.generate(), "bad")

    assert {:error, :invalid_request} =
             Tasks.create_from_duty(actor.id, snapshot, key, nil, Ecto.UUID.generate())

    assert {:error, :invalid_profile} =
             Tasks.create_from_duty("bad", snapshot, key, %{}, Ecto.UUID.generate())

    assert {:error, :invalid_profile} =
             Tasks.create_from_duty(
               actor.id,
               snapshot,
               key,
               %{"assigned_profile_id" => Ecto.UUID.generate()},
               Ecto.UUID.generate()
             )

    request = Ecto.UUID.generate()

    assert {:error, %Ecto.Changeset{}} =
             Tasks.create_from_duty(actor.id, snapshot, key, %{"title" => " "}, request)

    assert Repo.aggregate(Quest, :count) == 0
    assert Repo.aggregate(XpTransaction, :count) == 0

    assert {:ok, %{source_attempt: 1}} =
             Tasks.create_from_duty(actor.id, snapshot, key, %{}, request)
  end

  test "forged source attrs are ignored and all normal lifecycle edits preserve source metadata",
       %{
         michal: actor,
         snapshot: snapshot,
         key: key
       } do
    forged = %{
      "title" => "Real task",
      "source_namespace" => "forged",
      "source_ref" => Ecto.UUID.generate(),
      "source_type" => "arrival",
      "source_context" => %{"reason" => "Forged", "version" => 999},
      "source_request_key" => Ecto.UUID.generate(),
      "source_previous_id" => Ecto.UUID.generate(),
      "source_attempt" => 999,
      "status" => "completed",
      "managed" => false,
      "profile_id" => actor.id
    }

    request = Ecto.UUID.generate()
    {:ok, quest} = Tasks.create_from_duty(actor.id, snapshot, key, forged, request)
    original = Map.take(quest, @source_fields)
    assert quest.source_ref == elem(key, 0)
    assert quest.source_type == elem(key, 1)
    assert quest.source_namespace == "operation_v1"
    assert quest.source_request_key == request
    assert quest.source_previous_id == nil
    assert quest.source_attempt == 1
    assert quest.source_context["reason"] == hd(snapshot.issues).reason
    assert quest.source_context["version"] == 1
    assert quest.status == "waiting"
    assert quest.profile_id == nil
    assert quest.managed

    {_, queries} =
      QueryRecorder.record(fn ->
        {:ok, edited} = Tasks.update(actor.id, quest.id, Map.put(forged, "title", "Edited"))
        assert Map.take(edited, @source_fields) == original
        {:ok, started} = Tasks.start(actor.id, quest.id)
        assert Map.take(started, @source_fields) == original
        {:ok, completed} = Tasks.complete(actor.id, quest.id)
        assert Map.take(completed, @source_fields) == original
        {:ok, archived} = Tasks.archive(actor.id, quest.id)
        assert Map.take(archived, @source_fields) == original
      end)

    assert writes(queries) != []
    assert_adventure_only(queries)
    assert Repo.aggregate(XpTransaction, :count) == 1
  end

  test "database rejects a second waiting or active quest for the same source", %{
    michal: actor,
    snapshot: snapshot,
    key: key
  } do
    {:ok, quest} = create(actor, snapshot, key)

    duplicate = %{
      quest
      | id: Ecto.UUID.generate(),
        code: "task:" <> Ecto.UUID.generate(),
        source_request_key: Ecto.UUID.generate(),
        source_previous_id: quest.id,
        source_attempt: 2
    }

    changeset =
      duplicate
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint(:source_ref, name: :adventure_duty_open_work)

    assert {:error, waiting_error} = Repo.insert(changeset, mode: :savepoint)
    assert waiting_error.errors[:source_ref] != nil
    {:ok, _} = Tasks.start(actor.id, quest.id)
    assert {:error, active_error} = Repo.insert(changeset, mode: :savepoint)
    assert active_error.errors[:source_ref] != nil
    {:ok, _} = Tasks.complete(actor.id, quest.id)

    assert {:ok, %{source_attempt: 2}} =
             Tasks.create_from_duty(actor.id, snapshot, key, %{}, Ecto.UUID.generate(), quest.id)

    assert Repo.aggregate(Quest, :count) == 2
  end

  test "database source metadata cannot be rewritten outside the context", %{
    michal: actor,
    snapshot: snapshot,
    key: key
  } do
    {:ok, quest} = create(actor, snapshot, key)

    for change <- [
          source_namespace: "forged",
          source_ref: Ecto.UUID.generate(),
          source_type: "menu",
          source_context: %{"version" => 999},
          source_request_key: Ecto.UUID.generate(),
          source_previous_id: Ecto.UUID.generate(),
          source_attempt: 2
        ] do
      assert_raise Postgrex.Error, ~r/source history is immutable/, fn ->
        quest
        |> Ecto.Changeset.change([change])
        |> Repo.update!(mode: :savepoint)
      end
    end

    assert Map.take(Repo.get!(Quest, quest.id), @source_fields) ==
             Map.take(quest, @source_fields)
  end

  test "batch covers the full projection in one SELECT and disappearance never resolves work", %{
    michal: actor
  } do
    issues = for _ <- 1..8, do: issue()
    snapshot = snapshot(issues)

    quests =
      for issue <- issues do
        {:ok, quest} = create(actor, snapshot, Tasks.duty_key(issue))
        quest
      end

    {one, one_queries} = QueryRecorder.record(fn -> Tasks.duty_links(Enum.take(issues, 1)) end)
    {links, queries} = QueryRecorder.record(fn -> Tasks.duty_links(issues ++ issues) end)
    assert map_size(one) == 1
    assert map_size(links) == 8
    assert length(selects(one_queries)) == 1
    assert length(selects(queries)) == 1
    assert_adventure_only(queries)

    for quest <- quests do
      assert %{quest: linked, count: 1} = links[{quest.source_ref, quest.source_type}]
      assert linked.id == quest.id
      assert linked.source_context == quest.source_context
      assert linked.definition_snapshot == quest.definition_snapshot
    end

    assert {%{}, []} = QueryRecorder.record(fn -> Tasks.duty_links([]) end)
    assert {%{}, []} = QueryRecorder.record(fn -> Tasks.duty_links([%{kind: :arrival}]) end)
    assert Enum.all?(quests, &(Repo.get!(Quest, &1.id).status == "waiting"))
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "history pages twenty with one extra-row lookahead and latest/open batch preference", %{
    michal: actor,
    snapshot: snapshot,
    issue: issue,
    key: key
  } do
    quests =
      Enum.reduce(1..22, [], fn _, history ->
        previous_id =
          case history do
            [] -> nil
            [latest | _] -> latest.id
          end

        {:ok, quest} =
          Tasks.create_from_duty(actor.id, snapshot, key, %{}, Ecto.UUID.generate(), previous_id)

        {:ok, archived} = Tasks.archive(actor.id, quest.id)
        [archived | history]
      end)

    {first, first_queries} = QueryRecorder.record(fn -> Tasks.duty_history(key) end)
    {second, second_queries} = QueryRecorder.record(fn -> Tasks.duty_history(key, 1) end)
    assert %{quests: first_page, more?: true} = first
    assert %{quests: second_page, more?: false} = second
    assert length(first_page) == 20
    assert length(second_page) == 2
    assert Enum.map(first_page ++ second_page, & &1.id) == Enum.map(quests, & &1.id)
    assert length(selects(first_queries)) == 1
    assert length(selects(second_queries)) == 1
    assert hd(selects(first_queries)) =~ "LIMIT 21"
    assert_adventure_only(first_queries ++ second_queries)

    latest = hd(quests)
    assert %{^key => %{quest: linked, count: 22}} = Tasks.duty_links([issue])
    assert linked.id == latest.id

    {:ok, open} =
      Tasks.create_from_duty(actor.id, snapshot, key, %{}, Ecto.UUID.generate(), latest.id)

    {:ok, _} = Tasks.start(actor.id, open.id)
    assert %{^key => %{quest: active, count: 23}} = Tasks.duty_links([issue])
    assert active.id == open.id
    assert active.status == "active"
    assert %{quests: [], more?: false} = Tasks.duty_history(key, 2)
  end

  test "history isolates source kind and booking and managed detail needs at most one SELECT", %{
    michal: actor,
    snapshot: snapshot,
    key: key
  } do
    {:ok, quest} = create(actor, snapshot, key)
    {detail, queries} = QueryRecorder.record(fn -> Tasks.get_managed(quest.id) end)
    assert detail.id == quest.id
    assert length(selects(queries)) == 1
    assert_adventure_only(queries)
    assert %{quests: [], more?: false} = Tasks.duty_history({elem(key, 0), "menu"})
    assert %{quests: [], more?: false} = Tasks.duty_history({Ecto.UUID.generate(), "details"})
    assert %{quests: [], more?: false} = Tasks.duty_history(key, -1)
    assert %{quests: [], more?: false} = Tasks.duty_history(nil)
    assert {nil, []} = QueryRecorder.record(fn -> Tasks.get_managed("bad") end)
    {:ok, catalog} = Adventure.activate_quest(actor.id, "improvement")
    assert Tasks.get_managed(catalog.id) == nil
  end

  test "disabled Adventure neither reads nor writes duty quests", %{
    michal: actor,
    snapshot: snapshot,
    issue: issue,
    key: key
  } do
    {:ok, quest} = create(actor, snapshot, key)
    Application.put_env(:cozy_checkout, :adventure_enabled, false)

    {result, queries} =
      QueryRecorder.record(fn ->
        assert Tasks.duty_links([issue]) == %{}
        assert Tasks.duty_history(key) == %{quests: [], more?: false}
        assert Tasks.get_managed(quest.id) == nil
        create(actor, snapshot, key)
      end)

    assert result == {:error, :disabled}
    assert queries == []
  end

  test "follow-up is one bounded query across heroes and independent of the current projection",
       %{
         michal: actor,
         lucka: lucka
       } do
    quests =
      for n <- 1..23 do
        issue = %{issue() | booking_id: Ecto.UUID.generate()}

        attrs =
          if rem(n, 2) == 0,
            do: %{"title" => "Work #{n}", "assigned_profile_id" => lucka.id},
            else: %{"title" => "Work #{n}", "scope" => "shared"}

        {:ok, quest} =
          Tasks.create_from_duty(
            actor.id,
            snapshot([issue]),
            Tasks.duty_key(issue),
            attrs,
            Ecto.UUID.generate()
          )

        quest
      end

    [done, archived | remaining] = quests
    {:ok, _} = Tasks.start(actor.id, done.id)
    {:ok, _} = Tasks.complete(actor.id, done.id, %{"contributors" => [actor.id]})
    {:ok, _} = Tasks.archive(actor.id, archived.id)
    {:ok, _ordinary} = Tasks.create(actor.id, %{"title" => "Not from duty"})

    {first, queries} = QueryRecorder.record(fn -> Tasks.duty_follow_up() end)
    assert length(first.quests) == 20
    assert first.more?
    assert length(selects(queries)) == 1
    assert_adventure_only(queries)
    {last, queries} = QueryRecorder.record(fn -> Tasks.duty_follow_up(1) end)
    assert length(last.quests) == 1
    refute last.more?
    assert length(selects(queries)) == 1
    assert_adventure_only(queries)
    actual_ids = Enum.map(first.quests ++ last.quests, & &1.id)
    assert MapSet.new(actual_ids) == MapSet.new(remaining, & &1.id)
    assert length(Enum.uniq(actual_ids)) == 21
    assert Enum.any?(first.quests, &(&1.assigned_profile_id == lucka.id))
    assert Enum.any?(first.quests, &(&1.scope == "shared"))
    assert Tasks.duty_follow_up() == first
    assert Tasks.duty_follow_up(2) == %{quests: [], more?: false}
    assert Repo.aggregate(XpTransaction, :count) == 1
  end

  test "follow-up rejects invalid pages and the disabled feature without SQL" do
    for page <- [-1, "0", nil] do
      assert {%{quests: [], more?: false}, []} =
               QueryRecorder.record(fn -> Tasks.duty_follow_up(page) end)
    end

    Application.put_env(:cozy_checkout, :adventure_enabled, false)

    assert {%{quests: [], more?: false}, []} =
             QueryRecorder.record(fn -> Tasks.duty_follow_up() end)
  end

  test "source comparison is pure, uses the whole projection and never resolves absent work", %{
    michal: actor,
    snapshot: snapshot,
    issue: issue,
    key: key
  } do
    alias CozyCheckout.Adventure.Sources.Operation
    {:ok, quest} = create(actor, snapshot, key)
    now = snapshot.loaded_at
    other = for _ <- 1..4, do: %{issue | booking_id: Ecto.UUID.generate()}
    full = %{snapshot | issues: other ++ [issue]}

    {statuses, queries} =
      QueryRecorder.record(fn ->
        [
          Operation.duty_source_status(quest, full, :ready, now),
          Operation.duty_source_status(
            quest,
            %{full | issues: [%{issue | reason: "Changed"}]},
            :ready,
            now
          ),
          Operation.duty_source_status(
            quest,
            %{full | issues: [%{issue | on: ~D[2027-01-01]}]},
            :ready,
            now
          ),
          Operation.duty_source_status(quest, %{full | issues: []}, :ready, now),
          Operation.duty_source_status(quest, full, :ready, DateTime.add(now, 901)),
          Operation.duty_source_status(quest, full, :error, now),
          Operation.duty_source_status(quest, full, :loading, now),
          Operation.duty_source_status(quest, nil, :error, now)
        ]
      end)

    assert statuses == [
             :present,
             :changed,
             :changed,
             :absent,
             :stale,
             :unavailable,
             :unavailable,
             :unavailable
           ]

    assert queries == []
    assert Repo.get!(Quest, quest.id).status == "waiting"
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  defp issue do
    %{
      booking_id: Ecto.UUID.generate(),
      kind: :details,
      reason: "Confirm meal details",
      on: ~D[2026-11-14]
    }
  end

  defp snapshot(issues) do
    %{
      issues: issues,
      loaded_at: ~U[2026-11-12 12:00:00Z],
      today: ~D[2026-11-12],
      through: ~D[2026-11-19]
    }
  end

  defp create(actor, snapshot, key) do
    Tasks.create_from_duty(
      actor.id,
      snapshot,
      key,
      %{"title" => "Confirm meals"},
      Ecto.UUID.generate()
    )
  end

  defp selects(queries), do: Enum.filter(queries, &String.starts_with?(&1, "SELECT"))

  defp writes(queries) do
    Enum.filter(queries, &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM)/, &1))
  end

  defp assert_adventure_only(queries) do
    assert Enum.all?(
             writes(queries),
             &Regex.match?(~r/^(INSERT INTO|UPDATE|DELETE FROM) "adventure_/, &1)
           )

    assert Enum.all?(selects(queries), fn query ->
             query =~ "pg_advisory_xact_lock" or
               Regex.match?(~r/\bFROM "adventure_/, query)
           end)

    for query <- queries, [_, table] <- Regex.scan(~r/\b(?:FROM|JOIN) "([^"]+)"/, query) do
      assert String.starts_with?(table, "adventure_")
    end
  end
end

defmodule CozyCheckout.Adventure.TaskConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias CozyCheckout.{Adventure, Repo}

  alias CozyCheckout.Adventure.{
    Profile,
    Quest,
    Tasks,
    Templates,
    TaskTemplate,
    TemplateVersion,
    XpTransaction
  }

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)

    profiles =
      Sandbox.unboxed_run(Repo, fn ->
        for _ <- 1..2,
            do:
              Repo.insert!(%Profile{
                slug: "task-race-#{Ecto.UUID.generate()}",
                display_name: "Race"
              })
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        ids = Enum.map(profiles, & &1.id)

        quests =
          from q in Quest, where: q.created_by_id in ^ids or q.profile_id in ^ids, select: q.id

        Repo.delete_all(from x in XpTransaction, where: x.quest_id in subquery(quests))
        Repo.delete_all(from q in Quest, where: q.id in subquery(quests))
        templates = from t in TaskTemplate, where: t.created_by_id in ^ids, select: t.id
        Repo.delete_all(from v in TemplateVersion, where: v.template_id in subquery(templates))
        Repo.delete_all(from t in TaskTemplate, where: t.id in subquery(templates))
        Repo.delete_all(from p in Profile, where: p.id in ^ids)
      end)

      Application.put_env(:cozy_checkout, :adventure_enabled, previous)
    end)

    %{profiles: profiles}
  end

  test "different heroes completing one shared task produce one reward and one evidence", %{
    profiles: [first, second]
  } do
    task =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, task} = Tasks.create(first.id, %{"title" => "Společná práce", "scope" => "shared"})
        {:ok, task} = Tasks.start(first.id, task.id)
        task
      end)

    results =
      race(
        for profile <- [first, second],
            do: fn ->
              Tasks.complete(profile.id, task.id, %{"contributors" => [profile.id]})
            end
      )

    assert Enum.all?(results, &match?({:ok, %{status: "completed"}}, &1))
    [{:ok, a}, {:ok, b}] = results
    assert a.evidence == b.evidence

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(from(x in XpTransaction, where: x.quest_id == ^task.id), :count) == 1
      assert Repo.get_by!(XpTransaction, quest_id: task.id).recipient_type == "shared"
    end)
  end

  test "catalog activation and task start share the same profile lock", %{profiles: [p, _]} do
    task =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, _} = Adventure.activate_quest(p.id, "prepare_stay")
        {:ok, _} = Adventure.activate_quest(p.id, "review_deposits")
        {:ok, task} = Tasks.create(p.id, %{"title" => "Čtvrtá práce"})
        task
      end)

    results =
      race([
        fn -> Tasks.start(p.id, task.id) end,
        fn -> Adventure.activate_quest(p.id, "improvement") end
      ])

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :active_limit})) == 1
  end

  test "parallel refreshes create one occurrence and append one due shift", %{profiles: [p, _]} do
    day = Sandbox.unboxed_run(Repo, fn -> CozyCheckout.Adventure.Sources.Stays.today() end)

    template =
      Sandbox.unboxed_run(Repo, fn ->
        {:ok, t} =
          Templates.create(p.id, %{
            "title" => "Souběžná šablona",
            "starts_on" => Date.to_iso8601(day)
          })

        {:ok, t} = Templates.set_status(p.id, t.id, "active", "keep")
        t
      end)

    at = DateTime.new!(day, ~T[12:00:00], "Etc/UTC")
    results = race([fn -> Templates.generate(at) end, fn -> Templates.generate(at) end])
    assert Enum.all?(results, &match?({:ok, _}, &1))
    later = DateTime.new!(Date.add(day, 7), ~T[12:00:00], "Etc/UTC")

    assert Enum.all?(
             race([fn -> Templates.generate(later) end, fn -> Templates.generate(later) end]),
             &match?({:ok, _}, &1)
           )

    Sandbox.unboxed_run(Repo, fn ->
      task = Repo.one!(from q in Quest, where: q.template_id == ^template.id)
      assert task.first_due_on == day
      assert task.due_on == Date.add(day, 7)
      assert length(task.schedule_history["shifts"]) == 1
      assert Repo.aggregate(from(x in XpTransaction, where: x.quest_id == ^task.id), :count) == 0
    end)
  end

  defp race(functions) do
    parent = self()

    tasks =
      Enum.map(functions, fn fun ->
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> Sandbox.unboxed_run(Repo, fun)
          end
        end)
      end)

    for _ <- tasks do
      receive do
        {:ready, _} -> :ok
      after
        5000 -> flunk("Task did not start")
      end
    end

    Enum.each(tasks, &send(&1.pid, :go))
    Enum.map(tasks, &Task.await(&1, 15_000))
  end
end

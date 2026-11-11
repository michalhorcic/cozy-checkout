defmodule CozyCheckout.Adventure.ConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias CozyCheckout.{Adventure, Repo}
  alias CozyCheckout.Adventure.{Profile, Quest, XpTransaction}

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)

    profile =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.insert!(%Profile{slug: "race-#{Ecto.UUID.generate()}", display_name: "Race"})
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(
          from x in XpTransaction,
            where: x.profile_id == ^profile.id and not is_nil(x.reverses_id)
        )

        Repo.delete_all(from x in XpTransaction, where: x.profile_id == ^profile.id)
        Repo.delete_all(from q in Quest, where: q.profile_id == ^profile.id)
        Repo.delete!(profile)
      end)

      Application.put_env(:cozy_checkout, :adventure_enabled, previous)
    end)

    {:ok, profile: profile}
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

  test "parallel completions and corrections award and reverse once", %{profile: p} do
    {:ok, quest} =
      Sandbox.unboxed_run(Repo, fn -> Adventure.activate_quest(p.id, "improvement") end)

    results =
      race(
        for _ <- 1..2,
            do: fn ->
              Adventure.complete_manual_quest(p.id, quest.id, "Dokončeno a ověřeno souběžně.")
            end
      )

    assert Enum.all?(results, &match?({:ok, %{status: "completed"}}, &1))

    award =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.one!(from x in XpTransaction, where: x.profile_id == ^p.id)
      end)

    assert award.amount == 250

    [{:ok, first}, {:ok, second}] =
      race(
        for _ <- 1..2,
            do: fn ->
              Adventure.reverse_award(p.id, award.id, "Chybně potvrzené dokončení.")
            end
      )

    assert first.id == second.id

    assert Sandbox.unboxed_run(Repo, fn ->
             Repo.aggregate(from(x in XpTransaction, where: x.profile_id == ^p.id), :count)
           end) == 2
  end

  test "parallel activations cannot exceed the three-quest limit", %{profile: p} do
    Sandbox.unboxed_run(Repo, fn ->
      {:ok, _} = Adventure.activate_quest(p.id, "prepare_stay")
      {:ok, _} = Adventure.activate_quest(p.id, "review_deposits")
    end)

    results =
      race([
        fn -> Adventure.activate_quest(p.id, "shopping_plan") end,
        fn -> Adventure.activate_quest(p.id, "improvement") end
      ])

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :active_limit})) == 1
  end
end

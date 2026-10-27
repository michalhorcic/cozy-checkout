defmodule CozyCheckout.KitchenCosts.ConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias CozyCheckout.{KitchenCosts, Repo}
  alias CozyCheckout.KitchenCosts.{Purchase, PurchaseLine}
  alias CozyCheckout.Recipes.Ingredient

  # Separate committed sandbox checkouts are necessary to exercise PostgreSQL locks,
  # rather than serializing tasks through one shared sandbox connection.
  setup do
    ingredient =
      Sandbox.unboxed_run(Repo, fn -> CozyCheckout.RecipeFixtures.ingredient_fixture() end)

    merchant = "Concurrency #{Ecto.UUID.generate()}"

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(
          from l in PurchaseLine,
            join: p in Purchase,
            on: p.id == l.purchase_id,
            where: p.merchant == ^merchant
        )

        Repo.delete_all(
          from p in Purchase, where: p.merchant == ^merchant and not is_nil(p.replaces_id)
        )

        Repo.delete_all(from p in Purchase, where: p.merchant == ^merchant)
        Repo.delete_all(from i in Ingredient, where: i.id == ^ingredient.id)
      end)
    end)

    attrs = %{
      merchant: merchant,
      purchased_on: ~D[2026-10-27],
      total_paid: "100",
      import_id: Ecto.UUID.generate(),
      lines: [
        %{
          line_number: 1,
          source_name: "Surovina",
          classification: "ingredient",
          ingredient_id: ingredient.id,
          quantity: "1",
          unit: "kg",
          line_total: "100"
        }
      ]
    }

    {:ok, attrs: attrs, merchant: merchant}
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

    for _ <- tasks,
        do:
          (receive do
             {:ready, _} -> :ok
           after
             5000 -> flunk("Task did not start")
           end)

    Enum.each(tasks, &send(&1.pid, :go))
    Enum.map(tasks, &Task.await(&1, 15_000))
  end

  test "concurrent imports create exactly one purchase", %{attrs: attrs, merchant: merchant} do
    [{:ok, first}, {:ok, second}] =
      race([
        fn -> KitchenCosts.confirm_purchase(attrs) end,
        fn -> KitchenCosts.confirm_purchase(attrs) end
      ])

    assert first.id == second.id

    assert Sandbox.unboxed_run(Repo, fn ->
             Repo.aggregate(from(p in Purchase, where: p.merchant == ^merchant), :count)
           end) == 1
  end

  test "concurrent corrections cannot branch one original purchase", %{attrs: attrs} do
    {:ok, original} = Sandbox.unboxed_run(Repo, fn -> KitchenCosts.confirm_purchase(attrs) end)

    results =
      race(
        for n <- 1..2,
            do: fn ->
              KitchenCosts.confirm_purchase(
                %{attrs | import_id: Ecto.UUID.generate()}
                |> Map.put(:document_number, "correction-#{n}"),
                replaces_id: original.id
              )
            end
      )

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :already_replaced})) == 1
  end
end

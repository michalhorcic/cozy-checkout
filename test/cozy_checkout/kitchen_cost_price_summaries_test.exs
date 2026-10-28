defmodule CozyCheckout.KitchenCosts.PriceSummariesTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.RecipeFixtures
  alias CozyCheckout.{KitchenCosts, QueryRecorder}

  defp buy(ingredient, date, quantity, total, opts \\ []) do
    KitchenCosts.confirm_purchase(
      %{
        merchant: "Cenové souhrny",
        purchased_on: date,
        total_paid: total,
        document_number: Ecto.UUID.generate(),
        import_id: Ecto.UUID.generate(),
        lines: [
          %{
            line_number: 1,
            source_name: "Značka 1",
            ingredient_id: ingredient.id,
            classification: "ingredient",
            quantity: quantity,
            unit: ingredient.base_unit,
            line_total: total
          }
        ]
      },
      opts
    )
  end

  defp estimate(ingredient, date, price),
    do:
      KitchenCosts.create_manual_price(%{
        ingredient_id: ingredient.id,
        valid_from: date,
        unit_price: price,
        note: "Odhad"
      })

  test "SQL summaries match individual prices for all sources, dates and corrected purchases" do
    date = ~D[2026-10-28]
    recent = ingredient_fixture()
    older = ingredient_fixture(%{base_unit: "l"})
    manual = ingredient_fixture(%{base_unit: "ks"})
    future = ingredient_fixture()
    missing = ingredient_fixture()
    corrected = ingredient_fixture()
    archived = ingredient_fixture()

    {:ok, _} = buy(recent, Date.add(date, -90), "1", "999")
    {:ok, _} = buy(recent, Date.add(date, -89), "1", "100")
    {:ok, _} = buy(recent, date, "3", "600")
    {:ok, _} = buy(recent, Date.add(date, 1), "1", "999")
    {:ok, _} = estimate(recent, date, "1")
    {:ok, _} = buy(older, Date.add(date, -92), "1", "999")
    {:ok, _} = buy(older, Date.add(date, -90), "2", "300")
    {:ok, _} = buy(older, Date.add(date, -90), "1", "300")
    {:ok, _} = estimate(older, date, "1")
    {:ok, _} = estimate(manual, Date.add(date, -2), "10")
    {:ok, active} = estimate(manual, Date.add(date, -1), "12.12345678")
    {:ok, removed} = estimate(manual, date, "99")

    Repo.update!(
      Ecto.Changeset.change(removed,
        archived_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
    )

    {:ok, _} = estimate(manual, Date.add(date, 1), "99")
    {:ok, _} = buy(future, Date.add(date, 1), "1", "999")
    {:ok, _} = estimate(future, Date.add(date, 1), "999")
    {:ok, original} = buy(corrected, date, "1", "999")
    {:ok, _} = buy(corrected, date, "2", "80", replaces_id: original.id)
    {:ok, _} = buy(archived, date, "1", "50")
    {:ok, archived} = CozyCheckout.Recipes.archive_ingredient(archived)

    ingredients = [recent, older, manual, future, missing, corrected, archived]

    {summaries, queries} =
      QueryRecorder.record(fn -> KitchenCosts.price_summaries(ingredients, date) end)

    assert length(queries) == 3

    for ingredient <- ingredients do
      full = KitchenCosts.price_for(ingredient.id, date) |> Map.delete(:lines)
      summary = summaries[ingredient.id]
      assert Enum.sort(Map.keys(summary)) == Enum.sort(Map.keys(full))

      for {key, value} <- full do
        if is_struct(value, Decimal),
          do: assert(Decimal.equal?(summary[key], value)),
          else: assert(summary[key] == value)
      end
    end

    assert Decimal.equal?(summaries[recent.id].unit_price, "175")
    assert Decimal.equal?(summaries[older.id].unit_price, "200")
    assert summaries[manual.id].manual_price_id == active.id
    assert summaries[future.id].source == "missing"
    assert Decimal.equal?(summaries[corrected.id].unit_price, "40")
  end

  test "query count stays bounded for a growing catalogue and an empty input does no SQL" do
    first = ingredient_fixture()
    date = ~D[2026-10-28]

    {_, single_queries} =
      QueryRecorder.record(fn -> KitchenCosts.price_summaries([first], date) end)

    many = [first | for(_ <- 1..25, do: ingredient_fixture())]

    {prices, many_queries} =
      QueryRecorder.record(fn -> KitchenCosts.price_summaries(many, date) end)

    assert length(many_queries) == length(single_queries)
    assert length(many_queries) == 3
    assert map_size(prices) == 26
    assert {%{}, []} = QueryRecorder.record(fn -> KitchenCosts.price_summaries([], date) end)
  end

  test "all-recent prices skip the fallback queries" do
    ingredient = ingredient_fixture()
    {:ok, _} = buy(ingredient, ~D[2026-10-28], "1", "10")

    {_, queries} =
      QueryRecorder.record(fn -> KitchenCosts.price_summaries([ingredient], ~D[2026-10-28]) end)

    assert length(queries) == 1
  end
end

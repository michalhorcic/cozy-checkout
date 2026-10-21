defmodule CozyCheckout.Meals.MenuVariantsTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.MenuFixtures
  alias CozyCheckout.Meals.{MenuPlanning, MenuVariant, SlotSchedule}

  test "full-board weekend has five inclusive services; supplements are part of the lunch" do
    variant = variant_fixture()

    assert Enum.map(variant.items, &{&1.day_number, &1.meal_type}) ==
             [{1, "dinner"}, {2, "breakfast"}, {2, "lunch"}, {2, "dinner"}, {3, "breakfast"}]

    assert Enum.find(variant.items, &(&1.meal_type == "lunch")).supplements ==
             "Zeleninová polévka"

    half = variant_fixture(%{meal_plan: "half_board"})
    assert length(half.items) == 4
    refute Enum.any?(half.items, &(&1.meal_type == "lunch"))
  end

  test "requires an exact, complete schedule, with no duplicate or extra service" do
    attrs = variant_attrs()
    [first | rest] = attrs.items

    for items <- [
          rest,
          attrs.items ++ [first],
          attrs.items ++ [%{first | day_number: 99}],
          [%{first | menu_text: ""} | rest]
        ] do
      assert {:error, cs} = MenuPlanning.create_variant(%{attrs | items: items})
      refute cs.valid?
    end
  end

  test "validates settings, half-board lunch and same-day order" do
    for overrides <- [
          %{days: 0},
          %{days: 367},
          %{meal_plan: "none"},
          %{meal_plan: "half_board", first_meal: "lunch"},
          %{meal_plan: "half_board", last_meal: "lunch"},
          %{days: 1}
        ] do
      assert {:error, _} = MenuPlanning.create_variant(variant_attrs(overrides))
    end

    single = variant_fixture(%{days: 1, first_meal: "lunch", last_meal: "lunch"})
    assert Enum.map(single.items, & &1.meal_type) == ["lunch"]
  end

  test "Sunday-to-Friday dinner/breakfast matches the spreadsheet's 5/4/5 services" do
    types =
      SlotSchedule.slots(6, "full_board", "dinner", "breakfast")
      |> Enum.map(&elem(&1, 1))
      |> Enum.frequencies()

    assert types == %{"breakfast" => 5, "lunch" => 4, "dinner" => 5}
  end

  test "rebuilding the form preserves matching text, removes obsolete slots and adds buffet breakfasts" do
    variant = variant_fixture()

    params = %{
      "name" => variant.name,
      "days" => "4",
      "items" =>
        Map.new(Enum.with_index(variant.items), fn {item, index} ->
          {to_string(index),
           %{
             "id" => item.id,
             "day_number" => to_string(item.day_number),
             "meal_type" => item.meal_type,
             "menu_text" => "Ručně připravený text",
             "supplements" => item.supplements
           }}
        end)
    }

    cs = MenuPlanning.variant_form(variant, params)
    result = Ecto.Changeset.apply_changes(cs)

    assert Enum.find(result.items, &(&1.day_number == 2 and &1.meal_type == "lunch")).menu_text ==
             "Ručně připravený text"

    assert Enum.find(result.items, &(&1.day_number == 4)).menu_text == "Snídaňový bufet"
    assert MenuPlanning.get_variant!(variant.id).days == 3
  end

  test "reference import creates nine validated variants and never overwrites existing content" do
    assert {:ok, %{created: 9, skipped: 0}} = MenuPlanning.import_reference_variants()
    variants = MenuPlanning.list_variants() |> Enum.map(&MenuPlanning.get_variant!(&1.id))
    assert length(variants) == 9
    assert Enum.all?(variants, &MenuVariant.changeset(&1, %{}).valid?)
    weekend = Enum.find(variants, &(&1.name == "Víkend 3 dny – polopenze – méně práce"))
    assert length(weekend.items) == 4
    dinner = Enum.find(weekend.items, &(&1.day_number == 1))
    assert dinner.menu_text == "Kuře na paprice s rýží"
    assert dinner.supplements =~ "Zeleninový vývar"

    {:ok, edited} =
      MenuPlanning.update_variant(weekend, %{
        items:
          Enum.map(weekend.items, fn item ->
            %{
              id: item.id,
              day_number: item.day_number,
              meal_type: item.meal_type,
              menu_text: "Upravené menu",
              supplements: nil
            }
          end)
      })

    assert {:ok, %{created: 0, skipped: 9}} = MenuPlanning.import_reference_variants()

    assert Enum.all?(
             MenuPlanning.get_variant!(edited.id).items,
             &(&1.menu_text == "Upravené menu")
           )
  end

  test "concurrent variant edits are rejected rather than overwriting the first editor" do
    variant = variant_fixture()
    assert {:ok, _} = MenuPlanning.update_variant(variant, %{name: "První úprava"})

    assert {:error, :stale_variant} =
             MenuPlanning.update_variant(variant, %{name: "Druhá úprava"})

    assert MenuPlanning.get_variant!(variant.id).name == "První úprava"
  end
end

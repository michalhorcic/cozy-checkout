defmodule CozyCheckout.KitchenCosts.ImportTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.RecipeFixtures
  alias CozyCheckout.{KitchenCosts, Recipes}
  alias CozyCheckout.KitchenCosts.{Import, Purchase}

  defp example do
    Application.app_dir(:cozy_checkout, "priv/kitchen_costs/receipt-v1.example.json")
    |> File.read!()
    |> Jason.decode!()
  end

  test "versioned example accepts packaged, weighed and non-food rows without saving a purchase" do
    assert {:ok, parsed} = example() |> Jason.encode!() |> Import.parse()
    assert length(parsed.attrs["lines"]) == 3
    assert hd(parsed.attrs["lines"])["quantity"] == "280"
    assert parsed.shared_discount == "10.00"
    assert Repo.aggregate(Purchase, :count) == 0
    assert {:ok, rows} = Import.distribute_discount(parsed.attrs["lines"], parsed.shared_discount)

    assert Decimal.equal?(
             Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1["line_total"], &2)),
             "151.39"
           )

    assert {:ok, _} = KitchenCosts.confirm_reviewed_purchase(Map.put(parsed.attrs, "lines", rows))
  end

  test "unknown values stay nil and the proposal is not trusted as a confirmed ingredient" do
    data = put_in(example(), ["receipt", "purchased_on"], nil)
    assert {:ok, parsed} = Import.parse(Jason.encode!(data))
    assert parsed.attrs["purchased_on"] == nil
    assert {:error, %Ecto.Changeset{}} = KitchenCosts.confirm_reviewed_purchase(parsed.attrs)
    ingredient = ingredient_fixture()
    data = put_in(data, ["items", Access.at(0), "proposed_ingredient_id"], ingredient.id)
    assert {:ok, parsed} = Import.parse(Jason.encode!(data))
    assert {:error, :unconfirmed_mapping} = KitchenCosts.confirm_reviewed_purchase(parsed.attrs)
  end

  test "malformed JSON, unsupported versions, floats, image or URL fields and invalid UUIDs are rejected" do
    for data <- [
          Map.put(example(), "schema_version", 2),
          Map.put(example(), "image_url", "https://example.com/image.jpg"),
          Map.put(example(), "import_id", "made-up"),
          put_in(example(), ["receipt", "total_paid"], 151.0),
          put_in(example(), ["items", Access.at(0), "quantity"], 280),
          put_in(example(), ["items", Access.at(0), "unit"], "oz"),
          put_in(example(), ["items", Access.at(0), "line_total_after_discount"], "NaN"),
          put_in(example(), ["items", Access.at(1), "package_count"], "2"),
          Map.delete(example(), "warnings")
        ] do
      assert {:error, _} = Import.parse(Jason.encode!(data))
    end

    assert {:error, _} = Import.parse("invalid")
    assert {:error, _} = Import.parse(String.duplicate("x", 1_000_001))
    assert Repo.aggregate(Purchase, :count) == 0
  end

  test "discount allocations preserve every cent, allow zero-price goods and reject invalid amounts" do
    rows = for n <- 1..3, do: %{"line_number" => n, "line_total" => "0.01"}
    assert {:ok, discounted} = Import.distribute_discount(rows, "0.02")
    assert Enum.map(discounted, & &1["line_total"]) == ["0.00", "0.00", "0.01"]
    assert {:ok, _} = Import.distribute_discount(rows ++ [%{"line_total" => "0.00"}], "0.03")

    for amount <- ["-1", "NaN", "Infinity", "0.031", "0.04", "", nil] do
      assert {:error, _} = Import.distribute_discount(rows, amount)
    end
  end

  test "dictionary keys retain brands and packaging; edits require the version seen by the user" do
    ingredient = ingredient_fixture()
    other = ingredient_fixture()

    assert {:ok, mapping} =
             KitchenCosts.set_mapping(" OBCHOD ", "Protlak Značka A 140 g", ingredient.id, nil)

    assert KitchenCosts.mapping_for("obchod", "protlak  značka a 140 g").id == mapping.id
    refute KitchenCosts.mapping_for("obchod", "Protlak Značka B 140 g")
    refute KitchenCosts.mapping_for("obchod", "Protlak Značka A 200 g")

    assert {:error, :mapping_changed} =
             KitchenCosts.set_mapping("obchod", mapping.source_name, other.id, nil)

    assert {:ok, _} =
             KitchenCosts.set_mapping(
               "obchod",
               mapping.source_name,
               other.id,
               mapping.lock_version
             )

    assert KitchenCosts.mapping_for("obchod", mapping.source_name).ingredient_id == other.id
    catalog = Import.catalog()
    assert Enum.any?(catalog.ingredients, &(&1.id == ingredient.id))
    assert Enum.any?(catalog.mappings, &(&1.ingredient_id == other.id))
    assert {:ok, archived} = Recipes.archive_ingredient(other)

    assert {:error, :invalid_ingredient} =
             KitchenCosts.set_mapping("novy", "Zboží", archived.id, nil)
  end

  test "dictionary and purchase commit together, stale remembered mappings roll everything back" do
    ingredient = ingredient_fixture()
    other = ingredient_fixture()

    row = %{
      "line_number" => 1,
      "source_name" => "Značka 1 kg",
      "classification" => "ingredient",
      "ingredient_id" => ingredient.id,
      "confirmed_ingredient_id" => ingredient.id,
      "remember" => "true",
      "quantity" => "1",
      "unit" => "kg",
      "line_total" => "100"
    }

    attrs = %{
      "merchant" => "Obchod",
      "purchased_on" => "2026-10-27",
      "total_paid" => "100",
      "import_id" => Ecto.UUID.generate(),
      "lines" => [row]
    }

    versions = KitchenCosts.mapping_versions(attrs)

    assert {:ok, saved} =
             KitchenCosts.confirm_reviewed_purchase(attrs, mapping_versions: versions)

    mapping = KitchenCosts.mapping_for("Obchod", row["source_name"])
    assert mapping.ingredient_id == ingredient.id

    assert {:ok, repeated} =
             KitchenCosts.confirm_reviewed_purchase(attrs, mapping_versions: versions)

    assert repeated.id == saved.id
    assert KitchenCosts.mapping_for("Obchod", row["source_name"]).lock_version == 1

    assert {:ok, _} =
             KitchenCosts.set_mapping(
               "Obchod",
               row["source_name"],
               other.id,
               mapping.lock_version
             )

    assert hd(KitchenCosts.get_purchase!(saved.id).lines).ingredient_id == ingredient.id

    newer =
      attrs |> Map.put("import_id", Ecto.UUID.generate()) |> Map.put("document_number", "new")

    assert {:error, :mapping_changed} =
             KitchenCosts.confirm_reviewed_purchase(newer, mapping_versions: versions)

    assert Repo.aggregate(Purchase, :count) == 1
    assert KitchenCosts.mapping_for("Obchod", row["source_name"]).ingredient_id == other.id
  end

  test "a changed ingredient cannot reuse confirmation for the original proposal" do
    first = ingredient_fixture()
    second = ingredient_fixture()

    attrs = %{
      "lines" => [
        %{
          "classification" => "ingredient",
          "ingredient_id" => second.id,
          "confirmed_ingredient_id" => first.id
        }
      ]
    }

    assert {:error, :unconfirmed_mapping} = KitchenCosts.confirm_reviewed_purchase(attrs)
  end

  test "disabled recipe quantities need no fabricated zero purchase price" do
    ingredient = ingredient_fixture()

    recipe =
      recipe_fixture(ingredient, %{
        lines: [%{ingredient_id: ingredient.id, quantity: "0", unit: "kg"}]
      })

    consumption = Recipes.Consumption.calculate([recipe], 1, 0, "0.7")
    cost = KitchenCosts.cost_consumption(consumption, ~D[2026-10-27])
    assert cost.complete?
    assert cost.issues == []
    assert Decimal.equal?(cost.known_total, "0")
    assert hd(cost.quantities).price.source == "not_required"
  end
end

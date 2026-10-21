defmodule CozyCheckout.Repo.Migrations.CreateRecipeCatalog do
  use Ecto.Migration

  def up do
    create table(:kitchen_ingredients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :category, :string, null: false
      add :base_unit, :string, null: false
      add :purchase_mode, :string
      add :package_size, :decimal
      add :notes, :text
      add :source_key, :string
      add :archived_at, :utc_datetime
      add :lock_version, :integer, default: 1, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:kitchen_ingredients, [:name])
    create unique_index(:kitchen_ingredients, [:source_key])

    create constraint(:kitchen_ingredients, :ingredient_unit,
             check: "base_unit IN ('kg','l','ks')"
           )

    create table(:recipes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :base_servings, :decimal, null: false
      add :source_reference, :text
      add :notes, :text
      add :source_key, :string
      add :archived_at, :utc_datetime
      add :lock_version, :integer, default: 1, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:recipes, [:name])
    create unique_index(:recipes, [:source_key])
    create constraint(:recipes, :positive_base_servings, check: "base_servings > 0")

    create table(:recipe_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :recipe_id, references(:recipes, type: :binary_id, on_delete: :delete_all), null: false

      add :ingredient_id,
          references(:kitchen_ingredients, type: :binary_id, on_delete: :restrict),
          null: false

      add :quantity, :decimal, null: false
      add :unit, :string, null: false
      add :notes, :text
      add :position, :integer, default: 0, null: false
      add :source_row, :integer
      timestamps(type: :utc_datetime)
    end

    create index(:recipe_lines, [:recipe_id])
    create index(:recipe_lines, [:ingredient_id])
    create constraint(:recipe_lines, :nonnegative_recipe_quantity, check: "quantity >= 0")

    create table(:kitchen_settings) do
      add :hot_child_factor, :decimal, default: "0.7", null: false
      add :breakfast_child_factor, :decimal, default: "0.7", null: false
      add :lock_version, :integer, default: 1, null: false
      timestamps(type: :utc_datetime)
    end

    create constraint(:kitchen_settings, :singleton_settings, check: "id = 1")

    create constraint(:kitchen_settings, :child_factors_in_range,
             check: "hot_child_factor BETWEEN 0 AND 1 AND breakfast_child_factor BETWEEN 0 AND 1"
           )

    alter table(:menu_variant_items),
      do: add(:recipe_id, references(:recipes, type: :binary_id, on_delete: :restrict))

    alter table(:booking_menu_items),
      do: add(:recipe_id, references(:recipes, type: :binary_id, on_delete: :restrict))

    for {table, parent, parent_table} <- [
          {:menu_variant_supplements, :menu_variant_item_id, :menu_variant_items},
          {:booking_menu_supplements, :booking_menu_item_id, :booking_menu_items}
        ] do
      create table(table, primary_key: false) do
        add :id, :binary_id, primary_key: true

        add parent, references(parent_table, type: :binary_id, on_delete: :delete_all),
          null: false

        add :recipe_id, references(:recipes, type: :binary_id, on_delete: :restrict), null: false
        add :position, :integer, default: 0, null: false
        timestamps(type: :utc_datetime)
      end

      create unique_index(table, [parent, :recipe_id])
    end

    flush()
    import_snapshot()
  end

  # Versioned data and raw tables make this independent of future schema changes.
  defp import_snapshot do
    data =
      Application.app_dir(:cozy_checkout, "priv/recipes/drive_reference.json")
      |> File.read!()
      |> Jason.decode!()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(data["ingredients"], fn r ->
        %{
          id: uuid(),
          name: r["name"],
          category: r["category"],
          base_unit: r["base_unit"],
          purchase_mode: r["purchase_mode"],
          package_size: decimal(r["package_size"]),
          notes: r["notes"],
          source_key: key(r["name"]),
          inserted_at: now,
          updated_at: now
        }
      end)

    repo().insert_all("kitchen_ingredients", rows, on_conflict: :nothing)

    ids =
      repo().query!("SELECT name, id FROM kitchen_ingredients").rows
      |> Map.new(fn [n, id] -> {n, id} end)

    Enum.each(data["recipes"], fn r ->
      id = uuid()

      {count, _} =
        repo().insert_all(
          "recipes",
          [
            %{
              id: id,
              name: r["name"],
              base_servings: decimal(r["base_servings"]),
              source_reference: r["source_reference"],
              notes: r["notes"],
              source_key: key(r["name"]),
              inserted_at: now,
              updated_at: now
            }
          ],
          on_conflict: :nothing
        )

      if count == 1 do
        lines =
          Enum.with_index(r["lines"], fn l, i ->
            %{
              id: uuid(),
              recipe_id: id,
              ingredient_id: Map.fetch!(ids, l["ingredient_name"]),
              quantity: decimal(l["quantity"]),
              unit: l["unit"],
              notes: l["notes"],
              source_row: l["source_row"],
              position: i,
              inserted_at: now,
              updated_at: now
            }
          end)

        repo().insert_all("recipe_lines", lines)
      end
    end)

    repo().insert_all(
      "kitchen_settings",
      [
        %{
          id: 1,
          hot_child_factor: decimal(data["hot_child_factor"]),
          breakfast_child_factor: decimal(data["breakfast_child_factor"]),
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing
    )

    recipes =
      repo().query!("SELECT name, id FROM recipes").rows |> Map.new(fn [n, id] -> {n, id} end)

    for {table, links, parent} <- [
          {"menu_variant_items", "menu_variant_supplements", :menu_variant_item_id},
          {"booking_menu_items", "booking_menu_supplements", :booking_menu_item_id}
        ] do
      Enum.each(repo().query!("SELECT id, menu_text, supplements FROM #{table}").rows, fn [
                                                                                            id,
                                                                                            text,
                                                                                            supplements
                                                                                          ] ->
        if recipes[text],
          do:
            repo().query!(
              "UPDATE #{table} SET recipe_id = $1 WHERE id = $2 AND recipe_id IS NULL",
              [recipes[text], id]
            )

        (supplements || "")
        |> String.split("\n", trim: true)
        |> Enum.with_index()
        |> Enum.each(fn {name, i} ->
          name = name |> String.replace(~r/^Polévka k (obědu|večeři):\s*/u, "") |> String.trim()

          if recipes[name],
            do:
              repo().insert_all(
                links,
                [
                  %{
                    parent => id,
                    :id => uuid(),
                    :recipe_id => recipes[name],
                    :position => i,
                    :inserted_at => now,
                    :updated_at => now
                  }
                ],
                on_conflict: :nothing
              )
        end)
      end)
    end
  end

  defp decimal(nil), do: nil
  defp decimal(value), do: Decimal.new(value)
  defp uuid, do: Ecto.UUID.generate() |> Ecto.UUID.dump!()
  defp key(name), do: "drive:" <> Base.encode16(:crypto.hash(:sha256, name), case: :lower)

  def down do
    drop table(:booking_menu_supplements)
    drop table(:menu_variant_supplements)
    alter table(:booking_menu_items), do: remove(:recipe_id)
    alter table(:menu_variant_items), do: remove(:recipe_id)
    drop table(:kitchen_settings)
    drop table(:recipe_lines)
    drop table(:recipes)
    drop table(:kitchen_ingredients)
  end
end

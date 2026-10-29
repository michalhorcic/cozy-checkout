defmodule CozyCheckout.Repo.Migrations.CreateKitchenFreezerItems do
  use Ecto.Migration

  def change do
    create table(:kitchen_freezer_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :quantity, :decimal, null: false
      add :unit, :string, null: false
      add :frozen_on, :date, null: false
      add :ingredient_id, references(:kitchen_ingredients, type: :binary_id)
      add :recipe_id, references(:recipes, type: :binary_id)
      add :location, :string
      add :notes, :text
      add :archived_at, :utc_datetime
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create constraint(:kitchen_freezer_items, :freezer_quantity,
             check: "quantity >= 0 AND (archived_at IS NOT NULL OR quantity > 0)"
           )

    create constraint(:kitchen_freezer_items, :freezer_unit,
             check: "unit IN ('kg', 'g', 'l', 'ml', 'ks', 'porce')"
           )

    create constraint(:kitchen_freezer_items, :freezer_link,
             check: "ingredient_id IS NULL OR recipe_id IS NULL"
           )

    create index(:kitchen_freezer_items, [:frozen_on, :id], where: "archived_at IS NULL")
    create index(:kitchen_freezer_items, [:ingredient_id])
    create index(:kitchen_freezer_items, [:recipe_id])
  end
end

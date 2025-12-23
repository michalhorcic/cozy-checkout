defmodule CozyCheckout.Repo.Migrations.CreateMeals do
  use Ecto.Migration

  def change do
    create table(:meals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :date, :date, null: false
      add :meal_type, :string, null: false
      add :menu_text, :text
      add :dietary_notes, :text
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:meals, [:date, :meal_type], where: "deleted_at IS NULL")
    create index(:meals, [:date])
    create index(:meals, [:meal_type])
    create index(:meals, [:deleted_at])
  end
end

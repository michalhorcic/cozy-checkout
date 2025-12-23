defmodule CozyCheckout.Repo.Migrations.CreateMealTemplates do
  use Ecto.Migration

  def change do
    create table(:meal_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :category, :string, null: false
      add :default_menu_text, :text
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:meal_templates, [:category])
    create index(:meal_templates, [:deleted_at])
    create index(:meal_templates, [:name])
  end
end

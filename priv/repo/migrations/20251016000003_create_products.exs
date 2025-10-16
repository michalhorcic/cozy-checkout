defmodule CozyCheckout.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :category_id, references(:categories, type: :binary_id, on_delete: :nilify_all)
      add :active, :boolean, default: true, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:products, [:category_id])
    create index(:products, [:active])
    create index(:products, [:deleted_at])
  end
end

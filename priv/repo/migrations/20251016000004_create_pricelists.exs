defmodule CozyCheckout.Repo.Migrations.CreatePricelists do
  use Ecto.Migration

  def change do
    create table(:pricelists, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all),
        null: false

      add :price, :decimal, precision: 10, scale: 2, null: false
      add :vat_rate, :decimal, precision: 5, scale: 2, null: false
      add :valid_from, :date, null: false
      add :valid_to, :date
      add :active, :boolean, default: true, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:pricelists, [:product_id])
    create index(:pricelists, [:active])
    create index(:pricelists, [:valid_from, :valid_to])
    create index(:pricelists, [:deleted_at])
  end
end

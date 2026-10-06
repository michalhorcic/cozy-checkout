defmodule CozyCheckout.Repo.Migrations.CreatePosProductShortcuts do
  use Ecto.Migration

  def change do
    create table(:pos_product_shortcuts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:products, type: :binary_id, on_delete: :restrict), null: false

      add :unit_amount, :decimal, precision: 10, scale: 2
      add :position, :integer, null: false, default: 0
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:pos_product_shortcuts, [:product_id])
    create index(:pos_product_shortcuts, [:position])
    create index(:pos_product_shortcuts, [:deleted_at])
  end
end

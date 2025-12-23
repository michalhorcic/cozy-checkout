defmodule CozyCheckout.Repo.Migrations.CreateStockAdjustments do
  use Ecto.Migration

  def change do
    create table(:stock_adjustments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:products, type: :binary_id, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :unit_amount, :decimal, precision: 10, scale: 2
      add :adjustment_type, :string, null: false
      add :reason, :string, null: false
      add :notes, :text
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:stock_adjustments, [:product_id])
    create index(:stock_adjustments, [:deleted_at])
    create index(:stock_adjustments, [:adjustment_type])
    create index(:stock_adjustments, [:inserted_at])
  end
end

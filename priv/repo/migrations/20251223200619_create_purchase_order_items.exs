defmodule CozyCheckout.Repo.Migrations.CreatePurchaseOrderItems do
  use Ecto.Migration

  def change do
    create table(:purchase_order_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :purchase_order_id, references(:purchase_orders, on_delete: :delete_all, type: :binary_id), null: false
      add :product_id, references(:products, on_delete: :restrict, type: :binary_id), null: false
      add :quantity, :integer, null: false
      add :unit_amount, :decimal, precision: 10, scale: 2
      add :cost_price, :decimal, precision: 10, scale: 2, null: false
      add :notes, :text
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:purchase_order_items, [:purchase_order_id])
    create index(:purchase_order_items, [:product_id])
    create index(:purchase_order_items, [:deleted_at])
  end
end

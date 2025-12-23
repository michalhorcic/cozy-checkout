defmodule CozyCheckout.Repo.Migrations.CreatePurchaseOrders do
  use Ecto.Migration

  def change do
    create table(:purchase_orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_number, :string, null: false
      add :supplier_note, :text
      add :order_date, :date, null: false
      add :notes, :text
      add :total_cost, :decimal, precision: 10, scale: 2
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:purchase_orders, [:order_number])
    create index(:purchase_orders, [:deleted_at])
    create index(:purchase_orders, [:order_date])
  end
end

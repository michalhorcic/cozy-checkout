defmodule CozyCheckout.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :guest_id, references(:guests, type: :binary_id, on_delete: :restrict), null: false
      add :order_number, :string, null: false
      add :status, :string, null: false, default: "open"
      add :total_amount, :decimal, precision: 10, scale: 2, null: false, default: 0
      add :discount_amount, :decimal, precision: 10, scale: 2, default: 0
      add :notes, :text
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orders, [:order_number])
    create index(:orders, [:guest_id])
    create index(:orders, [:status])
    create index(:orders, [:deleted_at])
  end
end

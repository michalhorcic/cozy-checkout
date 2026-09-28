defmodule CozyCheckout.Repo.Migrations.AddBarInventory do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :track_bar_stock, :boolean, null: false, default: false
      add :bar_stock_threshold, :decimal, precision: 12, scale: 3, null: false, default: 0
    end

    create table(:bar_stock_movements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :product_id, references(:products, type: :binary_id, on_delete: :restrict), null: false
      add :order_item_id, references(:order_items, type: :binary_id, on_delete: :nilify_all)
      add :quantity, :decimal, precision: 12, scale: 3, null: false
      add :movement_type, :string, null: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:bar_stock_movements, [:product_id])
    create index(:bar_stock_movements, [:order_item_id])
    create index(:bar_stock_movements, [:movement_type])
    create index(:bar_stock_movements, [:inserted_at])
  end
end

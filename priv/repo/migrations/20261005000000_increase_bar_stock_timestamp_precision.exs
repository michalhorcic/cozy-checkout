defmodule CozyCheckout.Repo.Migrations.IncreaseBarStockTimestampPrecision do
  use Ecto.Migration

  def change do
    alter table(:bar_stock_movements) do
      modify :inserted_at, :utc_datetime_usec, null: false
      modify :updated_at, :utc_datetime_usec, null: false
    end
  end
end

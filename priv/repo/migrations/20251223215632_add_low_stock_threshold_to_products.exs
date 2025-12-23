defmodule CozyCheckout.Repo.Migrations.AddLowStockThresholdToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :low_stock_threshold, :integer, default: 0
    end
  end
end

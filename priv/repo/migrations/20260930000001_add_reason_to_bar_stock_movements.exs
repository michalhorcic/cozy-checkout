defmodule CozyCheckout.Repo.Migrations.AddReasonToBarStockMovements do
  use Ecto.Migration

  def change do
    alter table(:bar_stock_movements) do
      add :reason, :string
    end
  end
end

defmodule CozyCheckout.Repo.Migrations.IncreasePurchaseOrderItemCostPricePrecision do
  use Ecto.Migration

  def change do
    alter table(:purchase_order_items) do
      modify :cost_price, :decimal, precision: 10, scale: 4, null: false
      modify :unit_amount, :decimal, precision: 10, scale: 4
    end
  end
end

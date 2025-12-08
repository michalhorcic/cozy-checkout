defmodule CozyCheckout.Repo.Migrations.AddTipsAndDiscountReasonToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :tips_amount, :decimal, precision: 10, scale: 2, default: 0
      add :discount_reason, :string
    end
  end
end

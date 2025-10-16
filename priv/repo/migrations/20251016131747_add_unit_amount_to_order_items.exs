defmodule CozyCheckout.Repo.Migrations.AddUnitAmountToOrderItems do
  use Ecto.Migration

  def change do
    alter table(:order_items) do
      add :unit_amount, :decimal, precision: 10, scale: 2
    end
  end
end

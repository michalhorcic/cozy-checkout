defmodule CozyCheckout.Repo.Migrations.AddIsServiceOrderToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :is_service_order, :boolean, default: false, null: false
    end

    create index(:orders, [:is_service_order])
  end
end

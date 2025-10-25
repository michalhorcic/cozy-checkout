defmodule CozyCheckout.Repo.Migrations.AddPriceTiersToPricelists do
  use Ecto.Migration

  def change do
    alter table(:pricelists) do
      # Store array of price tiers: [%{unit_amount: 300, price: 45.00}, %{unit_amount: 500, price: 70.00}]
      add :price_tiers, :jsonb, default: "[]"

      # Make the old price column nullable for backwards compatibility
      modify :price, :decimal, precision: 10, scale: 2, null: true
    end

    # Create GIN index for efficient querying of JSONB data
    create index(:pricelists, [:price_tiers], using: :gin)
  end
end

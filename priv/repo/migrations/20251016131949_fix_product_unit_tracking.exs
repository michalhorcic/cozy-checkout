defmodule CozyCheckout.Repo.Migrations.FixProductUnitTracking do
  use Ecto.Migration

  def change do
    alter table(:products) do
      # Remove old unit_amount field if it exists
      remove_if_exists :unit_amount, :decimal

      # Add unit field if not exists (for ml, L, pcs)
      add_if_not_exists :unit, :string

      # Add default_unit_amounts for preset portions (stored as JSON array string)
      add_if_not_exists :default_unit_amounts, :text
    end
  end
end

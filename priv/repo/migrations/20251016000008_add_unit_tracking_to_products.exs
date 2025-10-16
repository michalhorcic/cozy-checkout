defmodule CozyCheckout.Repo.Migrations.AddUnitTrackingToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :unit, :string
      add :default_unit_amounts, :text
    end
  end
end

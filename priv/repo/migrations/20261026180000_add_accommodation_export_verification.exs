defmodule CozyCheckout.Repo.Migrations.AddAccommodationExportVerification do
  use Ecto.Migration

  def change do
    alter table(:accommodation_abra_exports) do
      add :verification, :map, null: false, default: %{}
    end
  end
end

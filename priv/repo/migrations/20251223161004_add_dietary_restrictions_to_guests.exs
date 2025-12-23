defmodule CozyCheckout.Repo.Migrations.AddDietaryRestrictionsToGuests do
  use Ecto.Migration

  def change do
    alter table(:guests) do
      add :dietary_restrictions, :text
    end
  end
end

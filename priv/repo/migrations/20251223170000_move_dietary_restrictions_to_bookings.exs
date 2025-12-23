defmodule CozyCheckout.Repo.Migrations.MoveDietaryRestrictionsToBookings do
  use Ecto.Migration

  def change do
    alter table(:bookings) do
      add :dietary_restrictions, :text
    end

    # Optional: Remove from guests if you want (commented out to preserve existing data)
    # alter table(:guests) do
    #   remove :dietary_restrictions
    # end
  end
end

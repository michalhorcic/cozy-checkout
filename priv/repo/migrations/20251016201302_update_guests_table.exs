defmodule CozyCheckout.Repo.Migrations.UpdateGuestsTable do
  use Ecto.Migration

  def up do
    alter table(:guests) do
      # Add email field
      add :email, :string

      # Remove booking-specific fields (already migrated to bookings table)
      remove :room_number
      remove :check_in_date
      remove :check_out_date
    end

    # Add unique constraint on email
    create unique_index(:guests, [:email], where: "email IS NOT NULL AND deleted_at IS NULL")
  end

  def down do
    drop_if_exists unique_index(:guests, [:email])

    alter table(:guests) do
      remove :email

      # Re-add the removed fields
      add :room_number, :string
      add :check_in_date, :date
      add :check_out_date, :date
    end
  end
end

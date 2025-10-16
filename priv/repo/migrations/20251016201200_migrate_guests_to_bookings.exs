defmodule CozyCheckout.Repo.Migrations.MigrateGuestsToBookings do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Migrate existing guest data to bookings table
    # Each guest becomes one booking
    execute("""
    INSERT INTO bookings (id, guest_id, room_number, check_in_date, check_out_date, status, notes, deleted_at, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      id,
      room_number,
      COALESCE(check_in_date, CURRENT_DATE),
      check_out_date,
      CASE
        WHEN check_in_date IS NULL THEN 'upcoming'
        WHEN check_in_date > CURRENT_DATE THEN 'upcoming'
        WHEN check_out_date IS NOT NULL AND check_out_date < CURRENT_DATE THEN 'completed'
        WHEN check_in_date <= CURRENT_DATE AND (check_out_date IS NULL OR check_out_date >= CURRENT_DATE) THEN 'active'
        ELSE 'active'
      END,
      NULL,
      deleted_at,
      inserted_at,
      updated_at
    FROM guests
    WHERE deleted_at IS NULL
    """)
  end

  def down do
    # Clear bookings table on rollback
    execute("DELETE FROM bookings")
  end
end

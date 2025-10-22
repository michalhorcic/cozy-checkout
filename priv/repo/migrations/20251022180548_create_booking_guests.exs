defmodule CozyCheckout.Repo.Migrations.CreateBookingGuests do
  use Ecto.Migration

  def change do
    create table(:booking_guests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :booking_id, references(:bookings, on_delete: :delete_all, type: :binary_id),
        null: false

      add :guest_id, references(:guests, on_delete: :delete_all, type: :binary_id), null: false
      add :is_primary, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:booking_guests, [:booking_id])
    create index(:booking_guests, [:guest_id])
    create unique_index(:booking_guests, [:booking_id, :guest_id])

    # Create booking_guests records for existing bookings
    execute(
      """
      INSERT INTO booking_guests (id, booking_id, guest_id, is_primary, inserted_at, updated_at)
      SELECT gen_random_uuid(), id, guest_id, true, inserted_at, updated_at
      FROM bookings
      WHERE guest_id IS NOT NULL AND deleted_at IS NULL
      """,
      """
      -- No rollback needed, table will be dropped
      """
    )
  end
end

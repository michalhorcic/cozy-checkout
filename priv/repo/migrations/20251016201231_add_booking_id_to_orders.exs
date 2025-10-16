defmodule CozyCheckout.Repo.Migrations.AddBookingIdToOrders do
  use Ecto.Migration

  def up do
    # Add booking_id column
    alter table(:orders) do
      add :booking_id, references(:bookings, type: :binary_id, on_delete: :restrict)
    end

    create index(:orders, [:booking_id])

    # Populate booking_id from guest_id
    # Match orders to bookings based on guest_id
    execute("""
    UPDATE orders
    SET booking_id = (
      SELECT b.id
      FROM bookings b
      WHERE b.guest_id = orders.guest_id
      AND b.deleted_at IS NULL
      ORDER BY b.check_in_date DESC
      LIMIT 1
    )
    WHERE deleted_at IS NULL
    """)

    # Make booking_id not null after populating
    alter table(:orders) do
      modify :booking_id, :binary_id, null: false
    end
  end

  def down do
    alter table(:orders) do
      remove :booking_id
    end
  end
end

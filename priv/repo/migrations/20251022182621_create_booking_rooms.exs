defmodule CozyCheckout.Repo.Migrations.CreateBookingRooms do
  use Ecto.Migration

  def change do
    create table(:booking_rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :booking_id, references(:bookings, on_delete: :delete_all, type: :binary_id),
        null: false
      add :room_id, references(:rooms, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:booking_rooms, [:booking_id])
    create index(:booking_rooms, [:room_id])
    create unique_index(:booking_rooms, [:booking_id, :room_id])
  end
end

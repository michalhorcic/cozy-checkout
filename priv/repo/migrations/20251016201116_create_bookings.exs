defmodule CozyCheckout.Repo.Migrations.CreateBookings do
  use Ecto.Migration

  def change do
    create table(:bookings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :guest_id, references(:guests, type: :binary_id, on_delete: :restrict), null: false
      add :room_number, :string
      add :check_in_date, :date, null: false
      add :check_out_date, :date
      add :status, :string, null: false, default: "active"
      add :notes, :text
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:bookings, [:guest_id])
    create index(:bookings, [:status])
    create index(:bookings, [:check_in_date])
    create index(:bookings, [:check_out_date])
    create index(:bookings, [:deleted_at])
    create unique_index(:bookings, [:guest_id, :check_in_date], where: "deleted_at IS NULL")
  end
end

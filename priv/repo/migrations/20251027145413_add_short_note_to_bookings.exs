defmodule CozyCheckout.Repo.Migrations.AddShortNoteToBookings do
  use Ecto.Migration

  def change do
    alter table(:bookings) do
      add :short_note, :string, size: 30
    end
  end
end

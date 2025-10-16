defmodule CozyCheckout.Repo.Migrations.CreateGuests do
  use Ecto.Migration

  def change do
    create table(:guests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :room_number, :string
      add :phone, :string
      add :notes, :text
      add :check_in_date, :date
      add :check_out_date, :date
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:guests, [:deleted_at])
  end
end

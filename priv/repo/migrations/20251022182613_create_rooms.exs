defmodule CozyCheckout.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_number, :string, null: false
      add :name, :string
      add :description, :text
      add :capacity, :integer, null: false
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rooms, [:room_number], where: "deleted_at IS NULL")
    create index(:rooms, [:deleted_at])
  end
end

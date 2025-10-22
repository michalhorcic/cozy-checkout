defmodule CozyCheckout.Rooms.Room do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "rooms" do
    field :room_number, :string
    field :name, :string
    field :description, :string
    field :capacity, :integer
    field :deleted_at, :utc_datetime

    has_many :booking_rooms, CozyCheckout.Bookings.BookingRoom
    has_many :bookings, through: [:booking_rooms, :booking]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:room_number, :name, :description, :capacity])
    |> validate_required([:room_number, :capacity])
    |> validate_number(:capacity, greater_than: 0)
    |> unique_constraint(:room_number)
  end
end

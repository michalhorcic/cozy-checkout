defmodule CozyCheckout.Bookings.BookingRoom do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "booking_rooms" do
    belongs_to :booking, CozyCheckout.Bookings.Booking
    belongs_to :room, CozyCheckout.Rooms.Room

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(booking_room, attrs) do
    booking_room
    |> cast(attrs, [:booking_id, :room_id])
    |> validate_required([:booking_id, :room_id])
    |> foreign_key_constraint(:booking_id)
    |> foreign_key_constraint(:room_id)
    |> unique_constraint([:booking_id, :room_id])
  end
end

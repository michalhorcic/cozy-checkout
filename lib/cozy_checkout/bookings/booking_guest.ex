defmodule CozyCheckout.Bookings.BookingGuest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "booking_guests" do
    field :is_primary, :boolean, default: false

    belongs_to :booking, CozyCheckout.Bookings.Booking
    belongs_to :guest, CozyCheckout.Guests.Guest

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(booking_guest, attrs) do
    booking_guest
    |> cast(attrs, [:booking_id, :guest_id, :is_primary])
    |> validate_required([:booking_id, :guest_id])
    |> foreign_key_constraint(:booking_id)
    |> foreign_key_constraint(:guest_id)
    |> unique_constraint([:booking_id, :guest_id])
  end
end

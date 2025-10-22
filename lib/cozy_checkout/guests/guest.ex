defmodule CozyCheckout.Guests.Guest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "guests" do
    field :name, :string
    field :email, :string
    field :phone, :string
    field :notes, :string
    field :deleted_at, :utc_datetime

    has_many :bookings, CozyCheckout.Bookings.Booking
    has_many :orders, CozyCheckout.Sales.Order
    has_many :booking_guests, CozyCheckout.Bookings.BookingGuest

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(guest, attrs) do
    guest
    |> cast(attrs, [:name, :email, :phone, :notes])
    |> validate_required([:name])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> unique_constraint(:email)
  end
end

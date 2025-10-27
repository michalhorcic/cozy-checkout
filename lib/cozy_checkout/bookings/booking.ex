defmodule CozyCheckout.Bookings.Booking do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [:status, :check_in_date, :check_out_date, :short_note],
    sortable: [:check_in_date, :check_out_date, :status, :inserted_at],
    default_order: %{
      order_by: [:check_in_date],
      order_directions: [:asc]
    },
    default_limit: 100,
    max_limit: 100
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "bookings" do
    field :room_number, :string
    field :check_in_date, :date
    field :check_out_date, :date
    field :status, :string, default: "upcoming"
    field :notes, :string
    field :short_note, :string
    field :deleted_at, :utc_datetime

    belongs_to :guest, CozyCheckout.Guests.Guest
    has_many :orders, CozyCheckout.Sales.Order
    has_many :booking_guests, CozyCheckout.Bookings.BookingGuest
    has_many :additional_guests, through: [:booking_guests, :guest]
    has_many :booking_rooms, CozyCheckout.Bookings.BookingRoom
    has_many :rooms, through: [:booking_rooms, :room]
    has_one :invoice, CozyCheckout.Bookings.BookingInvoice

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(booking, attrs) do
    booking
    |> cast(attrs, [
      :guest_id,
      :room_number,
      :check_in_date,
      :check_out_date,
      :status,
      :notes,
      :short_note
    ])
    |> validate_required([:guest_id, :check_in_date])
    |> validate_length(:short_note, max: 30)
    |> validate_inclusion(:status, ["upcoming", "active", "completed", "cancelled"])
    |> validate_date_range()
    |> foreign_key_constraint(:guest_id)
    |> unique_constraint([:guest_id, :check_in_date])
  end

  defp validate_date_range(changeset) do
    check_in = get_field(changeset, :check_in_date)
    check_out = get_field(changeset, :check_out_date)

    if check_in && check_out && Date.compare(check_in, check_out) == :gt do
      add_error(changeset, :check_out_date, "must be after check-in date")
    else
      changeset
    end
  end
end

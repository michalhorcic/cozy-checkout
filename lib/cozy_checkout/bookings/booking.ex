defmodule CozyCheckout.Bookings.Booking do
  use Ecto.Schema
  use Flop.Schema
  import Ecto.Changeset

  @flop_options [
    tiebreaker: false,
    filterable: [:status, :check_in_date, :check_out_date, :short_note],
    sortable: [:check_in_date, :check_out_date, :status, :inserted_at],
    default_order: %{
      order_by: [:check_in_date],
      order_directions: [:asc]
    },
    default_limit: 100,
    max_limit: 100
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "bookings" do
    field :room_number, :string
    field :check_in_date, :date
    field :check_out_date, :date
    field :status, :string, default: "upcoming"
    field :notes, :string
    field :short_note, :string
    field :dietary_restrictions, :string
    field :meal_plan, :string
    field :meal_adults, :integer
    field :meal_children, :integer
    field :first_meal, :string
    field :last_meal, :string
    field :deleted_at, :utc_datetime

    belongs_to :guest, CozyCheckout.Guests.Guest
    has_many :orders, CozyCheckout.Sales.Order
    has_many :booking_guests, CozyCheckout.Bookings.BookingGuest
    has_many :additional_guests, through: [:booking_guests, :guest]
    has_many :booking_rooms, CozyCheckout.Bookings.BookingRoom
    has_many :rooms, through: [:booking_rooms, :room]
    has_many :email_deliveries, CozyCheckout.GuestEmails.Delivery
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
      :short_note,
      :dietary_restrictions,
      :meal_plan,
      :meal_adults,
      :meal_children,
      :first_meal,
      :last_meal
    ])
    |> validate_required([:guest_id, :check_in_date])
    |> validate_length(:short_note, max: 30)
    |> validate_inclusion(:status, ["upcoming", "active", "completed", "cancelled"])
    |> validate_date_range()
    |> validate_meal_details()
    |> foreign_key_constraint(:guest_id)
    |> unique_constraint([:guest_id, :check_in_date])
  end

  @doc "Whether this booking has complete, valid catering instructions."
  def meal_details_complete?(%__MODULE__{} = booking) do
    meal_schedule_complete?(booking) and
      is_integer(booking.meal_adults) and booking.meal_adults >= 0 and
      is_integer(booking.meal_children) and booking.meal_children >= 0
  end

  @doc "A menu can be planned before the number of diners is known."
  def meal_schedule_complete?(%__MODULE__{} = booking) do
    booking.meal_plan in ["half_board", "full_board"] and
      booking.first_meal in ["breakfast", "lunch", "dinner"] and
      booking.last_meal in ["breakfast", "lunch", "dinner"] and
      (booking |> change() |> validate_meal_details()).valid? and
      not is_nil(booking.check_in_date) and
      not is_nil(booking.check_out_date) and
      Date.compare(booking.check_in_date, booking.check_out_date) != :gt
  end

  defp validate_meal_details(changeset) do
    changeset =
      changeset
      |> validate_inclusion(:meal_plan, ["none", "half_board", "full_board"])
      |> validate_number(:meal_adults, greater_than_or_equal_to: 0)
      |> validate_number(:meal_children, greater_than_or_equal_to: 0)
      |> validate_inclusion(:first_meal, ["breakfast", "lunch", "dinner"])
      |> validate_inclusion(:last_meal, ["breakfast", "lunch", "dinner"])

    if get_field(changeset, :meal_plan) in ["half_board", "full_board"] do
      changeset
      |> validate_required([
        :check_out_date,
        :first_meal,
        :last_meal
      ])
      |> validate_meal_boundaries()
    else
      # Unknown and explicitly uncatered bookings must not retain stale instructions.
      Enum.reduce([:meal_adults, :meal_children, :first_meal, :last_meal], changeset, fn field,
                                                                                         acc ->
        put_change(acc, field, nil)
      end)
    end
  end

  defp validate_meal_boundaries(changeset) do
    changeset =
      if get_field(changeset, :meal_plan) == "half_board" do
        Enum.reduce([:first_meal, :last_meal], changeset, fn field, acc ->
          if get_field(acc, field) == "lunch",
            do: add_error(acc, field, "Polopenze nezahrnuje oběd"),
            else: acc
        end)
      else
        changeset
      end

    meals = ["breakfast", "lunch", "dinner"]
    first = get_field(changeset, :first_meal)
    last = get_field(changeset, :last_meal)

    if get_field(changeset, :check_in_date) == get_field(changeset, :check_out_date) and
         first in meals and last in meals and
         Enum.find_index(meals, &(&1 == first)) > Enum.find_index(meals, &(&1 == last)) do
      add_error(
        changeset,
        :last_meal,
        "Poslední jídlo musí následovat po prvním jídle nebo být stejné"
      )
    else
      changeset
    end
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

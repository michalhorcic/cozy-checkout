defmodule CozyCheckout.Sales.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "orders" do
    field :order_number, :string
    field :status, :string, default: "open"
    field :total_amount, :decimal, default: Decimal.new("0")
    field :discount_amount, :decimal, default: Decimal.new("0")
    field :notes, :string
    field :deleted_at, :utc_datetime

    belongs_to :guest, CozyCheckout.Guests.Guest
    belongs_to :booking, CozyCheckout.Bookings.Booking
    has_many :order_items, CozyCheckout.Sales.OrderItem
    has_many :payments, CozyCheckout.Sales.Payment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:guest_id, :booking_id, :order_number, :status, :total_amount, :discount_amount, :notes])
    |> validate_required([:booking_id, :order_number])
    |> validate_inclusion(:status, ["open", "paid", "partially_paid", "cancelled"])
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
    |> validate_number(:discount_amount, greater_than_or_equal_to: 0)
    |> unique_constraint(:order_number)
    |> foreign_key_constraint(:guest_id)
    |> foreign_key_constraint(:booking_id)
  end
end

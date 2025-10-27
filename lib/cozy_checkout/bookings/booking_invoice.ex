defmodule CozyCheckout.Bookings.BookingInvoice do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "booking_invoices" do
    # Cached calculations
    field :subtotal, :decimal
    field :vat_amount, :decimal
    field :total_price, :decimal

    field :invoice_number, :string
    field :invoice_generated_at, :utc_datetime
    field :state, :string, default: "draft"

    belongs_to :booking, CozyCheckout.Bookings.Booking
    has_many :items, CozyCheckout.Bookings.BookingInvoiceItem, foreign_key: :booking_invoice_id

    timestamps(type: :utc_datetime)
  end

  @valid_states ~w(draft personal generated sent advance_paid paid)

  @doc false
  def changeset(booking_invoice, attrs) do
    booking_invoice
    |> cast(attrs, [
      :booking_id,
      :subtotal,
      :vat_amount,
      :total_price,
      :invoice_number,
      :invoice_generated_at,
      :state
    ])
    |> validate_required([:booking_id])
    |> validate_inclusion(:state, @valid_states)
    |> unique_constraint(:booking_id)
    |> unique_constraint(:invoice_number)
  end

  @doc """
  Calculate the number of nights between check-in and check-out dates.
  Returns 1 if check_out_date is nil (open-ended booking).
  """
  def calculate_nights(%{check_in_date: _check_in, check_out_date: nil}), do: 1

  def calculate_nights(%{check_in_date: check_in, check_out_date: check_out}) do
    Date.diff(check_out, check_in)
  end
end

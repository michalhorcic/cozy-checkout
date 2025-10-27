defmodule CozyCheckout.Bookings.BookingInvoiceItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "booking_invoice_items" do
    field :name, :string
    field :quantity, :integer
    field :price_per_night, :decimal
    field :nights, :integer, default: 1
    field :vat_rate, :decimal
    field :item_type, :string, default: "person"

    # Cached calculations
    field :subtotal, :decimal
    field :vat_amount, :decimal
    field :total, :decimal

    field :position, :integer, default: 0

    belongs_to :booking_invoice, CozyCheckout.Bookings.BookingInvoice

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(invoice_item, attrs) do
    invoice_item
    |> cast(attrs, [
      :booking_invoice_id,
      :name,
      :quantity,
      :price_per_night,
      :nights,
      :vat_rate,
      :subtotal,
      :vat_amount,
      :total,
      :position,
      :item_type
    ])
    |> validate_required([:name, :quantity, :price_per_night, :nights, :vat_rate, :item_type])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_number(:nights, greater_than: 0)
    |> validate_number(:price_per_night, greater_than_or_equal_to: 0)
    |> validate_number(:vat_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:item_type, ["person", "extra"])
  end

  @doc """
  Calculate line item totals based on the item's nights and pricing.
  Returns a map with :subtotal, :vat_amount, and :total.
  """
  def calculate_totals(invoice_item) do
    # Get nights from item, default to 1 if not set
    nights = invoice_item.nights || 1

    # subtotal = quantity * price_per_night * nights
    subtotal =
      invoice_item.price_per_night
      |> Decimal.mult(Decimal.new(invoice_item.quantity))
      |> Decimal.mult(Decimal.new(nights))

    # vat_amount = subtotal * (vat_rate / 100)
    vat_amount =
      subtotal
      |> Decimal.mult(invoice_item.vat_rate)
      |> Decimal.div(Decimal.new(100))

    # total = subtotal + vat_amount
    total = Decimal.add(subtotal, vat_amount)

    %{
      subtotal: subtotal,
      vat_amount: vat_amount,
      total: total
    }
  end
end

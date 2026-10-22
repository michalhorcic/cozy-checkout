defmodule CozyCheckout.Billing.Customer do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "billing_customers" do
    belongs_to :booking, CozyCheckout.Bookings.Booking
    field :data, :map, default: %{}
    timestamps(type: :utc_datetime)
  end
end

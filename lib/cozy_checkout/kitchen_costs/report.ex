defmodule CozyCheckout.KitchenCosts.Report do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "kitchen_cost_reports" do
    field :start_date, :date
    field :end_date, :date
    belongs_to :booking, CozyCheckout.Bookings.Booking
    field :snapshot, :map
    field :calculated_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

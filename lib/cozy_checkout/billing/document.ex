defmodule CozyCheckout.Billing.Document do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "billing_documents" do
    belongs_to :booking, CozyCheckout.Bookings.Booking
    belongs_to :parent, __MODULE__
    field :kind, :string
    field :number, :string
    field :variable_symbol, :string
    field :request_id, Ecto.UUID
    field :issued_on, :date
    field :tax_date, :date
    field :due_on, :date
    field :snapshot, :map
    field :lines, {:array, :map}, default: []
    field :total, :decimal
    field :pdf, :binary
    field :pdf_sha256, :string
    timestamps(type: :utc_datetime)
  end
end

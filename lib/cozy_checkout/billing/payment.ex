defmodule CozyCheckout.Billing.Payment do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "billing_payments" do
    belongs_to :booking, CozyCheckout.Bookings.Booking
    belongs_to :document, CozyCheckout.Billing.Document
    belongs_to :tax_document, CozyCheckout.Billing.Document
    field :request_id, Ecto.UUID
    field :kind, :string, default: "receipt"
    field :amount, :decimal
    field :paid_on, :date
    field :method, :string
    field :reference, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:request_id, :kind, :amount, :paid_on, :method, :reference, :document_id])
    |> validate_required([:request_id, :kind, :amount, :paid_on, :method])
    |> validate_number(:amount, greater_than: 0)
    |> validate_inclusion(:kind, ~w(receipt refund))
    |> validate_inclusion(:method, ~w(bank cash card))
    |> unique_constraint(:request_id)
  end
end

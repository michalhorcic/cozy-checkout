defmodule CozyCheckout.Sales.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "payments" do
    field :amount, :decimal
    field :payment_method, :string
    field :payment_date, :date
    field :notes, :string
    field :deleted_at, :utc_datetime

    belongs_to :order, CozyCheckout.Sales.Order

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [:order_id, :amount, :payment_method, :payment_date, :notes])
    |> validate_required([:order_id, :amount, :payment_method, :payment_date])
    |> validate_number(:amount, greater_than: 0)
    |> validate_inclusion(:payment_method, ["cash", "qr_code"])
    |> foreign_key_constraint(:order_id)
  end
end

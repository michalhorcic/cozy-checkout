defmodule CozyCheckout.Sales.InvoiceCounter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "invoice_counters" do
    field :year, :integer
    field :counter, :integer, default: 0

    timestamps()
  end

  @doc false
  def changeset(invoice_counter, attrs) do
    invoice_counter
    |> cast(attrs, [:year, :counter])
    |> validate_required([:year, :counter])
    |> validate_number(:counter, greater_than_or_equal_to: 0)
    |> unique_constraint(:year)
  end
end

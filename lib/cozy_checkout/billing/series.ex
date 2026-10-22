defmodule CozyCheckout.Billing.Series do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "billing_series" do
    field :kind, :string
    field :year, :integer
    field :prefix, :string
    field :digits, :integer, default: 5
    field :next_number, :integer, default: 1
    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:kind, :year, :prefix, :digits, :next_number])
    |> validate_required([:kind, :year, :prefix, :digits, :next_number])
    |> validate_inclusion(:kind, ~w(advance tax_receipt final correction))
    |> validate_format(:prefix, ~r/\A[A-Za-z0-9-]+\z/)
    |> validate_number(:digits, greater_than: 0, less_than_or_equal_to: 8)
    |> validate_number(:year, greater_than_or_equal_to: 2000, less_than_or_equal_to: 9999)
    |> validate_number(:next_number, greater_than: 0)
    |> unique_constraint([:kind, :year])
  end
end

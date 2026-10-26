defmodule CozyCheckout.Abra.BankMovement do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "abra_bank_movements" do
    field :base_url, :string
    field :company_id, :string
    field :evidence, :string, default: "banka"
    field :remote_id, :string
    field :account, :string
    field :amount, :decimal
    field :currency, :string
    field :direction, :string
    field :paid_on, :date
    field :variable_symbol, :string
    field :counterparty, :string
    field :pairing, :string
    field :raw, :map
    field :scan_id, Ecto.UUID
    field :missing_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

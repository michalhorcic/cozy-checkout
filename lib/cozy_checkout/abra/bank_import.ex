defmodule CozyCheckout.Abra.BankImport do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "abra_bank_imports" do
    field :base_url, :string
    field :company_id, :string
    field :account, :string
    field :scan_id, Ecto.UUID
    field :offset, :integer, default: 0
    field :last_success_at, :utc_datetime
    field :last_attempt_at, :utc_datetime
    field :error, :string
    timestamps(type: :utc_datetime)
  end
end

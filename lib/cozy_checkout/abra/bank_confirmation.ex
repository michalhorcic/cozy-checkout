defmodule CozyCheckout.Abra.BankConfirmation do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "abra_bank_confirmations" do
    belongs_to :movement, CozyCheckout.Abra.BankMovement
    belongs_to :payment, CozyCheckout.Billing.Payment
    belongs_to :source_export, CozyCheckout.Abra.AccommodationExport
    field :base_url, :string
    field :company_id, :string
    field :bank_snapshot, :map
    field :receipt_payload, :map
    field :remote_receipt_id, :string
    field :state, :string, default: "queued"
    field :attempts, :integer, default: 0
    field :error, :string
    field :synced_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

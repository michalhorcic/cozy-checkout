defmodule CozyCheckout.Repo.Migrations.CreateAbraBankConfirmations do
  use Ecto.Migration

  def change do
    create table(:abra_bank_confirmations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :movement_id, references(:abra_bank_movements, type: :binary_id), null: false
      add :payment_id, references(:billing_payments, type: :binary_id), null: false

      add :source_export_id, references(:accommodation_abra_exports, type: :binary_id),
        null: false

      add :base_url, :text, null: false
      add :company_id, :text, null: false
      add :bank_snapshot, :map, null: false
      add :receipt_payload, :map, null: false
      add :remote_receipt_id, :text
      add :state, :text, null: false, default: "queued"
      add :attempts, :integer, null: false, default: 0
      add :error, :text
      add :synced_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:abra_bank_confirmations, [:movement_id])
    create unique_index(:abra_bank_confirmations, [:payment_id])

    create constraint(:abra_bank_confirmations, :valid_bank_confirmation_state,
             check: "state IN ('queued', 'retrying', 'conflict', 'failed', 'synced')"
           )
  end
end

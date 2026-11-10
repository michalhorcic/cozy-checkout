defmodule CozyCheckout.Repo.Migrations.CreateBillingManualDeliveries do
  use Ecto.Migration

  def change do
    create table(:billing_manual_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :document_id, references(:billing_documents, type: :binary_id), null: false
      add :request_id, :uuid, null: false
      add :sent_on, :date, null: false
      add :note, :text
      add :replaces_id, references(:billing_manual_deliveries, type: :binary_id)
      add :voided_at, :utc_datetime
      add :void_reason, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_manual_deliveries, [:request_id])
    create unique_index(:billing_manual_deliveries, [:replaces_id])
    create index(:billing_manual_deliveries, [:document_id])

    create constraint(:billing_manual_deliveries, :manual_delivery_void_reason,
             check:
               "(voided_at IS NULL AND void_reason IS NULL) OR (voided_at IS NOT NULL AND void_reason IS NOT NULL AND void_reason IN ('corrected', 'cancelled'))"
           )
  end
end

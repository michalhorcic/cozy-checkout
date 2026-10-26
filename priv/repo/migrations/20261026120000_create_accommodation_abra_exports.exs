defmodule CozyCheckout.Repo.Migrations.CreateAccommodationAbraExports do
  use Ecto.Migration

  def change do
    create table(:accommodation_abra_exports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :document_id, references(:billing_documents, type: :binary_id), null: false
      add :base_url, :text, null: false
      add :company_id, :text, null: false
      add :external_id, :text, null: false
      add :payload, :map, null: false
      add :remote_id, :text
      add :state, :string, null: false, default: "queued"
      add :attempts, :integer, null: false, default: 0
      add :error, :text
      add :synced_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:accommodation_abra_exports, [:document_id])

    create unique_index(:accommodation_abra_exports, [:base_url, :company_id, :external_id],
             name: :accommodation_abra_exports_identity_index
           )

    create constraint(:accommodation_abra_exports, :valid_export_state,
             check: "state IN ('queued', 'retrying', 'failed', 'synced')"
           )
  end
end

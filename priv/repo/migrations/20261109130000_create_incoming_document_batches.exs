defmodule CozyCheckout.Repo.Migrations.CreateIncomingDocumentBatches do
  use Ecto.Migration

  def change do
    create table(:incoming_document_batches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :agenda, :string, null: false
      add :base_url, :string, null: false
      add :company_id, :string, null: false
      add :accounting_settings, :map, null: false, default: %{}
      add :include_items, :boolean, null: false, default: false
      add :max_files, :integer, null: false, default: 50
      add :model, :string
      add :started_at, :utc_datetime
      add :extraction_finished_at, :utc_datetime
      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create constraint(:incoming_document_batches, :incoming_batch_agenda,
             check: "agenda IN ('faktura-prijata', 'pokladni-pohyb', 'zavazek')"
           )

    create constraint(:incoming_document_batches, :incoming_batch_limit, check: "max_files > 0")

    alter table(:incoming_documents) do
      add :batch_id, references(:incoming_document_batches, type: :binary_id)
      add :batch_position, :integer
      add :deferred_at, :utc_datetime
      add :initial_extraction_run_id, :binary_id
    end

    execute """
            ALTER TABLE incoming_documents ADD CONSTRAINT incoming_initial_run_document
            FOREIGN KEY (initial_extraction_run_id, id)
            REFERENCES incoming_extraction_runs (id, document_id)
            """,
            "ALTER TABLE incoming_documents DROP CONSTRAINT incoming_initial_run_document"

    alter table(:incoming_extraction_runs) do
      add :model, :string
    end

    create unique_index(:incoming_documents, [:batch_id, :batch_position])
    create unique_index(:incoming_documents, [:batch_id, :sha256], where: "deleted_at IS NULL")
    create index(:incoming_document_batches, [:inserted_at])

    create constraint(:incoming_documents, :incoming_batch_position,
             check:
               "(batch_id IS NULL AND batch_position IS NULL) OR (batch_id IS NOT NULL AND batch_position IS NOT NULL AND batch_position > 0)"
           )

    drop constraint(:incoming_documents, :incoming_document_state)

    create constraint(:incoming_documents, :incoming_document_state,
             check:
               "state IN ('staged', 'uploaded', 'processing', 'review', 'validating', 'sending', 'sent', 'failed', 'uncertain')"
           )
  end
end

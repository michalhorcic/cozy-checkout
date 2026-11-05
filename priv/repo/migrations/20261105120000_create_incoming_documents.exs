defmodule CozyCheckout.Repo.Migrations.CreateIncomingDocuments do
  use Ecto.Migration

  def change do
    create table(:incoming_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agenda, :string, null: false
      add :state, :string, null: false, default: "uploaded"
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :original, :binary, null: false
      add :sha256, :string, null: false
      add :template_xml, :text, null: false
      add :generated_xml, :text
      add :current_xml, :text
      add :sent_xml, :text
      add :base_url, :string, null: false
      add :company_id, :string, null: false
      add :external_id, :string, null: false
      add :dry_run, :map, null: false, default: %{}
      add :response, :map, null: false, default: %{}
      add :remote_id, :string
      add :error, :text
      add :error_stage, :string
      add :sent_at, :utc_datetime
      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:incoming_documents, [:external_id])
    create index(:incoming_documents, [:sha256])
    create index(:incoming_documents, [:inserted_at])

    create constraint(:incoming_documents, :incoming_document_agenda,
             check: "agenda IN ('faktura-prijata', 'pokladni-pohyb', 'zavazek')"
           )

    create constraint(:incoming_documents, :incoming_document_state,
             check:
               "state IN ('uploaded', 'processing', 'review', 'validating', 'sending', 'sent', 'failed', 'uncertain')"
           )
  end
end

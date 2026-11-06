defmodule CozyCheckout.Repo.Migrations.CreateSupplierExtractionRuns do
  use Ecto.Migration

  def change do
    create table(:incoming_supplier_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :base_url, :text, null: false
      add :company_id, :text, null: false
      add :country_code, :string, null: false
      add :identity_kind, :string, null: false
      add :identity_value, :string, null: false
      add :name, :string
      add :ic, :string
      add :dic, :string
      add :instructions, :text, null: false, default: ""
      add :revision, :integer, null: false, default: 1
      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :incoming_supplier_profiles,
             [:base_url, :company_id, :country_code, :identity_kind, :identity_value],
             where: "deleted_at IS NULL",
             name: :incoming_supplier_identity
           )

    create constraint(:incoming_supplier_profiles, :incoming_supplier_kind,
             check:
               "identity_kind IN ('ic', 'dic') AND revision > 0 AND char_length(instructions) <= 8000"
           )

    create table(:incoming_extraction_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :document_id, references(:incoming_documents, type: :binary_id), null: false
      add :generation, :integer, null: false
      add :mode, :string, null: false
      add :strategy, :string, null: false, default: "header_form"
      add :source_sha256, :string, null: false
      add :base_url, :text, null: false
      add :company_id, :text, null: false
      add :state, :string, null: false, default: "pending"
      add :active_step, :string, null: false
      add :identity_result, :map, null: false, default: %{}
      add :identity, :map, null: false, default: %{}
      add :selection, :string, null: false, default: "none"
      add :selection_reason, :text
      add :supplier_profile_id, references(:incoming_supplier_profiles, type: :binary_id)
      add :profile_revision, :integer
      add :supplier_instructions, :text, null: false, default: ""
      add :supplier_instructions_hash, :string, null: false
      add :common_instructions, :text, null: false
      add :common_instructions_hash, :string, null: false
      add :identity_instructions, :text, null: false
      add :schemas, :map, null: false
      add :identification, :map, null: false, default: %{}
      add :content, :map, null: false, default: %{}
      add :result, :map, null: false, default: %{}
      add :previous_draft, :map, null: false, default: %{}
      add :origin_run_id, references(:incoming_extraction_runs, type: :binary_id)
      add :identity_conflict, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:incoming_extraction_runs, [:document_id, :generation])
    create unique_index(:incoming_extraction_runs, [:id, :document_id])

    create constraint(:incoming_extraction_runs, :incoming_run_mode,
             check: "mode IN ('identify_and_extract', 'extract_only') AND generation > 0"
           )

    create constraint(:incoming_extraction_runs, :incoming_run_state,
             check:
               "state IN ('pending', 'running', 'completed', 'failed') AND active_step IN ('identify', 'content', 'done')"
           )

    create unique_index(:incoming_extraction_runs, [:document_id],
             where: "state IN ('pending', 'running')",
             name: :incoming_one_active_run
           )

    alter table(:incoming_documents) do
      add :active_extraction_run_id, :binary_id
    end

    execute """
            ALTER TABLE incoming_documents ADD CONSTRAINT incoming_active_run_document
            FOREIGN KEY (active_extraction_run_id, id)
            REFERENCES incoming_extraction_runs (id, document_id)
            """,
            "ALTER TABLE incoming_documents DROP CONSTRAINT incoming_active_run_document"
  end
end

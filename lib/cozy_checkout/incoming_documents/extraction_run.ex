defmodule CozyCheckout.IncomingDocuments.ExtractionRun do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "incoming_extraction_runs" do
    field :document_id, :binary_id
    field :generation, :integer
    field :mode, :string
    field :strategy, :string, default: "header_form"
    field :source_sha256, :string
    field :base_url, :string
    field :company_id, :string
    field :state, :string, default: "pending"
    field :active_step, :string
    field :identity_result, :map, default: %{}
    field :identity, :map, default: %{}
    field :selection, :string, default: "none"
    field :selection_reason, :string
    field :supplier_profile_id, :binary_id
    field :profile_revision, :integer
    field :supplier_instructions, :string, default: ""
    field :supplier_instructions_hash, :string
    field :common_instructions, :string
    field :common_instructions_hash, :string
    field :identity_instructions, :string
    field :schemas, :map
    field :identification, :map, default: %{}
    field :content, :map, default: %{}
    field :content_result, :map, default: %{}
    field :supplier_task, :map, default: %{}
    field :supplier_task_result, :map, default: %{}
    field :supplier_task_instructions, :string
    field :result, :map, default: %{}
    field :previous_draft, :map, default: %{}
    field :origin_run_id, :binary_id
    field :identity_conflict, :string
    timestamps(type: :utc_datetime)
  end
end

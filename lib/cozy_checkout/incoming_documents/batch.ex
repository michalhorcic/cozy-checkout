defmodule CozyCheckout.IncomingDocuments.Batch do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "incoming_document_batches" do
    field :name, :string
    field :agenda, :string
    field :base_url, :string
    field :company_id, :string
    field :accounting_settings, :map, default: %{}
    field :include_items, :boolean, default: false
    field :max_files, :integer, default: 50
    field :model, :string
    field :started_at, :utc_datetime
    field :extraction_finished_at, :utc_datetime
    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

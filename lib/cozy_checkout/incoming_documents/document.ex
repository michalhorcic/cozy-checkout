defmodule CozyCheckout.IncomingDocuments.Document do
  @moduledoc "Private source, template snapshot and immutable approved import for a received document."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "incoming_documents" do
    field :agenda, :string
    field :state, :string, default: "uploaded"
    field :filename, :string
    field :content_type, :string
    field :original, :binary
    field :sha256, :string
    field :template_xml, :string
    field :generated_xml, :string
    field :current_xml, :string
    field :sent_xml, :string
    field :base_url, :string
    field :company_id, :string
    field :external_id, :string
    field :dry_run, :map, default: %{}
    field :response, :map, default: %{}
    field :remote_id, :string
    field :error, :string
    field :error_stage, :string
    field :sent_at, :utc_datetime
    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

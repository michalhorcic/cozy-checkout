defmodule CozyCheckout.IncomingDocuments.SupplierProfile do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "incoming_supplier_profiles" do
    field :base_url, :string
    field :company_id, :string
    field :country_code, :string
    field :identity_kind, :string
    field :identity_value, :string
    field :name, :string
    field :ic, :string
    field :dic, :string
    field :instructions, :string, default: ""
    field :revision, :integer, default: 1
    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

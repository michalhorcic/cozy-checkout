defmodule CozyCheckout.Abra.AccommodationExport do
  @moduledoc "Persistent delivery state, target and immutable payload for an accommodation document."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "accommodation_abra_exports" do
    belongs_to :document, CozyCheckout.Billing.Document
    field :base_url, :string
    field :company_id, :string
    field :external_id, :string
    field :payload, :map
    field :remote_id, :string
    field :state, :string, default: "queued"
    field :attempts, :integer, default: 0
    field :error, :string
    field :synced_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

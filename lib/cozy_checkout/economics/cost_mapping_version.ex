defmodule CozyCheckout.Economics.CostMappingVersion do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "economics_cost_mapping_versions" do
    belongs_to :source, CozyCheckout.Economics.Source
    field :number, :integer
    field :state, :string, default: "draft"
    field :note, :string
    field :published_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

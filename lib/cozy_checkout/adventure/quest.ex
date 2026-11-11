defmodule CozyCheckout.Adventure.Quest do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "adventure_quests" do
    belongs_to :profile, CozyCheckout.Adventure.Profile
    field :code, :string
    field :version, :integer
    field :period_key, :string
    field :status, :string, default: "active"
    field :definition_snapshot, :map
    field :evidence, :map, default: %{}
    field :completed_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

defmodule CozyCheckout.Adventure.Unlock do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "adventure_unlocks" do
    belongs_to :campaign, CozyCheckout.Adventure.Campaign
    field :code, :string
    field :rules_version, :string
    field :xp, :integer
    field :status, :string, default: "unlocked"
    field :unlocked_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :evidence, :map
    field :revocation_evidence, :map
    timestamps(type: :utc_datetime)
  end
end

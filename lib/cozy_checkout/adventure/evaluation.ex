defmodule CozyCheckout.Adventure.Evaluation do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "adventure_evaluations" do
    belongs_to :campaign, CozyCheckout.Adventure.Campaign
    belongs_to :actor, CozyCheckout.Adventure.Profile
    field :snapshot, :map
    field :as_of, :utc_datetime_usec
    field :version, :integer
    field :correction_reason, :string
    field :campaign_metadata, :map
    belongs_to :previous_evaluation, __MODULE__
    timestamps(type: :utc_datetime, updated_at: false)
  end
end

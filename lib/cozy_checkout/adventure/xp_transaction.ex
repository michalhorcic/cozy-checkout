defmodule CozyCheckout.Adventure.XpTransaction do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "adventure_xp_transactions" do
    belongs_to :profile, CozyCheckout.Adventure.Profile
    belongs_to :quest, CozyCheckout.Adventure.Quest
    belongs_to :reverses, __MODULE__
    belongs_to :unlock, CozyCheckout.Adventure.Unlock
    field :recipient_type, :string, default: "profile"
    field :award_key, :string
    field :amount, :integer
    field :reason, :string
    field :attribution, :string
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def award_changeset(attrs) do
    %__MODULE__{attribution: "self_selected"}
    |> cast(attrs, [:profile_id, :quest_id, :award_key, :amount, :reason])
    |> validate_required([:profile_id, :quest_id, :award_key, :amount, :reason])
    |> validate_number(:amount, greater_than: 0)
    |> check_constraint(:amount, name: :adventure_xp_sign)
  end
end

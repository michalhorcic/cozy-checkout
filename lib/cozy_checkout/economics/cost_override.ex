defmodule CozyCheckout.Economics.CostOverride do
  use Ecto.Schema
  import Ecto.Changeset
  alias CozyCheckout.Economics.CostAssignment
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "economics_cost_overrides" do
    belongs_to :version, CozyCheckout.Economics.CostMappingVersion
    field :account, :string
    field :module, :string
    field :document_id, :string
    field :month, :date
    field :fingerprint, :string
    field :behavior, :string, default: "unclassified"
    field :extraordinary, :boolean, default: false
    field :fixed_percent, :decimal
    field :reason, :string
    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(override, attrs) do
    override
    |> cast(attrs, [
      :account,
      :module,
      :document_id,
      :month,
      :fingerprint,
      :behavior,
      :extraordinary,
      :fixed_percent,
      :reason
    ])
    |> CostAssignment.validate()
    |> validate_required([:module, :document_id, :month, :fingerprint])
    |> CostAssignment.first_month(:month)
    |> validate_format(:fingerprint, ~r/^[a-f0-9]{64}$/)
  end
end

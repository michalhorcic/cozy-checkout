defmodule CozyCheckout.Economics.CostRule do
  use Ecto.Schema
  import Ecto.Changeset
  alias CozyCheckout.Economics.CostAssignment
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "economics_cost_rules" do
    belongs_to :version, CozyCheckout.Economics.CostMappingVersion
    field :account, :string
    field :partner_id, :string
    field :description_contains, :string
    field :valid_from, :date
    field :valid_to, :date
    field :behavior, :string, default: "unclassified"
    field :extraordinary, :boolean, default: false
    field :fixed_percent, :decimal
    field :reason, :string
    field :deleted_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :account,
      :partner_id,
      :description_contains,
      :valid_from,
      :valid_to,
      :behavior,
      :extraordinary,
      :fixed_percent,
      :reason
    ])
    |> update_change(:description_contains, &String.trim/1)
    |> CostAssignment.validate()
    |> validate_required([:valid_from])
    |> CostAssignment.first_month(:valid_from)
    |> CostAssignment.first_month(:valid_to)
    |> validate_length(:description_contains, max: 500)
    |> validate_length(:partner_id, max: 200)
    |> validate_change(:valid_to, fn :valid_to, last ->
      first = get_field(cast(rule, attrs, [:valid_from]), :valid_from)

      if first && Date.compare(last, first) == :lt,
        do: [valid_to: "Konec předchází začátku."],
        else: []
    end)
  end
end

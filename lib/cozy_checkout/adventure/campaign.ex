defmodule CozyCheckout.Adventure.Campaign do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "adventure_campaigns" do
    field :name, :string
    field :starts_on, :date
    field :ends_on, :date
    field :capacity, :integer
    field :completed_goal, :integer
    field :reserved_goal, :integer
    field :occupancy_goal, :integer
    field :status, :string, default: "draft"
    field :rules_version, :string, default: "stays_v1"
    field :timezone, :string, default: "Europe/Prague"
    field :activated_at, :utc_datetime
    field :closed_at, :utc_datetime
    belongs_to :activated_by, CozyCheckout.Adventure.Profile
    belongs_to :last_evaluation, CozyCheckout.Adventure.Evaluation
    has_many :unlocks, CozyCheckout.Adventure.Unlock
    timestamps(type: :utc_datetime)
  end

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [
      :name,
      :starts_on,
      :ends_on,
      :capacity,
      :completed_goal,
      :reserved_goal,
      :occupancy_goal
    ])
    |> validate_required([
      :name,
      :starts_on,
      :ends_on,
      :capacity,
      :completed_goal,
      :reserved_goal,
      :occupancy_goal
    ])
    |> validate_length(:name, min: 3, max: 100)
    |> validate_number(:capacity, greater_than: 0, less_than_or_equal_to: 500)
    |> validate_number(:completed_goal, greater_than: 0, less_than_or_equal_to: 100_000)
    |> validate_number(:reserved_goal, greater_than: 0, less_than_or_equal_to: 1_000_000)
    |> validate_number(:occupancy_goal, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_dates()
  end

  defp validate_dates(changeset) do
    case {get_field(changeset, :starts_on), get_field(changeset, :ends_on)} do
      {%Date{} = first, %Date{} = last} ->
        if Date.diff(last, first) in 0..1095,
          do: changeset,
          else: add_error(changeset, :ends_on, "musí být po začátku, nejvýše o 3 roky")

      _ ->
        changeset
    end
  end
end

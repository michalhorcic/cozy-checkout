defmodule CozyCheckout.Adventure.TaskTemplate do
  use Ecto.Schema
  import Ecto.Changeset
  alias CozyCheckout.Adventure.Quest
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "adventure_task_templates" do
    field :title, :string
    field :description, :string, default: ""
    field :category, :string, default: "Provoz"
    field :priority, :string, default: "normal"
    field :scope, :string, default: "personal"
    belongs_to :assigned_profile, CozyCheckout.Adventure.Profile
    field :size, :string, default: "small"
    field :xp, :integer, default: 50
    field :cadence, :string, default: "daily"
    field :weekdays, {:array, :integer}, default: [1]
    field :starts_on, :date
    field :next_due_on, :date
    field :applicability, :string, default: "always"
    belongs_to :campaign, CozyCheckout.Adventure.Campaign
    field :status, :string, default: "paused"
    field :version, :integer, default: 1
    field :seed_key, :string
    belongs_to :legacy_profile, CozyCheckout.Adventure.Profile
    field :legacy_code, :string
    field :last_check, :map, default: %{}
    belongs_to :created_by, CozyCheckout.Adventure.Profile
    timestamps(type: :utc_datetime)
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [
      :title,
      :description,
      :category,
      :priority,
      :scope,
      :assigned_profile_id,
      :size,
      :xp,
      :cadence,
      :weekdays,
      :starts_on,
      :applicability,
      :campaign_id
    ])
    |> normalize_calendar_weekdays()
    |> update_change(:title, fn value ->
      if is_binary(value), do: String.trim(value), else: value
    end)
    |> validate_required([
      :title,
      :category,
      :priority,
      :scope,
      :size,
      :xp,
      :cadence,
      :weekdays,
      :starts_on,
      :applicability
    ])
    |> update_change(:weekdays, fn
      days when is_list(days) -> Enum.uniq(days)
      days -> days
    end)
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:description, max: 5000)
    |> validate_length(:weekdays, min: 1, max: 7)
    |> validate_subset(:weekdays, [1, 2, 3, 4, 5, 6, 7])
    |> validate_inclusion(:category, Quest.categories())
    |> validate_inclusion(:scope, ["personal", "shared"])
    |> validate_inclusion(:priority, ["low", "normal", "high"])
    |> validate_inclusion(:size, ["small", "medium", "large"])
    |> validate_inclusion(:cadence, ["daily", "weekly", "monthly", "semiannual", "yearly", "once"])
    |> validate_inclusion(:applicability, ["always", "campaign", "guests"])
    |> validate_number(:xp, greater_than: 0, less_than_or_equal_to: 10000)
    |> normalize_scope()
    |> foreign_key_constraint(:assigned_profile_id)
    |> foreign_key_constraint(:campaign_id)
    |> check_constraint(:scope, name: :adventure_template_rules)
  end

  defp normalize_calendar_weekdays(changeset) do
    if get_field(changeset, :cadence) in ["monthly", "semiannual", "yearly"],
      do: put_change(changeset, :weekdays, [1]),
      else: changeset
  end

  defp normalize_scope(changeset) do
    changeset =
      if get_field(changeset, :scope) == "shared",
        do: put_change(changeset, :assigned_profile_id, nil),
        else: changeset

    if get_field(changeset, :applicability) == "campaign",
      do: validate_required(changeset, [:campaign_id]),
      else: put_change(changeset, :campaign_id, nil)
  end
end

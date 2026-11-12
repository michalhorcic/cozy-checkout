defmodule CozyCheckout.Adventure.Quest do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "adventure_quests" do
    belongs_to :profile, CozyCheckout.Adventure.Profile
    belongs_to :assigned_profile, CozyCheckout.Adventure.Profile
    belongs_to :created_by, CozyCheckout.Adventure.Profile
    field :title, :string, virtual: true
    field :size, :string, virtual: true, default: "small"
    field :xp, :integer, virtual: true
    belongs_to :template, CozyCheckout.Adventure.TaskTemplate
    field :first_due_on, :date
    field :schedule_history, :map, default: %{}
    field :managed, :boolean, default: false
    field :scope, :string, default: "personal"
    field :due_on, :date
    field :priority, :string, default: "normal"
    field :category, :string, default: "Provoz"
    field :description, :string, default: ""
    field :archived_at, :utc_datetime
    field :code, :string
    field :version, :integer
    field :period_key, :string
    field :status, :string, default: "active"
    field :definition_snapshot, :map
    field :evidence, :map, default: %{}
    field :completed_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def task_changeset(quest, attrs) do
    quest
    |> cast(attrs, [
      :title,
      :size,
      :xp,
      :scope,
      :assigned_profile_id,
      :due_on,
      :priority,
      :category,
      :description
    ])
    |> update_change(:title, fn
      title when is_binary(title) -> String.trim(title)
      title -> title
    end)
    |> validate_required([:title, :size, :scope, :priority, :category])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_inclusion(:size, ["small", "medium", "large"])
    |> validate_number(:xp, greater_than: 0, less_than_or_equal_to: 10000)
    |> validate_inclusion(:scope, ["personal", "shared"])
    |> validate_inclusion(:priority, ["low", "normal", "high"])
    |> validate_inclusion(:category, categories())
    |> validate_length(:description, max: 5000)
    |> foreign_key_constraint(:assigned_profile_id)
    |> check_constraint(:scope, name: :adventure_task_scope)
  end

  def categories, do: ["Provoz", "Úklid", "Kuchyně", "Bar", "Údržba", "Administrativa"]
end

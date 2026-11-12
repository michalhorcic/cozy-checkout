defmodule CozyCheckout.Adventure.ProjectStage do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "adventure_project_stages" do
    belongs_to :project, CozyCheckout.Adventure.Project
    belongs_to :quest, CozyCheckout.Adventure.Quest
    field :position, :integer
    field :output, :string
    field :quest_snapshot, :map
    field :archived_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

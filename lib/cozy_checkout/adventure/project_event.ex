defmodule CozyCheckout.Adventure.ProjectEvent do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "adventure_project_events" do
    belongs_to :project, CozyCheckout.Adventure.Project
    belongs_to :actor, CozyCheckout.Adventure.Profile
    field :version, :integer
    field :action, :string
    field :snapshot, :map
    timestamps(type: :utc_datetime, updated_at: false)
  end
end

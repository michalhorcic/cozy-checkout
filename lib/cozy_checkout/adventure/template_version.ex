defmodule CozyCheckout.Adventure.TemplateVersion do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "adventure_template_versions" do
    belongs_to :template, CozyCheckout.Adventure.TaskTemplate
    field :version, :integer
    field :definition, :map
    belongs_to :actor, CozyCheckout.Adventure.Profile
    timestamps(type: :utc_datetime, updated_at: false)
  end
end

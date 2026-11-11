defmodule CozyCheckout.Adventure.Profile do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "adventure_profiles" do
    field :slug, :string
    field :display_name, :string
    field :active, :boolean, default: true
    timestamps(type: :utc_datetime)
  end
end

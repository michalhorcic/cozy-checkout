defmodule CozyCheckout.KitchenCosts.Mapping do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "kitchen_purchase_mappings" do
    field :merchant_key, :string
    field :source_key, :string
    field :source_name, :string
    belongs_to :ingredient, CozyCheckout.Recipes.Ingredient
    field :lock_version, :integer, default: 1
    field :archived_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:merchant_key, :source_key, :source_name, :ingredient_id])
    |> validate_required([:merchant_key, :source_key, :source_name, :ingredient_id])
    |> validate_length(:source_name, max: 255)
    |> foreign_key_constraint(:ingredient_id)
    |> unique_constraint([:merchant_key, :source_key])
  end
end

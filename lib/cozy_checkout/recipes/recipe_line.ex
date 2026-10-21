defmodule CozyCheckout.Recipes.RecipeLine do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recipe_lines" do
    belongs_to :recipe, CozyCheckout.Recipes.Recipe
    belongs_to :ingredient, CozyCheckout.Recipes.Ingredient
    field :quantity, :decimal
    field :unit, :string, default: "kg"
    field :notes, :string
    field :position, :integer, default: 0
    field :source_row, :integer
    timestamps(type: :utc_datetime)
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [:ingredient_id, :quantity, :unit, :notes, :position])
    |> validate_required([:ingredient_id, :quantity, :unit])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_inclusion(:unit, ["kg", "g", "l", "ml", "ks"])
    |> foreign_key_constraint(:ingredient_id)
  end
end

defmodule CozyCheckout.Meals.MenuVariantItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "menu_variant_items" do
    field :day_number, :integer
    field :meal_type, :string
    belongs_to :recipe, CozyCheckout.Recipes.Recipe
    has_many :recipe_supplements, CozyCheckout.Recipes.VariantSupplement
    field :menu_text, :string
    field :supplements, :string
    belongs_to :menu_variant, CozyCheckout.Meals.MenuVariant
    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:day_number, :meal_type, :menu_text, :supplements])
    |> validate_required([:day_number, :meal_type, :menu_text])
    |> validate_number(:day_number, greater_than: 0, less_than_or_equal_to: 366)
    |> validate_inclusion(:meal_type, ["breakfast", "lunch", "dinner"])
    |> validate_length(:menu_text, max: 4000)
    |> validate_length(:supplements, max: 4000)
    |> unique_constraint([:menu_variant_id, :day_number, :meal_type])
  end
end

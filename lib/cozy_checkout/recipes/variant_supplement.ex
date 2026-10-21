defmodule CozyCheckout.Recipes.VariantSupplement do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "menu_variant_supplements" do
    belongs_to :menu_variant_item, CozyCheckout.Meals.MenuVariantItem
    belongs_to :recipe, CozyCheckout.Recipes.Recipe
    field :position, :integer, default: 0
    timestamps(type: :utc_datetime)
  end
end

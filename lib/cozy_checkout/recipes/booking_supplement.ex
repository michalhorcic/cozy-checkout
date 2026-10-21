defmodule CozyCheckout.Recipes.BookingSupplement do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "booking_menu_supplements" do
    belongs_to :booking_menu_item, CozyCheckout.Meals.BookingMenuItem
    belongs_to :recipe, CozyCheckout.Recipes.Recipe
    field :position, :integer, default: 0
    timestamps(type: :utc_datetime)
  end
end

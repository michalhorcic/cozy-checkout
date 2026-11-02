defmodule CozyCheckout.Meals.BookingMenuItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "booking_menu_items" do
    belongs_to :booking_menu, CozyCheckout.Meals.BookingMenu
    field :day_number, :integer
    field :date, :date
    field :meal_type, :string
    belongs_to :recipe, CozyCheckout.Recipes.Recipe
    has_many :recipe_supplements, CozyCheckout.Recipes.BookingSupplement
    field :menu_text, :string
    field :supplements, :string
    field :note, :string
    field :recipe_links_reviewed_at, :utc_datetime
    field :supplement_recipe_ids, {:array, :binary_id}, virtual: true, default: []
    field :reviewed, :boolean, virtual: true, default: false
    field :manually_edited, :boolean, default: false
    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :menu_text,
      :supplements,
      :note,
      :recipe_id,
      :supplement_recipe_ids,
      :reviewed
    ])
    |> validate_length(:menu_text, max: 4000)
    |> validate_length(:supplements, max: 4000)
    |> validate_length(:note, max: 4000)
    |> foreign_key_constraint(:recipe_id)
    |> unique_constraint([:booking_menu_id, :date, :meal_type])
  end
end

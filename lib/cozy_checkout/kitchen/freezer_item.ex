defmodule CozyCheckout.Kitchen.FreezerItem do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "kitchen_freezer_items" do
    field :name, :string
    field :quantity, :decimal
    field :unit, :string, default: "kg"
    field :frozen_on, :date
    belongs_to :ingredient, CozyCheckout.Recipes.Ingredient
    belongs_to :recipe, CozyCheckout.Recipes.Recipe
    field :location, :string
    field :notes, :string
    field :archived_at, :utc_datetime
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :name,
      :quantity,
      :unit,
      :frozen_on,
      :ingredient_id,
      :recipe_id,
      :location,
      :notes
    ])
    |> validate_required([:name, :quantity, :unit, :frozen_on])
    |> validate_length(:name, max: 200)
    |> validate_length(:location, max: 200)
    |> validate_inclusion(:unit, ~w(kg g l ml ks porce))
    |> validate_number(:quantity, greater_than: 0)
    |> validate_link()
    |> foreign_key_constraint(:ingredient_id)
    |> foreign_key_constraint(:recipe_id)
    |> check_constraint(:quantity, name: :freezer_quantity)
    |> check_constraint(:unit, name: :freezer_unit)
    |> check_constraint(:ingredient_id, name: :freezer_link)
  end

  defp validate_link(cs) do
    if get_field(cs, :ingredient_id) && get_field(cs, :recipe_id),
      do: add_error(cs, :ingredient_id, "Vyberte pouze surovinu nebo recept"),
      else: cs
  end
end

defmodule CozyCheckout.KitchenCosts.ManualPrice do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "kitchen_manual_prices" do
    belongs_to :ingredient, CozyCheckout.Recipes.Ingredient
    field :valid_from, :date
    field :unit_price, :decimal
    field :base_unit, :string
    field :note, :string
    field :archived_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(price, attrs) do
    price
    |> cast(attrs, [:ingredient_id, :valid_from, :unit_price, :note])
    |> validate_required([:ingredient_id, :valid_from, :unit_price, :note])
    |> validate_number(:unit_price, greater_than: 0)
    |> foreign_key_constraint(:ingredient_id)
    |> unique_constraint([:ingredient_id, :valid_from])
  end
end

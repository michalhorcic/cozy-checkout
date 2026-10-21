defmodule CozyCheckout.Recipes.Ingredient do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kitchen_ingredients" do
    field :name, :string
    field :category, :string, default: "Ostatní"
    field :base_unit, :string, default: "kg"
    field :purchase_mode, :string
    field :package_size, :decimal
    field :notes, :string
    field :source_key, :string
    field :archived_at, :utc_datetime
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime)
  end

  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:name, :category, :base_unit, :purchase_mode, :package_size, :notes])
    |> validate_required([:name, :category, :base_unit])
    |> validate_inclusion(:base_unit, ["kg", "l", "ks"])
    |> validate_number(:package_size, greater_than: 0)
    |> validate_length(:name, max: 200)
    |> validate_length(:category, max: 100)
    |> unique_constraint(:name, name: :kitchen_ingredients_name_index)
  end
end

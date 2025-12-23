defmodule CozyCheckout.Meals.MealTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "meal_templates" do
    field :name, :string
    field :category, :string
    field :default_menu_text, :string
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @categories ["breakfast", "lunch", "dinner"]

  @doc false
  def changeset(meal_template, attrs) do
    meal_template
    |> cast(attrs, [:name, :category, :default_menu_text])
    |> validate_required([:name, :category])
    |> validate_inclusion(:category, @categories)
  end

  def categories, do: @categories
end

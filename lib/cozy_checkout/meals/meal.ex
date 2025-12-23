defmodule CozyCheckout.Meals.Meal do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "meals" do
    field :date, :date
    field :meal_type, :string
    field :menu_text, :string
    field :dietary_notes, :string
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @meal_types ["breakfast", "lunch", "dinner"]

  @doc false
  def changeset(meal, attrs) do
    meal
    |> cast(attrs, [:date, :meal_type, :menu_text, :dietary_notes])
    |> validate_required([:date, :meal_type])
    |> validate_inclusion(:meal_type, @meal_types)
    |> unique_constraint([:date, :meal_type])
  end

  def meal_types, do: @meal_types
end

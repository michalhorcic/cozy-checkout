defmodule CozyCheckout.Recipes.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  schema "kitchen_settings" do
    field :hot_child_factor, :decimal, default: Decimal.new("0.7")
    field :breakfast_child_factor, :decimal, default: Decimal.new("0.7")
    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:hot_child_factor, :breakfast_child_factor])
    |> validate_required([:hot_child_factor, :breakfast_child_factor])
    |> validate_number(:hot_child_factor, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:breakfast_child_factor,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1
    )
  end
end

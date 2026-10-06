defmodule CozyCheckout.Catalog.PosProductShortcut do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pos_product_shortcuts" do
    field :unit_amount, :decimal
    field :position, :integer, default: 0
    field :deleted_at, :utc_datetime

    belongs_to :product, CozyCheckout.Catalog.Product

    timestamps(type: :utc_datetime)
  end

  def changeset(shortcut, attrs) do
    shortcut
    |> cast(attrs, [:product_id, :unit_amount, :position])
    |> validate_required([:product_id, :position])
    |> validate_number(:unit_amount, greater_than: 0)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:product_id)
  end
end

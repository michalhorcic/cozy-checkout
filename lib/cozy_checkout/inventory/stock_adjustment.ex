defmodule CozyCheckout.Inventory.StockAdjustment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @adjustment_types ~w(increase decrease correction spillage breakage theft spoilage expired other)

  schema "stock_adjustments" do
    field :quantity, :integer
    field :unit_amount, :decimal
    field :adjustment_type, :string
    field :reason, :string
    field :notes, :string
    field :deleted_at, :utc_datetime

    belongs_to :product, CozyCheckout.Catalog.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(stock_adjustment, attrs) do
    stock_adjustment
    |> cast(attrs, [:product_id, :quantity, :unit_amount, :adjustment_type, :reason, :notes])
    |> validate_required([:product_id, :quantity, :adjustment_type, :reason])
    |> validate_inclusion(:adjustment_type, @adjustment_types)
    |> validate_number(:quantity, not_equal_to: 0, message: "must not be zero")
    |> validate_number(:unit_amount, greater_than: 0)
    |> foreign_key_constraint(:product_id)
  end

  def adjustment_types, do: @adjustment_types
end

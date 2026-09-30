defmodule CozyCheckout.Inventory.BarStockMovement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @movement_types ~w(opening restock sale sale_reversal count_adjustment waste)
  @waste_reasons ~w(spillage breakage theft spoilage expired other)

  schema "bar_stock_movements" do
    field :quantity, :decimal
    field :movement_type, :string
    field :notes, :string
    field :reason, :string

    belongs_to :product, CozyCheckout.Catalog.Product
    belongs_to :order_item, CozyCheckout.Sales.OrderItem

    timestamps(type: :utc_datetime)
  end

  def changeset(movement, attrs) do
    movement
    |> cast(attrs, [:product_id, :order_item_id, :quantity, :movement_type, :notes, :reason])
    |> validate_required([:product_id, :quantity, :movement_type])
    |> validate_number(:quantity, not_equal_to: 0)
    |> validate_inclusion(:movement_type, @movement_types)
    |> validate_waste_reason()
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:order_item_id)
  end

  def waste_reasons, do: @waste_reasons

  defp validate_waste_reason(changeset) do
    if get_field(changeset, :movement_type) == "waste" do
      changeset
      |> validate_required([:reason])
      |> validate_inclusion(:reason, @waste_reasons)
    else
      changeset
    end
  end
end

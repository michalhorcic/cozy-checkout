defmodule CozyCheckout.Sales.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "order_items" do
    field :quantity, :integer
    field :unit_amount, :decimal
    field :unit_price, :decimal
    field :vat_rate, :decimal
    field :subtotal, :decimal
    field :deleted_at, :utc_datetime

    belongs_to :order, CozyCheckout.Sales.Order
    belongs_to :product, CozyCheckout.Catalog.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, [
      :order_id,
      :product_id,
      :quantity,
      :unit_amount,
      :unit_price,
      :vat_rate,
      :subtotal
    ])
    |> validate_required([:order_id, :product_id, :quantity, :unit_price, :vat_rate, :subtotal])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_amount, greater_than: 0)
    |> validate_number(:unit_price, greater_than: 0)
    |> validate_number(:vat_rate, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:order_id)
    |> foreign_key_constraint(:product_id)
  end
end

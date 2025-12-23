defmodule CozyCheckout.Inventory.PurchaseOrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "purchase_order_items" do
    field :quantity, :integer
    field :unit_amount, :decimal
    field :cost_price, :decimal
    field :notes, :string
    field :deleted_at, :utc_datetime

    belongs_to :purchase_order, CozyCheckout.Inventory.PurchaseOrder
    belongs_to :product, CozyCheckout.Catalog.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(purchase_order_item, attrs) do
    purchase_order_item
    |> cast(attrs, [:product_id, :quantity, :unit_amount, :cost_price, :notes])
    |> validate_required([:product_id, :quantity, :cost_price])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:cost_price, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:purchase_order_id)
    |> foreign_key_constraint(:product_id)
  end

  @doc false
  def soft_delete_changeset(purchase_order_item) do
    change(purchase_order_item, deleted_at: DateTime.truncate(DateTime.utc_now(), :second))
  end
end

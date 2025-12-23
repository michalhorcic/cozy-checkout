defmodule CozyCheckout.Inventory.PurchaseOrder do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "purchase_orders" do
    field :order_number, :string
    field :supplier_note, :string
    field :order_date, :date
    field :notes, :string
    field :total_cost, :decimal
    field :deleted_at, :utc_datetime

    has_many :purchase_order_items, CozyCheckout.Inventory.PurchaseOrderItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(purchase_order, attrs) do
    purchase_order
    |> cast(attrs, [:order_number, :supplier_note, :order_date, :notes, :total_cost])
    |> validate_required([:order_number, :order_date])
    |> unique_constraint(:order_number)
  end

  @doc false
  def soft_delete_changeset(purchase_order) do
    change(purchase_order, deleted_at: DateTime.truncate(DateTime.utc_now(), :second))
  end
end

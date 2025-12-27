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
    require Logger
    Logger.debug("PurchaseOrderItem attrs: #{inspect(attrs)}")

    purchase_order_item
    |> cast(attrs, [:product_id, :quantity, :unit_amount, :cost_price, :notes])
    |> validate_required([:product_id, :quantity, :cost_price])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_cost_price()
    |> foreign_key_constraint(:purchase_order_id)
    |> foreign_key_constraint(:product_id)
  end

  defp validate_cost_price(changeset) do
    case get_change(changeset, :cost_price) do
      nil ->
        changeset

      cost_price when is_binary(cost_price) ->
        # Handle string input from forms
        case Decimal.parse(cost_price) do
          {decimal_value, _} ->
            if Decimal.compare(decimal_value, Decimal.new("0")) in [:eq, :gt] do
              put_change(changeset, :cost_price, decimal_value)
            else
              add_error(changeset, :cost_price, "must be greater than or equal to 0")
            end

          :error ->
            add_error(changeset, :cost_price, "is not a valid number")
        end

      %Decimal{} = decimal_value ->
        if Decimal.compare(decimal_value, Decimal.new("0")) in [:eq, :gt] do
          changeset
        else
          add_error(changeset, :cost_price, "must be greater than or equal to 0")
        end

      numeric_value when is_number(numeric_value) ->
        if numeric_value >= 0 do
          changeset
        else
          add_error(changeset, :cost_price, "must be greater than or equal to 0")
        end
    end
  end

  @doc false
  def soft_delete_changeset(purchase_order_item) do
    change(purchase_order_item, deleted_at: DateTime.truncate(DateTime.utc_now(), :second))
  end
end

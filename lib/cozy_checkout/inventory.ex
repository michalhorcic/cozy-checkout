defmodule CozyCheckout.Inventory do
  @moduledoc """
  The Inventory context - manages purchase orders and stock levels.
  """

  import Ecto.Query, warn: false
  alias CozyCheckout.Repo
  alias CozyCheckout.Inventory.{PurchaseOrder, PurchaseOrderItem}
  alias CozyCheckout.Catalog.Product

  ## Purchase Orders

  @doc """
  Returns the list of purchase orders.
  """
  def list_purchase_orders do
    PurchaseOrder
    |> where([po], is_nil(po.deleted_at))
    |> order_by([po], desc: po.order_date)
    |> preload(:purchase_order_items)
    |> Repo.all()
  end

  @doc """
  Gets a single purchase order.
  Raises `Ecto.NoResultsError` if the Purchase order does not exist.
  """
  def get_purchase_order!(id) do
    PurchaseOrder
    |> where([po], is_nil(po.deleted_at))
    |> preload([purchase_order_items: [product: :category]])
    |> Repo.get!(id)
  end

  @doc """
  Creates a purchase order.
  """
  def create_purchase_order(attrs \\ %{}) do
    %PurchaseOrder{}
    |> PurchaseOrder.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a purchase order.
  """
  def update_purchase_order(%PurchaseOrder{} = purchase_order, attrs) do
    purchase_order
    |> PurchaseOrder.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft deletes a purchase order.
  """
  def delete_purchase_order(%PurchaseOrder{} = purchase_order) do
    purchase_order
    |> PurchaseOrder.soft_delete_changeset()
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking purchase order changes.
  """
  def change_purchase_order(%PurchaseOrder{} = purchase_order, attrs \\ %{}) do
    PurchaseOrder.changeset(purchase_order, attrs)
  end

  @doc """
  Generates a unique purchase order number in format YYPOXXX.
  """
  def generate_purchase_order_number do
    today = Date.utc_today()
    year = today.year |> Integer.to_string() |> String.slice(-2..-1//1)

    # Get the highest order number for this year
    query = from po in PurchaseOrder,
      where: fragment("LEFT(?, 2) = ?", po.order_number, ^year),
      select: po.order_number,
      order_by: [desc: po.order_number],
      limit: 1

    case Repo.one(query) do
      nil ->
        "#{year}PO00001"
      last_number ->
        sequence = String.slice(last_number, 4..-1//1) |> String.to_integer()
        "#{year}PO#{String.pad_leading(Integer.to_string(sequence + 1), 5, "0")}"
    end
  end

  ## Purchase Order Items

  @doc """
  Creates a purchase order item.
  """
  def create_purchase_order_item(%PurchaseOrder{} = purchase_order, attrs) do
    %PurchaseOrderItem{}
    |> PurchaseOrderItem.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:purchase_order, purchase_order)
    |> Repo.insert()
  end

  @doc """
  Updates a purchase order item.
  """
  def update_purchase_order_item(%PurchaseOrderItem{} = item, attrs) do
    item
    |> PurchaseOrderItem.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft deletes a purchase order item.
  """
  def delete_purchase_order_item(%PurchaseOrderItem{} = item) do
    item
    |> PurchaseOrderItem.soft_delete_changeset()
    |> Repo.update()
  end

  ## Stock Calculations

  @doc """
  Get current stock level for a product with specific unit_amount.
  Returns the quantity available.

  ## Examples

      iex> get_stock_level(product_id, 500)
      #Decimal<100>

      iex> get_stock_level(product_id, nil)
      #Decimal<250>
  """
  def get_stock_level(product_id, unit_amount \\ nil) do
    purchased = get_total_purchased(product_id, unit_amount)
    sold = get_total_sold(product_id, unit_amount)

    Decimal.sub(purchased, sold)
  end

  defp get_total_purchased(product_id, nil) do
    query = from poi in PurchaseOrderItem,
      where: poi.product_id == ^product_id and is_nil(poi.deleted_at),
      select: coalesce(sum(poi.quantity), 0)

    Repo.one(query) || Decimal.new(0)
  end

  defp get_total_purchased(product_id, unit_amount) do
    query = from poi in PurchaseOrderItem,
      where: poi.product_id == ^product_id
        and poi.unit_amount == ^unit_amount
        and is_nil(poi.deleted_at),
      select: coalesce(sum(poi.quantity), 0)

    Repo.one(query) || Decimal.new(0)
  end

  defp get_total_sold(product_id, nil) do
    query = from oi in CozyCheckout.Sales.OrderItem,
      where: oi.product_id == ^product_id and is_nil(oi.deleted_at),
      select: coalesce(sum(oi.quantity), 0)

    Repo.one(query) || Decimal.new(0)
  end

  defp get_total_sold(product_id, unit_amount) do
    query = from oi in CozyCheckout.Sales.OrderItem,
      where: oi.product_id == ^product_id
        and oi.unit_amount == ^unit_amount
        and is_nil(oi.deleted_at),
      select: coalesce(sum(oi.quantity), 0)

    Repo.one(query) || Decimal.new(0)
  end

  @doc """
  Get stock overview for all products.
  Returns list of maps with product, unit_amount, and stock quantity.

  ## Examples

      iex> get_stock_overview()
      [
        %{product: %Product{}, unit_amount: #Decimal<500>, stock: #Decimal<100>},
        %{product: %Product{}, unit_amount: nil, stock: #Decimal<50>}
      ]
  """
  def get_stock_overview do
    # Get all unique product+unit_amount combinations from both tables
    purchased_items = from poi in PurchaseOrderItem,
      where: is_nil(poi.deleted_at),
      select: %{product_id: poi.product_id, unit_amount: poi.unit_amount},
      distinct: true

    sold_items = from oi in CozyCheckout.Sales.OrderItem,
      where: is_nil(oi.deleted_at),
      select: %{product_id: oi.product_id, unit_amount: oi.unit_amount},
      distinct: true

    all_combinations = Repo.all(purchased_items) ++ Repo.all(sold_items)
    all_combinations = Enum.uniq_by(all_combinations, &{&1.product_id, &1.unit_amount})

    products = CozyCheckout.Catalog.list_products()
    product_map = Map.new(products, &{&1.id, &1})

    all_combinations
    |> Enum.map(fn %{product_id: product_id, unit_amount: unit_amount} ->
      stock = get_stock_level(product_id, unit_amount)

      %{
        product: Map.get(product_map, product_id),
        unit_amount: unit_amount,
        stock: stock
      }
    end)
    |> Enum.reject(&is_nil(&1.product))
    |> Enum.sort_by(&{&1.product.name, &1.unit_amount || Decimal.new(0)})
  end
end

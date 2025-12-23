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
  Get current stock level for a product.
  For volume-based products (ml, L, cl), returns total volume in base units (milliliters).
  For piece-based products, returns quantity count.

  ## Examples

      iex> get_stock_level(product_id)  # Beer product with unit="ml"
      #Decimal<25000>  # 25 liters total

      iex> get_stock_level(product_id)  # Glasses with unit="pcs"
      #Decimal<24>  # 24 pieces
  """
  def get_stock_level(product_id) do
    product = CozyCheckout.Catalog.get_product!(product_id)

    # Check if this is a volume-based product
    volume_based? = product.unit in ["ml", "L", "cl"]

    if volume_based? do
      get_total_volume(product_id)
    else
      get_total_quantity(product_id)
    end
  end

  defp get_total_volume(product_id) do
    purchased_volume = get_total_purchased_volume(product_id)
    sold_volume = get_total_sold_volume(product_id)

    Decimal.sub(purchased_volume, sold_volume)
  end

  defp get_total_quantity(product_id) do
    purchased = get_total_purchased(product_id, nil)
    sold = get_total_sold(product_id, nil)

    Decimal.sub(purchased, sold)
  end

  # Calculate total purchased volume (quantity × unit_amount)
  defp get_total_purchased_volume(product_id) do
    query =
      from poi in PurchaseOrderItem,
        where: poi.product_id == ^product_id and is_nil(poi.deleted_at),
        select: coalesce(sum(fragment("? * COALESCE(?, 1)", poi.quantity, poi.unit_amount)), 0)

    Repo.one(query) || Decimal.new(0)
  end

  # Calculate total sold volume (quantity × unit_amount)
  defp get_total_sold_volume(product_id) do
    query =
      from oi in CozyCheckout.Sales.OrderItem,
        where: oi.product_id == ^product_id and is_nil(oi.deleted_at),
        select: coalesce(sum(fragment("? * COALESCE(?, 1)", oi.quantity, oi.unit_amount)), 0)

    Repo.one(query) || Decimal.new(0)
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
  Returns list of %{product: product, stock: qty, display_unit: unit, raw_stock: raw_value}

  ## Examples

      iex> get_stock_overview()
      [
        %{product: %Product{name: "Beer"}, stock: #Decimal<25>, display_unit: "L", raw_stock: #Decimal<25000>},
        %{product: %Product{name: "Glasses"}, stock: #Decimal<24>, display_unit: "pcs", raw_stock: #Decimal<24>}
      ]
  """
  def get_stock_overview do
    products = CozyCheckout.Catalog.list_products()

    products
    |> Enum.map(fn product ->
      stock = get_stock_level(product.id)
      volume_based? = product.unit in ["ml", "L", "cl"]

      # For volume products, show in liters if >= 1000ml
      {display_stock, display_unit} =
        if volume_based? && Decimal.compare(stock, 1000) != :lt do
          {Decimal.div(stock, 1000), "L"}
        else
          {stock, product.unit || "pcs"}
        end

      %{
        product: product,
        stock: display_stock,
        display_unit: display_unit,
        raw_stock: stock
      }
    end)
    |> Enum.reject(fn item -> Decimal.eq?(item.raw_stock, 0) end)
    |> Enum.sort_by(& &1.product.name)
  end
end

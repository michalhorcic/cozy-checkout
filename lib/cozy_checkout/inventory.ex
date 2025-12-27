defmodule CozyCheckout.Inventory do
  @moduledoc """
  The Inventory context - manages purchase orders and stock levels.
  """

  import Ecto.Query, warn: false
  alias CozyCheckout.Repo
  alias CozyCheckout.Inventory.{PurchaseOrder, PurchaseOrderItem, StockAdjustment}
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
  Gets a single purchase order item.
  """
  def get_purchase_order_item(id), do: Repo.get(PurchaseOrderItem, id)

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

  ## Stock Adjustments

  @doc """
  Returns the list of stock adjustments.
  """
  def list_stock_adjustments do
    StockAdjustment
    |> where([sa], is_nil(sa.deleted_at))
    |> order_by([sa], desc: sa.inserted_at)
    |> preload([product: :category])
    |> Repo.all()
  end

  @doc """
  Gets a single stock adjustment.
  """
  def get_stock_adjustment!(id) do
    StockAdjustment
    |> where([sa], is_nil(sa.deleted_at))
    |> preload([product: :category])
    |> Repo.get!(id)
  end

  @doc """
  Creates a stock adjustment.
  """
  def create_stock_adjustment(attrs \\ %{}) do
    %StockAdjustment{}
    |> StockAdjustment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a stock adjustment.
  """
  def update_stock_adjustment(%StockAdjustment{} = adjustment, attrs) do
    adjustment
    |> StockAdjustment.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a stock adjustment (soft delete).
  """
  def delete_stock_adjustment(%StockAdjustment{} = adjustment) do
    adjustment
    |> Ecto.Changeset.change(deleted_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking stock adjustment changes.
  """
  def change_stock_adjustment(%StockAdjustment{} = adjustment, attrs \\ %{}) do
    StockAdjustment.changeset(adjustment, attrs)
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
    adjustment_volume = get_total_adjustment_volume(product_id)

    purchased_volume
    |> Decimal.sub(sold_volume)
    |> Decimal.add(adjustment_volume)
  end

  defp get_total_quantity(product_id) do
    purchased = get_total_purchased(product_id, nil)
    sold = get_total_sold(product_id, nil)
    adjustment = get_total_adjustment_quantity(product_id)

    purchased
    |> Decimal.sub(sold)
    |> Decimal.add(adjustment)
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

  # Get total adjustment volume for volume-based products
  defp get_total_adjustment_volume(product_id) do
    query = from sa in StockAdjustment,
      where: sa.product_id == ^product_id and is_nil(sa.deleted_at),
      select: coalesce(sum(fragment("? * COALESCE(?, 1)", sa.quantity, sa.unit_amount)), 0)

    Repo.one(query) || Decimal.new(0)
  end

  # Get total adjustment quantity for piece-based products
  defp get_total_adjustment_quantity(product_id) do
    query = from sa in StockAdjustment,
      where: sa.product_id == ^product_id and is_nil(sa.deleted_at),
      select: coalesce(sum(sa.quantity), 0)

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

  ## Reporting Functions

  @doc """
  Get total inventory valuation using latest purchase prices.
  """
  def get_inventory_valuation do
    products = CozyCheckout.Catalog.list_products()

    products
    |> Enum.map(fn product ->
      stock = get_stock_level(product.id)
      latest_cost = get_latest_purchase_cost(product.id)

      value = Decimal.mult(stock, latest_cost || Decimal.new(0))

      %{
        product: product,
        stock: stock,
        unit_cost: latest_cost,
        total_value: value
      }
    end)
    |> Enum.reject(fn item -> Decimal.eq?(item.stock, 0) end)
  end

  @doc """
  Get profit analysis for products comparing purchase cost vs actual sales.
  """
  def get_profit_analysis(filters \\ %{}) do
    products = CozyCheckout.Catalog.list_products()

    products
    |> Enum.map(fn product ->
      stock = get_stock_level(product.id)
      avg_purchase_cost = get_average_purchase_cost(product.id, filters)
      avg_sale_price = get_average_sale_price(product.id, filters)
      total_sold = get_total_sold_quantity(product.id, filters)

      profit_per_unit =
        if avg_purchase_cost && avg_sale_price do
          Decimal.sub(avg_sale_price, avg_purchase_cost)
        else
          Decimal.new(0)
        end

      profit_margin_percent =
        if avg_sale_price && Decimal.compare(avg_sale_price, 0) == :gt do
          profit_per_unit
          |> Decimal.div(avg_sale_price)
          |> Decimal.mult(100)
        else
          Decimal.new(0)
        end

      total_profit = Decimal.mult(profit_per_unit, total_sold || Decimal.new(0))

      %{
        product: product,
        stock: stock,
        avg_purchase_cost: avg_purchase_cost,
        avg_sale_price: avg_sale_price,
        profit_per_unit: profit_per_unit,
        profit_margin_percent: profit_margin_percent,
        total_sold: total_sold,
        total_profit: total_profit
      }
    end)
    |> Enum.reject(fn item ->
      is_nil(item.avg_purchase_cost) && is_nil(item.avg_sale_price)
    end)
    |> Enum.sort_by(& &1.total_profit, {:desc, Decimal})
  end

  @doc """
  Get stock movement history with all transactions.
  """
  def get_stock_movements(filters \\ %{}) do
    purchases = get_purchase_movements(filters)
    sales = get_sale_movements(filters)
    adjustments = get_adjustment_movements(filters)

    (purchases ++ sales ++ adjustments)
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end

  defp get_latest_purchase_cost(product_id) do
    query = from poi in PurchaseOrderItem,
      join: po in PurchaseOrder,
      on: poi.purchase_order_id == po.id,
      where: poi.product_id == ^product_id
        and is_nil(poi.deleted_at)
        and is_nil(po.deleted_at),
      order_by: [desc: po.order_date],
      limit: 1,
      select: fragment("? / COALESCE(?, 1)", poi.cost_price, poi.unit_amount)

    Repo.one(query)
  end

  defp get_average_purchase_cost(product_id, filters) do
    query = from poi in PurchaseOrderItem,
      join: po in PurchaseOrder,
      on: poi.purchase_order_id == po.id,
      as: :purchase_order,
      where: poi.product_id == ^product_id
        and is_nil(poi.deleted_at)
        and is_nil(po.deleted_at)

    query = apply_date_filter(query, filters, :purchase_order)

    query = from [poi, po] in query,
      select: avg(fragment("? / COALESCE(?, 1)", poi.cost_price, poi.unit_amount))

    Repo.one(query)
  end

  defp get_average_sale_price(product_id, filters) do
    query = from oi in CozyCheckout.Sales.OrderItem,
      join: o in CozyCheckout.Sales.Order,
      on: oi.order_id == o.id,
      as: :order,
      where: oi.product_id == ^product_id
        and is_nil(oi.deleted_at)
        and is_nil(o.deleted_at)
        and o.status != "cancelled"

    query = apply_date_filter(query, filters, :order)

    query = from [oi, o] in query,
      select: avg(oi.unit_price)

    Repo.one(query)
  end

  defp get_total_sold_quantity(product_id, filters) do
    query = from oi in CozyCheckout.Sales.OrderItem,
      join: o in CozyCheckout.Sales.Order,
      on: oi.order_id == o.id,
      as: :order,
      where: oi.product_id == ^product_id
        and is_nil(oi.deleted_at)
        and is_nil(o.deleted_at)
        and o.status != "cancelled"

    query = apply_date_filter(query, filters, :order)

    query = from [oi, o] in query,
      select: coalesce(sum(oi.quantity), 0)

    Repo.one(query) || Decimal.new(0)
  end

  defp get_purchase_movements(filters) do
    query = from poi in PurchaseOrderItem,
      join: po in PurchaseOrder,
      on: poi.purchase_order_id == po.id,
      as: :purchase_order,
      join: p in CozyCheckout.Catalog.Product,
      on: poi.product_id == p.id,
      as: :product,
      join: c in CozyCheckout.Catalog.Category,
      on: p.category_id == c.id,
      where: is_nil(poi.deleted_at) and is_nil(po.deleted_at),
      select: %{
        type: "purchase",
        date: po.order_date,
        product_id: p.id,
        product_name: p.name,
        category_name: c.name,
        quantity: poi.quantity,
        unit_amount: poi.unit_amount,
        unit: p.unit,
        price: poi.cost_price,
        reference: po.order_number,
        notes: poi.notes
      }

    query = apply_date_filter(query, filters, :purchase_order)
    query = apply_product_filter(query, filters)
    query = apply_type_filter(query, filters, "purchase")

    Repo.all(query)
  end

  defp get_sale_movements(filters) do
    query = from oi in CozyCheckout.Sales.OrderItem,
      join: o in CozyCheckout.Sales.Order,
      on: oi.order_id == o.id,
      as: :order,
      join: p in CozyCheckout.Catalog.Product,
      on: oi.product_id == p.id,
      as: :product,
      join: c in CozyCheckout.Catalog.Category,
      on: p.category_id == c.id,
      where: is_nil(oi.deleted_at)
        and is_nil(o.deleted_at)
        and o.status != "cancelled",
      select: %{
        type: "sale",
        date: fragment("DATE(?)", o.inserted_at),
        product_id: p.id,
        product_name: p.name,
        category_name: c.name,
        quantity: fragment("-?", oi.quantity),
        unit_amount: oi.unit_amount,
        unit: p.unit,
        price: oi.unit_price,
        reference: o.order_number,
        notes: type(^nil, :string)
      }

    query = apply_date_filter(query, filters, :order)
    query = apply_product_filter(query, filters)
    query = apply_type_filter(query, filters, "sale")

    Repo.all(query)
  end

  defp get_adjustment_movements(filters) do
    query = from sa in StockAdjustment,
      join: p in CozyCheckout.Catalog.Product,
      on: sa.product_id == p.id,
      as: :product,
      join: c in CozyCheckout.Catalog.Category,
      on: p.category_id == c.id,
      as: :adjustment,
      where: is_nil(sa.deleted_at),
      select: %{
        type: fragment("CONCAT('adjustment-', ?)", sa.adjustment_type),
        date: fragment("DATE(?)", sa.inserted_at),
        product_id: p.id,
        product_name: p.name,
        category_name: c.name,
        quantity: sa.quantity,
        unit_amount: sa.unit_amount,
        unit: p.unit,
        price: type(^nil, :decimal),
        reference: sa.reason,
        notes: sa.notes
      }

    query = apply_date_filter(query, filters, :adjustment)
    query = apply_product_filter(query, filters)
    query = apply_type_filter(query, filters, "adjustment")

    Repo.all(query)
  end

  defp apply_date_filter(query, %{start_date: start_date, end_date: end_date}, table_alias)
       when not is_nil(start_date) and not is_nil(end_date) do
    case table_alias do
      :purchase_order ->
        from [poi, po] in query,
        where: as(:purchase_order).order_date >= ^start_date and as(:purchase_order).order_date <= ^end_date
      :order ->
        from [oi, o] in query,
        where: fragment("DATE(?)", as(:order).inserted_at) >= ^start_date and fragment("DATE(?)", as(:order).inserted_at) <= ^end_date
      :adjustment ->
        from sa in query,
        where: fragment("DATE(?)", sa.inserted_at) >= ^start_date and fragment("DATE(?)", sa.inserted_at) <= ^end_date
    end
  end
  defp apply_date_filter(query, _filters, _table_alias), do: query

  defp apply_product_filter(query, %{product_id: product_id}) when not is_nil(product_id) do
    from q in query, where: as(:product).id == ^product_id
  end
  defp apply_product_filter(query, _filters), do: query

  defp apply_type_filter(query, %{transaction_type: type}, expected_type) when not is_nil(type) do
    if String.starts_with?(type, expected_type), do: query, else: from(_ in query, where: false)
  end
  defp apply_type_filter(query, _filters, _expected_type), do: query
end

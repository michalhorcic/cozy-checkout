defmodule CozyCheckout.Inventory do
  @moduledoc """
  The Inventory context - manages purchase orders and stock levels.
  """

  import Ecto.Query, warn: false
  alias CozyCheckout.Repo

  alias CozyCheckout.Inventory.{
    BarStockMovement,
    PurchaseOrder,
    PurchaseOrderItem,
    StockAdjustment
  }

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
    |> preload(purchase_order_items: [product: :category])
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
    query =
      from po in PurchaseOrder,
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
    |> preload(product: :category)
    |> Repo.all()
  end

  @doc """
  Gets a single stock adjustment.
  """
  def get_stock_adjustment!(id) do
    StockAdjustment
    |> where([sa], is_nil(sa.deleted_at))
    |> preload(product: :category)
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

  ## Bar Stock

  def list_bar_stock_products do
    Product
    |> where([p], is_nil(p.deleted_at) and p.track_bar_stock == true)
    |> preload(:category)
    |> order_by([p], asc: p.name)
    |> Repo.all()
    |> Enum.map(fn product ->
      raw_stock = get_bar_stock_level(product.id)
      volume_based? = product.unit in ["ml", "L", "cl"]
      stock = if volume_based?, do: Decimal.div(raw_stock, 1000), else: raw_stock
      display_unit = if volume_based?, do: "L", else: product.unit || "pcs"
      threshold = product.bar_stock_threshold || Decimal.new("0")

      status =
        cond do
          Decimal.compare(stock, 0) != :gt ->
            :out_of_stock

          Decimal.compare(threshold, 0) == :gt and Decimal.compare(stock, threshold) != :gt ->
            :low_stock

          true ->
            :in_stock
        end

      %{
        product: product,
        raw_stock: raw_stock,
        stock: stock,
        display_unit: display_unit,
        threshold: threshold,
        status: status
      }
    end)
  end

  def list_bar_stock_candidates do
    Product
    |> where([p], is_nil(p.deleted_at) and p.active == true and p.track_bar_stock == false)
    |> preload(:category)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Returns per-product totals of net sold vs. lost quantity for all bar-tracked
  products, so staff can see which products lose the most relative to sales.
  Loss only counts negative count adjustments and recorded waste, not overages.
  Accepts optional `:start_date` / `:end_date` (`Date`) to scope to a period.
  """
  def get_bar_stock_loss_summary(filters \\ %{}) do
    Product
    |> where([p], is_nil(p.deleted_at) and p.track_bar_stock == true)
    |> preload(:category)
    |> order_by([p], asc: p.name)
    |> Repo.all()
    |> Enum.map(fn product ->
      sold = get_bar_stock_net_sold(product.id, filters)
      loss = get_bar_stock_loss_quantity(product.id, filters)
      volume_based? = product.unit in ["ml", "L", "cl"]
      display_unit = if volume_based?, do: "L", else: product.unit || "pcs"
      display_sold = if volume_based?, do: Decimal.div(sold, 1000), else: sold
      display_loss = if volume_based?, do: Decimal.div(loss, 1000), else: loss
      denominator = Decimal.add(sold, loss)

      loss_rate =
        if Decimal.compare(denominator, 0) == :gt do
          loss |> Decimal.div(denominator) |> Decimal.mult(100)
        else
          Decimal.new("0")
        end

      %{
        product: product,
        sold: display_sold,
        loss: display_loss,
        display_unit: display_unit,
        loss_rate: loss_rate
      }
    end)
    |> Enum.sort_by(& &1.loss_rate, {:desc, Decimal})
  end

  def add_product_to_bar(product_id, attrs) do
    with {:ok, initial_quantity} <- parse_stock_decimal(Map.get(attrs, "initial_quantity")),
         {:ok, threshold} <- parse_stock_decimal(Map.get(attrs, "threshold")),
         :ok <- validate_non_negative(initial_quantity),
         :ok <- validate_non_negative(threshold) do
      Repo.transaction(fn ->
        product = Repo.get!(Product, product_id)

        if product.track_bar_stock do
          Repo.rollback(:already_tracked)
        end

        if not valid_product_quantity?(product, initial_quantity) or
             not valid_product_quantity?(product, threshold) do
          Repo.rollback(:invalid_quantity)
        end

        product =
          product
          |> Product.changeset(%{track_bar_stock: true, bar_stock_threshold: threshold})
          |> Repo.update!()

        opening_stock = to_base_stock(product, initial_quantity)

        if Decimal.compare(opening_stock, 0) == :gt do
          insert_bar_movement!(%{
            product_id: product.id,
            quantity: opening_stock,
            movement_type: "opening",
            notes: "Počáteční zásoba baru"
          })
        end

        product
      end)
    end
  end

  def restock_bar_stock(product_id, quantity) do
    with {:ok, quantity} <- parse_stock_decimal(quantity),
         :ok <- validate_positive(quantity),
         %Product{} = product <- get_tracked_bar_product(product_id),
         :ok <- validate_product_quantity(product, quantity) do
      quantity = to_base_stock(product, quantity)

      Repo.insert(
        BarStockMovement.changeset(%BarStockMovement{}, %{
          product_id: product.id,
          quantity: quantity,
          movement_type: "restock",
          notes: "Doplnění baru"
        })
      )
    else
      nil -> {:error, :not_tracked}
      error -> error
    end
  end

  def count_bar_stock(product_id, counted_quantity) do
    with {:ok, counted_quantity} <- parse_stock_decimal(counted_quantity),
         :ok <- validate_non_negative(counted_quantity),
         %Product{} = product <- get_tracked_bar_product(product_id),
         :ok <- validate_product_quantity(product, counted_quantity) do
      counted_stock = to_base_stock(product, counted_quantity)
      current_stock = get_bar_stock_level(product.id)
      difference = Decimal.sub(counted_stock, current_stock)

      if Decimal.compare(difference, 0) == :eq do
        {:ok, difference}
      else
        display_difference =
          if product.unit in ["ml", "L", "cl"],
            do: Decimal.div(difference, 1000),
            else: difference

        notes =
          "Inventura: napočítáno #{Decimal.to_string(counted_quantity)} #{if product.unit in ["ml", "L", "cl"], do: "L", else: product.unit || "pcs"}; rozdíl #{Decimal.to_string(display_difference)}"

        case Repo.insert(
               BarStockMovement.changeset(%BarStockMovement{}, %{
                 product_id: product.id,
                 quantity: difference,
                 movement_type: "count_adjustment",
                 notes: notes
               })
             ) do
          {:ok, _movement} -> {:ok, difference}
          error -> error
        end
      end
    else
      nil -> {:error, :not_tracked}
      error -> error
    end
  end

  @doc """
  Records a bar stock loss (spillage, breakage, theft, spoilage, expired, other)
  entered directly by staff during operation, separate from periodic counts.
  """
  def record_bar_stock_waste(product_id, quantity, reason) do
    with {:ok, quantity} <- parse_stock_decimal(quantity),
         :ok <- validate_positive(quantity),
         %Product{} = product <- get_tracked_bar_product(product_id),
         :ok <- validate_product_quantity(product, quantity) do
      base_quantity = to_base_stock(product, quantity)

      Repo.insert(
        BarStockMovement.changeset(%BarStockMovement{}, %{
          product_id: product.id,
          quantity: Decimal.negate(base_quantity),
          movement_type: "waste",
          reason: reason,
          notes: "Loss recorded during service"
        })
      )
    else
      nil -> {:error, :not_tracked}
      error -> error
    end
  end

  def bar_stock_waste_reasons, do: BarStockMovement.waste_reasons()

  @doc """
  Stops tracking a product in the bar. Movement history is kept for records/analytics.
  """
  def untrack_bar_stock_product(product_id) do
    case get_tracked_bar_product(product_id) do
      nil ->
        {:error, :not_tracked}

      %Product{} = product ->
        product
        |> Product.changeset(%{track_bar_stock: false})
        |> Repo.update()
    end
  end

  def update_bar_stock_threshold(product_id, threshold) do
    with {:ok, threshold} <- parse_stock_decimal(threshold),
         :ok <- validate_non_negative(threshold),
         %Product{} = product <- get_tracked_bar_product(product_id),
         :ok <- validate_product_quantity(product, threshold) do
      product
      |> Product.changeset(%{bar_stock_threshold: threshold})
      |> Repo.update()
    else
      nil -> {:error, :not_tracked}
      error -> error
    end
  end

  def get_bar_stock_level(product_id) do
    Repo.one(
      from m in BarStockMovement,
        where: m.product_id == ^product_id,
        select: coalesce(sum(m.quantity), 0)
    ) || Decimal.new("0")
  end

  def list_recent_bar_stock_movements(limit \\ 50) do
    BarStockMovement
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> preload([:product, order_item: :order])
    |> Repo.all()
  end

  def record_bar_stock_sale(%CozyCheckout.Sales.OrderItem{} = item) do
    product = Repo.get!(Product, item.product_id)

    if product.track_bar_stock do
      insert_bar_movement!(%{
        product_id: product.id,
        order_item_id: item.id,
        quantity: Decimal.negate(order_item_stock_quantity(item, product)),
        movement_type: "sale",
        notes: "Prodej na účtu"
      })
    end

    :ok
  end

  def sync_bar_stock_order_item(old_item, new_item) do
    old_product = Repo.get!(Product, old_item.product_id)
    new_product = Repo.get!(Product, new_item.product_id)
    has_movements? = bar_stock_movements_exist?(old_item.id)

    if old_item.product_id == new_item.product_id do
      if has_movements? or new_product.track_bar_stock do
        old_quantity =
          if has_movements?,
            do: order_item_stock_quantity(old_item, old_product),
            else: Decimal.new("0")

        new_quantity = order_item_stock_quantity(new_item, new_product)
        difference = Decimal.sub(old_quantity, new_quantity)

        if Decimal.compare(difference, 0) != :eq do
          movement_type =
            if Decimal.compare(difference, 0) == :gt, do: "sale_reversal", else: "sale"

          insert_bar_movement!(%{
            product_id: new_product.id,
            order_item_id: new_item.id,
            quantity: difference,
            movement_type: movement_type,
            notes: "Úprava položky účtu"
          })
        end
      end
    else
      if has_movements? do
        insert_bar_movement!(%{
          product_id: old_product.id,
          order_item_id: old_item.id,
          quantity: order_item_stock_quantity(old_item, old_product),
          movement_type: "sale_reversal",
          notes: "Změna produktu na účtu"
        })
      end

      if new_product.track_bar_stock do
        insert_bar_movement!(%{
          product_id: new_product.id,
          order_item_id: new_item.id,
          quantity: Decimal.negate(order_item_stock_quantity(new_item, new_product)),
          movement_type: "sale",
          notes: "Prodej na účtu"
        })
      end
    end

    :ok
  end

  def reverse_bar_stock_sale(%CozyCheckout.Sales.OrderItem{} = item) do
    if is_nil(item.deleted_at) and bar_stock_movements_exist?(item.id) do
      product = Repo.get!(Product, item.product_id)

      insert_bar_movement!(%{
        product_id: product.id,
        order_item_id: item.id,
        quantity: order_item_stock_quantity(item, product),
        movement_type: "sale_reversal",
        notes: "Odstranění položky z účtu"
      })
    end

    :ok
  end

  defp get_tracked_bar_product(product_id) do
    Repo.one(
      from p in Product,
        where: p.id == ^product_id and p.track_bar_stock == true and is_nil(p.deleted_at)
    )
  end

  # Net units removed via sales: sale movements are negative, reversals positive.
  defp get_bar_stock_net_sold(product_id, filters) do
    sum =
      from(m in BarStockMovement,
        where: m.product_id == ^product_id and m.movement_type in ["sale", "sale_reversal"]
      )
      |> apply_movement_date_filter(filters)
      |> select([m], coalesce(sum(m.quantity), 0))
      |> Repo.one()
      |> Kernel.||(Decimal.new("0"))

    negated = Decimal.negate(sum)
    if Decimal.compare(negated, 0) == :lt, do: Decimal.new("0"), else: negated
  end

  # Only negative differences count as loss; positive overages are ignored.
  defp get_bar_stock_loss_quantity(product_id, filters) do
    sum =
      from(m in BarStockMovement,
        where:
          m.product_id == ^product_id and m.movement_type in ["count_adjustment", "waste"] and
            m.quantity < 0
      )
      |> apply_movement_date_filter(filters)
      |> select([m], coalesce(sum(m.quantity), 0))
      |> Repo.one()
      |> Kernel.||(Decimal.new("0"))

    Decimal.abs(sum)
  end

  defp apply_movement_date_filter(query, filters) do
    query
    |> filter_movements_from(Map.get(filters, :start_date))
    |> filter_movements_until(Map.get(filters, :end_date))
  end

  defp filter_movements_from(query, nil), do: query

  defp filter_movements_from(query, %Date{} = date) do
    starts_at = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    where(query, [m], m.inserted_at >= ^starts_at)
  end

  defp filter_movements_until(query, nil), do: query

  defp filter_movements_until(query, %Date{} = date) do
    ends_at = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    where(query, [m], m.inserted_at <= ^ends_at)
  end

  defp insert_bar_movement!(attrs) do
    %BarStockMovement{}
    |> BarStockMovement.changeset(attrs)
    |> Repo.insert!()
  end

  defp bar_stock_movements_exist?(order_item_id) do
    Repo.exists?(from m in BarStockMovement, where: m.order_item_id == ^order_item_id)
  end

  defp order_item_stock_quantity(item, product) do
    quantity = Decimal.new(item.quantity)

    if product.unit in ["ml", "L", "cl"] do
      Decimal.mult(quantity, item.unit_amount || Decimal.new("1"))
    else
      quantity
    end
  end

  defp to_base_stock(product, quantity) do
    if product.unit in ["ml", "L", "cl"], do: Decimal.mult(quantity, 1000), else: quantity
  end

  defp parse_stock_decimal(%Decimal{} = value), do: {:ok, value}
  defp parse_stock_decimal(value) when is_integer(value), do: {:ok, Decimal.new(value)}

  defp parse_stock_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> {:ok, decimal}
      _ -> {:error, :invalid_quantity}
    end
  end

  defp parse_stock_decimal(_value), do: {:error, :invalid_quantity}

  defp validate_non_negative(value) do
    if Decimal.compare(value, 0) == :lt, do: {:error, :invalid_quantity}, else: :ok
  end

  defp validate_positive(value) do
    if Decimal.compare(value, 0) != :gt, do: {:error, :invalid_quantity}, else: :ok
  end

  defp validate_product_quantity(%Product{unit: unit}, _quantity) when unit in ["ml", "L", "cl"],
    do: :ok

  defp validate_product_quantity(product, quantity) do
    if valid_product_quantity?(product, quantity), do: :ok, else: {:error, :invalid_quantity}
  end

  defp valid_product_quantity?(%Product{unit: unit}, _quantity) when unit in ["ml", "L", "cl"],
    do: true

  defp valid_product_quantity?(_product, quantity) do
    Decimal.equal?(quantity, Decimal.round(quantity, 0))
  end

  @doc """
  Creates a single purchase order with multiple items for a batch shopping trip.
  """
  def batch_restock(attrs) do
    Repo.transaction(fn ->
      order_number = generate_purchase_order_number()

      {:ok, po} =
        create_purchase_order(%{
          order_number: order_number,
          order_date: Date.utc_today(),
          supplier_note: attrs[:supplier]
        })

      Enum.each(attrs.items, fn item ->
        item_attrs =
          %{
            product_id: item.product_id,
            quantity: item.quantity,
            cost_price: "0"
          }
          |> maybe_put_unit_amount(item[:unit_amount])

        case create_purchase_order_item(po, item_attrs) do
          {:ok, _} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

      po
    end)
  end

  @doc """
  Creates a purchase order with a single item for quick restocking from the UI.
  Silently generates the order number and uses today as the order date.
  """
  def quick_restock(product_id, attrs) do
    Repo.transaction(fn ->
      order_number = generate_purchase_order_number()

      {:ok, po} =
        create_purchase_order(%{
          order_number: order_number,
          order_date: Date.utc_today()
        })

      item_attrs =
        %{
          product_id: product_id,
          quantity: attrs.quantity,
          cost_price: attrs[:cost_price] || "0"
        }
        |> maybe_put_unit_amount(attrs[:unit_amount])

      case create_purchase_order_item(po, item_attrs) do
        {:ok, item} -> item
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp maybe_put_unit_amount(attrs, v) when v in [nil, ""], do: attrs
  defp maybe_put_unit_amount(attrs, unit_amount), do: Map.put(attrs, :unit_amount, unit_amount)

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
    query =
      from poi in PurchaseOrderItem,
        where: poi.product_id == ^product_id and is_nil(poi.deleted_at),
        select: coalesce(sum(poi.quantity), 0)

    Repo.one(query) || Decimal.new(0)
  end

  defp get_total_sold(product_id, nil) do
    query =
      from oi in CozyCheckout.Sales.OrderItem,
        where: oi.product_id == ^product_id and is_nil(oi.deleted_at),
        select: coalesce(sum(oi.quantity), 0)

    Repo.one(query) || Decimal.new(0)
  end

  # Get total adjustment volume for volume-based products
  defp get_total_adjustment_volume(product_id) do
    query =
      from sa in StockAdjustment,
        where: sa.product_id == ^product_id and is_nil(sa.deleted_at),
        select: coalesce(sum(fragment("? * COALESCE(?, 1)", sa.quantity, sa.unit_amount)), 0)

    Repo.one(query) || Decimal.new(0)
  end

  # Get total adjustment quantity for piece-based products
  defp get_total_adjustment_quantity(product_id) do
    query =
      from sa in StockAdjustment,
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
    products = CozyCheckout.Catalog.list_trackable_products()

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
    query =
      from poi in PurchaseOrderItem,
        join: po in PurchaseOrder,
        on: poi.purchase_order_id == po.id,
        where:
          poi.product_id == ^product_id and
            is_nil(poi.deleted_at) and
            is_nil(po.deleted_at),
        order_by: [desc: po.order_date],
        limit: 1,
        select: fragment("? / COALESCE(?, 1)", poi.cost_price, poi.unit_amount)

    Repo.one(query)
  end

  defp get_average_purchase_cost(product_id, filters) do
    query =
      from poi in PurchaseOrderItem,
        join: po in PurchaseOrder,
        on: poi.purchase_order_id == po.id,
        as: :purchase_order,
        where:
          poi.product_id == ^product_id and
            is_nil(poi.deleted_at) and
            is_nil(po.deleted_at)

    query = apply_date_filter(query, filters, :purchase_order)

    query =
      from [poi, po] in query,
        select: avg(fragment("? / COALESCE(?, 1)", poi.cost_price, poi.unit_amount))

    Repo.one(query)
  end

  defp get_average_sale_price(product_id, filters) do
    query =
      from oi in CozyCheckout.Sales.OrderItem,
        join: o in CozyCheckout.Sales.Order,
        on: oi.order_id == o.id,
        as: :order,
        where:
          oi.product_id == ^product_id and
            is_nil(oi.deleted_at) and
            is_nil(o.deleted_at) and
            o.status != "cancelled"

    query = apply_date_filter(query, filters, :order)

    query =
      from [oi, o] in query,
        select: avg(oi.unit_price)

    Repo.one(query)
  end

  defp get_total_sold_quantity(product_id, filters) do
    query =
      from oi in CozyCheckout.Sales.OrderItem,
        join: o in CozyCheckout.Sales.Order,
        on: oi.order_id == o.id,
        as: :order,
        where:
          oi.product_id == ^product_id and
            is_nil(oi.deleted_at) and
            is_nil(o.deleted_at) and
            o.status != "cancelled"

    query = apply_date_filter(query, filters, :order)

    query =
      from [oi, o] in query,
        select: coalesce(sum(oi.quantity), 0)

    Repo.one(query) || Decimal.new(0)
  end

  defp get_purchase_movements(filters) do
    query =
      from poi in PurchaseOrderItem,
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
    query =
      from oi in CozyCheckout.Sales.OrderItem,
        join: o in CozyCheckout.Sales.Order,
        on: oi.order_id == o.id,
        as: :order,
        join: p in CozyCheckout.Catalog.Product,
        on: oi.product_id == p.id,
        as: :product,
        join: c in CozyCheckout.Catalog.Category,
        on: p.category_id == c.id,
        where:
          is_nil(oi.deleted_at) and
            is_nil(o.deleted_at) and
            o.status != "cancelled",
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
    query =
      from sa in StockAdjustment,
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
          where:
            as(:purchase_order).order_date >= ^start_date and
              as(:purchase_order).order_date <= ^end_date

      :order ->
        from [oi, o] in query,
          where:
            fragment("DATE(?)", as(:order).inserted_at) >= ^start_date and
              fragment("DATE(?)", as(:order).inserted_at) <= ^end_date

      :adjustment ->
        from sa in query,
          where:
            fragment("DATE(?)", sa.inserted_at) >= ^start_date and
              fragment("DATE(?)", sa.inserted_at) <= ^end_date
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

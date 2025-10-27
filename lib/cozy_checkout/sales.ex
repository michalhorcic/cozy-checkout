defmodule CozyCheckout.Sales do
  @moduledoc """
  The Sales context.
  """

  import Ecto.Query, warn: false
  alias CozyCheckout.Repo

  alias CozyCheckout.Sales.{Order, OrderItem, Payment}
  alias CozyCheckout.Catalog
  alias CozyCheckout.Bookings

  ## Orders

  @doc """
  Returns the list of active bookings with their open order counts.
  """
  def list_active_bookings_with_orders do
    bookings = Bookings.list_active_bookings()

    Enum.map(bookings, fn booking ->
      open_orders_count =
        Order
        |> where([o], o.booking_id == ^booking.id)
        |> where([o], is_nil(o.deleted_at))
        |> where([o], o.status in ["open", "partially_paid"])
        |> Repo.aggregate(:count, :id)

      Map.put(booking, :open_orders_count, open_orders_count)
    end)
  end

  @doc """
  Gets or creates an open order for a booking.
  Returns {:needs_guest_selection, guests} if booking has multiple guests and no orders exist.
  Returns {:multiple, orders} if multiple open orders exist (requires manual order selection).
  Returns {:ok, order} if a single order exists or was created.
  """
  def get_or_create_booking_order(booking_id) do
    open_orders =
      Order
      |> where([o], o.booking_id == ^booking_id)
      |> where([o], is_nil(o.deleted_at))
      |> where([o], o.status in ["open", "partially_paid"])
      |> preload([:guest, booking: :guest, order_items: :product, payments: []])
      |> order_by([o], desc: o.inserted_at)
      |> Repo.all()
      |> Enum.map(fn order ->
        order_items = Enum.reject(order.order_items, & &1.deleted_at)
        %{order | order_items: order_items}
      end)

    case open_orders do
      [] ->
        # Check if booking has multiple guests
        booking_guests = Bookings.list_booking_guests(booking_id)

        case booking_guests do
          [_single_guest] ->
            # Only one guest - auto-create order
            guest_id = hd(booking_guests).guest_id

            {:ok, order} =
              create_order(%{
                "booking_id" => booking_id,
                "guest_id" => guest_id,
                "status" => "open"
              })

            {:ok, get_order!(order.id)}

          multiple_guests when length(multiple_guests) > 1 ->
            # Multiple guests - need selection
            {:needs_guest_selection, multiple_guests}
        end

      [order] ->
        # Check if booking has multiple guests
        booking_guests = Bookings.list_booking_guests(order.booking_id)

        if length(booking_guests) > 1 do
          # Multiple guests but only 1 order - still allow creating more orders
          {:multiple, [order]}
        else
          # Single guest, single order
          {:ok, order}
        end

      orders when length(orders) > 1 ->
        {:multiple, orders}
    end
  end

  @doc """
  Creates an order for a specific guest in a booking.
  """
  def create_booking_order_for_guest(booking_id, guest_id) do
    {:ok, order} =
      create_order(%{
        "booking_id" => booking_id,
        "guest_id" => guest_id,
        "status" => "open"
      })

    {:ok, get_order!(order.id)}
  end

  @doc """
  Returns the list of orders.
  """
  def list_orders do
    orders =
      Order
      |> where([o], is_nil(o.deleted_at))
      |> preload([:guest, booking: :guest, order_items: [], payments: []])
      |> order_by([o], desc: o.inserted_at)
      |> Repo.all()

    # Filter out deleted order items from each order
    Enum.map(orders, fn order ->
      order_items = Enum.reject(order.order_items, & &1.deleted_at)
      %{order | order_items: order_items}
    end)
  end

  @doc """
  Returns paginated, filtered, and sorted orders with Flop.
  """
  def list_orders_with_flop(params \\ %{}) do
    # Extract and handle date and guest_name filters separately
    {date_filters, params_without_dates} = extract_date_filters(params)
    {guest_name_filter, other_params} = extract_guest_name_filter(params_without_dates)

    query =
      Order
      |> where([o], is_nil(o.deleted_at))
      |> apply_date_filters(date_filters)
      |> apply_guest_name_filter(guest_name_filter)
      |> preload([:guest, booking: :guest, order_items: [], payments: []])

    Flop.validate_and_run(query, other_params, for: Order)
  end

  defp extract_date_filters(params) do
    filters = params["filters"] || %{}

    {date_filters, other_filters} =
      filters
      |> Enum.split_with(fn {_idx, filter} ->
        filter["field"] == "inserted_at"
      end)

    date_filters_map =
      Enum.reduce(date_filters, %{}, fn {_idx, filter}, acc ->
        case {filter["op"], filter["value"]} do
          {">=", value} when value != nil and value != "" ->
            Map.put(acc, :from, value)

          {"<=", value} when value != nil and value != "" ->
            Map.put(acc, :to, value)

          _ ->
            acc
        end
      end)

    other_params = Map.put(params, "filters", Map.new(other_filters))

    {date_filters_map, other_params}
  end

  defp extract_guest_name_filter(params) do
    filters = params["filters"] || %{}

    {guest_name_filters, other_filters} =
      filters
      |> Enum.split_with(fn {_idx, filter} ->
        filter["field"] == "guest_name"
      end)

    guest_name =
      case guest_name_filters do
        [{_idx, filter}] when is_map(filter) ->
          case filter["value"] do
            value when value != nil and value != "" -> value
            _ -> nil
          end

        _ ->
          nil
      end

    other_params = Map.put(params, "filters", Map.new(other_filters))

    {guest_name, other_params}
  end

  defp apply_date_filters(query, date_filters) when date_filters == %{}, do: query

  defp apply_date_filters(query, date_filters) do
    query
    |> apply_date_from_filter(Map.get(date_filters, :from))
    |> apply_date_to_filter(Map.get(date_filters, :to))
  end

  defp apply_date_from_filter(query, nil), do: query

  defp apply_date_from_filter(query, date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        datetime = DateTime.new!(date, ~T[00:00:00])
        where(query, [o], o.inserted_at >= ^datetime)

      _ ->
        query
    end
  end

  defp apply_date_to_filter(query, nil), do: query

  defp apply_date_to_filter(query, date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        datetime = DateTime.new!(date, ~T[23:59:59])
        where(query, [o], o.inserted_at <= ^datetime)

      _ ->
        query
    end
  end

  defp apply_guest_name_filter(query, nil), do: query

  defp apply_guest_name_filter(query, guest_name) do
    pattern = "%#{guest_name}%"

    query
    |> join(:left, [o], b in assoc(o, :booking))
    |> join(:left, [o, b], g in assoc(b, :guest))
    |> where([o, b, g], ilike(g.name, ^pattern))
  end

  @doc """
  Gets a single order.
  """
  def get_order!(id) do
    order =
      Order
      |> where([o], is_nil(o.deleted_at))
      |> preload([:guest, booking: :guest, order_items: :product, payments: []])
      |> Repo.get!(id)

    # Filter out deleted order items
    order_items = Enum.reject(order.order_items, & &1.deleted_at)
    %{order | order_items: order_items}
  end

  @doc """
  Creates an order.
  """
  def create_order(attrs \\ %{}) do
    attrs = Map.put_new(attrs, "order_number", generate_order_number())

    %Order{}
    |> Order.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a standalone order without a guest or booking.
  """
  def create_standalone_order(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put_new("order_number", generate_order_number())
      |> Map.put_new("status", "open")

    %Order{}
    |> Order.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets the display name for an order (guest name or order name).
  """
  def get_order_display_name(%Order{} = order) do
    cond do
      order.guest && order.guest.name -> order.guest.name
      order.name && order.name != "" -> order.name
      true -> "Unknown"
    end
  end

  @doc """
  Updates an order.
  """
  def update_order(%Order{} = order, attrs) do
    order
    |> Order.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an order (soft delete).
  """
  def delete_order(%Order{} = order) do
    order
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking order changes.
  """
  def change_order(%Order{} = order, attrs \\ %{}) do
    Order.changeset(order, attrs)
  end

  @doc """
  Generates a unique order number.
  """
  def generate_order_number do
    date = Date.utc_today()
    date_str = Calendar.strftime(date, "%Y%m%d")
    random = :rand.uniform(9999) |> Integer.to_string() |> String.pad_leading(4, "0")
    "ORD-#{date_str}-#{random}"
  end

  ## Order Items

  @doc """
  Returns the most popular products based on order frequency.
  """
  def get_popular_products(limit \\ 20) do
    # Get product IDs with their order counts
    product_ids_with_counts =
      OrderItem
      |> where([oi], is_nil(oi.deleted_at))
      |> group_by([oi], oi.product_id)
      |> select([oi], {oi.product_id, count(oi.id)})
      |> order_by([oi], desc: count(oi.id))
      |> limit(^limit)
      |> Repo.all()
      |> Enum.map(fn {product_id, _count} -> product_id end)

    # Fetch the actual products maintaining the order
    products = Catalog.list_products()

    product_ids_with_counts
    |> Enum.map(fn product_id ->
      Enum.find(products, fn p -> p.id == product_id end)
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Creates an order item with price from current pricelist.
  """
  def create_order_item(attrs \\ %{}) do
    product_id = Map.get(attrs, "product_id") || Map.get(attrs, :product_id)

    attrs =
      if product_id do
        quantity =
          case Map.get(attrs, "quantity") do
            q when is_binary(q) -> String.to_integer(q)
            q when is_integer(q) -> q
            _ -> 1
          end

        unit_amount =
          case Map.get(attrs, "unit_amount") do
            nil -> nil
            "" -> nil
            ua when is_binary(ua) -> Decimal.new(ua)
            ua -> Decimal.new(to_string(ua))
          end

        # Get price for the specific unit amount if available
        price_result =
          if unit_amount do
            Catalog.get_price_for_product(product_id, unit_amount)
          else
            pricelist = Catalog.get_active_pricelist_for_product(product_id)

            if pricelist && pricelist.price do
              {:ok, pricelist.price, pricelist.vat_rate, pricelist}
            else
              {:error, :no_active_pricelist}
            end
          end

        case price_result do
          {:ok, unit_price, vat_rate, _pricelist} ->
            subtotal = Decimal.mult(unit_price, quantity)

            attrs
            |> Map.put("unit_price", unit_price)
            |> Map.put("vat_rate", vat_rate)
            |> Map.put("subtotal", subtotal)
            |> Map.put("unit_amount", unit_amount)

          {:error, _reason} ->
            # No price found - attrs remain unchanged and validation will fail
            attrs
        end
      else
        attrs
      end

    %OrderItem{}
    |> OrderItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes an order item (soft delete).
  """
  def delete_order_item(%OrderItem{} = order_item) do
    order_item
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Recalculates order total based on items and discount.
  """
  def recalculate_order_total(%Order{} = order) do
    order = Repo.preload(order, :order_items, force: true)

    items_total =
      order.order_items
      |> Enum.filter(&is_nil(&1.deleted_at))
      |> Enum.reduce(Decimal.new("0"), fn item, acc ->
        Decimal.add(acc, item.subtotal)
      end)

    discount = order.discount_amount || Decimal.new("0")
    total = Decimal.sub(items_total, discount)
    total = if Decimal.lt?(total, 0), do: Decimal.new("0"), else: total

    order
    |> Ecto.Changeset.change(total_amount: total)
    |> Repo.update()
  end

  ## Payments

  @doc """
  Returns the list of payments for an order.
  """
  def list_payments_for_order(order_id) do
    Payment
    |> where([p], p.order_id == ^order_id)
    |> where([p], is_nil(p.deleted_at))
    |> order_by([p], desc: p.payment_date)
    |> Repo.all()
  end

  @doc """
  Generates a unique invoice number for a payment.
  Format: PAY-YYYYMMDD-NNNN
  """
  def generate_invoice_number do
    date_part = Date.utc_today() |> Calendar.strftime("%Y%m%d")

    # Get the count of payments created today
    count =
      Payment
      |> where([p], fragment("DATE(?)", p.inserted_at) == ^Date.utc_today())
      |> Repo.aggregate(:count, :id)

    sequence = String.pad_leading("#{count + 1}", 4, "0")
    "PAY-#{date_part}-#{sequence}"
  end

  @doc """
  Creates a payment and updates order status.
  """
  def create_payment(attrs \\ %{}) do
    # Generate invoice number if not provided
    attrs = Map.put_new(attrs, "invoice_number", generate_invoice_number())

    case Repo.transaction(fn ->
           with {:ok, payment} <- do_create_payment(attrs),
                {:ok, _order} <- update_order_payment_status(payment.order_id) do
             payment
           else
             {:error, changeset} -> Repo.rollback(changeset)
           end
         end) do
      {:ok, payment} -> {:ok, payment}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp do_create_payment(attrs) do
    %Payment{}
    |> Payment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a payment (soft delete) and updates order status.
  """
  def delete_payment(%Payment{} = payment) do
    case Repo.transaction(fn ->
           with {:ok, payment} <- do_delete_payment(payment),
                {:ok, _order} <- update_order_payment_status(payment.order_id) do
             payment
           else
             {:error, changeset} -> Repo.rollback(changeset)
           end
         end) do
      {:ok, payment} -> {:ok, payment}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp do_delete_payment(payment) do
    payment
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Updates order status based on payments.
  """
  def update_order_payment_status(order_id) do
    order = get_order!(order_id)
    payments = list_payments_for_order(order_id)

    total_paid =
      payments
      |> Enum.reduce(Decimal.new("0"), fn payment, acc ->
        Decimal.add(acc, payment.amount)
      end)

    status =
      cond do
        Decimal.eq?(total_paid, 0) -> "open"
        Decimal.gte?(total_paid, order.total_amount) -> "paid"
        true -> "partially_paid"
      end

    order
    |> Ecto.Changeset.change(status: status)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking payment changes.
  """
  def change_payment(%Payment{} = payment, attrs \\ %{}) do
    Payment.changeset(payment, attrs)
  end

  ## POHODA Export

  @doc """
  Lists orders with preloaded associations for POHODA export.
  """
  def list_orders_for_pohoda_export(order_ids) do
    from(o in Order,
      where: o.id in ^order_ids,
      where: o.status == "paid",
      where: is_nil(o.deleted_at),
      preload: [:guest, booking: :guest, order_items: :product, payments: []]
    )
    |> Repo.all()
    |> Enum.map(fn order ->
      order_items = Enum.reject(order.order_items, & &1.deleted_at)
      %{order | order_items: order_items}
    end)
  end

  @doc """
  Lists paid orders within a date range for POHODA export.
  """
  def list_paid_orders_by_date(date_from, date_to) do
    from(o in Order,
      where: o.status == "paid",
      where: is_nil(o.deleted_at),
      where: o.inserted_at >= ^date_from,
      where: o.inserted_at <= ^date_to,
      preload: [:guest, booking: :guest, order_items: :product, payments: []],
      order_by: [asc: o.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn order ->
      order_items = Enum.reject(order.order_items, & &1.deleted_at)
      %{order | order_items: order_items}
    end)
  end
end

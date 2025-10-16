defmodule CozyCheckout.Sales do
  @moduledoc """
  The Sales context.
  """

  import Ecto.Query, warn: false
  alias CozyCheckout.Repo

  alias CozyCheckout.Sales.{Order, OrderItem, Payment}
  alias CozyCheckout.Catalog

  ## Orders

  @doc """
  Returns the list of orders.
  """
  def list_orders do
    Order
    |> where([o], is_nil(o.deleted_at))
    |> preload([:guest, :order_items, :payments])
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single order.
  """
  def get_order!(id) do
    Order
    |> where([o], is_nil(o.deleted_at))
    |> preload([:guest, order_items: :product, payments: []])
    |> Repo.get!(id)
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
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
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
  Creates an order item with price from current pricelist.
  """
  def create_order_item(attrs \\ %{}) do
    product_id = Map.get(attrs, "product_id") || Map.get(attrs, :product_id)

    attrs =
      if product_id do
        pricelist = Catalog.get_active_pricelist_for_product(product_id)

        if pricelist do
          quantity = String.to_integer(Map.get(attrs, "quantity", "1"))
          unit_price = pricelist.price
          vat_rate = pricelist.vat_rate
          subtotal = Decimal.mult(unit_price, quantity)

          attrs
          |> Map.put("unit_price", unit_price)
          |> Map.put("vat_rate", vat_rate)
          |> Map.put("subtotal", subtotal)
        else
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
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
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
  Creates a payment and updates order status.
  """
  def create_payment(attrs \\ %{}) do
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
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
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
end

defmodule CozyCheckoutWeb.OrderItemGrouper do
  @moduledoc """
  Helper module for grouping order items by product and unit amount for display purposes.
  """

  alias Decimal

  @doc """
  Groups order items by product_id and unit_amount for cleaner display.
  Returns a list of grouped items with aggregated quantities and totals.

  Each group contains:
  - product: the product struct
  - unit_amount: the unit amount (if applicable)
  - unit: the unit string (e.g., "ml", "L")
  - price_per_unit: the price per single unit
  - total_quantity: sum of all quantities in the group
  - total_price: total price for all items in the group
  - item_ids: list of all order_item ids in this group
  - items: list of actual order_item structs
  - grouped?: boolean indicating if multiple items were grouped
  """
  def group_order_items(order_items) do
    order_items
    |> Enum.reject(&(!is_nil(&1.deleted_at)))
    |> Enum.group_by(fn item ->
      {item.product_id, item.unit_amount}
    end)
    |> Enum.map(fn {{_product_id, _unit_amount}, items} ->
      first = hd(items)
      total_quantity = Enum.reduce(items, Decimal.new("0"), fn item, acc ->
        Decimal.add(acc, item.quantity)
      end)

      total_price = Enum.reduce(items, Decimal.new("0"), fn item, acc ->
        Decimal.add(acc, item.subtotal)
      end)

      %{
        product: first.product,
        unit_amount: first.unit_amount,
        unit: first.product.unit,
        price_per_unit: first.unit_price,
        vat_rate: first.vat_rate,
        total_quantity: total_quantity,
        total_price: total_price,
        item_ids: Enum.map(items, & &1.id),
        items: items,
        grouped?: length(items) > 1,
        expanded?: false
      }
    end)
    |> Enum.sort_by(& &1.product.name)
  end

  @doc """
  Expands a specific group to show individual items.
  """
  def expand_group(grouped_items, product_id, unit_amount) do
    Enum.map(grouped_items, fn group ->
      if group.product.id == product_id && group.unit_amount == unit_amount do
        Map.put(group, :expanded?, true)
      else
        group
      end
    end)
  end

  @doc """
  Collapses a specific group to hide individual items.
  """
  def collapse_group(grouped_items, product_id, unit_amount) do
    Enum.map(grouped_items, fn group ->
      if group.product.id == product_id && group.unit_amount == unit_amount do
        Map.put(group, :expanded?, false)
      else
        group
      end
    end)
  end
end

defmodule CozyCheckoutWeb.OrderLive.Receipt do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales
  alias CozyCheckoutWeb.OrderItemGrouper

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    order = Sales.get_order!(id)
    payments = Sales.list_payments_for_order(id)

    grouped_items = OrderItemGrouper.group_order_items(order.order_items)

    vat_breakdown = calculate_vat_breakdown(order)

    total_paid =
      Enum.reduce(payments, Decimal.new("0"), fn payment, acc ->
        Decimal.add(acc, payment.amount)
      end)

    socket =
      socket
      |> assign(:page_title, "Receipt - Order #{order.order_number}")
      |> assign(:order, order)
      |> assign(:payments, payments)
      |> assign(:grouped_items, grouped_items)
      |> assign(:vat_breakdown, vat_breakdown)
      |> assign(:total_paid, total_paid)
      |> assign(:generated_at, DateTime.utc_now())

    {:ok, socket}
  end

  @impl true
  def handle_event("print", _params, socket) do
    {:noreply, push_event(socket, "print", %{})}
  end

  defp calculate_vat_breakdown(order) do
    groups =
      order.order_items
      |> Enum.reject(& &1.deleted_at)
      |> Enum.group_by(& &1.vat_rate, & &1.subtotal)
      |> Enum.map(fn {vat_rate, subtotals} ->
        total_incl_vat = Enum.reduce(subtotals, Decimal.new("0"), &Decimal.add/2)
        %{vat_rate: vat_rate, total_incl_vat: total_incl_vat}
      end)
      |> Enum.sort_by(& &1.vat_rate)

    items_total =
      Enum.reduce(groups, Decimal.new("0"), fn group, total ->
        Decimal.add(total, group.total_incl_vat)
      end)

    discount = order.discount_amount || Decimal.new("0")
    discount = if Decimal.gt?(discount, items_total), do: items_total, else: discount
    tips = order.tips_amount || Decimal.new("0")
    last_index = length(groups) - 1

    {breakdown, _allocated_discount} =
      groups
      |> Enum.with_index()
      |> Enum.map_reduce(Decimal.new("0"), fn {group, index}, allocated_discount ->
        discount_share =
          if index == last_index do
            Decimal.sub(discount, allocated_discount)
          else
            discount
            |> Decimal.mult(group.total_incl_vat)
            |> Decimal.div(items_total)
            |> Decimal.round(2)
          end

        adjusted_total = Decimal.sub(group.total_incl_vat, discount_share)
        divisor = Decimal.add(Decimal.new("1"), Decimal.div(group.vat_rate, 100))

        base =
          adjusted_total
          |> Decimal.div(divisor)
          |> Decimal.round(2)

        base =
          if Decimal.equal?(group.vat_rate, 0), do: Decimal.add(base, tips), else: base

        vat_amount =
          if Decimal.equal?(group.vat_rate, 0) do
            Decimal.new("0")
          else
            adjusted_total
            |> Decimal.sub(Decimal.div(adjusted_total, divisor) |> Decimal.round(2))
            |> Decimal.round(2)
          end

        result = %{
          vat_rate: group.vat_rate,
          base: base,
          vat_amount: vat_amount,
          total_incl_vat:
            Decimal.add(
              adjusted_total,
              if(Decimal.equal?(group.vat_rate, 0), do: tips, else: Decimal.new("0"))
            )
        }

        {result, Decimal.add(allocated_discount, discount_share)}
      end)

    has_zero_rate = Enum.any?(breakdown, &Decimal.equal?(&1.vat_rate, 0))

    if Decimal.gt?(tips, 0) and not has_zero_rate do
      [
        %{
          vat_rate: Decimal.new("0"),
          base: tips,
          vat_amount: Decimal.new("0"),
          total_incl_vat: tips
        }
        | breakdown
      ]
    else
      breakdown
    end
  end
end

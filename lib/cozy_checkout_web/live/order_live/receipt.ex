defmodule CozyCheckoutWeb.OrderLive.Receipt do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    order = Sales.get_order!(id)
    payments = Sales.list_payments_for_order(id)

    # Group items by VAT rate for VAT breakdown
    vat_breakdown = calculate_vat_breakdown(order.order_items)

    total_paid =
      Enum.reduce(payments, Decimal.new("0"), fn payment, acc ->
        Decimal.add(acc, payment.amount)
      end)

    socket =
      socket
      |> assign(:page_title, "Receipt - Order #{order.order_number}")
      |> assign(:order, order)
      |> assign(:payments, payments)
      |> assign(:vat_breakdown, vat_breakdown)
      |> assign(:total_paid, total_paid)
      |> assign(:generated_at, DateTime.utc_now())

    {:ok, socket}
  end

  @impl true
  def handle_event("print", _params, socket) do
    {:noreply, push_event(socket, "print", %{})}
  end

  defp calculate_vat_breakdown(order_items) do
    active_items = Enum.filter(order_items, &is_nil(&1.deleted_at))

    active_items
    |> Enum.group_by(& &1.vat_rate)
    |> Enum.map(fn {vat_rate, items} ->
      # Calculate total for this VAT rate group
      total_incl_vat =
        Enum.reduce(items, Decimal.new("0"), fn item, acc ->
          Decimal.add(acc, item.subtotal)
        end)

      # Calculate base (without VAT) and VAT amount
      # Formula: base = total / (1 + vat_rate/100)
      # vat_amount = total - base
      divisor = Decimal.add(Decimal.new("1"), Decimal.div(vat_rate, 100))
      base = Decimal.div(total_incl_vat, divisor)
      vat_amount = Decimal.sub(total_incl_vat, base)

      %{
        vat_rate: vat_rate,
        base: Decimal.round(base, 2),
        vat_amount: Decimal.round(vat_amount, 2),
        total_incl_vat: total_incl_vat
      }
    end)
    |> Enum.sort_by(& &1.vat_rate)
  end
end

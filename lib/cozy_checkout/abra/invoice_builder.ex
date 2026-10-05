defmodule CozyCheckout.Abra.InvoiceBuilder do
  @moduledoc """
  Builds ABRA Flexi JSON payloads for faktura-vydana from Order structs.
  """

  @doc """
  Builds the winstrom JSON map for a given order.
  Cash payments include hotovostni-uhrada. QR/bank payments do not (accountant reconciles).
  """
  def build(order) do
    cfg = Application.fetch_env!(:cozy_checkout, :abra)
    date = format_date(order.inserted_at)
    items = order |> active_items() |> group_items() |> apply_adjustments(order)
    validate_order_total!(items, order)
    validate_order_payments!(order)

    invoice =
      %{
        "typDokl" => "code:BAR",
        "rada" => "code:#{cfg[:document_series_code]}",
        "typUcOp" => "code:TRŽBA ZBOŽÍ",
        "id" => "ext:cozy-checkout:order:#{order.id}",
        "varSym" => sanitize_sym_var(order.order_number),
        "datVyst" => date,
        "duzpPuv" => date,
        "duzpUcto" => date,
        "datUcto" => date,
        "popis" => "Účtenka bar #{order.order_number}",
        "nazFirmy" => get_customer_name(order),
        "polozkyFaktury" => Enum.map(items, &build_item/1)
      }

    invoice = maybe_add_cash_payment(invoice, order, cfg, date)
    invoice = maybe_add_bank_account(invoice, order, cfg)

    %{"winstrom" => %{"faktura-vydana" => [invoice]}}
  end

  defp maybe_add_cash_payment(invoice, order, cfg, date) do
    # Only cash payments get immediate settlement; QR/bank is reconciled via bank statement
    cash_total =
      order.payments
      |> Enum.filter(&(is_nil(&1.deleted_at) and &1.payment_method == "cash"))
      |> Enum.reduce(Decimal.new("0"), fn p, acc -> Decimal.add(acc, p.amount) end)

    if Decimal.gt?(cash_total, Decimal.new("0")) do
      # JSON key keeps the hyphen to match the XML element name.
      Map.put(invoice, "hotovostni-uhrada", %{
        "typDokl" => "code:STANDARD",
        "pokladna" => "code:#{cfg[:cash_register_code]}",
        "castka" => Decimal.to_string(Decimal.round(cash_total, 2)),
        "datumUhrady" => date
      })
    else
      invoice
    end
  end

  defp maybe_add_bank_account(invoice, order, cfg) do
    has_qr =
      Enum.any?(order.payments, &(is_nil(&1.deleted_at) and &1.payment_method == "qr_code"))

    if has_qr and cfg[:bank_account_code] not in [nil, ""] do
      Map.put(invoice, "bankovniUcet", "code:#{cfg[:bank_account_code]}")
    else
      invoice
    end
  end

  defp build_item(item) do
    product_name =
      Map.get(item, :name) || if(item.product, do: item.product.name, else: "Produkt")

    name = if item.unit_amount, do: "#{product_name} (#{item.unit_amount})", else: product_name

    %{
      "nazev" => name,
      "mnozMj" => Decimal.to_string(item.quantity),
      "cenaMj" => Decimal.to_string(Decimal.round(item.unit_price, 2)),
      "typCenyDphK" => "typCeny.sDph",
      "typSzbDphK" => vat_type_key(item.vat_rate)
    }
  end

  defp group_items(order_items) do
    order_items
    |> Enum.group_by(fn i -> {i.product_id, i.unit_amount, i.unit_price, i.vat_rate} end)
    |> Enum.map(fn {{_pid, _ua, _up, _vat_rate}, items} ->
      first = hd(items)
      total_qty = Enum.reduce(items, Decimal.new("0"), &Decimal.add(&2, Decimal.new(&1.quantity)))

      %{
        product: first.product,
        unit_amount: first.unit_amount,
        unit_price: first.unit_price,
        vat_rate: first.vat_rate,
        quantity: total_qty
      }
    end)
  end

  defp apply_adjustments(items, order) do
    items_total =
      Enum.reduce(items, Decimal.new("0"), fn item, total ->
        Decimal.add(total, Decimal.mult(item.unit_price, item.quantity))
      end)

    discount = order.discount_amount || Decimal.new("0")
    discount = if Decimal.gt?(discount, items_total), do: items_total, else: discount
    discount_lines = build_discount_lines(items, discount, items_total)
    tips_line = build_tips_line(order.tips_amount)

    items ++ discount_lines ++ tips_line
  end

  defp validate_order_total!(items, order) do
    exported_total =
      Enum.reduce(items, Decimal.new("0"), fn item, total ->
        Decimal.add(total, Decimal.mult(item.unit_price, item.quantity))
      end)

    unless Decimal.equal?(exported_total, order.total_amount) do
      raise ArgumentError,
            "order #{order.order_number} total does not match its exported invoice lines"
    end
  end

  defp validate_order_payments!(%{status: "paid"} = order) do
    active_payments =
      Enum.reject(order.payments, & &1.deleted_at)

    paid_total =
      Enum.reduce(active_payments, Decimal.new("0"), fn payment, total ->
        Decimal.add(total, payment.amount)
      end)

    unless Decimal.equal?(paid_total, order.total_amount) do
      raise ArgumentError,
            "paid order #{order.order_number} does not have active payments matching its total"
    end
  end

  defp validate_order_payments!(_order), do: :ok

  defp build_discount_lines(items, discount, items_total) do
    if Decimal.gt?(discount, 0) and Decimal.gt?(items_total, 0) do
      groups =
        items
        |> Enum.group_by(& &1.vat_rate)
        |> Enum.map(fn {vat_rate, rate_items} ->
          gross =
            Enum.reduce(rate_items, Decimal.new("0"), fn item, total ->
              Decimal.add(total, Decimal.mult(item.unit_price, item.quantity))
            end)

          {vat_rate, gross}
        end)
        |> Enum.sort_by(fn {vat_rate, _gross} -> vat_rate end)

      last_index = length(groups) - 1

      {discounts, _allocated} =
        groups
        |> Enum.with_index()
        |> Enum.map_reduce(Decimal.new("0"), fn {{vat_rate, gross}, index}, allocated ->
          amount =
            if index == last_index do
              Decimal.sub(discount, allocated)
            else
              discount
              |> Decimal.mult(gross)
              |> Decimal.div(items_total)
              |> Decimal.round(2)
            end

          {{vat_rate, amount}, Decimal.add(allocated, amount)}
        end)

      Enum.map(discounts, fn {vat_rate, amount} ->
        %{
          name: "Sleva",
          unit_amount: nil,
          unit_price: Decimal.negate(amount),
          vat_rate: vat_rate,
          quantity: Decimal.new("1"),
          product: nil
        }
      end)
    else
      []
    end
  end

  defp build_tips_line(tips) do
    if tips && Decimal.gt?(tips, Decimal.new("0")) do
      [
        %{
          name: "Spropitné",
          unit_amount: nil,
          unit_price: tips,
          vat_rate: Decimal.new("0"),
          quantity: Decimal.new("1"),
          product: nil
        }
      ]
    else
      []
    end
  end

  defp active_items(order), do: Enum.filter(order.order_items, &is_nil(&1.deleted_at))

  defp get_customer_name(order) do
    cond do
      order.guest -> order.guest.name
      order.name -> order.name
      true -> "Zákazník"
    end
  end

  # typSzbDphK is the correct field for VAT rate on invoice items; szbDph only accepts a plain number.
  defp vat_type_key(rate) when is_struct(rate, Decimal) do
    cond do
      Decimal.equal?(rate, Decimal.new(21)) -> "typSzbDph.dphZakl"
      Decimal.equal?(rate, Decimal.new(12)) -> "typSzbDph.dphSniz"
      true -> "typSzbDph.dphOsv"
    end
  end

  defp format_date(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.to_iso8601()

  # Strips non-digits and keeps the last 10 characters (matches QR variable symbol logic).
  defp sanitize_sym_var(value) when is_binary(value) do
    value |> String.replace(~r/\D/, "") |> String.slice(-10..-1//1)
  end
end

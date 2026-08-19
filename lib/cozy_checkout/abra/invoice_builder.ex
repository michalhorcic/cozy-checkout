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
    items = order |> active_items() |> group_items()

    invoice =
      %{
        "typDokl" => "code:BAR",
        "rada" => "code:#{cfg[:document_series_code]}",
        "typUcOp" => "code:TRŽBA ZBOŽÍ",
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
    has_qr = Enum.any?(order.payments, &(is_nil(&1.deleted_at) and &1.payment_method == "qr_code"))

    if has_qr and cfg[:bank_account_code] not in [nil, ""] do
      Map.put(invoice, "bankovniUcet", "code:#{cfg[:bank_account_code]}")
    else
      invoice
    end
  end

  defp build_item(item) do
    product_name = if item.product, do: item.product.name, else: "Produkt"
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
    |> Enum.group_by(fn i -> {i.product_id, i.unit_amount, i.unit_price} end)
    |> Enum.map(fn {{_pid, _ua, _up}, items} ->
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

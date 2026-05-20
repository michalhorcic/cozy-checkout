defmodule CozyCheckout.Pohoda do
  @moduledoc """
  Handles export of paid orders to POHODA accounting software XML format.
  """

  alias CozyCheckout.Sales

  @doc """
  Exports paid orders to POHODA XML format.
  Returns XML string that can be saved to file or sent to POHODA mServer.
  """
  def export_orders(order_ids) when is_list(order_ids) do
    orders = Sales.list_orders_for_pohoda_export(order_ids)
    generate_xml(orders)
  end

  def export_orders(date_from, date_to) do
    orders = Sales.list_paid_orders_by_date(date_from, date_to)
    generate_xml(orders)
  end

  defp generate_xml(orders) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <dat:dataPack version="2.0" id="Export" ico="#{ico()}" application="CozyCheckout" note="Export paid orders" xmlns:dat="http://www.stormware.cz/schema/version_2/data.xsd">
    #{Enum.map_join(orders, "\n", &order_to_xml/1)}
    </dat:dataPack>
    """
  end

  defp order_to_xml(order) do
    date = format_date(order.inserted_at)
    {account_no, bank_code} = parse_bank_account()
    {payment_ids, payment_type} = payment_type_to_pohoda(order.payments)
    items = order |> active_order_items() |> group_items()
    {price_none, price_low, price_low_vat, price_low_sum, price_high, price_high_vat, price_high_sum} = calculate_vat_totals(items)

    """
      <dat:dataPackItem id="#{order.order_number}" version="2.0">
        <inv:invoice version="2.0" xmlns:inv="http://www.stormware.cz/schema/version_2/invoice.xsd">
          <inv:invoiceHeader xmlns:typ="http://www.stormware.cz/schema/version_2/type.xsd">
            <inv:invoiceType>receivable</inv:invoiceType>
            <inv:number>
              <typ:numberRequested>#{order.order_number}</typ:numberRequested>
            </inv:number>
            <inv:symVar>#{order.order_number}</inv:symVar>
            <inv:date>#{date}</inv:date>
            <inv:dateTax>#{date}</inv:dateTax>
            <inv:dateAccounting>#{date}</inv:dateAccounting>
            <inv:dateDue>#{date}</inv:dateDue>
            <inv:accounting>
              <typ:ids>1Op</typ:ids>
            </inv:accounting>
            <inv:text>Tržby bar #{order.order_number}</inv:text>
            <inv:partnerIdentity>
              <typ:address linkToAddress="true">
                <typ:name>#{escape_xml(get_customer_name(order))}</typ:name>
              </typ:address>
            </inv:partnerIdentity>
            <inv:myIdentity>
              <typ:address>
                <typ:company>Moruška s.r.o.</typ:company>
                <typ:city>Praha</typ:city>
                <typ:street>Za skalkou</typ:street>
                <typ:number>770/13</typ:number>
                <typ:zip>147 00</typ:zip>
                <typ:ico>#{ico()}</typ:ico>
                <typ:dic>CZ#{ico()}</typ:dic>
                <typ:mobilPhone>+420 777235566</typ:mobilPhone>
                <typ:email>jindrichuvdum@jindrichuvdum.cz</typ:email>
                <typ:www>www.jindrichuvdum.cz</typ:www>
              </typ:address>
              <typ:establishment>
                <typ:company>Chata Jindřichův dům</typ:company>
                <typ:city>Pec pod Sněžkou</typ:city>
                <typ:street>Pec pod Sněžkou 24</typ:street>
                <typ:zip>542 21</typ:zip>
              </typ:establishment>
            </inv:myIdentity>
            <inv:paymentType>
              <typ:ids>#{payment_ids}</typ:ids>
              <typ:paymentType>#{payment_type}</typ:paymentType>
            </inv:paymentType>
            <inv:account>
              <typ:ids>KB</typ:ids>
              <typ:accountNo>#{account_no}</typ:accountNo>
              <typ:bankCode>#{bank_code}</typ:bankCode>
            </inv:account>
            <inv:symConst>0308</inv:symConst>
            <inv:liquidation>
              <typ:amountHome>#{order.total_amount}</typ:amountHome>
            </inv:liquidation>
            <inv:lock2>false</inv:lock2>
            <inv:markRecord>false</inv:markRecord>
          </inv:invoiceHeader>
          <inv:invoiceDetail xmlns:typ="http://www.stormware.cz/schema/version_2/type.xsd">
    #{Enum.map_join(items, "\n", &order_item_to_xml/1)}
          </inv:invoiceDetail>
          <inv:invoiceSummary xmlns:typ="http://www.stormware.cz/schema/version_2/type.xsd">
            <inv:roundingDocument>none</inv:roundingDocument>
            <inv:roundingVAT>none</inv:roundingVAT>
            <inv:typeCalculateVATInclusivePrice>VATNewMethod</inv:typeCalculateVATInclusivePrice>
            <inv:homeCurrency>
              <typ:priceNone>#{price_none}</typ:priceNone>
              <typ:priceLow>#{price_low}</typ:priceLow>
              <typ:priceLowVAT>#{price_low_vat}</typ:priceLowVAT>
              <typ:priceLowSum>#{price_low_sum}</typ:priceLowSum>
              <typ:priceHigh>#{price_high}</typ:priceHigh>
              <typ:priceHighVAT>#{price_high_vat}</typ:priceHighVAT>
              <typ:priceHighSum>#{price_high_sum}</typ:priceHighSum>
              <typ:round>
                <typ:priceRound>0</typ:priceRound>
              </typ:round>
            </inv:homeCurrency>
          </inv:invoiceSummary>
        </inv:invoice>
      </dat:dataPackItem>
    """
  end

  defp order_item_to_xml(item) do
    product_name = if item.product, do: item.product.name, else: "Unknown Product"

    """
            <inv:invoiceItem xmlns:typ="http://www.stormware.cz/schema/version_2/type.xsd">
              <inv:text>#{escape_xml(product_name)}</inv:text>
              <inv:quantity>#{item.quantity}</inv:quantity>
              <inv:unit>#{item.unit_amount || "pcs"}</inv:unit>
              <inv:coefficient>1.0</inv:coefficient>
              <inv:payVAT>#{vat_pay?(item.vat_rate)}</inv:payVAT>
              <inv:rateVAT>#{vat_rate_to_pohoda(item.vat_rate)}</inv:rateVAT>
              <inv:homeCurrency>
                <typ:unitPrice>#{item.unit_price}</typ:unitPrice>
              </inv:homeCurrency>
            </inv:invoiceItem>
    """
  end

  defp group_items(order_items) do
    order_items
    |> Enum.group_by(fn item ->
      {item.product_id, item.unit_amount, item.unit_price}
    end)
    |> Enum.map(fn {{_product_id, _unit_amount, _unit_price}, items} ->
      first = hd(items)

      total_quantity =
        Enum.reduce(items, Decimal.new("0"), fn item, acc ->
          Decimal.add(acc, Decimal.new(item.quantity))
        end)

      total_subtotal =
        Enum.reduce(items, Decimal.new("0"), fn item, acc ->
          Decimal.add(acc, item.subtotal)
        end)

      %{
        product: first.product,
        unit_amount: first.unit_amount,
        unit_price: first.unit_price,
        vat_rate: first.vat_rate,
        quantity: total_quantity,
        subtotal: total_subtotal
      }
    end)
  end

  defp active_order_items(order) do
    Enum.filter(order.order_items, &is_nil(&1.deleted_at))
  end

  defp get_customer_name(order) do
    cond do
      order.guest ->
        order.guest.name

      order.name ->
        order.name

      true ->
        "Unknown Customer"
    end
  end

  # Calculates VAT breakdown for the invoice summary.
  # Returns {priceNone, priceLow, priceLowVAT, priceLowSum, priceHigh, priceHighVAT, priceHighSum}
  # priceNone = base amount for 0% VAT items
  # priceLow  = base amount for 12% VAT items; priceLowVAT = VAT portion; priceLowSum = base + VAT
  # priceHigh = base amount for 21% VAT items; priceHighVAT = VAT portion; priceHighSum = base + VAT
  defp calculate_vat_totals(items) do
    zero = Decimal.new(0)

    {price_none, price_low, price_low_sum, price_high, price_high_sum} =
      Enum.reduce(items, {zero, zero, zero, zero, zero}, fn item, {none, low, low_sum, high, high_sum} ->
        subtotal = item.subtotal || Decimal.mult(item.unit_price, item.quantity)
        rate = item.vat_rate

        cond do
          Decimal.equal?(rate, Decimal.new(12)) ->
            base = Decimal.div(Decimal.mult(subtotal, 100), Decimal.new(112)) |> Decimal.round(2)
            {none, Decimal.add(low, base), Decimal.add(low_sum, subtotal), high, high_sum}

          Decimal.equal?(rate, Decimal.new(21)) ->
            base = Decimal.div(Decimal.mult(subtotal, 100), Decimal.new(121)) |> Decimal.round(2)
            {none, low, low_sum, Decimal.add(high, base), Decimal.add(high_sum, subtotal)}

          true ->
            {Decimal.add(none, subtotal), low, low_sum, high, high_sum}
        end
      end)

    price_low_vat = Decimal.sub(price_low_sum, price_low) |> Decimal.round(2)
    price_high_vat = Decimal.sub(price_high_sum, price_high) |> Decimal.round(2)

    {
      Decimal.round(price_none, 2),
      Decimal.round(price_low, 2),
      price_low_vat,
      Decimal.round(price_low_sum, 2),
      Decimal.round(price_high, 2),
      price_high_vat,
      Decimal.round(price_high_sum, 2)
    }
  end

  defp format_date(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp escape_xml(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp vat_rate_to_pohoda(rate) when is_struct(rate, Decimal) do
    cond do
      Decimal.equal?(rate, Decimal.new(12)) -> "low"
      Decimal.equal?(rate, Decimal.new(21)) -> "high"
      true -> "none"
    end
  end

  defp vat_pay?(rate) when is_struct(rate, Decimal) do
    if Decimal.equal?(rate, Decimal.new(0)), do: "false", else: "true"
  end

  defp payment_type_to_pohoda(payments) when is_list(payments) do
    case List.first(payments) do
      %{method: "card"} -> {"Kartou", "card"}
      %{method: "cash"} -> {"Hotově", "cash"}
      _ -> {"Hotově", "cash"}
    end
  end

  defp parse_bank_account do
    bank_account = Application.get_env(:cozy_checkout, :bank_account, "0/0000")

    case String.split(bank_account, "/") do
      [account_no, bank_code] -> {account_no, bank_code}
      _ -> {"0", "0000"}
    end
  end

  defp ico do
    Application.get_env(:cozy_checkout, :pohoda_ico, "12345678")
  end
end

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
    <dat:dataPack id="Export" ico="#{ico()}" application="CozyCheckout" version="2.0" note="Export paid orders" xmlns:dat="http://www.stormware.cz/schema/version_2/data.xsd" xmlns:inv="http://www.stormware.cz/schema/version_2/invoice.xsd" xmlns:typ="http://www.stormware.cz/schema/version_2/type.xsd">
    #{Enum.map_join(orders, "\n", &order_to_xml/1)}
    </dat:dataPack>
    """
  end

  defp order_to_xml(order) do
    """
      <dat:dataPackItem id="#{order.order_number}" version="2.0">
        <inv:invoice version="2.0">
          <inv:invoiceHeader>
            <inv:invoiceType>issuedInvoice</inv:invoiceType>
            <inv:number>
              <typ:numberRequested>#{order.order_number}</typ:numberRequested>
            </inv:number>
            <inv:date>#{format_date(order.inserted_at)}</inv:date>
            <inv:dateTax>#{format_date(order.inserted_at)}</inv:dateTax>
            <inv:dateAccounting>#{format_date(order.inserted_at)}</inv:dateAccounting>
            <inv:text>Order #{order.order_number}</inv:text>
            <inv:partnerIdentity>
              <typ:address>
                <typ:company>#{escape_xml(get_customer_name(order))}</typ:company>
              </typ:address>
            </inv:partnerIdentity>
            <inv:paymentType>
              <typ:paymentType>#{payment_type_to_pohoda(order.payments)}</typ:paymentType>
            </inv:paymentType>
            <inv:account>
              <typ:ids>#{default_account()}</typ:ids>
            </inv:account>
            <inv:symPar>#{order.order_number}</inv:symPar>
          </inv:invoiceHeader>
          <inv:invoiceDetail>
    #{Enum.map_join(active_order_items(order), "\n", &order_item_to_xml/1)}
          </inv:invoiceDetail>
          <inv:invoiceSummary>
            <inv:homeCurrency>
              <typ:priceNone>#{order.total_amount}</typ:priceNone>
            </inv:homeCurrency>
          </inv:invoiceSummary>
        </inv:invoice>
      </dat:dataPackItem>
    """
  end

  defp order_item_to_xml(item) do
    product_name = if item.product, do: item.product.name, else: "Unknown Product"

    """
            <inv:invoiceItem>
              <inv:text>#{escape_xml(product_name)}</inv:text>
              <inv:quantity>#{item.quantity}</inv:quantity>
              <inv:unit>#{item.unit_amount || "pcs"}</inv:unit>
              <inv:coefficient>1.0</inv:coefficient>
              <inv:payVAT>false</inv:payVAT>
              <inv:rateVAT>#{vat_rate_to_pohoda(item.vat_rate)}</inv:rateVAT>
              <inv:homeCurrency>
                <typ:unitPrice>#{item.unit_price}</typ:unitPrice>
              </inv:homeCurrency>
            </inv:invoiceItem>
    """
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
    case Decimal.to_string(rate) do
      "0" -> "none"
      "12" -> "low"
      "21" -> "high"
      _ -> "none"
    end
  end

  defp payment_type_to_pohoda(payments) when is_list(payments) do
    case List.first(payments) do
      %{method: "card"} -> "card"
      %{method: "cash"} -> "cash"
      _ -> "cash"
    end
  end

  # Configuration helpers - these should be moved to application config
  defp ico do
    Application.get_env(:cozy_checkout, :pohoda_ico, "12345678")
  end

  defp default_account do
    Application.get_env(:cozy_checkout, :pohoda_default_account, "1")
  end
end

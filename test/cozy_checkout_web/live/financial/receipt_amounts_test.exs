defmodule CozyCheckoutWeb.ReceiptAmountsTest do
  use CozyCheckoutWeb.ConnCase, async: true
  @moduletag :financial
  import Phoenix.LiveViewTest
  import CozyCheckout.SalesFixtures
  alias CozyCheckout.Sales

  test "receipt item totals, VAT and payment agree for an unadjusted order", %{conn: conn} do
    order = paid_order(%{})
    {:ok, view, _} = live(conn, "/pos/orders/#{order.id}/receipt")
    assert has_element?(view, ".receipt-total span", "333.00 CZK")
    assert has_element?(view, ".receipt-item", "100")
    assert_amount(receipt_tax_total(view), "333")
  end

  @tag :known_bug
  test "receipt VAT includes proportional discount and zero-VAT tips", %{conn: conn} do
    order = paid_order(%{"discount_amount" => "33.30", "tips_amount" => "20"})
    {:ok, view, _} = live(conn, "/pos/orders/#{order.id}/receipt")
    assert has_element?(view, ".receipt-total span", "319.70 CZK")
    assert_amount(receipt_tax_total(view), "319.70")
    amounts = vat_amounts(view)
    assert_amount(amounts["Základ DPH 0%:"], "110")
    assert_amount(amounts["Základ DPH 12%:"], "90")
    assert_amount(amounts["DPH 12%:"], "10.80")
    assert_amount(amounts["Základ DPH 21%:"], "90")
    assert_amount(amounts["DPH 21%:"], "18.90")
  end

  test "deleted items and payments are omitted from receipt", %{conn: conn} do
    order = order_fixture()
    removed = item_fixture(order, "50")
    {:ok, _} = Sales.delete_order_item(removed)
    item_fixture(order, "100")
    {:ok, removed_payment} = Sales.create_payment(payment_attrs(order, "50"))
    {:ok, _} = Sales.delete_payment(removed_payment)
    {:ok, active_payment} = Sales.create_payment(payment_attrs(order, "100"))
    {:ok, view, _} = live(conn, "/pos/orders/#{order.id}/receipt")
    assert has_element?(view, ".receipt-total span", "100.00 CZK")
    assert has_element?(view, ".receipt-section span", active_payment.invoice_number)
    refute has_element?(view, ".receipt-section span", removed_payment.invoice_number)
    assert_amount(receipt_tax_total(view), "100")
  end

  defp paid_order(adjustments) do
    order = order_fixture()
    item_fixture(order, "100", "0")
    item_fixture(order, "112", "12")
    item_fixture(order, "121", "21")

    total =
      Decimal.new("333")
      |> Decimal.sub(Decimal.new(adjustments["discount_amount"] || "0"))
      |> Decimal.add(Decimal.new(adjustments["tips_amount"] || "0"))

    {:ok, order} =
      Sales.update_order(Sales.get_order!(order.id), Map.put(adjustments, "total_amount", total))

    {:ok, _} = Sales.create_payment(payment_attrs(order, total))
    order
  end

  defp vat_amounts(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".receipt-section > div[style]")
    |> Enum.reduce(%{}, fn row, amounts ->
      spans = row |> LazyHTML.query("span") |> Enum.map(&LazyHTML.text/1)

      case spans do
        [label, value] ->
          label = String.trim(label)

          if String.starts_with?(label, ["Základ DPH", "DPH "]) do
            amount =
              value
              |> String.replace("CZK", "")
              |> String.replace(" ", "")
              |> String.trim()
              |> Decimal.new()

            Map.put(amounts, label, amount)
          else
            amounts
          end

        _ ->
          amounts
      end
    end)
  end

  defp receipt_tax_total(view) do
    Enum.reduce(vat_amounts(view), Decimal.new(0), fn {_label, amount}, total ->
      Decimal.add(total, amount)
    end)
  end
end

defmodule CozyCheckout.AccountingAmountsTest do
  use CozyCheckout.DataCase, async: true
  @moduletag :financial
  import CozyCheckout.SalesFixtures
  alias CozyCheckout.{Sales, Pohoda}
  alias CozyCheckout.Abra.InvoiceBuilder

  test "plain mixed-VAT order has matching ABRA lines, POHODA totals and payments" do
    order = paid_order()
    assert_exports_match(order, "333")
    xml = Pohoda.export_orders([order.id]) |> parse_xml()
    assert_amount(xml_number(xml, "//typ:priceLowVAT"), "12")
    assert_amount(xml_number(xml, "//typ:priceHighVAT"), "21")
  end

  test "discount and tips are reflected in ABRA lines, total and payments" do
    order = paid_order(%{"discount_amount" => "33.30", "tips_amount" => "20"})
    assert_amount(sum_abra_lines(abra_invoice(order)), "319.70")
  end

  test "discount and tips are reflected in POHODA lines and summary" do
    order = paid_order(%{"discount_amount" => "33.30", "tips_amount" => "20"})
    xml = Pohoda.export_orders([order.id]) |> parse_xml()
    assert_amount(sum_pohoda_lines(xml), "319.70")
    assert_amount(xml_summary_total(xml), "319.70")
  end

  test "discount is allocated proportionally across original VAT rates and tips are exempt" do
    order = paid_order(%{"discount_amount" => "33.30", "tips_amount" => "20"})
    invoice = abra_invoice(order)
    by_rate = Enum.group_by(invoice["polozkyFaktury"], & &1["typSzbDphK"])

    expected = %{
      "typSzbDph.dphOsv" => "110",
      "typSzbDph.dphSniz" => "100.80",
      "typSzbDph.dphZakl" => "108.90"
    }

    for {rate, amount} <- expected do
      total =
        Enum.reduce(by_rate[rate] || [], Decimal.new(0), fn line, sum ->
          Decimal.add(sum, Decimal.mult(Decimal.new(line["mnozMj"]), Decimal.new(line["cenaMj"])))
        end)

      assert_amount(total, amount)
    end
  end

  test "discount and tips adjust the POHODA VAT breakdown" do
    order = paid_order(%{"discount_amount" => "33.30", "tips_amount" => "20"})
    xml = Pohoda.export_orders([order.id]) |> parse_xml()
    assert_amount(xml_number(xml, "//typ:priceNone"), "110")
    assert_amount(xml_number(xml, "//typ:priceLowVAT"), "10.80")
    assert_amount(xml_number(xml, "//typ:priceHighVAT"), "18.90")
  end

  test "one-cent discount does not get lost when allocated across VAT rates" do
    order = paid_order(%{"discount_amount" => "0.01"})
    assert_exports_match(order, "332.99")
  end

  test "same product and price with different historical VAT remain separate ABRA lines" do
    order = same_product_different_vat_order()
    invoice = abra_invoice(order)
    assert length(invoice["polozkyFaktury"]) == 2

    assert Enum.sort(Enum.map(invoice["polozkyFaktury"], & &1["typSzbDphK"])) ==
             ["typSzbDph.dphSniz", "typSzbDph.dphZakl"]
  end

  test "same product and price with different historical VAT remain separate POHODA lines" do
    order = same_product_different_vat_order()
    xml = Pohoda.export_orders([order.id]) |> parse_xml()
    assert length(xpath(xml, "//inv:invoiceItem")) == 2
    assert_amount(xml_number(xml, "//typ:priceLowSum"), "100")
    assert_amount(xml_number(xml, "//typ:priceHighSum"), "100")
  end

  test "ABRA refuses a cached total that does not match invoice lines" do
    order = paid_order()

    assert_rejected(fn ->
      InvoiceBuilder.build(%{order | total_amount: Decimal.new("332")})
    end)
  end

  @tag :known_bug
  test "POHODA refuses a cached total that does not match invoice lines" do
    order = paid_order()
    order |> Ecto.Changeset.change(total_amount: Decimal.new("332")) |> Repo.update!()
    assert_rejected(fn -> Pohoda.export_orders([order.id]) end)
  end

  test "ABRA refuses a paid flag without matching active payments" do
    order = paid_order()
    assert_rejected(fn -> InvoiceBuilder.build(%{order | payments: []}) end)
  end

  test "deleted items and payments are excluded from exported amounts" do
    order = order_fixture()
    removed = item_fixture(order, "50")
    {:ok, _} = Sales.delete_order_item(removed)
    item_fixture(order, "100")
    {:ok, payment} = Sales.create_payment(payment_attrs(order, "50"))
    {:ok, _} = Sales.delete_payment(payment)
    {:ok, _} = Sales.create_payment(payment_attrs(order, "100"))
    order = Sales.get_order!(order.id)
    assert_exports_match(order, "100")
    assert_amount(Decimal.new(abra_invoice(order)["hotovostni-uhrada"]["castka"]), "100")
  end

  test "cash and bank payments retain the cash portion of the settlement" do
    order = order_fixture()
    item_fixture(order, "300")
    {:ok, _} = Sales.create_payment(payment_attrs(order, "100"))
    {:ok, _} = Sales.create_payment(payment_attrs(order, "200", "qr_code"))
    invoice = abra_invoice(Sales.get_order!(order.id))
    assert_amount(sum_abra_lines(invoice), "300")
    assert_amount(Decimal.new(invoice["hotovostni-uhrada"]["castka"]), "100")
    assert invoice["bankovniUcet"] != nil
  end

  test "QR payments do not generate a cash settlement in ABRA" do
    order = paid_order(%{}, "qr_code")
    invoice = abra_invoice(order)
    refute Map.has_key?(invoice, "hotovostni-uhrada")
    assert invoice["bankovniUcet"] != nil
  end

  @tag :known_bug
  test "unsupported VAT is rejected rather than silently exported as exempt" do
    order = order_fixture()
    item_fixture(order, "100", "15")
    {:ok, _} = Sales.create_payment(payment_attrs(order, "100"))
    assert_rejected(fn -> InvoiceBuilder.build(Sales.get_order!(order.id)) end)
  end

  defp same_product_different_vat_order do
    order = order_fixture()
    first = item_fixture(order, "100", "12")

    {:ok, second} =
      Sales.create_order_item(%{
        "order_id" => order.id,
        "product_id" => first.product_id,
        "quantity" => 1
      })

    second |> Ecto.Changeset.change(vat_rate: Decimal.new(21)) |> Repo.update!()
    {:ok, _} = Sales.recalculate_order_total(order)
    {:ok, _} = Sales.create_payment(payment_attrs(order, "200"))
    Sales.get_order!(order.id)
  end

  defp paid_order(adjustments \\ %{}, method \\ "cash") do
    order = order_fixture()
    item_fixture(order, "100", "0")
    item_fixture(order, "112", "12")
    item_fixture(order, "121", "21")
    # Independent valid snapshot: do not rely on the recalculation under test.
    discount = Decimal.new(adjustments["discount_amount"] || "0")
    tips = Decimal.new(adjustments["tips_amount"] || "0")
    amount = Decimal.new("333") |> Decimal.sub(discount) |> Decimal.add(tips)

    {:ok, order} =
      Sales.update_order(Sales.get_order!(order.id), Map.put(adjustments, "total_amount", amount))

    {:ok, _} = Sales.create_payment(payment_attrs(order, amount, method))
    Sales.get_order!(order.id)
  end

  defp assert_exports_match(order, expected) do
    assert_amount(order.total_amount, expected)
    active_payments = Enum.filter(order.payments, &is_nil(&1.deleted_at))

    assert_amount(
      Enum.reduce(active_payments, Decimal.new(0), &Decimal.add(&2, &1.amount)),
      expected
    )

    assert_amount(sum_abra_lines(abra_invoice(order)), expected)
    xml = Pohoda.export_orders([order.id]) |> parse_xml()
    assert_amount(sum_pohoda_lines(xml), expected)
    assert_amount(xml_number(xml, "//typ:amountHome"), expected)
    assert_amount(xml_summary_total(xml), expected)
  end

  defp xml_summary_total(xml) do
    Decimal.add(
      xml_number(xml, "//typ:priceNone"),
      Decimal.add(xml_number(xml, "//typ:priceLowSum"), xml_number(xml, "//typ:priceHighSum"))
    )
  end

  defp abra_invoice(order), do: InvoiceBuilder.build(order)["winstrom"]["faktura-vydana"] |> hd()

  defp sum_abra_lines(invoice) do
    Enum.reduce(invoice["polozkyFaktury"], Decimal.new(0), fn item, sum ->
      Decimal.add(sum, Decimal.mult(Decimal.new(item["mnozMj"]), Decimal.new(item["cenaMj"])))
    end)
  end

  defp parse_xml(xml), do: xml |> :binary.bin_to_list() |> :xmerl_scan.string() |> elem(0)
  defp xpath(xml, path), do: :xmerl_xpath.string(String.to_charlist(path), xml)

  defp xml_number(xml, path) do
    {:xmlObj, :string, value} = xpath(xml, "string(#{path})")
    Decimal.new(to_string(value))
  end

  defp sum_pohoda_lines(xml) do
    Enum.reduce(xpath(xml, "//inv:invoiceItem"), Decimal.new(0), fn item, sum ->
      Decimal.add(
        sum,
        Decimal.mult(
          xml_number(item, "inv:quantity"),
          xml_number(item, "inv:homeCurrency/typ:unitPrice")
        )
      )
    end)
  end
end

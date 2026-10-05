defmodule CozyCheckout.Payments.QrCodeTest do
  use ExUnit.Case, async: true
  @moduletag :financial
  alias CozyCheckout.Payments.QrCode

  test "SPD preserves the amount, CZK and numeric variable symbol" do
    data =
      QrCode.generate_qr_data(%{
        account_number: "123456789/0100",
        amount: Decimal.new("150.50"),
        variable_symbol: "ORD-20261005-1234",
        message: "Order payment"
      })

    assert data ==
             "SPD*1.0*ACC:CZ1801000000000123456789*AM:150.50*CC:CZK*MSG:Order payment*X-VS:2610051234"
  end

  @tag :known_bug
  test "Czech account prefixes are converted to a valid known IBAN" do
    data =
      QrCode.generate_qr_data(%{
        account_number: "19-2000145399/0800",
        amount: Decimal.new("100.00"),
        variable_symbol: nil
      })

    assert data =~ "ACC:CZ6508000000192000145399"
  end

  test "QR and ABRA use the same variable symbol" do
    order = %CozyCheckout.Sales.Order{
      id: Ecto.UUID.generate(),
      order_number: "ORD-20261005-1234",
      name: "QR customer",
      inserted_at: DateTime.utc_now(),
      guest: nil,
      order_items: [],
      payments: []
    }

    [invoice] = CozyCheckout.Abra.InvoiceBuilder.build(order)["winstrom"]["faktura-vydana"]

    data =
      QrCode.generate_qr_data(%{
        account_number: "123456789/0100",
        amount: Decimal.new("100"),
        variable_symbol: order.order_number
      })

    assert data =~ "X-VS:#{invoice["varSym"]}"
  end

  test "SVG generation returns an actual SVG document" do
    encoded =
      QrCode.generate_qr_svg(%{
        account_number: "123456789/0100",
        amount: Decimal.new("100"),
        variable_symbol: "1234"
      })

    svg = Base.decode64!(encoded)
    assert svg =~ "<svg"
  end
end

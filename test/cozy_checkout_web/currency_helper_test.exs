defmodule CozyCheckoutWeb.CurrencyHelperTest do
  use ExUnit.Case, async: true
  alias CozyCheckoutWeb.CurrencyHelper

  test "negative amounts keep the minus attached when the digit count is a multiple of three" do
    for {amount, expected} <- [
          {"-100.00", "-100.00 CZK"},
          {"-100000.25", "-100 000.25 CZK"},
          {"-100000000.50", "-100 000 000.50 CZK"}
        ] do
      assert CurrencyHelper.format_currency(Decimal.new(amount)) == expected
    end
  end

  test "number formatting groups digits independently of the sign" do
    for {number, expected} <- [
          {-100, "-100"},
          {-1000, "-1 000"},
          {-100_000, "-100 000"},
          {100, "100"},
          {1000, "1 000"},
          {100_000, "100 000"}
        ] do
      assert CurrencyHelper.format_number(number) == expected
    end

    assert CurrencyHelper.format_number(Decimal.new("-100.25")) == "-100.25"
    assert CurrencyHelper.format_number(Decimal.new("100000.25")) == "100 000.25"
  end

  test "explicit precision and decimal separator preserve a single leading minus" do
    assert CurrencyHelper.format_number(Decimal.new("-100000.25"),
             precision: 2,
             decimal_separator: ","
           ) == "-100 000,25"
  end
end

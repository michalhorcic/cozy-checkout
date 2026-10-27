defmodule CozyCheckout.Billing.Presentation do
  @moduledoc "Czech presentation of immutable billing snapshots, shared by preview and PDF."
  alias CozyCheckout.Billing.Money
  alias CozyCheckoutWeb.CurrencyHelper

  def number(value),
    do: CurrencyHelper.format_number(value, precision: 2, decimal_separator: ",")

  def amount(value), do: number(value) <> " " <> CurrencyHelper.currency_symbol()

  def date(nil), do: "—"
  def date(value) when is_binary(value), do: value |> Date.from_iso8601!() |> date()
  def date(value), do: Calendar.strftime(value, "%d.%m.%Y")

  def country_name("CZ"), do: "Česká Republika"
  def country_name(country), do: country

  def lines(%{kind: "advance", total: total}), do: [%{"gross" => to_string(total)}]
  def lines(document), do: document.lines

  def line_label(_line, "advance"), do: "Záloha na pobyt a objednané služby"
  def line_label(_line, "tax_receipt"), do: "Přijatá záloha na pobyt a objednané služby"
  def line_label(line, _kind), do: line["name"]

  def advance_breakdown(%{kind: "advance", snapshot: snapshot}),
    do: snapshot["advance_calculation"]

  def advance_breakdown(_document), do: nil

  def advance_explanation(%{"method" => "percent"} = calculation) do
    "#{number(calculation["percent"])} % z #{amount(calculation["stay_total"])} = #{amount(calculation["amount"])}"
  end

  def advance_explanation(%{"method" => "amount"} = calculation),
    do: "Záloha zadaná částkou: #{amount(calculation["amount"])}"

  def gross_unit_price(%{"basis" => "legacy_net", "tax_mode" => "taxable"} = line) do
    Decimal.mult(
      Money.value(line, "unit"),
      Decimal.add(1, Decimal.div(Money.value(line, "vat_rate"), 100))
    )
  end

  def gross_unit_price(line), do: Money.value(line, "unit")

  def balance_label(value) do
    case Decimal.compare(Money.decimal(value), 0) do
      :gt -> "K úhradě"
      :lt -> "Přeplatek"
      :eq -> "Zbývá k úhradě"
    end
  end

  def balance_amount(value), do: value |> Money.decimal() |> Decimal.abs() |> amount()
end

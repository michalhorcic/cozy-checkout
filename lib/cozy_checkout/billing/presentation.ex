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

  def lines(%{kind: "advance", total: total}), do: [%{"gross" => to_string(total)}]
  def lines(document), do: document.lines

  def line_label(_line, "advance"), do: "Záloha na pobyt a objednané služby"
  def line_label(_line, "tax_receipt"), do: "Přijatá záloha na pobyt a objednané služby"
  def line_label(line, _kind), do: line["name"]

  def balance_label(value) do
    case Decimal.compare(Money.decimal(value), 0) do
      :gt -> "K úhradě"
      :lt -> "Přeplatek"
      :eq -> "Zbývá k úhradě"
    end
  end

  def balance_amount(value), do: value |> Money.decimal() |> Decimal.abs() |> amount()
end

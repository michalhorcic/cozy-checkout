defmodule CozyCheckoutWeb.CurrencyHelper do
  @moduledoc """
  Helper functions for currency formatting.

  Configuration:
  - Currency symbol: "CZK" (default)
  - To change the currency, modify @currency_symbol
  - To change position (before/after), modify format_currency/1
  """

  @currency_symbol "CZK"

  @doc """
  Formats a Decimal amount with the configured currency symbol.

  ## Examples

      iex> format_currency(Decimal.new("100"))
      "100 CZK"

      iex> format_currency(Decimal.new("100.50"))
      "100.50 CZK"
  """
  def format_currency(amount) when is_struct(amount, Decimal) do
    "#{Decimal.round(amount, 2)} #{@currency_symbol}"
  end

  def format_currency(nil) do
    "0 #{@currency_symbol}"
  end

  @doc """
  Returns the configured currency symbol.

  ## Examples

      iex> currency_symbol()
      "CZK"
  """
  def currency_symbol, do: @currency_symbol
end

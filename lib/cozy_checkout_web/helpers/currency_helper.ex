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
  Formats a Decimal amount with the configured currency symbol and thousand separators.

  ## Examples

      iex> format_currency(Decimal.new("100"))
      "100 CZK"

      iex> format_currency(Decimal.new("100.50"))
      "100.50 CZK"

      iex> format_currency(Decimal.new("1234.56"))
      "1 234.56 CZK"

      iex> format_currency(Decimal.new("1234567.89"))
      "1 234 567.89 CZK"
  """
  def format_currency(amount) when is_struct(amount, Decimal) do
    formatted_amount = format_number_with_separator(Decimal.round(amount, 2))
    "#{formatted_amount} #{@currency_symbol}"
  end

  def format_currency(nil) do
    "0 #{@currency_symbol}"
  end

  @doc """
  Formats a number (integer, float, or Decimal) with thousand separators.

  ## Examples

      iex> format_number(1234)
      "1 234"

      iex> format_number(1234.56)
      "1 234.56"

      iex> format_number(Decimal.new("1234567.89"))
      "1 234 567.89"
  """
  def format_number(number) when is_integer(number) do
    format_number_with_separator(number)
  end

  def format_number(number) when is_float(number) do
    format_number_with_separator(number)
  end

  def format_number(number) when is_struct(number, Decimal) do
    format_number_with_separator(number)
  end

  def format_number(nil), do: "0"

  defp format_number_with_separator(number) do
    # Convert to string
    number_str =
      cond do
        is_struct(number, Decimal) -> Decimal.to_string(number)
        is_integer(number) -> Integer.to_string(number)
        is_float(number) -> :erlang.float_to_binary(number, [:compact, {:decimals, 2}])
        true -> to_string(number)
      end

    # Split integer and decimal parts
    [integer_part | decimal_parts] = String.split(number_str, ".")

    # Add thousand separators to integer part (non-breaking space for Czech format)
    formatted_integer =
      integer_part
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.join/1)
      |> Enum.join(" ")
      |> String.reverse()

    # Combine with decimal part if it exists
    case decimal_parts do
      [] -> formatted_integer
      [decimal_part] -> "#{formatted_integer}.#{decimal_part}"
      _ -> formatted_integer
    end
  end

  @doc """
  Returns the configured currency symbol.

  ## Examples

      iex> currency_symbol()
      "CZK"
  """
  def currency_symbol, do: @currency_symbol
end

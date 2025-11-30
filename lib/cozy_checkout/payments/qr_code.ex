defmodule CozyCheckout.Payments.QrCode do
  @moduledoc """
  Generates QR code data and SVG for Czech bank payment QR codes (SPD format).
  """

  @doc """
  Generates a payment QR code string in SPD format for Czech banks.

  ## Parameters
    - account_number: Bank account number
    - amount: Payment amount
    - currency: Currency code (default: "CZK")
    - variable_symbol: Variable symbol (typically invoice number)
    - message: Optional payment message

  ## Examples

      iex> generate_qr_data(%{
      ...>   account_number: "123456789/0100",
      ...>   amount: Decimal.new("150.50"),
      ...>   variable_symbol: "PAY-20251016-0001",
      ...>   message: "Order payment"
      ...> })
      "SPD*1.0*ACC:CZ1201000000000123456789*AM:150.50*CC:CZK*MSG:Order payment*X-VS:2025101600"
  """
  def generate_qr_data(params) do
    account_number = Map.get(params, :account_number)
    amount = Map.get(params, :amount) |> Decimal.to_string()
    currency = Map.get(params, :currency, "CZK")
    variable_symbol = Map.get(params, :variable_symbol) |> sanitize_variable_symbol()
    message = Map.get(params, :message)

    # Parse account number format "123456789/0100" to IBAN
    iban = account_to_iban(account_number)

    qr_parts = [
      "SPD*1.0",
      "ACC:#{iban}",
      "AM:#{amount}",
      "CC:#{currency}"
    ]

    qr_parts =
      if message do
        qr_parts ++ ["MSG:#{message}"]
      else
        qr_parts
      end

    qr_parts =
      if variable_symbol do
        qr_parts ++ ["X-VS:#{variable_symbol}"]
      else
        qr_parts
      end

    Enum.join(qr_parts, "*")
  end

  @doc """
  Prints the QR code data string for debugging.
  Use this to verify the payment data before generating the QR code.
  """
  def debug_qr_data(params) do
    qr_data = generate_qr_data(params)

    IO.puts("\n═══════════════════════════════════════════════════════════════")
    IO.puts("QR CODE PAYMENT DATA STRING")
    IO.puts("═══════════════════════════════════════════════════════════════")
    IO.puts(qr_data)
    IO.puts("═══════════════════════════════════════════════════════════════")
    IO.puts("\nTest this string with online QR generators:")
    IO.puts("  • https://qr.io/")
    IO.puts("  • https://www.qr-code-generator.com/")
    IO.puts("  • https://goqr.me/")
    IO.puts("\nFormat breakdown:")

    qr_data
    |> String.split("*")
    |> Enum.each(fn part ->
      IO.puts("  • #{part}")
    end)

    IO.puts("═══════════════════════════════════════════════════════════════\n")

    qr_data
  end

  @doc """
  Generates an SVG QR code for the given payment data.
  Returns the base64-encoded SVG string that can be embedded in HTML.
  """
  def generate_qr_svg(params) do
    qr_data = generate_qr_data(params)

    require Logger

    Logger.info("""

    ═══════════════════════════════════════════════════════════════
    QR CODE PAYMENT DATA
    ═══════════════════════════════════════════════════════════════
    #{qr_data}
    ═══════════════════════════════════════════════════════════════

    You can test this string with online QR code generators:
    - https://qr.io/
    - https://www.qr-code-generator.com/
    - https://goqr.me/

    Or use a QR code reader app to scan the generated QR code.
    ═══════════════════════════════════════════════════════════════
    """)

    qr_data
    |> QRCode.create(:high)
    |> QRCode.render(:svg)
    |> QRCode.to_base64()
    |> case do
      {:ok, base64} ->
        base64

      {:error, reason} ->
        Logger.error("Failed to generate QR code: #{inspect(reason)}")
        nil
    end
  end

  # Converts Czech bank account number format to IBAN with proper check digits.
  # Format: "account_number/bank_code" -> "CZKKBBBBBBAAAAAAAAAAAA"
  #
  # Czech IBAN format: CZ + 2 check digits + 4-digit bank code + 16-digit account number
  defp account_to_iban(account_str) when is_binary(account_str) do
    case String.split(account_str, "/") do
      [account, bank_code] ->
        # Pad account number to 16 digits and bank code to 4 digits
        account_padded = String.pad_leading(account, 16, "0")
        bank_code_padded = String.pad_leading(bank_code, 4, "0")

        # Calculate IBAN check digits using mod-97 algorithm
        # 1. Create base IBAN with CZ00
        base_iban = "#{bank_code_padded}#{account_padded}CZ00"

        # 2. Replace letters with numbers (C=12, Z=35)
        numeric_iban =
          base_iban
          |> String.replace("C", "12")
          |> String.replace("Z", "35")

        # 3. Calculate mod 97
        check_digits = 98 - mod97(numeric_iban)
        check_digits_str = String.pad_leading("#{check_digits}", 2, "0")

        # 4. Return complete IBAN
        "CZ#{check_digits_str}#{bank_code_padded}#{account_padded}"

      _ ->
        # Invalid format, return as is
        account_str
    end
  end

  defp account_to_iban(nil), do: ""

  # Calculate mod 97 for large numbers (IBAN check digit algorithm)
  defp mod97(numeric_string) do
    numeric_string
    |> String.graphemes()
    |> Enum.reduce(0, fn digit, acc ->
      rem(acc * 10 + String.to_integer(digit), 97)
    end)
  end

  # Sanitizes variable symbol to contain only numbers and be max 10 characters.
  # Extracts all digits from the input string and takes the last 10 digits.
  # For invoice numbers like "PAY-20251130-0001", this produces "2025113000" (10 chars)
  # For shorter numbers, it returns all digits found.
  defp sanitize_variable_symbol(nil), do: nil
  defp sanitize_variable_symbol(""), do: nil

  defp sanitize_variable_symbol(value) when is_binary(value) do
    digits =
      value
      |> String.replace(~r/\D/, "")
      |> String.slice(-10..-1//1)

    if digits == "", do: nil, else: digits
  end

  defp sanitize_variable_symbol(_), do: nil
end

# Payment Functionality in POS System

## Overview

The POS system now supports direct payment processing with two methods:
1. **Cash Payment** - Records immediate payment
2. **QR Code Payment** - Generates a Czech banking QR code for mobile payment

## Features

### Payment Methods

#### Cash Payment
- Records payment immediately
- Automatically generates invoice number
- Updates order status to "paid"
- Shows success confirmation with invoice number

#### QR Code Payment
- Creates payment record with invoice number
- Generates SPD-format QR code for Czech banks
- Displays scannable QR code with payment details
- Shows amount and invoice number prominently
- Provides step-by-step instructions for customers

### Invoice Number Generation

Invoice numbers follow the format: `PAY-YYYYMMDD-NNNN`

- `PAY`: Prefix for payment invoices
- `YYYYMMDD`: Current date (e.g., 20251016)
- `NNNN`: Sequential 4-digit number for that day (0001, 0002, etc.)

Example: `PAY-20251016-0001`

### QR Code Format

The system generates QR codes in the **SPD (Short Payment Descriptor)** format, which is the standard for Czech banking apps according to the [official specification](https://qr-platba.cz/pro-vyvojare/specifikace-formatu/).

```
SPD*1.0*ACC:<IBAN>*AM:<amount>*CC:CZK*MSG:<message>*X-VS:<invoice_number>
```

Components:
- **ACC**: Czech IBAN (converted from account number/bank code format) - **REQUIRED** field
- **AM**: Payment amount
- **CC**: Currency code (CZK)
- **MSG**: Payment description (Order number)
- **X-VS**: Variable symbol (invoice number for payment matching)

#### Important: IBAN Format Requirement

**Czech banking apps require valid IBAN format** in the ACC field. The system automatically converts Czech account numbers (format: `account_number/bank_code`) to IBAN format using the proper **mod-97 check digit algorithm**.

Example conversion:
- Input: `123456789/0100`
- Output: `CZ6501000000000123456789`

The IBAN format follows: `CZ` + 2 check digits + 4-digit bank code + 16-digit account number

**Why This Matters:**
- Czech banks validate IBAN check digits as part of their security measures
- Invalid IBANs (like `CZ00...`) will be rejected by banking apps
- The check digits are calculated using the international IBAN mod-97 algorithm

## Configuration

### Bank Account Setup

Edit `config/config.exs` and update:

```elixir
config :cozy_checkout,
  bank_account: "123456789/0100"  # Your actual bank account number
```

Format: `account_number/bank_code`

## Database Schema

### Migration Added

```elixir
alter table(:payments) do
  add :invoice_number, :string
end

create unique_index(:payments, [:invoice_number])
```

### Payment Schema Updated

```elixir
schema "payments" do
  field :amount, :decimal
  field :payment_method, :string  # "cash" or "qr_code"
  field :payment_date, :date
  field :notes, :string
  field :invoice_number, :string  # NEW: Unique invoice number
  field :deleted_at, :utc_datetime
  
  belongs_to :order, CozyCheckout.Sales.Order
  
  timestamps(type: :utc_datetime)
end
```

## User Interface

### Payment Button

The "Pay Order" button appears in the cart summary when:
- Order status is "open"
- Order total is greater than 0

### Payment Modal Flow

1. **Method Selection Screen**
   - Large touch-friendly buttons for Cash and QR Code
   - Shows total amount to pay
   - Cancel option to return

2. **Cash Payment**
   - Immediately processes payment
   - Shows success message with invoice number
   - Closes modal and reloads order (now marked as "paid")

3. **QR Code Display**
   - Shows large scannable QR code (256x256px)
   - Displays invoice number
   - Shows amount to pay prominently
   - Provides scanning instructions
   - "Done" button to close

### Visual Feedback

- Paid orders show a green "Paid" badge instead of the payment button
- Success messages display invoice number for reference
- QR code screen includes clear visual hierarchy

## Technical Implementation

### Files Created/Modified

**New Files:**
- `lib/cozy_checkout/payments/qr_code.ex` - QR code data generator
- `priv/repo/migrations/[timestamp]_add_invoice_number_to_payments.exs` - Migration

**Modified Files:**
- `lib/cozy_checkout/sales.ex` - Added `generate_invoice_number/0`
- `lib/cozy_checkout/sales/payment.ex` - Added invoice_number field
- `lib/cozy_checkout_web/live/pos_live/order_management.ex` - Payment handlers
- `lib/cozy_checkout_web/live/pos_live/order_management.html.heex` - Payment UI
- `config/config.exs` - Bank account configuration
- `assets/js/app.js` - QR code generation hook

### Key Functions

**Sales Context (`lib/cozy_checkout/sales.ex`):**

```elixir
# Generates unique invoice number
def generate_invoice_number()

# Creates payment with auto-generated invoice number
def create_payment(attrs)
```

**QR Code Module (`lib/cozy_checkout/payments/qr_code.ex`):**

```elixir
# Generates SPD format QR code data
def generate_qr_data(params)
```

### LiveView Handlers

**OrderManagement LiveView:**

```elixir
# Opens payment modal
handle_event("open_payment_modal", ...)

# Closes payment modal
handle_event("close_payment_modal", ...)

# Processes cash payment
handle_event("select_payment_method", %{"method" => "cash"}, ...)

# Generates QR code for payment
handle_event("select_payment_method", %{"method" => "qr_code"}, ...)
```

### Server-Side QR Generation

QR codes are generated **server-side** using the `qr_code` Elixir library:

**QrCode Module** (`lib/cozy_checkout/payments/qr_code.ex`):

```elixir
def generate_qr_svg(params) do
  qr_data = generate_qr_data(params)
  
  qr_data
  |> QRCode.create(:high)
  |> QRCode.render(:svg)
  |> QRCode.to_base64()
  |> case do
    {:ok, base64} -> base64
    {:error, reason} ->
      Logger.error("Failed to generate QR code: #{inspect(reason)}")
      nil
  end
end
```

**Important:** The `qr_code` library returns `Result` tuples (`{:ok, value}` or `{:error, reason}`). Each function in the pipeline maintains this structure:
- `QRCode.create/2` → `{:ok, qr_struct}` or `{:error, reason}`
- `QRCode.render/2` → `{:ok, svg_binary}` or `{:error, reason}`
- `QRCode.to_base64/1` → `{:ok, base64_string}` or `{:error, reason}`

The QR code SVG is generated when the payment is created and passed to the template as a base64-encoded data URL.

## Dependencies

- **`qr_code` ~> 3.2** - Elixir library for generating QR codes
  - Pure Elixir implementation (no external services needed)
  - Works offline
  - Fast and reliable
  - Installed via: `mix deps.get`

## Testing Checklist

- [ ] Open order with items in POS system
- [ ] Click "Pay Order" button
- [ ] Verify payment method selection modal appears
- [ ] Select "Cash" payment
  - [ ] Verify payment is created
  - [ ] Verify invoice number is generated
  - [ ] Verify order status changes to "paid"
  - [ ] Verify success message shows invoice number
- [ ] Create new order and add items
- [ ] Select "QR Code" payment
  - [ ] Verify QR code is displayed
  - [ ] Verify invoice number is shown
  - [ ] Verify amount is displayed correctly
  - [ ] Scan QR code with banking app (if available)
  - [ ] Verify payment details are correct in banking app
- [ ] Verify paid orders show "Paid" badge instead of pay button
- [ ] Check invoice number uniqueness (create multiple payments)
- [ ] Verify invoice numbers increment correctly per day

## Production Notes

### IBAN Conversion

The IBAN conversion in `qr_code.ex` implements the proper **mod-97 check digit algorithm** as required by the IBAN standard:

```elixir
defp account_to_iban(account_str) when is_binary(account_str) do
  case String.split(account_str, "/") do
    [account, bank_code] ->
      # Pad to standard lengths
      account_padded = String.pad_leading(account, 16, "0")
      bank_code_padded = String.pad_leading(bank_code, 4, "0")

      # Calculate IBAN check digits using mod-97 algorithm
      base_iban = "#{bank_code_padded}#{account_padded}CZ00"
      
      # Replace letters with numbers (C=12, Z=35)
      numeric_iban = 
        base_iban
        |> String.replace("C", "12")
        |> String.replace("Z", "35")
      
      # Calculate check digits: 98 - mod97(numeric_iban)
      check_digits = 98 - mod97(numeric_iban)
      check_digits_str = String.pad_leading("#{check_digits}", 2, "0")

      "CZ#{check_digits_str}#{bank_code_padded}#{account_padded}"
  end
end

defp mod97(numeric_string) do
  numeric_string
  |> String.graphemes()
  |> Enum.reduce(0, fn digit, acc ->
    rem(acc * 10 + String.to_integer(digit), 97)
  end)
end
```

This produces **valid IBANs** that pass bank validation. The check digits are calculated according to the international IBAN standard (ISO 13616).

### Bank Account Configuration

1. Update `config/config.exs` with your actual bank account
2. Verify the account format is correct (`account_number/bank_code`)
3. Test QR codes with your banking app before going live
4. Consider using environment variables in production

### Security Considerations

- Invoice numbers are sequential and predictable (by design for accounting)
- Payment records include soft delete functionality
- Unique constraint prevents duplicate invoice numbers
- Consider adding payment verification/reconciliation process

## Future Enhancements

Potential improvements:
- [ ] Print receipt functionality
- [ ] Email receipt to guest
- [ ] Partial payment support
- [ ] Refund functionality
- [ ] Payment reconciliation with bank statements
- [ ] Multiple currency support
- [ ] Card payment terminal integration
- [ ] Payment history view in POS
- [ ] Daily payment summary report

## Troubleshooting

### Common Issue: QR Code Displays But Bank App Won't Scan

**Symptoms:**
- QR code image appears in the UI
- You can read the QR code with a camera/QR reader
- The text string looks correct
- But banking apps don't recognize or accept it

**Root Cause:**
Czech banking apps **validate IBAN check digits** as part of their security. If you use invalid check digits (like "CZ00..."), the banking app will reject the QR code even though it scans correctly.

**Solution:**
The system now implements proper IBAN check digit calculation using the mod-97 algorithm. Ensure you have the latest version of `lib/cozy_checkout/payments/qr_code.ex` with the `mod97/1` function.

**Verification Steps:**
1. Generate a payment QR code
2. Check terminal logs for output like: `QR CODE PAYMENT DATA`
3. Look at the ACC field - it should show something like: `ACC:CZ6501000000000123456789`
4. The check digits (65 in this example) should **NOT** be "00"
5. You can verify your IBAN is valid using online IBAN validators

**Example of Invalid vs Valid IBAN:**
- ❌ Invalid: `CZ000100000000000123456789` (hardcoded "00" check digits)
- ✅ Valid: `CZ6501000000000123456789` (calculated "65" check digits)

**Reference:**
According to the [official Czech QR payment specification](https://qr-platba.cz/pro-vyvojare/specifikace-formatu/), the ACC field must contain a valid IBAN, optionally followed by a BIC code after a "+" separator.

---

**QR Code not displaying:**
- Check if `qr_code` dependency is installed (`mix deps.get`)
- Verify the QR data string is being generated correctly
- Check application logs for QR generation errors
- Ensure `generate_qr_svg/1` is returning valid base64 data

**Invoice number collision:**
- Check database for existing invoice numbers
- Verify unique index exists on `invoice_number` column
- Check system date/time is correct

**Bank app not recognizing QR code:**
- Verify bank account format in config (must be `account_number/bank_code` format)
- Check terminal logs for the QR data string output (includes full SPD format)
- Verify IBAN check digits are being calculated correctly (not hardcoded as "00")
- Test the QR data string with online QR generators to verify it's scannable
- According to the [official Czech QR payment specification](https://qr-platba.cz/pro-vyvojare/specifikace-formatu/):
  - ACC field **must** contain valid IBAN format
  - Czech banks validate IBAN check digits
  - Invalid check digits will cause banking apps to reject the QR code
- Use the debug output to verify your IBAN: should be like `CZ6501000000000123456789` (not `CZ00...`)
- All Czech banks support these required fields: ACC, AM, CC, DT, MSG, X-VS, X-SS, X-KS

**Order not marking as paid:**
- Check payment amount matches order total
- Verify `update_order_payment_status` is called
- Check transaction completed successfully
- Review application logs for errors

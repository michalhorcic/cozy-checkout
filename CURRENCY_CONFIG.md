# Currency Configuration

The application now supports configurable currency display throughout the system.

## Configuration

The currency is configured in code in the `CozyCheckoutWeb.CurrencyHelper` module:

**File:** `lib/cozy_checkout_web/helpers/currency_helper.ex`

```elixir
@currency_symbol "CZK"
```

### How to Change Currency

To change the currency from CZK to another currency (e.g., EUR, USD):

1. Open `lib/cozy_checkout_web/helpers/currency_helper.ex`
2. Modify the `@currency_symbol` module attribute:
   ```elixir
   @currency_symbol "EUR"  # or "USD", "$", "€", etc.
   ```
3. Restart your Phoenix server

## Usage

### In Templates

Always use the `format_currency/1` function to display currency values:

```heex
<!-- Good ✓ -->
<p>{format_currency(@order.total_amount)}</p>

<!-- Bad ✗ - Never hardcode currency symbols -->
<p>${@order.total_amount}</p>
```

### In LiveView Modules

The `format_currency/1` function is automatically imported in all LiveViews, LiveComponents, and HTML modules through `cozy_checkout_web.ex`.

## Currency Helper Functions

### `format_currency/1`

Formats a Decimal amount with the configured currency symbol.

**Examples:**
```elixir
format_currency(Decimal.new("100"))     # => "100 CZK"
format_currency(Decimal.new("100.50"))  # => "100.50 CZK"
format_currency(nil)                    # => "0 CZK"
```

### `currency_symbol/0`

Returns the configured currency symbol.

**Example:**
```elixir
currency_symbol()  # => "CZK"
```

## Updated Files

All currency displays have been updated to use the helper function:

- ✅ POS System
  - `order_selection.html.heex`
  - `order_management.html.heex`
- ✅ Admin Order Management
  - `order_live/index.ex`
  - `order_live/show.ex`
  - `order_live/edit.ex`
  - `order_live/new.ex`
- ✅ Payment Management
  - `payment_live/index.ex`
  - `payment_live/new.ex`

## Benefits

1. **Centralized Configuration**: Change currency in one place (`CurrencyHelper`)
2. **Consistent Formatting**: All currency values formatted the same way
3. **Easy Maintenance**: No hardcoded currency symbols scattered throughout the codebase
4. **Type Safety**: Works seamlessly with Decimal types
5. **Future-Proof**: Easy to extend for multi-currency support if needed

## Future Enhancements

If multi-currency support is needed in the future, the helper can be extended to:
- Accept currency as a parameter
- Store currency per order/transaction in the database
- Support currency conversion
- Respect locale-specific formatting

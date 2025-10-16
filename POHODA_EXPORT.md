# POHODA Export Guide

This guide explains how to export paid orders from Cozy Checkout to POHODA accounting software.

## Overview

The POHODA Export feature allows you to export paid orders as XML files that can be imported directly into POHODA accounting software. The export follows POHODA's standard XML schema for issued invoices.

## Configuration

Before using the export feature, you need to configure your company details in `config/config.exs`:

```elixir
config :cozy_checkout,
  pohoda_ico: "12345678",  # Your company ICO (tax ID)
  pohoda_default_account: "1"  # Default accounting account in POHODA
```

### Configuration Options

- **`pohoda_ico`**: Your company's ICO (identification number). This is your tax ID number.
- **`pohoda_default_account`**: The default accounting account number in POHODA where these transactions should be recorded.

## Using the Export Feature

### Accessing the Export Interface

1. Navigate to the dashboard
2. Click on "POHODA Export"
3. Or go directly to `/pohoda-export`

### Exporting Orders

1. **Select Date Range**: Choose the start and end dates for orders you want to export
2. **Load Orders**: Click "Load Orders" to display all paid orders in the selected date range
3. **Select Orders**: 
   - Check individual orders you want to export
   - Use "Select All" to select all visible orders
   - Use "Deselect All" to clear your selection
4. **Export**: Click "Export Selected Orders" to generate the XML file
5. The XML file will be automatically downloaded to your computer

### File Format

The exported file will be named: `pohoda_export_YYYY-MM-DD.xml`

## Importing into POHODA

1. Open POHODA accounting software
2. Go to **File → Import → XML**
3. Select the exported XML file
4. Follow POHODA's import wizard to complete the import

## XML Structure

The export generates an XML file containing:

- **Invoice Header**: Order number, dates, guest information, payment type
- **Invoice Items**: Individual order items with product names, quantities, prices, VAT rates
- **Invoice Summary**: Total amounts

### VAT Rate Mapping

The system maps VAT rates to POHODA's standard rates:

- `0%` → `none`
- `12%` → `low`
- `21%` → `high`

### Payment Type Mapping

- Card payments → `card`
- Cash payments → `cash`

## Important Notes

- Only **paid orders** are available for export
- Orders with `status = "paid"` are included
- Deleted order items are automatically excluded from the export
- Each order includes the guest name as the partner/customer
- **Product names are retrieved from the current product data** - if a product is renamed or deleted after an order is created, the export will use the current product name or "Unknown Product"

## Troubleshooting

### No Orders Appear

- Verify that you have paid orders in the selected date range
- Check that orders have the status "paid" (not "open" or "partially_paid")

### Import Fails in POHODA

- Verify your ICO is correct in the configuration
- Check that your default account number exists in POHODA
- Ensure VAT rates match your POHODA setup (you may need to adjust the mapping)

### Customizing the Export

If you need to customize the XML format (different fields, additional data, etc.), you can modify the `CozyCheckout.Pohoda` module at:

`lib/cozy_checkout/pohoda.ex`

Key functions to modify:
- `order_to_xml/1` - Customizes the invoice header
- `order_item_to_xml/1` - Customizes individual line items
- `vat_rate_to_pohoda/1` - Adjusts VAT rate mapping
- `payment_type_to_pohoda/1` - Adjusts payment type mapping

## Technical Details

### Database Queries

The export uses optimized queries to:
1. Filter only paid orders
2. Preload all necessary associations (guest, order items, payments)
3. Exclude soft-deleted items
4. Sort by date

### Performance

The export is designed to handle:
- Large date ranges efficiently
- Hundreds of orders
- Multiple order items per order

## Support

For issues or questions about POHODA export:
1. Check POHODA's official documentation for XML import format
2. Verify your configuration settings
3. Review the generated XML file structure
4. Consult with your accountant about specific POHODA requirements

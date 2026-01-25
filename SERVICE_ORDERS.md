# Service Orders Feature

## Overview
Service orders are a special type of order used for owner consumption, friends, and other non-standard purchases. They are completely separate from standard orders and can be toggled via a switch in the POS system.

## Implementation Details

### Database Changes
- Added `is_service_order` boolean field to `orders` table (defaults to `false`)
- Created index on `is_service_order` for efficient filtering
- Migration: `20260125130329_add_is_service_order_to_orders.exs`

### Schema Updates
- Updated `CozyCheckout.Sales.Order` schema to include `is_service_order` field
- Added `is_service_order` to Flop filterable fields for admin filtering
- Updated changeset to handle the new field

### POS System Changes

#### Guest Selection Page (`/pos`)
- **Service Mode Toggle**: Added a toggle switch in the header that switches between "Standard" and "Service" modes
  - When enabled, shows only service orders (standalone orders with `is_service_order = true`)
  - When disabled, shows only standard orders (`is_service_order = false`)
- **Visual Styling**: 
  - Purple theme for service mode
  - Gray/disabled appearance for the inactive mode label
  - Smooth transitions and animations

#### Order Selection Page (`/pos/bookings/:id/orders`)
- Filters orders based on service mode passed via URL parameter
- Creates new orders with appropriate `is_service_order` flag based on mode

#### Order Management Page (`/pos/orders/:id`)
- **Service Order Badge**: Displays "Service Order" badge for service orders
- **Convert Button**: Shows "Convert to Standard/Service" button for unpaid orders
  - Only visible for unpaid orders
  - Toggles the order between service and standard types
  - Shows confirmation flash message on success

### Sales Context Functions

#### New/Updated Functions
- `toggle_service_order/1`: Toggles an order between service and standard mode
  - Returns `{:error, :cannot_convert_paid_order}` for paid orders
  - Updates the `is_service_order` field
  
- `get_or_create_booking_order/2`: Updated to accept `is_service_order` parameter
  - Filters existing orders by service mode
  - Creates new orders with correct service flag

- `create_booking_order_for_guest/3`: Updated to accept `is_service_order` parameter
  - Creates orders with appropriate service flag

### Filtering Behavior
When service mode is **ON**:
- Shows ONLY service orders (quick orders and booking orders with `is_service_order = true`)
- Hides all standard orders

When service mode is **OFF** (default):
- Shows ONLY standard orders (`is_service_order = false`)
- Hides all service orders

## User Experience

### Creating Service Orders
1. Navigate to POS (`/pos`)
2. Toggle the "Service" switch in the header
3. Create a quick order or select a booking
4. The order will be automatically marked as a service order

### Converting Existing Orders
1. Open an unpaid order in the order management page
2. Click "Convert to Service" or "Convert to Standard" button below the order number
3. The order type is immediately updated
4. A "Service Order" badge appears for service orders

### Restrictions
- **Cannot convert paid orders**: Once an order is paid, it cannot be converted between service and standard types
- **Separate filtering**: Service and standard orders are completely separated - you cannot see both at the same time in the POS

## Future Considerations
- Service orders are currently treated the same as standard orders in terms of pricing
- No special handling in receipts, Pohoda export, or reports (can be added later if needed)
- No permission restrictions (anyone can create/manage service orders)
- No conversion history tracking

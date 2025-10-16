# Point of Sale (POS) System

## Overview

The POS system is a touch-friendly interface designed for bar staff to quickly manage guest orders. It's optimized for iPad (11 inches and larger) and provides a fast, intuitive experience for day-to-day operations.

## Access

The POS system is accessible at `/pos` and is completely separate from the admin dashboard.

From the main dashboard, click the "🍹 POS System" card to access it.

## User Workflow

### 1. Guest Selection (`/pos`)
- **Large Touch Cards**: Each active guest is displayed as a large, tappable card
- **Guest Information**: Shows guest name, room number, and check-in period
- **Order Badge**: Displays the number of open orders for each guest
- **Auto-Navigation**: 
  - If guest has no orders → automatically creates new order
  - If guest has 1 order → opens that order directly
  - If guest has multiple orders → shows order selection screen

### 2. Order Selection (`/pos/guests/:guest_id/orders`)
- Only shown when a guest has multiple open orders
- Displays all open orders with:
  - Order number
  - Item count
  - Total amount
  - Payment status
- Option to create a new order
- Back button to return to guest selection

### 3. Order Management (`/pos/orders/:id`)

#### Layout
The screen is split into two main sections:

**Left Side - Product Selection**
- **Category Tabs**: Quick filter by category or view popular products
- **Product Grid**: Large, tappable product cards (60x60px minimum)
- **Popular Products**: First tab shows most-ordered items across all orders
- **One-Tap Add**: Single tap to add item to order

**Right Side - Order Cart**
- **Fixed Position**: Always visible during scrolling
- **Current Order Summary**: Shows item count and guest info
- **Cart Items**: Listed with product name, quantity, and price
- **Swipe to Delete**: Swipe left on any item to remove it
- **Order Total**: Prominent display at the bottom
- **Touch-Friendly**: All buttons and targets are minimum 44x44px

#### Features
- ✅ **Real-time Updates**: Cart updates immediately when items are added
- ✅ **Success Feedback**: Visual confirmation when item is added
- ✅ **Swipe Gestures**: Natural iOS-style swipe-to-delete for cart items
- ✅ **Category Filtering**: Quick access to products by category
- ✅ **Popular Products**: Most frequently ordered items shown first
- ✅ **Automatic Calculations**: Prices and totals calculated from active pricelists
- ✅ **Smooth Animations**: Professional transitions and feedback
- ✅ **Unit Amount Selection**: For products with units (ml, L, etc.), a modal appears allowing staff to:
  - Select from preset amounts (from `default_unit_amounts`)
  - Enter custom amounts
  - Large touch-friendly buttons for quick selection
- ✅ **Smart Display**: Cart items show unit amounts clearly (e.g., "500ml × 1")

## Technical Implementation

### New Files Created

#### LiveViews
- `lib/cozy_checkout_web/live/pos_live/guest_selection.ex` - Guest selection screen
- `lib/cozy_checkout_web/live/pos_live/order_selection.ex` - Multiple order selection
- `lib/cozy_checkout_web/live/pos_live/order_management.ex` - Main order interface

#### Templates
- `lib/cozy_checkout_web/live/pos_live/guest_selection.html.heex`
- `lib/cozy_checkout_web/live/pos_live/order_selection.html.heex`
- `lib/cozy_checkout_web/live/pos_live/order_management.html.heex`

#### Context Functions (Added to `Sales`)
- `list_active_guests_with_orders/0` - Get active guests with order counts
- `get_or_create_guest_order/1` - Smart order retrieval/creation
- `get_popular_products/1` - Get most frequently ordered products

#### JavaScript Hooks
- `SwipeToDelete` hook in `assets/js/app.js` - Touch swipe gesture handling
- `UnitAmountSelector` hook in `assets/js/app.js` - Quick amount button handling

#### Layouts
- `Layouts.pos/1` - Minimal layout for POS interface (no navigation chrome)

#### Routes
```elixir
scope "/pos", CozyCheckoutWeb.PosLive do
  live "/", GuestSelection
  live "/guests/:guest_id/orders", OrderSelection
  live "/orders/:id", OrderManagement
end
```

### Design Principles

#### Touch-Friendly
- All interactive elements are minimum 44x44px (recommended 60x60px)
- Large, clear typography
- Generous padding and spacing
- No hover states (touch-first design)

#### Performance
- Minimal LiveView state
- Efficient queries with preloading
- Smooth animations (CSS transitions)
- Debounced interactions

#### Accessibility
- Clear visual hierarchy
- High contrast colors
- Large touch targets
- Semantic HTML

#### Mobile-First
- Responsive grid layouts
- Touch gesture support (swipe-to-delete)
- Optimized for tablets (iPad 11"+)
- Native-feeling interactions

## Future Enhancements

Potential improvements for future versions:

- [ ] Search/filter guests by name or room
- [ ] Barcode scanner integration for products
- [ ] Offline support with sync
- [ ] Quick quantity adjustment (long-press for +5, +10)
- [ ] Order notes/special instructions
- [ ] Split bill functionality
- [ ] Print receipt integration
- [ ] Staff login/authentication
- [ ] Shift tracking and reporting
- [ ] Inventory warnings on low stock
- [ ] Customer favorites/preferences

## Testing Checklist

- [ ] Select guest with no orders (creates new order)
- [ ] Select guest with one order (opens that order)
- [ ] Select guest with multiple orders (shows selection screen)
- [ ] Add products from popular tab
- [ ] Filter products by category
- [ ] Add multiple items to cart
- [ ] Add product with unit (modal appears)
- [ ] Select preset unit amount from quick buttons
- [ ] Enter custom unit amount
- [ ] Verify unit amounts display in cart (e.g., "500ml × 1")
- [ ] Swipe to delete item from cart
- [ ] Tap delete button on item
- [ ] View order total updates in real-time
- [ ] Navigate back to guest selection
- [ ] Test on iPad 11" or larger tablet
- [ ] Test touch gestures (tap, swipe)
- [ ] Verify order totals are calculated correctly
- [ ] Confirm prices come from active pricelists
- [ ] Confirm unit amounts are stored in order_items

## Best Practices

### For Bar Staff
1. Always verify the guest name before adding items
2. Use the popular products tab for frequently ordered items
3. Swipe items to remove them quickly
4. Check the total before leaving the order screen
5. Return to guest selection when finished

### For Administrators
1. Keep categories organized and logically grouped
2. Ensure pricelists are active and up-to-date
3. Monitor popular products to optimize menu layout
4. Train staff on swipe gestures for efficiency
5. Regularly check orders for completeness

## Troubleshooting

**Problem**: Can't find a guest
- **Solution**: Check if guest is checked in (requires check-in date to be active)

**Problem**: Product prices showing as $0
- **Solution**: Ensure active pricelist exists for that product

**Problem**: Swipe gesture not working
- **Solution**: Ensure you're using a touch-enabled device; mouse doesn't support swipe

**Problem**: Order total not updating
- **Solution**: Refresh the page; recalculation happens on item add/remove

## Architecture Notes

The POS system is designed to be completely independent from the admin interface:
- Separate route namespace (`/pos`)
- Custom minimal layout (no admin navigation)
- Optimized queries for speed
- Touch-first interaction patterns
- No complex forms or text input

This separation allows the admin interface to remain full-featured while keeping the POS system fast and simple for staff use.

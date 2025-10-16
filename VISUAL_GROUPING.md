# Visual Grouping Feature

## Overview

Order items with the same product and unit amount are visually grouped in both the POS system and admin CRUD interfaces to provide a cleaner, more intuitive display while maintaining data integrity.

## Architecture Decision

### Approach: Visual Grouping (Database Unchanged)

We chose to implement **visual grouping** rather than database merging for the following reasons:

#### Advantages
- ✅ **Audit Trail**: Each item addition remains as a separate database record
- ✅ **Historical Context**: Can track when items were added over time
- ✅ **Reporting**: Better insights into ordering patterns
- ✅ **Data Integrity**: No risk of data loss during updates
- ✅ **Simplicity**: Easier to implement and maintain
- ✅ **Flexibility**: Staff can still view and manage individual items

#### How It Works
1. **Database**: Individual `order_items` records are created for each product addition
2. **Display**: Items are grouped by `(product_id, unit_amount)` for UI presentation
3. **Interaction**: Users see grouped totals but can expand to view/manage individual items

## Implementation

### Core Module

`CozyCheckoutWeb.OrderItemGrouper` provides the grouping logic:

```elixir
# Group items for display
grouped_items = OrderItemGrouper.group_order_items(order.order_items)

# Each group contains:
%{
  product: %Product{},           # The product struct
  unit_amount: Decimal.t(),      # Unit amount (if applicable)
  total_quantity: Decimal.t(),   # Sum of all quantities
  total_price: Decimal.t(),      # Sum of all prices
  item_ids: [binary()],          # List of order_item IDs
  items: [%OrderItem{}],         # List of actual order_items
  grouped?: boolean(),           # True if multiple items
  expanded?: boolean()           # Current expansion state
}
```

### Functions

- `group_order_items/1` - Groups items by product and unit amount
- `expand_group/3` - Shows individual items within a group
- `collapse_group/3` - Hides individual items within a group

## User Interface

### POS System (`/pos/orders/:id`)

**Collapsed Group Display:**
```
┌─────────────────────────────────────┐
│ Beer                                │
│ 500ml × 3            [2 items] $15  │
│ ▼ Show 2 individual items           │
└─────────────────────────────────────┘
```

**Expanded Group Display:**
```
┌─────────────────────────────────────┐
│ Beer                                │
│ 500ml × 3            [2 items] $15  │
│ ▲ Hide individual items             │
├─────────────────────────────────────┤
│   1 × 500ml                    $5   │×
│   2 × 500ml                   $10   │×
└─────────────────────────────────────┘
```

**Features:**
- Swipe left on individual items to delete (when expanded)
- Tap "×" button to delete individual items (when expanded)
- Tap expand/collapse to show/hide individual items
- Blue badge shows item count in group
- **Group deletion is disabled** for safety - staff must delete items individually

### Admin CRUD (`/orders/:id` and `/orders/:id/edit`)

Similar display with:
- Expand/collapse buttons for grouped items
- Individual delete buttons when expanded
- Group delete button (with confirmation for multiple items)
- Visual badge indicating number of items in group

## Benefits for Staff

### Bar Staff (POS)
1. **Cleaner Cart**: Easier to scan what's in the order
2. **Quick Actions**: One swipe/tap to remove all of a product
3. **Flexibility**: Can still manage individual items if needed
4. **Clear Totals**: See aggregated quantities at a glance

### Admin Staff
1. **Better Overview**: See what was ordered without clutter
2. **Audit Capability**: Expand to see individual additions
3. **Reporting**: Database maintains full detail for reports
4. **Data Integrity**: No loss of information

## Database Schema

Order items table remains unchanged:

```sql
CREATE TABLE order_items (
  id UUID PRIMARY KEY,
  order_id UUID NOT NULL,
  product_id UUID NOT NULL,
  quantity DECIMAL NOT NULL,
  unit_amount DECIMAL,          -- e.g., 500 for 500ml
  unit_price DECIMAL NOT NULL,
  vat_rate DECIMAL NOT NULL,
  subtotal DECIMAL NOT NULL,
  deleted_at TIMESTAMP,
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

**Example Data:**
```
| id   | product_id | quantity | unit_amount | subtotal |
|------|------------|----------|-------------|----------|
| 1    | beer-123   | 1        | 500         | $5       |
| 2    | beer-123   | 2        | 500         | $10      |
| 3    | beer-123   | 1        | 1000        | $8       |
```

**Display Result:**
- Group 1: "Beer - 500ml × 3" ($15) - 2 items
- Group 2: "Beer - 1000ml × 1" ($8) - 1 item

## Future Considerations

If staff feedback indicates a preference for database merging, we could:

1. Add a `merge_order_items/2` function to Sales context
2. Optionally merge on specific actions (e.g., "Finalize Order" button)
3. Keep audit log in separate `order_item_history` table

However, the current approach provides excellent UX while maintaining data integrity and flexibility.

## Testing

See `POS_SYSTEM.md` for comprehensive testing checklist including:
- Adding same product multiple times
- Verifying grouping behavior
- Testing expand/collapse functionality
- Deleting individual vs. grouped items
- Admin interface grouping display

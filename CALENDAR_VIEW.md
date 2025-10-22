# Booking Calendar View Implementation

## Overview

A pure Elixir/Phoenix LiveView calendar implementation for viewing bookings without JavaScript dependencies. The calendar provides an intuitive month view with navigation and booking details.

## Features

- **Monthly Calendar View**: Displays bookings in a traditional month-grid format
- **Navigation**: Previous/Next month buttons and "Today" quick navigation
- **Color-Coded Status**: Visual indicators for booking status (upcoming, active, completed, cancelled)
- **Booking Details**: Shows guest name and room number for each booking
- **Click-through**: Click on any booking to view details
- **Overflow Handling**: Shows first 3 bookings per day with "+X more" indicator
- **Today Highlighting**: Current date is highlighted with a blue circle
- **Pure Elixir**: No JavaScript dependencies, fully server-rendered

## Implementation Details

### Files Created

1. **`lib/cozy_checkout/bookings.ex`** (updated)
   - Added `list_bookings_for_month/2` - Fetches bookings for a specific month
   - Added `list_bookings_for_date_range/2` - Fetches bookings for a date range
   - Smart query logic to include bookings that span across month boundaries

2. **`lib/cozy_checkout_web/live/booking_live/calendar_helpers.ex`**
   - `generate_calendar_grid/2` - Creates 7-day week grid starting Monday
   - `month_name/1` - Returns month name from month number
   - `day_name/1` - Returns short day name (Mon, Tue, etc.)
   - `bookings_for_date/2` - Filters bookings overlapping a specific date
   - `date_in_range?/3` - Checks if date falls within booking range
   - `previous_month/2` & `next_month/2` - Navigation helpers
   - `today?/1` - Checks if date is today

3. **`lib/cozy_checkout_web/live/booking_live/calendar.ex`**
   - LiveView module with navigation event handlers
   - `day_cell/1` - Private function component for rendering individual day cells
   - `status_color/1` - Maps booking status to Tailwind CSS classes

4. **`lib/cozy_checkout_web/live/booking_live/calendar.html.heex`**
   - Responsive calendar grid layout
   - Day headers (Mon-Sun)
   - Calendar navigation UI
   - Legend for status colors

### Routes Added

```elixir
# In router.ex
live "/admin/bookings/calendar", BookingLive.Calendar
```

### Navigation Links Added

- **Bookings Index**: Added "Calendar View" button
- **Calendar View**: Added "List View" button
- **Admin Dashboard**: Added "Calendar" card

## Design Choices

### Pure Elixir Implementation

Following project guidelines, the calendar is implemented entirely in Elixir/Phoenix LiveView:
- No JavaScript libraries required
- Server-rendered for reliability
- LiveView handles all interactivity
- Tailwind CSS for styling

### Calendar Grid Logic

The grid starts on Monday and includes partial weeks:
- First week may include days from previous month (shown as empty)
- Last week may include days from next month (shown as empty)
- This provides a complete 4-6 week grid for consistency

### Booking Overlap Detection

The query in `list_bookings_for_month/2` correctly handles bookings that:
- Start within the month
- End within the month
- Span across the entire month (check-in before, check-out after)

### Performance Considerations

- Single database query per month
- Bookings filtered in-memory per day
- Limited to 3 bookings shown per cell to prevent UI crowding
- Efficient date range queries with proper indexes

## Usage

Navigate to:
- **From Admin Dashboard**: Click "Calendar" card
- **From Bookings List**: Click "Calendar View" button
- **Direct URL**: `/admin/bookings/calendar`

## Color Legend

- **Blue** (bg-blue-100): Upcoming bookings
- **Green** (bg-green-100): Active bookings (currently checked in)
- **Gray** (bg-gray-100): Completed bookings (checked out)
- **Red** (bg-red-100): Cancelled bookings

## Future Enhancements (Optional)

- Week view option
- Day view with hourly breakdown
- Drag-and-drop booking rescheduling
- Multi-room view (rows per room)
- Export calendar to PDF
- iCal feed integration for external calendars
- Filtering by status or room
- Search/filter guests

## Best Practices Followed

✅ Pure Elixir/LiveView (no JS libraries)
✅ Tailwind CSS for styling
✅ Proper Phoenix 1.8 patterns
✅ Efficient database queries
✅ Responsive design
✅ Accessibility considerations
✅ Clean code organization
✅ Proper error handling
✅ Documentation

## Testing

To test the calendar:

1. Start the server: `mix phx.server`
2. Navigate to: `http://localhost:4000/admin/bookings/calendar`
3. Test navigation: Click prev/next month buttons
4. Test today button: Jump to current month
5. Test booking links: Click on any booking to view details
6. Verify color coding matches booking status
7. Check responsiveness on different screen sizes

## Database Schema

The calendar relies on the `bookings` table:

```sql
CREATE TABLE bookings (
  id UUID PRIMARY KEY,
  guest_id UUID REFERENCES guests(id),
  check_in_date DATE NOT NULL,
  check_out_date DATE,
  status VARCHAR (upcoming|active|completed|cancelled),
  room_number VARCHAR,
  notes TEXT,
  deleted_at TIMESTAMP,
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- Indexes used by calendar queries
CREATE INDEX ON bookings(check_in_date);
CREATE INDEX ON bookings(check_out_date);
CREATE INDEX ON bookings(deleted_at);
```

## Notes

- The calendar uses Monday as the first day of the week (standard in Europe)
- Empty cells for days outside current month prevent visual clutter
- Bookings without check-out dates are assumed to continue indefinitely
- The "today" indicator uses UTC date for consistency

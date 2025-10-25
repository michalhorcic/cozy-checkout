---
description: AI rules derived by SpecStory from the project AI interaction history
globs: *
---

---
description: AI rules derived by SpecStory from the project AI interaction history
---

## PROJECT RULES & CODING STANDARDS

*   When designing databases, implement soft deletes using a `deleted_at` column of type `:utc_datetime` and create an index on this column. When setting the `deleted_at` timestamp, use `DateTime.truncate(utc_datetime, :second)` (available in Elixir v1.6+) to remove microseconds.
*   Capture the price and VAT rate at the time of purchase in the `order_items` table to ensure accurate historical records.
*   Ensure all tables include `inserted_at` and `updated_at` timestamps.
*   When creating a database table, every table with soft deletes should also have an index on the `deleted_at` column.
*   When designing a database related to financial transactions, capture the VAT rate at the time of purchase to ensure accurate historical records.
*   When creating a database table, use `binary_id` for primary key and foreign key columns.
*   When creating a database table, create unique index for columns with unique values.
*   When creating a database table, name indexes for foreign keys according to `[:column_name]` convention.
*   When creating products, include a `unit` field (e.g., "ml", "L", "pcs") to indicate what type of measurement they use. This field should be nullable.
*   Add `unit_amount` (decimal) to `order_items` to store the size of each unit (e.g., 500 for 0.5L).
*   Products should have a `default_unit_amounts` (text/jsonb, nullable) field for optional preset amounts like [300, 500, 1000].
*   When implementing soft delete functions, always use `DateTime.truncate(utc_datetime, :second)` to remove microseconds to ensure compatibility with the `:utc_datetime` field type in Ecto.
*   When displaying order items in the POS system and admin CRUD interfaces, group items visually by product and unit amount. The database should maintain individual `order_items` records. Allow staff to expand the grouped items to view and delete individual items. Group deletion is disabled in the POS system; only individual item deletion is allowed.
*   Make the currency configurable and default to CZK. The currency configuration should be kept in code.
*   **Always** use the `format_currency/1` helper function from `CozyCheckoutWeb.CurrencyHelper` to format currency values in templates and LiveViews. **Never** hardcode currency symbols like `$` or `€` directly in templates.
*   The currency symbol is configured in `CozyCheckoutWeb.CurrencyHelper` (default: "CZK"). To change the currency, modify the `@currency_symbol` module attribute in that file.
*   Separate the `guests` table into two tables: one for `guests` (as persons who may visit the cottage multiple times) and another for `bookings` (actual stays at the cottage). Link payments to both the `bookings` table and to the `guest` table.
*   The `guests` table should have the following columns:
    *   `id` (binary_id, primary key)
    *   `name` (string, required)
    *   `email` (string, nullable, unique)
    *   `phone` (string, nullable)
    *   `notes` (text, nullable) - preferences, allergies, etc.
    *   `inserted_at`, `updated_at`
    *   `deleted_at` (soft delete)
*   The `bookings` table (Stays/Visits) should have the following columns:
    *   `id` (binary_id, primary key)
    *   `guest_id` (binary_id, foreign key → guests)
    *   `room_number` (string, nullable)
    *   `check_in_date` (date, required)
    *   `check_out_date` (date, nullable)
    *   `status` (string: "upcoming", "active", "completed", "cancelled")
    *   `notes` (text, nullable) - stay-specific notes
    *   `inserted_at`, `updated_at`
    *   `deleted_at` (soft delete)
*   The `orders` table should:
    *   Keep `guest_id` for quick reference, but make it nullable.
    *   Add `booking_id` (binary_id, foreign key → bookings), but make it nullable.
    *   Add `name` field (string, nullable).
    *   This way orders are linked to both the guest AND the specific stay
*   The `payments` table should remain linked to orders (which are already linked to bookings).
*   Add a `bookings.status` field to distinguish:
    *   `"upcoming"` - future bookings
    *   `"active"` - currently checked in
    *   `"completed"` - checked out
    *   `"cancelled"` - cancelled bookings
*   Consider adding to guests table:
    *   `preferred_payment_method` (string, nullable)
    *   `loyalty_tier` (string, nullable) - for future loyalty programs
    *   `total_stays` (integer, default 0) - cached count
*   Add unique index on `(guest_id, check_in_date)` to prevent double bookings
*   Implement the ability to import bookings from iCal files (.ics). The import process should:
    *   Parse the iCal file to extract guest names, dates, contact info, and notes from each VEVENT.
    *   Create or find guests, matching by name/email, or creating new guests if no match is found.
    *   Create bookings with the extracted information.
*   In the POS order management, when creating a new order, show a modal:
    *   "Who is this order for?"
    *   Quick buttons: "Main Guest", "Partner", "Kids", "Other"
    *   Text input for custom name
*   Display the order name in the order selection screen (e.g., "📋 Order #001 (Dad) - $25.50").
*   Implement a `booking_guests` join table to track all people in a booking:
    *   `id` (binary_id, primary key)
    *   `booking_id` (binary_id, foreign key → bookings, on_delete: :delete_all)
    *   `guest_id` (binary_id, foreign key → guests, on_delete: :delete_all)
    *   `is_primary` (boolean, default: false) - indicates the primary guest who pays for accommodation.
    *   `inserted_at`, `updated_at`
*   When creating a booking, a `booking_guest` record must be automatically created for the primary guest (the person paying for accommodation). The `is_primary` field should be set to `true`.
*   Users should be able to add more guests to every booking via a separate "Manage Guests" section in the admin area.
*   When adding additional guests to a booking, the system should allow selecting from existing guests in the database or creating new guests on the fly.
*   In the booking list/calendar view, only the primary guest should be shown for now.
*   Users should be able to remove additional guests from a booking, but not the primary guest.
*   Add a `rooms` table with the following columns:
    *   `id` (binary_id, primary key)
    *   `room_number` (string, required, unique)
    *   `name` (string, nullable)
    *   `description` (text, nullable)
    *   `capacity` (integer, required)
    *   `inserted_at`, `updated_at`
    *   `deleted_at` (soft delete)
*   Add a `booking_rooms` join table to track rooms associated with each booking:
    *   `id` (binary_id, primary key)
    *   `booking_id` (binary_id, foreign key → bookings, on_delete: :delete_all)
    *   `room_id` (binary_id, foreign key → rooms, on_delete: :delete_all)
    *   `inserted_at`, `updated_at`
*   The system should prevent double-booking the same room for overlapping dates.
*   The system should enforce that the number of guests in a booking doesn't exceed the total capacity of all booked rooms.
*   Rooms will have different prices, and pricing will be handled per room.
*   Room management should appear in the admin section for CRUD operations.
*   During booking creation/editing, staff should select rooms via a modal. There will be just 13 rooms in our case.
*   In the calendar view and booking list, show the specific room numbers that are booked.
*   If a room's details (name, capacity) change, bookings should retain the room information as it was at booking time.
*   Create a `booking_invoices` table to store the invoicing details. The table should have the following columns:
    *   `id` (binary_id, primary key)
    *   `booking_id` (binary_id, foreign key → bookings, on_delete: :delete_all), null: false
    *   `adult_count` (integer, required)
    *   `kids_under_2_count` (integer, default: 0)
    *   `kids_under_12_count` (integer, default: 0)
    *   `price_per_adult_per_night` (decimal, precision: 10, scale: 2, null: false)
    *   `price_per_kid_under_2_per_night` (decimal, precision: 10, scale: 2, default: 0)
    *   `price_per_kid_under_12_per_night` (decimal, precision: 10, scale: 2, null: false)
    *   `vat_rate` (decimal, precision: 5, scale: 2, null: false)
    *   `subtotal` (decimal, precision: 10, scale: 2, nullable: true) # Calculated/cached
    *   `vat_amount` (decimal, precision: 10, scale: 2, nullable: true) # Calculated/cached
    *   `total_price` (decimal, precision: 10, scale: 2, nullable: true) # Calculated/cached
    *   `invoice_number` (string, nullable, unique)
    *   `invoice_generated_at` (:utc_datetime, nullable)
    *   `inserted_at`, `updated_at`
*   Add unique index on `booking_invoices` table for `booking_id` column.
*   Add unique index on `booking_invoices` table for `invoice_number` column.
*   The invoicing system should have:
    *   A `booking_invoice` table that acts as a "header" (stores invoice_number, invoice_generated_at, cached totals).
    *   A `booking_invoice_items` table that stores individual line items (name, quantity, price_per_night, vat_rate).
    *   A `quantity` field for each line item.
    *   Automatically create default line items (Adults, Kids under 2, Kids under 12) that can be edited/removed when creating an invoice for a booking.
    *   Per-item VAT for flexibility (in case you add extras with different rates).
    *   Cache the total on the `booking_invoice` header.
*   The quantity field in `booking_invoice_items` must allow zero values.
*   Add `item_type` (string, default: "person", null: false) to the `booking_invoice_items` table, and create an index on this column. The `item_type` field should be validated to be either "person" or "extra".
*   When calculating occupancy, use the `booking_invoice_items` table and filter by `item_type = "person"` to count the number of people booked for a given date.
*   The cottage capacity is 45 people. This value is hardcoded in the `CozyCheckout.Bookings` module.
*   When displaying the calendar view, show the total number of booked people for each day, color-coded against the capacity limit.
    *   🟢 Green (0-29): Plenty of space
    *   🟡 Yellow (30-39): Getting full
    *   🟠 Orange (40-44): Almost full
    *   🔴 Red (45+): At/over capacity
*   When displaying numbers in invoice items, use proper formatting, including thousand separators.
*   Ensure that numbers in invoice items do not wrap. The booking form may need to be wider to accommodate this.
*   After creating a new booking in the admin section, redirect to the booking detail page (`/admin/bookings/:id`) instead of the booking index page. Use `push_navigate` for this redirect.
*   **When implementing sorting, pagination, and filtering in admin tables:** Attempt to use the Flop library, creating reusable table components for filtering, sorting, and pagination, keeping the business logic separate from the UI, and making it easily reusable for other tables. However, due to version incompatibilities, it may be necessary to implement Flop without `flop_phoenix`, building the table components manually. If `flop_phoenix` can't be used, ensure that the filter parameters are properly encoded in the URL. If errors occur due to nil values, add guards to handle empty results.
*   Orders can be created without a booking or guest, using an "order name" to identify the order. This provides flexibility when bookings are made for only one person, and there's no need to add all guests to the system. These standalone orders must be payable via the POS system.
*   In the `orders` table, `guest_id` and `booking_id` are nullable to support standalone orders.
*   The `name` field is the primary identifier for standalone orders. Examples include:
    *   "Kids - Room 5"
    *   "Staff order"
    *   "Walk-in customer"
*   Orders must have either a `guest_id` OR a `name`.
*   When implementing product selection in pricelists, use a modern autocomplete search component with the following features:
    *   Real-time filtering with a debounce of 300ms.
    *   Search by product name or category name.
    *   Limit results to 10 items.
    *   Display selected product as a card with a check icon, product name, category name, and clear button.
    *   Use a dropdown for results, showing product name, category, and unit badge.
    *   Implement proper state management for products, filtered results, selected product, and search query.
    *   Utilize daisyUI components for styling.
    *   Ensure the component is responsive and accessible.
    *   Initially display at least 20 products even without search.
    *   Ensure the component is responsive and accessible.
*   When using `phx-change` on an input, the input element needs a `name` attribute for `phx-change` to work properly.

## TECH STACK

*   Ecto (with Elixir) for database interactions and migrations.
*   daisyUI (with Phoenix 1.8) for UI components.
*   `qr_code` Elixir library (version 3.2.0) for generating QR codes.
*   Flop - for sorting, filtering and pagination.

## PROJECT DOCUMENTATION & CONTEXT SYSTEM
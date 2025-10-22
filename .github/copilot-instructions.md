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
    *   Keep `guest_id` for quick reference
    *   Add `booking_id` (binary_id, foreign key → bookings)
    *   Add `order_name` field (string, nullable).
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
*   ~~When creating new bookings in the admin section, implement a guest autocomplete feature:
    *   The autocomplete should search guests by name and email.
    *   Autocomplete suggestions should appear after typing a minimum of 3 characters.
    *   When a user types a name that doesn't match any existing guest, show a "+ Create new guest: [name]" option that opens a modal to create the guest with additional details (email, phone, notes).
    *   Guests should appear in the autocomplete dropdown with their name and email: "John Doe (john@example.com)".
    *   Show a maximum of 10 guest suggestions at once.
    *   The autocomplete should be inline in the booking form, replacing the current select dropdown.
    *   Use `phx-debounce="300"` on the search input to avoid excessive server calls.
    *   Display selected guest as a removable badge below the search input.
    *   Use `phx-click-away` to hide the suggestions dropdown when clicking outside.~~
*   When creating new bookings in the admin section, implement a guest autocomplete feature:
    *   The autocomplete should search guests by name, email, and phone.
    *   Autocomplete suggestions should appear after typing a minimum of 2-3 characters.
    *   When a user types a name that doesn't match any existing guest, show a "+ Create new guest: [name]" option that opens a modal/form to create the guest with additional details (email, phone, notes).
    *   Guests should appear in the autocomplete dropdown with their name and email: "John Doe (john@example.com)".
    *   Show a maximum of 5-10 guest suggestions at once.
    *   The autocomplete should be inline in the booking form, replacing the current select dropdown.

## TECH STACK

*   Ecto (with Elixir) for database interactions and migrations.
*   daisyUI (with Phoenix 1.8) for UI components.
*   `qr_code` Elixir library (version 3.2.0) for generating QR codes.

## PROJECT DOCUMENTATION & CONTEXT SYSTEM

## WORKFLOW & RELEASE RULES

*   When building CRUD interfaces, create full CRUD for all tables.
*   When building an application with multiple sections, create a main menu to access all sections.
*   When building order management systems, ensure the ability to edit orders after creation, including adding new items.
*   For day-to-day staff order management, create a separate, touch-friendly Point of Sale (POS) interface, distinct from the admin dashboard. This POS interface should prioritize simplicity and speed of use, and should be created from scratch, not using existing liveviews. The POS interface should be accessible via a separate route, specifically `/pos`.
*   The POS interface should:
    *   Utilize large touch targets (minimum 44x44px, ideally 60x60px for buttons).
    *   Minimize text input, using buttons and taps wherever possible.
    *   Provide clear visual feedback for all actions (loading states, success confirmations).
    *   Include a product grid with category filters for fast access.
    *   Include a floating cart summary that is always visible, showing the current order total.
    *   Utilize swipe gestures to remove items.
    *   Utilize clear color coding (green for success, red for remove, etc.).
    *   Display popular products across all orders for quick access.
    *   Display a list of open orders to choose from if a guest has multiple open orders.
    *   Automatically create a new order when the first item is added for a guest with no existing open orders.
    *   Target iPad 11 inches size and bigger.
    *   When adding products with a `unit` field to orders in the POS interface, provide a modal allowing staff to select from `default_unit_amounts` or enter a custom amount.
    *   When adding items with a `unit` field to an order in the POS interface, when a user clicks on a chosen amount, the item is immediately added to the order without requiring a separate "Add Item" button click. The quick add buttons should be visually distinct (green) and labeled clearly in the modal as "Quick Add". Custom amounts can still be entered, requiring a separate "Add Custom" button click.
    *   When displaying Guest cards in the POS view, use a more compact layout to display more cards at once. Use the following styles:
        *   Grid layout: `grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6`
        *   Card size: Reduced padding from `p-8` to `p-4`, reduced min-height from `180px` to `120px`, reduced gap between cards from `gap-6` to `gap-3`, reduced border from `border-4` to `border-2`, changed border radius from `rounded-2xl` to `rounded-xl`.
        *   Typography & spacing: Guest name: `text-2xl mb-3` → `text-lg mb-2`, Room info: `text-lg gap-2 mb-2` → `text-sm gap-1.5 mb-1.5`, Icons: Reduced from `w-5 h-5` to `w-4 h-4` (and `w-3.5 h-3.5` for calendar), Check-in dates: `text-sm` → `text-xs`, Badge: Reduced padding and font sizes.
        *   Header: Made slightly smaller (`text-4xl` → `text-3xl`, `text-lg` → `text-base`), Reduced bottom margin from `mb-8` to `mb-4`.
*   Implement functionality to export paid orders into POHODA accounting software, generating POHODA-compatible XML files.
    *   The XML format should follow POHODA's standard for issued invoices. VAT rates, payment types and account numbers may need adjustment.
    *   ICO and default account should be configurable in `config.exs`.
*   Implement the ability to pay for orders directly within the POS system, supporting two payment methods:
    *   Cash: Creates a payment record directly.
    *   QR Code: Creates a payment record and displays a QR code containing relevant order details. The `invoice_number` must be included in the payment table and embedded within the QR code. The QR code should be generated using the `qr_code` Elixir library. Use `QRCode.render/2` to generate the QR code struct, then use `QRCode.to_base64/1` on the result to get the base64-encoded SVG.
        *   When generating the QR code, ensure that the ACC field contains the account number in IBAN format. Czech banking apps require valid IBAN format in the ACC field. The IBAN check digits must be correctly calculated using the mod-97 algorithm.
    *   The invoice number should follow the format `PAY-YYYYMMDD-NNNN` (e.g., `PAY-20251016-0001`), auto-incrementing per day. A unique constraint should be added to the database to prevent duplicates.
    *   The bank account for QR code payments should be configurable in `config.exs`.
    *   The ACC field in the QR code data must contain the account number in IBAN format.
*   Implement a main menu to switch between the POS and admin sections of the application. The admin dashboard should be located under the `/admin` route. The navigation card to the POS system should be removed from the current dashboard and placed within the admin route. Add a "Back to Menu" link to the POS guest selection page.
*   **All routes for admin CRUD interfaces must be prefixed with `/admin`.** This includes routes for creating, editing, and viewing guests, categories, and other admin-managed resources. When separating the admin and POS sections, ensure all routes are updated accordingly.
*   In the admin section, order editing and deletion should be disabled for paid orders. Paid orders serve as immutable historical records for accounting purposes and should not be modified or deleted.
*   Ensure that partially paid orders can be paid from the POS view. By default, the whole remaining amount will be selected, but staff must be able to choose which amount will be paid. Partially paid orders must also be able to receive additional payments.
*   Ensure that all orders without payments have `open` status in the seeds file.
*   When populating the seeds file, the `payment_method` field in the `payments` table should use strings (`"cash"`, `"qr_code"`) instead of atoms (`:cash`, `:qr_code`).
*   In the seeds file, all orders should be either fully paid with one payment or have `"open"` status. Partially paid orders should not be created in the seeds file.
*   Create full CRUD for `bookings` in the admin section.
*   When implementing the calendar view for bookings:
    *   Prioritize pure Elixir/LiveView implementation to avoid JavaScript dependencies.
    *   Utilize Tailwind CSS for styling.
    *   Create a new context function to get bookings for a specific month.
    *   Create a calendar LiveView component.
    *   Create calendar helper functions to generate the calendar grid.
*   When implementing the calendar view, ensure the templates don't use the `<Layouts.app>` wrapper, mirroring the structure of other LiveView templates.
*   Add an option to change the daisyUI theme from dark to light in the top part of the system.
*   When displaying the "Manage Guests" button on the booking show page, use a properly styled link with Tailwind classes directly for a consistent look:
    *   Purple background (`bg-purple-600`)
    *   Darker purple on hover (`hover:bg-purple-700`)
    *   White text
    *   Proper padding, rounded corners, and shadow
    *   Smooth transition effect
*   When adding rooms to the system:
    *   Create a `rooms` table with soft deletes.
    *   Create a `booking_rooms` join table to link bookings to rooms.
    *   Add validation to prevent double-booking the same room for overlapping dates.
    *   Create full CRUD for rooms in the admin section.
    *   Add room selection (multi-select) during booking creation/editing via a modal. There will be just 13 rooms in our case.
    *   In the calendar view, don't show specific room numbers for now.
    *   Show current room details. No need to track room details historically.
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
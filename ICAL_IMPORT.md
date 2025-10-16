# iCal Import Feature

## Overview
The system can now import bookings from iCal (.ics) files. This feature automatically creates guests and bookings from calendar entries.

## Features
- ✅ Parse iCal VEVENT entries
- ✅ Extract guest information (name, email, phone, notes)
- ✅ Create new guests or find existing ones by email/name
- ✅ Create bookings with proper status mapping
- ✅ Handle duplicate bookings (skips existing bookings for same guest + check-in date)
- ✅ Drag-and-drop file upload interface
- ✅ Detailed import statistics and error reporting

## How to Use

1. Navigate to the Admin Dashboard at http://localhost:4000/admin
2. Click on "Import Bookings" card
3. Upload an iCal (.ics) file by:
   - Clicking "Upload a file" and selecting a file, or
   - Dragging and dropping the file into the upload area
4. Click "Import Bookings" button
5. Review the import results showing:
   - Guests created
   - Guests found (existing)
   - Bookings created
   - Bookings skipped (duplicates)
   - Any errors encountered

## Data Mapping

### From iCal to Guest
- `SUMMARY` → Guest name
- `Description` field `Email:` → Guest email
- `Description` field `Telefon:` → Guest phone
- Text after adults/children count → Guest notes

### From iCal to Booking
- `DTSTART` → Check-in date
- `DTEND` → Check-out date
- `STATUS`:
  - `CONFIRMED` → `active`
  - `TENTATIVE` → `upcoming`
  - Other → `upcoming`
- Remaining description text → Booking notes

## Implementation Details

### Files Created
- `lib/cozy_checkout/ical_importer.ex` - Core import logic
- `lib/cozy_checkout_web/live/ical_import_live/index.ex` - LiveView interface
- `test/cozy_checkout/ical_importer_test.exs` - Test suite

### Files Modified
- `lib/cozy_checkout_web/router.ex` - Added `/admin/ical-import` route
- `lib/cozy_checkout_web/live/dashboard_live.ex` - Added import card to dashboard

## Example iCal Format

```ical
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//e-chalupy.cz//Zap Calendar 1.0//CZ
BEGIN:VEVENT
DTSTART:20251205T140000
DTEND:20251207T100000
SUMMARY:John Doe
UID:unique-id@domain.com
STATUS:CONFIRMED
Description:Telefon: 603873879\nEmail: john@example.com\nDospělí: 2\, děti 1\nSpecial requirements
END:VEVENT
END:VCALENDAR
```

## Duplicate Handling
- Guests are matched by email first, then by name
- Bookings are considered duplicates if they have the same guest_id and check_in_date
- Duplicate bookings are skipped and reported in the import results

## Error Handling
- Invalid iCal format: Returns error message
- Missing required fields: Skips the event and reports error
- Database constraint violations: Skips the record and reports error
- All errors are collected and displayed after import

## Testing
Run the test suite:
```bash
mix test test/cozy_checkout/ical_importer_test.exs
```

## Future Enhancements
- Support for room_number extraction from description
- Batch import from multiple files
- Preview before import
- Undo/rollback functionality
- Support for recurring events
- Export bookings to iCal format

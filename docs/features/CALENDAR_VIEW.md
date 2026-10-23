# Kalendář rezervací

Měsíční kalendář je na `/admin/bookings/calendar` a vyžaduje správní relaci.
Nabízí předchozí/další měsíc, návrat na dnešek, přechod do seznamu rezervací
nebo časové osy `/admin/bookings/timeline`.

Týden začíná pondělím; pole mimo aktuální měsíc jsou prázdná. Den ukazuje první
tři rezervace a tlačítko pro ostatní. Kliknutí na rezervaci otevře její detail,
kliknutí na obsazenost, příjezdy, odjezdy nebo počet dalších rezervací otevře
přehled dne rozdělený na příjezdy, pobyty a odjezdy.

## Obsazenost a barvy

Obsazenost a rozpis dospělých/dětí se počítají z pobytových položek přes kontext
`Bookings`. Nejde o počet porcí; den odjezdu již není obsazenou nocí, ale může
obsahovat odjezdovou snídani. Příjezdy a odjezdy jsou samostatné ukazatele.

Rezervace používají růžovou pro `upcoming`, zelenou pro `active`, šedou pro
`completed` a terakotovou pro `cancelled`. Kapacitní ukazatele používají zelenou,
výstražnou a chybovou barvu podle `Bookings.occupancy_level/1`.

Kalendářní seznam může zobrazit rezervaci včetně dne odjezdu. To je oddělené od
výpočtu obsazenosti. Rezervace bez odjezdu má v kalendářním filtru otevřený konec.
Zvýraznění dneška používá `Date.utc_today/0`.

## Odběr iCal

Při nastavení prostředí `BOOKING_ICAL_TOKEN` je dostupný odkaz **Calendar feed**
na `/calendar/bookings.ics?token=…`. Feed používá tento token místo správní
relace. Bez platného tokenu vrací 404. Odkaz obsahuje přístupový token a nepatří
do veřejně sdílených podkladů.

Jde o výstupní odběr; [nahrání iCal souboru](../integrations/ICAL_IMPORT.md)
je jiná funkce.

## Implementace a ověření

- `lib/cozy_checkout/bookings.ex`: rezervace pro měsíc, obsazenost a iCal výstup.
- `lib/cozy_checkout_web/live/booking_live/calendar_helpers.ex`: mřížka a filtry dnů.
- `lib/cozy_checkout_web/live/booking_live/calendar.ex` a `calendar.html.heex`: LiveView.
- `lib/cozy_checkout_web/controllers/booking_calendar_controller.ex`: kontrola tokenu.
- `test/cozy_checkout_web/controllers/booking_calendar_controller_test.exs`: feed.

Kalendář je serverově vykreslovaný přes LiveView bez externí kalendářové knihovny.
Ruční kontrola zahrnuje přelom měsíce, překrývající se pobyty, den odjezdu,
rozbalení dne a přechod mezi kalendářem, seznamem a časovou osou.

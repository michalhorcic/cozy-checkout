# Import rezervací z iCal

Soubor `.ics` lze nahrát na `/admin/ical-import` po přihlášení PINem.
Import zakládá hosty a rezervace; není to obousměrná synchronizace kalendáře.
Výstupní odběr popisuje [kalendář](../features/CALENDAR_VIEW.md#odběr-ical).

## Postup

Nahrajte soubor výběrem nebo přetažením, spusťte **Import Bookings** a projděte
počty vytvořených a nalezených hostů, vytvořených a přeskočených rezervací a chyby.
Importované rezervace nemají vyplněný [režim stravování](../features/CATERING.md).

## Mapování

| Vstup | Uložená hodnota |
| --- | --- |
| `SUMMARY` | Jméno hosta |
| `DTSTART`, `DTEND` | Datum příjezdu a odjezdu |
| `Description` s `Email:` a `Telefon:` | Kontakt hosta |
| `STATUS:CONFIRMED` | Stav rezervace `active` |
| `STATUS:TENTATIVE` a ostatní hodnoty | Stav rezervace `upcoming` |

Parser vyžaduje `SUMMARY`, `DTSTART` a `DTEND`; datum bere z části `YYYYMMDD`.
Podporuje jednoduchý vstup podle následujícího vzoru, nikoli celý standard iCal
včetně časových pásem, skládání řádků a opakovaných událostí.

```ical
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTART:20261023T140000
DTEND:20261025T100000
SUMMARY:Testovací host
UID:example-event
STATUS:CONFIRMED
Description:Telefon: 603000000\nEmail: guest@example.com
END:VEVENT
END:VCALENDAR
```

Je-li e-mail vyplněný, host se hledá podle něj; bez e-mailu podle přesného jména
mezi nesmazanými hosty. Při nenalezeném e-mailu není druhý pokus podle jména.
Existující kontakt se importem neaktualizuje. Duplicita rezervace se určuje podle
hosta a příjezdu, nikoli `UID`; existující rezervace se nepřepisuje.

## Omezení a diagnostika

Zpracování poznámek je závislé na konkrétním tvaru `Description`; parser nelze
považovat za obecný přenos všech údajů ani počtů hostů. Zkontrolujte výsledek
v rezervaci. Událost bez povinných polí se vynechá již při parsování a nemusí
být zahrnuta do statistik chyb. Chyba tvorby rezervace se vykáže jako přeskočení,
ale host vytvořený před ní může zůstat uložený. Import nemá hromadné vrácení změn.

Implementace: `lib/cozy_checkout/ical_importer.ex` a
`lib/cozy_checkout_web/live/ical_import_live/index.ex`. Původně uváděný soubor
`test/cozy_checkout/ical_importer_test.exs` v repozitáři není; samostatná
automatická sada importu zatím chybí. Test feedu ověřuje jinou funkci.

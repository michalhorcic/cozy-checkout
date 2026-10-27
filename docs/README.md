# Dokumentace Cozy Checkout

Základní spuštění, runtime a přihlášení jsou v [hlavním README](../README.md).
Podrobnosti jsou rozdělené podle účelu:

| Adresář | Obsah |
| --- | --- |
| [features](#funkce-a-provoz) | Současné chování aplikace a návody obsluhy |
| [integrations](#integrace) | Importy, exporty a jejich omezení |
| [development](#vývoj-a-ověření) | Technické podklady a regresní testy |
| [plans](plans/README.md) | Uložené návrhy budoucích funkcí, rozhodnutí a postup realizace |

## Funkce a provoz

- [Jak s aplikací pracovat — přehledová mapa a workflow stravování](features/WORKFLOWS.md)
- [Administrace a provozní přehled](features/ADMINISTRATION.md)
- [POS / samoobslužný bar](features/POS_SYSTEM.md)
- [Barové platby](features/PAYMENT_FUNCTIONALITY.md)
- [Servisní účty](features/SERVICE_ORDERS.md)
- [Vizuální seskupování položek](features/VISUAL_GROUPING.md)
- [Výběr produktu v ceníku](features/AUTOCOMPLETE_FEATURE.md)
- [Kalendář a odběr iCal](features/CALENDAR_VIEW.md)
- [Fakturace pobytů](features/BILLING.md)
- [Emaily hostům](features/GUEST_EMAILS.md)
- [Stravování, menu, receptury a nákup](features/CATERING.md)

## Integrace

- [Import rezervací z iCal](integrations/ICAL_IMPORT.md)
- [Integrace s ABRA Flexi](integrations/ABRA_INTEGRATION.md)
- [Export barových účtů do POHODA](integrations/POHODA_EXPORT.md)

Export pobytových dokladů do ABRA zůstává další etapou. Současnou barovou
integraci a podklady pro její rozšíření popisuje [návod ABRA](integrations/ABRA_INTEGRATION.md);
uživatelský postup je ve [fakturaci](features/BILLING.md#ověření-a-další-etapa).

## Vývoj a ověření

- [Finanční regresní testy](development/FINANCIAL_TESTS.md)
- [Barvy a téma](development/COLOR_SYSTEM_GUIDE.md)
- [Formátování peněz a čísel](development/CURRENCY_CONFIG.md)
- [Diagnostika LiveView](development/COMMON_LIVEVIEW_ERRORS.md)

Cesty ke zdrojům uvedené jako kód jsou relativní ke kořeni repozitáře.
Instrukce pro agenty zůstávají v [AGENTS.md](../AGENTS.md).

## Kontrola a přesun dokumentace (23. 10. 2026)

Původní názvy souborů zůstaly zachované kvůli snadnému dohledání v historii.
Kontrola vycházela ze zdrojového kódu, konfigurace a existujících testů; neověřuje
produkční prostředí, reálné odesílání pošty ani import do účetního systému.

| Původní podklad | Výsledek kontroly |
| --- | --- |
| `POS_SYSTEM.md`, `PAYMENT_FUNCTIONALITY.md` | Aktualizované cesty, rezervace místo starého výběru hostů, PIN, rozdělení plateb a potvrzení QR |
| `SERVICE_ORDERS.md`, `VISUAL_GROUPING.md` | Upřesněné filtry režimu a seskupení podle historické ceny |
| `AUTOCOMPLETE_FEATURE.md` | Zachovaná funkce, doplněné limity a skutečný způsob hledání |
| `CALENDAR_VIEW.md` | Doplněná obsazenost, detail dne, časová osa a existující výstup iCal |
| `BILLING.md` | Zachovaný podrobný aktuální návod fakturace |
| `ICAL_IMPORT.md` | Upřesněné párování, omezení parseru a chybějící samostatné testy importu |
| `POHODA_EXPORT.md` | Opravená cesta, používaná konfigurace, slevy, spropitné a omezení smíšených úhrad |
| `CURRENCY_CONFIG.md` | Upřesněné formátování; změna symbolu nepřevádí měnu |
| `COMMON_LIVEVIEW_ERRORS.md` | Odstraněný plošný catch-all a zákaz jednotlivých `phx-change`; diagnostika podle konkrétních parametrů |
| `COLOR_SYSTEM_GUIDE.md`, `COLOR_UPDATE_SUMMARY.md` | Sloučené do průvodce; odstraněný duplicitní souhrn a zastaralé seznamy dokončených úprav |
| `test/FINANCIAL_TESTS.md` | Přesunuté sem, doplněné pobytové sady, odstraněný zastaralý počet testů |
| Podrobné provozní sekce `README.md` | Přesunuté do administrace, emailů a stravování; README obsahuje odkazy |

Neúplný obecný návod na zpřístupnění PostgreSQL do lokální sítě byl z README
odstraněn: neobsahoval avizované pravidlo `pg_hba.conf` a nebyl postupem nutným
pro lokální spuštění této aplikace. Lokální konfigurace zůstává v `config/dev.exs`
a `config/test.exs`; produkční připojení v `config/runtime.exs`.

Původní seznamy „Future Enhancements“ nebyly schválenými plány a obsahovaly i již
hotové funkce (například rozdělení platby a iCal feed). Nejsou proto vedené jako
aktuální backlog. Nové konkrétní záměry mají místo v [plans](plans/README.md).

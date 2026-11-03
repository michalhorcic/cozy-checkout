# Dokumentace Cozy Checkout

Základní přehled a rychlé spuštění jsou v [hlavním README](../README.md).
Pro vývoj pokračujte [nastavením prostředí](development/SETUP.md), pro správu
[nasazením a provozem](development/DEPLOYMENT.md) a
[nastavením Admin PINu](features/ADMINISTRATION.md#admin-pin).
Dokumentaci lze také sestavit jako [HTML web s vyhledáváním](development/DOCUMENTATION_WEB.md).

| Adresář | Obsah |
| --- | --- |
| [features](#funkce-a-provoz) | Současné chování aplikace a návody obsluhy |
| [integrations](#integrace) | Importy, exporty, konfigurace a jejich omezení |
| [development](#vývoj-a-ověření) | Vývojové prostředí, nasazení a technické podklady |
| [plans](plans/README.md) | Návrhy, přijatá rozhodnutí a historie realizace funkcí |

## Funkce a provoz

- [Grafické postupy práce — pobyty, kuchyň, doklady, ABRA, bar a sklady](features/WORKFLOWS.md)
- [Administrace, přihlášení PINem a provozní přehled](features/ADMINISTRATION.md)
- [POS / samoobslužný bar](features/POS_SYSTEM.md)
- [Barové platby](features/PAYMENT_FUNCTIONALITY.md)
- [Servisní účty](features/SERVICE_ORDERS.md)
- [Vizuální seskupování položek](features/VISUAL_GROUPING.md)
- [Výběr produktu v ceníku](features/AUTOCOMPLETE_FEATURE.md)
- [Kalendář a odběr iCal](features/CALENDAR_VIEW.md)
- [Fakturace pobytů, PDF a platby](features/BILLING.md)
- [Emaily hostům](features/GUEST_EMAILS.md)
- [Stravování, menu z receptů, nákup, náklady a mrazák](features/CATERING.md)
- [Ekonomika firmy a mapování fixních / variabilních nákladů](features/ECONOMICS.md)

## Integrace

- [Import rezervací z iCal](integrations/ICAL_IMPORT.md)
- [ABRA Flexi — bar, pobytové doklady, bankovní platby a přehled přenosů](integrations/ABRA_INTEGRATION.md)
- [Ruční export zálohové výzvy a konfigurace pobytové integrace](integrations/ABRA_ACCOMMODATION.md)
- [Konečné faktury — podklad pro účetní, mapování a omezení](integrations/ABRA_ACCOUNTANT_REVIEW.md)
- [PDF přílohy pobytových faktur v ABRA](integrations/ABRA_PDF_ATTACHMENTS.md)
- [Čtecí kontrakt ekonomiky firmy s ABRA](integrations/ECONOMICS_ABRA_CONTRACT.md)
- [Export barových účtů do POHODA](integrations/POHODA_EXPORT.md)

Barová a pobytová integrace mají odlišné mapování. Pobytová integrace podporuje
výzvy, konečné faktury s odpočty a potvrzované bankovní platby; její zapnutí
neznamená automatické potvrzení příjmu peněz. Economics čte účetnictví
samostatně. Podmínky zapojení a dosud nepodporované situace jsou v návodech výše.

## Vývoj a ověření

- [Vývojové prostředí, lokální spuštění a údržba závislostí](development/SETUP.md)
- [Nasazení, proměnné prostředí, migrace a zálohy](development/DEPLOYMENT.md)
- [HTML dokumentace a její sestavení](development/DOCUMENTATION_WEB.md)
- [Finanční regresní testy](development/FINANCIAL_TESTS.md)
- [Barvy a téma](development/COLOR_SYSTEM_GUIDE.md)
- [Formátování peněz a čísel](development/CURRENCY_CONFIG.md)
- [Diagnostika LiveView](development/COMMON_LIVEVIEW_ERRORS.md)
- [Zdroje a obnova workflow obrázků](development/WORKFLOW_DIAGRAMS.md)

Cesty ke zdrojům uvedené jako kód jsou relativní ke kořeni repozitáře.
Instrukce pro agenty zůstávají v [AGENTS.md](../AGENTS.md).

## Aktuálnost podkladů

Kontrola k 3. 11. 2026 vychází z kódu, konfigurace, migrací a existujících testů
na `main` po PR #80. Opravené jsou zejména odkazy na přihlášení, stav pobytové
integrace ABRA, nákupů kuchyně a přehled plánů. Čtení testů neznamená jejich
spuštění ani ověření produkce, skutečné pošty nebo účetních přenosů.

Grafy workflow zachycují stav k 27. 10. 2026, viz datum a hranice ověření
v [jejich návodu](features/WORKFLOWS.md). Podrobné návody funkcí zahrnují i pozdější
rozšíření. Plány uchovávají původní návrhy a historii; aktuální obsluhu popisují
`features` a `integrations`. Historie přesunů a dřívějších kontrol je v Gitu.

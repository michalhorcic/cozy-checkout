# Workflow grafy — zdroje a obnova obrázků

Uživatelská galerie je v [Jak s aplikací pracovat](../features/WORKFLOWS.md).
Mermaid zdroje jsou v [adresáři workflows](../features/workflows); každý má
stejnojmenné SVG a PNG. Galerie zobrazuje PNG kvůli mobilním klientům,
SVG slouží ke zvětšení a Mermaid k úpravám. Obrázky nepoužívají externí fonty,
skripty ani služby; pro SVG je vypnuté `htmlLabels` i vkládání fontů.

## Obnova

Potřebujete Python 3, Node.js podporovaný Mermaid CLI 12 a Chrome/Chromium.
Renderer je oddělený od závislostí aplikace. Následující příklad jej instaluje
do dočasného adresáře; nezmění `mix.lock` ani balíčky aplikace:

```sh
PUPPETEER_SKIP_DOWNLOAD=true npm install --prefix /tmp/cozy-workflow-render --no-audit --no-fund @mermaid-js/mermaid-cli@12.0.0
python3 docs/features/workflows/render.py --cli /tmp/cozy-workflow-render/node_modules/.bin/mmdc --browser /usr/bin/chromium
```

V izolovaném vývojovém kontejneru, kde Chromium nemůže použít vlastní sandbox,
přidejte `--no-sandbox`. Pro běžné lokální spuštění jej vynechte. Cestu k prohlížeči
upravte podle instalace. Pro jediný graf přidejte například `--only 09-bank-confirmation`.
Na počítači bez předinstalovaného prohlížeče lze při instalaci vynechat
`PUPPETEER_SKIP_DOWNLOAD` a při renderování `--browser`; Puppeteer použije svůj prohlížeč.

Po změně `.mmd` obnovte oba obrázky a zkontrolujte jejich čitelnost. Odkazy
v galerii a text pod obrázkem musí popisovat stejný postup jako zdroj grafu.

## Podklady a hranice ověření

Kontrola kódu: 27. 10. 2026, základ `origin/main` na `0523bb7`.
Grafy popisují doporučené postupy a podmínky implementace, ne ověření konkrétního
produkčního nastavení. Větve přehledové mapy ukazují vztahy, nikoli pevné pořadí.
Stejně tak souběžné větve rezervace nebo kuchyně nemusí být hotové současně,
aby šlo uložit průběžnou práci.

| Grafy | Hlavní implementace | Existující testové podklady |
| --- | --- | --- |
| 01–02: přehled, rezervace | [Navigace](../../lib/cozy_checkout_web/admin_navigation.ex), [dashboard](../../lib/cozy_checkout/dashboard.ex), [rezervace](../../lib/cozy_checkout/bookings.ex), [formulář](../../lib/cozy_checkout_web/live/booking_live/form_component.ex) | [Provozní přehled](../../test/cozy_checkout/dashboard_test.exs), [stravování rezervací](../../test/cozy_checkout/booking_meals_test.exs) |
| 03: iCal | [Importer](../../lib/cozy_checkout/ical_importer.ex), [obrazovka](../../lib/cozy_checkout_web/live/ical_import_live/index.ex) | Samostatná sada importu v repozitáři chybí; test výstupního feedu import neověřuje |
| 04: stravování a nákup | [Schéma rezervace](../../lib/cozy_checkout/bookings/booking.ex), [menu](../../lib/cozy_checkout/meals/menu_planning.ex), [nákup](../../lib/cozy_checkout/kitchen/shopping_list.ex) | [Menu](../../test/cozy_checkout/meals/booking_menus_test.exs), [nákup](../../test/cozy_checkout/kitchen/shopping_list_test.exs), [UI nákupu](../../test/cozy_checkout_web/shopping_live_test.exs) |
| 05–08: kalkulace, doklady, opravy, odeslání | [Billing](../../lib/cozy_checkout/billing.ex), [doklad](../../lib/cozy_checkout/billing/document.ex), [fakturační UI](../../lib/cozy_checkout_web/live/billing_live/booking.ex) | [Finanční pravidla](../../test/cozy_checkout/financial/booking_billing_test.exs), [UI fakturace](../../test/cozy_checkout_web/billing_live_test.exs) |
| 09–10: banka a ABRA | [Banka](../../lib/cozy_checkout/abra/bank.ex), [potvrzení](../../lib/cozy_checkout/abra/bank_payments.ex), [doplatky](../../lib/cozy_checkout/abra/final_bank_payments.ex), [přenos dokladů](../../lib/cozy_checkout/abra/accommodation.ex), [podmínky vyúčtování](../../lib/cozy_checkout/abra/final_invoice_export.ex), [přehled přenosů](../../lib/cozy_checkout_web/live/billing_live/transfers.ex) | [Zálohy](../../test/cozy_checkout/financial/abra_bank_payments_test.exs), [doplatky](../../test/cozy_checkout/financial/abra_final_bank_payments_test.exs), [export](../../test/cozy_checkout/financial/abra_accommodation_test.exs), [UI banky](../../test/cozy_checkout_web/abra_bank_live_test.exs) |
| 11–12: bar a platby | [Sales](../../lib/cozy_checkout/sales.ex), [POS účet](../../lib/cozy_checkout_web/live/pos_live/order_management.ex) | [POS platby](../../test/cozy_checkout_web/live/financial/pos_payments_test.exs) |
| 13: produkty a ceny | [Catalog](../../lib/cozy_checkout/catalog.ex), [ceník](../../lib/cozy_checkout/catalog/pricelist.ex), [správa cen](../../lib/cozy_checkout_web/live/pricelist_live/management.ex) | [Ceny](../../test/cozy_checkout/financial/catalog_pricing_test.exs) |
| 14–15: sklady | [Inventory](../../lib/cozy_checkout/inventory.ex), [bar](../../lib/cozy_checkout_web/live/bar_stock_live.ex), [korekce](../../lib/cozy_checkout/inventory/stock_adjustment.ex) | [Oddělení skladů a změny spotřeby](../../test/cozy_checkout/inventory_bar_stock_test.exs) |
| 16: emaily hostům | [GuestEmails](../../lib/cozy_checkout/guest_emails.ex), [editor](../../lib/cozy_checkout_web/live/guest_email_live/index.ex), [worker](../../lib/cozy_checkout/workers/booking_email_worker.ex) | [Obsah a stavy](../../test/cozy_checkout/guest_emails_test.exs), [editor](../../test/cozy_checkout_web/guest_email_live_test.exs) |
| 17–18: přehledy a POHODA | [Statistiky](../../lib/cozy_checkout_web/live/statistics_live/index.ex), [ekonomika](../../lib/cozy_checkout_web/live/economy_live/index.ex), [skladové reporty](../../lib/cozy_checkout_web/live/inventory_reports_live/index.ex), [POHODA](../../lib/cozy_checkout/pohoda.ex) | [Částky účetních výstupů](../../test/cozy_checkout/financial/accounting_amounts_test.exs) |

Související datové struktury byly kontrolovány ve schématech a migracích
stravování rezervací, barových pohybů a fakturačních dokladů. Čtení testů slouží
jako podklad; neznamená jejich spuštění. Lokální aplikační testy nebyly spuštěny
podle `AGENTS.md`; výsledky CI ověří uživatel. Renderování diagramů je samostatná
kontrola dokumentace. Reálné emaily, účetní přenosy ani bankovní operace nebyly prováděny.

V tomto spravovaném prostředí Chromium nepovoluje navigaci na `file://`.
Při renderování proto dočasná instalace CLI načetla svou pomocnou prázdnou
HTML stránku přes lokální HTTP; síťová politika prohlížeče zůstala zachovaná.
Tato úprava se netýká aplikace ani verzovaných Mermaid zdrojů.

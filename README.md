# Cozy Checkout

Samoobslužný bar a správa penzionu Jindřichův dům. Aplikace propojuje rezervace,
obsazenost, stravování a kuchyň, barové účty a sklady, pobytovou fakturaci
a účetní integrace. Barové a pobytové finance mají oddělenou evidenci.

Základ tvoří **Elixir, Phoenix 1.8 / LiveView, PostgreSQL a Oban**; rozhraní
používá Tailwind CSS v4 a daisyUI. Produkce běží jako Docker release přes Coolify.

## Rychlé lokální spuštění

1. Nainstalujte Elixir a Erlang podle [.tool-versions](.tool-versions), spusťte
   PostgreSQL a připravte roli `elixir` podle [návodu pro vývoj](docs/development/SETUP.md).
2. Z kořene repozitáře spusťte:

   ```sh
   mix setup
   mix phx.server
   ```

3. Otevřete [POS](http://localhost:4000/) nebo [administraci](http://localhost:4000/admin).
   Přístup do administrace nastavte podle [návodu k přihlášení](docs/features/ADMINISTRATION.md#admin-pin).

`mix setup` stáhne závislosti, vytvoří databázi, provede migrace a seed a připraví
assets. Pro PDF je potřeba Chrome nebo Chromium; lokální poštu najdete
v [development mailboxu](http://localhost:4000/dev/mailbox).
[Podrobná instalace, PDF a ověření změn](docs/development/SETUP.md).

## Dokumentace a provoz

[Rozcestník dokumentace](docs/README.md) obsahuje všechny návody, technické
podklady a [plány funkcí](docs/plans/README.md). Dokumentaci lze procházet také
jako [HTML web s menu a vyhledáváním](docs/development/DOCUMENTATION_WEB.md).

| Potřebuji | Návod |
| --- | --- |
| Zorientovat se v aplikaci | [Administrace](docs/features/ADMINISTRATION.md) · [Grafické postupy](docs/features/WORKFLOWS.md) |
| Spravovat rezervace a komunikaci | [Kalendář a iCal odběr](docs/features/CALENDAR_VIEW.md) · [Import iCal](docs/integrations/ICAL_IMPORT.md) · [Emaily hostům](docs/features/GUEST_EMAILS.md) |
| Obsluhovat bar | [POS](docs/features/POS_SYSTEM.md) · [Platby](docs/features/PAYMENT_FUNCTIONALITY.md) · [Servisní účty](docs/features/SERVICE_ORDERS.md) |
| Připravit jídla a nákup | [Menu z receptů, porce, nákup, náklady a mrazák](docs/features/CATERING.md) |
| Vystavovat pobytové doklady | [Fakturace, PDF a platby](docs/features/BILLING.md) |
| Zpracovat přijatou fakturu nebo účtenku | [Přijaté doklady — pilot](docs/features/INCOMING_DOCUMENTS.md) |
| Nastavit účetní integrace | [ABRA: bar, ubytování a banka](docs/integrations/ABRA_INTEGRATION.md) · [PDF přílohy v ABRA](docs/integrations/ABRA_PDF_ATTACHMENTS.md) · [POHODA](docs/integrations/POHODA_EXPORT.md) |
| Sledovat ekonomiku firmy | [Ekonomika a mapování nákladů](docs/features/ECONOMICS.md) |
| Nasadit a spravovat aplikaci | [Docker, konfigurace, migrace a zálohy](docs/development/DEPLOYMENT.md) |

## Vývoj a ověření

- [Vývojové prostředí, testy a údržba závislostí](docs/development/SETUP.md)
- [Finanční regresní pokrytí](docs/development/FINANCIAL_TESTS.md)
- [Konfigurace aplikace](config/config.exs), [developmentu](config/dev.exs),
  [testů](config/test.exs) a [runtime / prostředí nasazení](config/runtime.exs)
- [CI aplikace](.github/workflows/tests.yml) a [CI dokumentace](.github/workflows/documentation.yml)
- [Instrukce pro agenty](AGENTS.md)

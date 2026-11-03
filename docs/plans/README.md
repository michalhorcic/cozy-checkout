# Plány funkcí

Tento adresář slouží pro uložené plány, ke kterým se lze vracet napříč chaty.
[Šablona](TEMPLATE.md) je výchozí kostra, nikoli schválený záměr realizace.

## Přehled plánů

- [Tvorba a úprava menu přímo z receptů](2026-11-02-menu-z-receptu.md)
  — implementováno v `main`; menu, přiřazení pobytům a nákup používají odkazy
  na recepty, změny platí i do minulosti. [Současný návod](../features/CATERING.md).
  Ruční ověření konkrétních dat a zařízení zůstává samostatným krokem.
- [Integrace fakturace ubytování s ABRA Flexi](2026-10-23-abra-ubytovani.md)
  — implementované výzvy, banka, ZDD, konečné faktury a doplatky;
  [současný postup a omezení](../integrations/ABRA_INTEGRATION.md).
  Účetní schválení mapování a ověření testovací firmy zůstávají samostatné.
- [Nákupy surovin a nákladovost kuchyně](2026-10-27-nakupy-a-nakladovost-kuchyne.md)
  — implementováno v `main` od PR #55; JSON import, přiřazení surovin,
  historie cen a nákladové reporty. [Návod](../features/CATERING.md#nákupy-a-kalkulované-náklady-surovin).
  Ověření skutečných účtenek a víkendového menu zůstává provozním krokem.
- [Jednoduchá evidence mrazáku](2026-10-28-evidence-mrazaku.md)
  — implementováno; ruční evidence a informace u menu, plánovače a nákupu.
  Nákupní množství zůstávají beze změny; bez rezervací a externích notifikací.

- [Ekonomický dashboard firmy z ABRA Flexi](2026-10-28-ekonomicky-dashboard.md)
  — implementováno; samostatný modul, účetní ukazatele, kontrola úplnosti,
  denní saldo a grafy. Účetní odsouhlasení podkladů zůstává samostatným krokem.

- [Fixní a variabilní náklady v Ekonomice firmy](2026-10-29-fixni-a-variabilni-naklady.md)
  — první verze implementována v `main` od PR #68; záložka Nákladovost,
  verzované mapování a fixní/variabilní/smíšené náklady.
  [Současný návod](../features/ECONOMICS.md#nákladovost-fixní-a-variabilní-náklady).
  Smluvní závazky a provozní jednotkové ukazatele zůstávají další etapou.

Přehled odpovídá `main` k 3. 11. 2026. Historické návrhy a záznamy ověření
v jednotlivých plánech nejsou návodem k současné obsluze ani výsledkem nové kontroly CI.

## Jak plán uložit a znovu otevřít

1. Nejprve společně připravíme plán a vyjasníme rozsah a otevřené otázky.
2. Uložíme jej například jako `docs/plans/2026-10-23-nazev-funkce.md`.
   Datum označuje vznik; název zůstává stabilní i při pozdější aktualizaci.
3. Plán obsahuje stav, datum aktualizace, přijatá rozhodnutí, dosavadní postup
   a nejbližší další krok. Otázky bez odpovědi zůstávají viditelně otevřené.
4. V novém chatu stačí odkaz na soubor a konkrétní požadavek, například:
   „Přečti plán v docs/plans/2026-10-23-nazev-funkce.md, ověř současný stav kódu
   a pokračuj nejbližším nedokončeným krokem.“
5. Po dokončení zůstává plán na stejném místě se stavem **dokončeno** a odkazy
   na implementaci a ověření. Popis skutečně dodané funkce patří do `features`
   nebo `integrations`; původní plán zachovává důvody rozhodnutí.

Navržené stavy: **návrh → připraveno → rozpracováno → dokončeno**.
Pro odložený nebo opuštěný záměr lze použít **odloženo** nebo **zrušeno** s důvodem.
Uložený plán sám nepředstavuje pokyn k zahájení implementace.

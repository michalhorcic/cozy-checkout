# Plány funkcí

Tento adresář slouží pro uložené plány, ke kterým se lze vracet napříč chaty.
[Šablona](TEMPLATE.md) je výchozí kostra, nikoli schválený záměr realizace.

## Přehled plánů

- [Integrace fakturace ubytování s ABRA Flexi](2026-10-23-abra-ubytovani.md)
  — návrh; čeká na vzory od účetní a ověření API v testovací firmě.
- [Nákupy surovin a nákladovost kuchyně](2026-10-27-nakupy-a-nakladovost-kuchyne.md)
  — připraveno; JSON import nákupů, přiřazení ke stávajícím surovinám,
  historie cen a nákladové reporty. Implementace začne v novém vlákně.
- [Jednoduchá evidence mrazáku](2026-10-28-evidence-mrazaku.md)
  — implementováno; ruční evidence a informace u menu, plánovače a nákupu.
  Nákupní množství zůstávají beze změny; bez rezervací a externích notifikací.

- [Ekonomický dashboard firmy z ABRA Flexi](2026-10-28-ekonomicky-dashboard.md)
  — implementováno; samostatný modul, účetní ukazatele, kontrola úplnosti,
  denní saldo a grafy. Účetní odsouhlasení podkladů zůstává samostatným krokem.

- [Fixní a variabilní náklady v Ekonomice firmy](2026-10-29-fixni-a-variabilni-naklady.md)
  — návrh; samostatná záložka Nákladovost, editovatelné a verzované mapování,
  fixní/variabilní/smíšené náklady a oddělené označení mimořádných položek.

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

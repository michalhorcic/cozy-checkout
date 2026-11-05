# Ruční formulář přijatého dokladu s návrhy z OpenAI

Nová alternativa na `/admin/incoming-document-form`, přístupná z Přijatých dokladů
přes „Nový doklad přes formulář“. Zachovává původní podrobný přepis a XML editor.
Používá stejné tři vzory, připojení ABRA, soukromé originály, OpenAI Responses API,
Oban worker, účetní předpisy a bezpečný proces dry-run → schválení → přenos.

## Stav převzatého řešení

Větev `codex/prijate-doklady` na commitu `d45647a` již obsahuje nahrávání,
strukturovaný přepis nebo přímé XML, editaci přepisu, deterministický sestavovač,
kontrolu pokrytí a součtů položek, účetní číselník, diagnostiku odpovědí ABRA a
create-only import s externím ID. Potíže s neúplnými položkami se v podrobném
režimu správně projevují blokací. Tato alternativa je obchází změnou rozsahu
zpracovávaného dokladu, nikoliv oslabením kontroly položkového režimu.

## Použití

1. Vybrat agendu: přijatá faktura, pokladní výdaj nebo ostatní závazek (karta).
2. Buď vyplnit doklad ručně bez souboru a bez volání OpenAI, nebo nejdříve nahrát
   PDF/JPEG/PNG. U nahrávání se zachovává kontrola duplicity a limit 10 MB.
3. Nová strategie `header_form` vrací návrhy hlavičky a rekapitulace DPH. I při
   `complete=false`, neúplných položkách nebo chybějící celkové částce se zpřístupní
   formulář. Vytěžování má jeden pokus, nedoplňuje chybějící položky opakováním.
   Chybu API lze vyřešit ručním vyplněním stejného formuláře.
4. Zkontrolovat a opravit návrhy proti zobrazenému originálu. Původní vytěžená data
   zůstávají uložená, ruční formulář je uložen zvlášť. Nejasnosti, přečtená měna a
   rekapitulace originálu jsou viditelné. Podporovány jsou tuzemské doklady v CZK
   a souhrnné sazby 0 %, 12 % a 21 %. Jiné sazby nebo měny vyžadují jiné zpracování.
5. Potvrdit kontrolu CZK, údajů a souhrnné DPH. Teprve uložením formuláře vzniká
   validované XML. Součet základů, osvobozené částky a daní musí souhlasit s celkem;
   chybějící DPH se nepřevádí automaticky na osvobozenou částku.
6. Ve stávajícím detailu zkontrolovat účetní nastavení ze vzoru, případně vybrat
   předpis z ABRA, spustit dry-run a samostatně schválit přenos. Uložením dalších
   změn se předchozí dry-run ruší. Po zahájení přenosu je formulář uzamčený.

Položky OpenAI podle možností přepíše do `items`, ale použijí se pouze jako
orientační text v `poznam`. Do ABRA neposíláme kolekci `polozkyDokladu`, skladové
pohyby ani ceny jednotlivých položek. ABRA může interně vytvořit své automatické
účetní řádky podle souhrnné DPH; to popisuje její dokumentace bezpoložkových dokladů.

## Co obsahuje výsledné XML

Společná obálka je `winstrom version="1.0"`. Jeden doklad má `create="ok"`
a `update="fail"` a vlastní `id` ve tvaru `ext:cozy-incoming:<UUID>`. Interní
číslo `kod` může přidělit ABRA; dodavatelské číslo patří do `cisDosle`.

| Agenda / kořen dokladu | Nastavení převzaté z dodaného vzoru | Povinné údaje v novém formuláři |
| --- | --- | --- |
| `faktura-prijata` | `typDokl=code:FAKTURA`, účet 321001, předpis a členění DPH ze vzoru | Dodavatel, číslo původního dokladu, vystavení, splatnost, celkem, odpovídající rekapitulace |
| `pokladni-pohyb` | `typDokl=code:STANDARD`, `typPohybuK=typPohybu.vydej`, `pokladna=code:POKLADNA KČ`, účet 211001 | Dodavatel, číslo původního dokladu, vystavení, celkem, odpovídající rekapitulace |
| `zavazek` | `typDokl=code:1.OST. ZÁVAZ - KARTA`, účet 325000, předpis a členění DPH ze vzoru | Dodavatel, číslo původního dokladu, vystavení, splatnost, celkem, odpovídající rekapitulace |

Při nenulové DPH formulář vyžaduje `duzpPuv` i `duzpUcto`; data neodhaduje z
originálu ani z aktuálního dne. Adresa, IČO/DIČ, variabilní symbol, datum účtování,
bankovní spojení a popis lze doplnit. Konkrétní požadavky firmy, účtů a kontrolního
hlášení včetně DIČ ověří ABRA dry-run. Číslo dokladu a dodavatel jsou společné
aplikační požadavky pro dohledatelnost, nikoliv tvrzení o povinnosti ve všech
agendách ABRA. Účetní kódy ve vzorech nejsou univerzální pro jiné firmy.

V každé agendě se přenáší `bezPolozek=true`, `ucetni=true`, `mena=code:CZK`,
`stat=code:CZ`, `statDph=code:CZ` a následující peněžní hlavička (příklad):

```xml
<sumOsv>10.00</sumOsv>
<sumZklSniz>100.00</sumZklSniz><sumDphSniz>12.00</sumDphSniz>
<sumZklSniz2>0.00</sumZklSniz2><sumDphSniz2>0.00</sumDphSniz2>
<sumZklZakl>1000.00</sumZklZakl><sumDphZakl>210.00</sumDphZakl>
<sumCelkem>1332.00</sumCelkem>
<poznam>Orientační přepis položek (bez zaúčtování): ...</poznam>
```

Model nevybírá účetní předpis, účty, typ dokladu ani XML elementy. Text je escapován
stávajícím XML rendererem. Formulář nepřijímá účetní pole nebo položkové kolekce.

## Zdroje ověřené při implementaci

- [ABRA: přijatá faktura](https://podpora.flexibee.eu/cs/articles/4611404-prijata-faktura):
  povinná pole, datum uplatnění DPH, splatnost a bezpoložkové zadání souhrnných částek.
- [ABRA: pokladna](https://podpora.flexibee.eu/cs/articles/4632069-pokladna):
  typ pohybu, pokladna, vystavení, souhrnné částky a poznámka.
- [ABRA: ostatní závazky](https://podpora.flexibee.eu/cs/articles/4569870-ostatni-zavazky):
  číslo došlé, splatnost, DPH a bezpoložkové zadání.
- [ABRA: testovací uložení](https://podpora.flexibee.eu/cs/articles/4720123-testovaci-ulozeni-dry-run).
- Dodané XML v `priv/incoming_documents/{faktura-prijata,pokladni-pohyb,zavazek}.xml`.

Veřejné metadata `demo.flexibee.eu/c/demo/<agenda>/properties.json` při ověření
vracely HTTP 401. Živý import do cílové ABRA ani volání OpenAI nebyly provedeny;
platnost pro konkrétní firmu musí potvrdit její dry-run. Dokumentace popisuje
podporovaný postup, nikoliv důkaz akceptace konkrétního payloadu v cílové instalaci.

## Migrace a ověření

Migrace `20261105220000` povoluje prázdný originál, MIME typ a hash u ručně
vytvořených dokladů. Soukromý endpoint originálu u takového dokladu vrací 404.
Existující dokumenty se nemění. Není potřeba nová konfigurace ani závislost.

Přidané testy pokrývají XML všech tří agend, DPH a součty, text položek v poznámce,
částečné vytěžení, ruční vytvoření, souběžné změny, zrušení dry-runu, neměnnost
po schválení, kontrolovaný payload, admin PIN a formulář. Lokální testy podle
AGENTS.md nebyly spuštěny; výsledky GitHub CI ověří uživatel. Kompilace a kontrola
formátování byly provedeny s Elixir 1.20.4 / OTP 29.1.

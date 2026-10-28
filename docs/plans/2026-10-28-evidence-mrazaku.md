# Jednoduchá evidence mrazáku

- Stav: **připraveno**; implementace nezahájena.
- Vytvořeno: 2026-10-28
- Aktualizováno: 2026-10-28
- Podklad: rozsah potvrzený uživatelem v chatu; podrobnosti níže jsou návrh implementace.
- Související dokumentace: [Stravování a kuchyň](../features/CATERING.md),
  [Nákupy a nákladovost kuchyně](2026-10-27-nakupy-a-nakladovost-kuchyne.md).

## Problém a očekávaný výsledek

V mrazáku se hromadí ovoce, zelenina, vývary a zbytky hotových jídel, protože
při plánování a vaření není jejich obsah po ruce. Cozy umožní rychle zapsat,
co bylo zamrazeno, a ukáže relevantní zásoby u plánovaných jídel a nákupu.
Množství lze zadávat; cílem je jednoduchá evidence, ne automatické řízení skladu.

**Množství potřebné k nákupu zůstává vždy beze změny.** Zásoby jsou pouze
informace pro člověka. Nemění spotřebu receptů, počty porcí, menu ani náklady.

## Současný stav a podklady

Ověřeno v implementaci a po načtení aktuálního `origin/main`:

- `Recipes`, `Ingredient`, `Recipe` a `RecipeLine` již obsahují katalog surovin,
  receptury, UUID vazby a archivaci. Základní jednotky surovin jsou kg/l/ks.
- `Recipes.Consumption` počítá spotřebu z receptů a dětských koeficientů.
- `Meals.MenuPlanning` spravuje menu konkrétní rezervace, data jídel, hlavní
  recept i doplňky; kontroluje neaktuální menu a chrání ruční úpravy.
- `Kitchen.ShoppingList` sčítá spotřebu za období a volitelně pobyt, zachovává
  zdroje podle receptu/jídla/skupiny a zaokrouhluje nákupní balení.
  Kuchyňské zásoby do výpočtu nevstupují.
- `ShoppingLive`, `BookingLive.Menu` a plánovač jsou místa pro zobrazení zásob.
  `FoodNavigation` již přenáší období a rezervaci mezi obrazovkami.
- Odškrtnutí nákupu je lokální v prohlížeči a závisí na otisku položky.
  Není dokladem nákupu ani použití zásoby.
- Barový sklad má vlastní model a účel; mrazák se napojí na kuchyňské suroviny
  a recepty. Připravený plán nákladovosti zatím není implementován a tuto
  funkci neblokuje.

## Rozsah

První verze zahrne sdílenou evidenci jednoho mrazáku, ruční přidávání,
opravy a částečné či úplné odebrání zásoby. Připomínáním se v této etapě
rozumí informace přímo na užitečných obrazovkách aplikace.

Mimo rozsah jsou rezervace zásob pro pobyty, automatické odpisy, změny
nákupních množství, přepočty nákladů, návrhy menu, AI párování, hlasové zadání,
fotky, QR štítky, push/e-mailové notifikace a plánování rozmrazování.
Nevzniká samostatný katalog surovin ani obecný skladový či účetní modul.

## Navržené řešení

### Rychlé zadání a správa

Do společné navigace kuchyně přidat **Mrazák**. Přehled zobrazí název,
zbývající množství, datum zamrazení, případné umístění a vazbu na surovinu
nebo recept. Výchozí řazení je od nejstaršího zamrazení; hledání podle názvu
a filtr aktivní / vyřazené. Prázdný stav nabídne přidání první položky.

Formulář obsahuje:

- název, množství a jednotku;
- datum zamrazení, předvyplněné dnešním datem v časové zóně aplikace;
- volitelnou vazbu **Surovina / Hotové jídlo (recept) / Bez propojení**;
- volitelné umístění jako krátký text, například „prostřední zásuvka“;
- volitelnou poznámku.

Výběr suroviny nebo receptu předvyplní název; uživatel ho může upřesnit.
Bez vazby lze rychle uložit například „zbytek omáčky“ a přiřadit ji později.
Každé nové zamrazení je samostatná položka, i když už stejná surovina existuje;
různá data a krabičky se automaticky neslučují.

Jednotky: kg/g/l/ml/ks/porce. Převody g → kg a ml → l používají existující
pomocné funkce. U vazby na surovinu musí být jednotka slučitelná s její
základní jednotkou; u hotového jídla lze evidovat porce, hmotnost nebo objem.
Hmotnost, objem, kusy a porce se mezi sebou neodhadují ani nepřepočítávají.
Počet krabiček lze uvést v poznámce. Vývar používaný jako surovina se propojí
s odpovídající položkou katalogu; z pouhé shody názvu vazba nevzniká.

Akce **Odebrat** umožní zadat část množství nebo zvolit **Vše**.
Nulový zůstatek položku vyřadí z aktivního přehledu. **Upravit** opraví
název, množství, datum nebo vazbu; **Vyřadit** odstraní položku z aktivní
evidence bez fyzického smazání, například když už v mrazáku není.
Nic se neodečítá při otevření menu, uplynutí data jídla nebo odškrtnutí nákupu.

### Kde zásoby pomohou

| Místo | Zobrazení |
| --- | --- |
| Menu konkrétního pobytu | U jídla kompaktní blok „V mrazáku“: zásoby propojené s hlavním receptem, doplňky nebo jejich surovinami. |
| Plánovač jídel | U konkrétního jídla/skupiny počet relevantních zásob, po rozbalení názvy, množství, stáří a umístění. |
| Nákupní seznam | U suroviny informace o odpovídajících zásobách. Samostatný blok upozorní na hotová jídla podle receptů ve zvoleném období/pobytu. |
| Přehled mrazáku | Všechny aktivní zásoby včetně nepropojených; nejstarší nahoře. Dostupný ze společné navigace kuchyně. |

Příklad u suroviny: „V mrazáku: hrášek 0,5 kg · zamrazeno 12. 9. · horní
zásuvka“. Příklad u jídla: „V mrazáku: guláš 4 porce“.
Bloky označit jako **informativní; nákupní množství se nemění**.
Stejná zásoba se může zobrazit u více vhodných jídel; není tím přidělená
ani rezervovaná. Upozornění nesmí tvrdit, že zásoba pokryje konkrétní počet hostů.

Shody určit výhradně podle uložených ID, včetně surovin všech připojených
receptů a doplňků. Zásobu zobrazit v jednom bloku jen jednou, i když odpovídá
více receptům. Nepropojené položky nabízet v krátkém samostatném přehledu
„Další zásoby k využití“ u menu a nákupu, s odkazem na celý mrazák; neprezentovat
je jako shodu s jídlem. Přehled omezit například na pět nejstarších položek.

Období a rezervace omezují plánovaná jídla, nikoli datum zamrazení zásoby.
Zobrazujeme aktuální fyzický stav mrazáku, ne rekonstrukci stavu k datu pobytu.
U minulých jídel nevydávat dnešní zásoby za historickou dostupnost.
U neaktuálního menu nebo chybějících vazeb zachovat existující upozornění;
nenabízet konkrétní shody ze zastaralého menu. Obecný odkaz na mrazák zůstane.
Stáří je informace pro pořadí využití, nikoli automaticky určená trvanlivost.

### Data a implementační hranice

Navržený samostatný kontext `Kitchen.Freezer` a tabulka `kitchen_freezer_items`:

- UUID, název, zbývající množství (`Decimal`), jednotka, datum zamrazení;
- volitelné `ingredient_id` nebo `recipe_id`, nejvýše jedna z těchto vazeb;
- umístění, poznámka, `archived_at`, `lock_version` a časová razítka.

Databáze i changesety vynutí nezáporné množství, povolené jednotky, platné
cizí klíče a vzájemné vyloučení vazeb. Nová aktivní položka vyžaduje kladné
množství; odebrání do nuly ji atomicky archivuje. Souběžné úpravy/odebrání
nesmějí vést k zápornému stavu ani přepsat novější záznam; použít stávající
vzor optimistického zámku a srozumitelné obnovení po konfliktu.

Archivace suroviny či receptu nesmaže existující zásobu. Vazbu ponechat
dohledatelnou a označit; pro nové propojení nabízet aktivní katalog.
Načítat shody hromadně pro zobrazené recepty/suroviny, nikoli dotazem pro
každý řádek. Stávající návratové výpočty spotřeby a nákupu zachovat; zásoby
připojit jako samostatná prezentační data podle ID.

Změna zásoby nesmí měnit `quantity`, `buy_quantity`, `packages`, zdroje,
otisk nákupní položky ani její lokální odškrtnutí. Informace o mrazáku
v první verzi zobrazovat na obrazovce, mimo stávající tisk nákupního seznamu.
Po vlastní změně obnovit aktuální pohled; na ostatních otevřených obrazovkách
stačí načtení stránky nebo explicitní obnovení dat, bez nové realtime vrstvy.

Administrace i informační bloky zachovají stávající PIN ochranu.
Použít současný LiveView, komponenty a navigační kontext období/pobytu.
Funkce nezapisuje do finančních dokladů, barového skladu ani receptových norem.

## Rozhodnutí

| Datum | Rozhodnutí | Potvrzení / zdroj |
| --- | --- | --- |
| 2026-10-28 | Množství lze při ukládání zadávat. | Výslovné potvrzení uživatele. |
| 2026-10-28 | První etapa má být jednoduchá evidence s užitečnými informacemi na existujících obrazovkách. | Výslovný požadavek uživatele. |
| 2026-10-28 | Množství potřebné koupit se nesmí měnit. | Výslovný požadavek uživatele. |
| 2026-10-28 | Nyní uložit plán a vytvořit PR, nikoli implementovat funkci. | Výslovný požadavek uživatele. |

Ostatní podrobnosti tohoto dokumentu jsou návrhem implementace v rámci
potvrzeného rozsahu, nikoli dalšími jednotlivě potvrzenými požadavky.

## Otevřené otázky

Žádná otázka neblokuje tuto jednoduchou variantu. Výchozí návrh počítá s jedním
sdíleným mrazákem a volitelným textovým umístěním. Konkrétní popisky a pořadí
polí ověřit při ručním průchodu. Externí připomínky a případné rozšíření na
další skladovací místa ponechat další etapě.

## Postup realizace

- [ ] Na začátku implementace ověřit aktuální `main`, AGENTS.md a tento plán.
- [ ] Přidat migraci, schéma a kontext pro evidenci, archivaci a bezpečné odebrání.
- [ ] Přidat administrační přehled, formulář, hledání a navigaci Mrazák.
- [ ] Připravit hromadné párování podle ID surovin/receptů včetně doplňků.
- [ ] Doplnit informační bloky do menu pobytu, plánovače a nákupního seznamu.
- [ ] Doplnit regresní testy neměnnosti nákupů a testy evidence, shod a oprávnění.
- [ ] Aktualizovat návod stravování a stav tohoto plánu podle skutečné implementace.
- [ ] Ručně ověřit zadání a použití na jednom reálném menu pobytu.

## Ověření a podmínky dokončení

- Zapsat hrášek 500 g, vývar 1 l, guláš 4 porce a nepropojený zbytek omáčky.
  Najít položky, opravit je, odebrat část a vyřadit zbytek.
- Dvě várky stejné suroviny s různými daty zůstávají oddělené a řadí se
  od nejstarší. Nepropojená položka zůstává viditelná bez falešné shody.
- Recept i doplněk najdou své zásoby přes ID; podobný název s jiným ID nikoli.
  Převody jednotek respektují stávající pravidla, nevzniká převod kg na porce.
- Změna receptu/menu obnoví relevantní shody. Neaktuální či zrušený pobyt
  nezíská doporučení z neplatného rozpisu. Historický pohled nepředstírá
  historický stav mrazáku.
- Stejná zásoba u dvou pobytů je stále jen informace; nevznikne rezervace
  ani automatické odebrání. Částečný odběr, nulový zůstatek a souběžné změny
  mají testy včetně odmítnutí odběru nad dostupné množství.
- Porovnat výstup `ShoppingList.generate` před a po přidání, úpravě i odebrání
  zásob: stejné spotřeby, nákupní množství, balení, zdroje a fingerprinty.
  Totéž ověřit pro hotové jídlo, jednu skupinu i souběžné pobyty.
- LiveView testy ověří viditelnost bloků, ruční správu a PIN ochranu;
  v prohlížeči zkontrolovat zachování odškrtnutí nákupů a původního tisku.
- Lokální testy standardně nespouštět; dle AGENTS.md je provede GitHub CI
  a výsledky ověří uživatel. Při implementaci splnit předepsané formátování.

## Nasazení a rizika

Implementace přidá novou tabulku, bez odhadovaného počátečního obsahu mrazáku.
První naplnění je ruční inventura. Nevyžaduje externí službu, API klíč,
novou konfiguraci ani změnu účetních integrací.

Hlavním rizikem je zapomenuté odebrání, proto musí být snadné opravit zůstatek
a vyřadit položku. Dalším je záměna doporučení za rezervovanou zásobu nebo
odečet nákupu; řeší ji jasné označení a regresní testy. První verze nevede
úplný deník skladových pohybů ani historickou skladovou kalkulaci.

## Průběh a předání dalšímu chatu

- Hotovo: průzkum existující aplikace, upřesnění jednoduchého rozsahu,
  sepsání plánu. Aplikační kód se tímto plánem nemění.
- Zbývá: celá implementace podle postupu výše.
- Blokuje: nic pro přípravu implementace; tento dokument ji sám nezahajuje.
- Nejbližší další krok: po pokynu k implementaci ověřit aktuální kód a začít
  datovým modelem a jednoduchým formulářem evidence.

Pro nový chat:

> Přečti plán v `docs/plans/2026-10-28-evidence-mrazaku.md`, ověř aktuální
> `main` a začni implementovat jednoduchou evidenci mrazáku. Zachovej nákupní
> množství beze změny a nepřidávej rezervace zásob ani externí notifikace.
> Průběžně aktualizuj stav a dokončené kroky v plánu.

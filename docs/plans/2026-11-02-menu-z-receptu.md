# Tvorba a úprava menu přímo z receptů

- Stav: **rozpracováno**; implementace pokračuje v jedné větvi a jednom draft PR.
- Vytvořeno: 2026-11-02
- Aktualizováno: 2026-11-02
- Podklad: analýza aktuálního `origin/main` (`314d7e8`) a rozhodnutí uživatele v tomto chatu.

## Problém a očekávaný výsledek

Menu dnes obsahuje samostatně zadávané názvy jídel a dodatečně připojené
recepty. Názvy se mohou rozcházet a změna textu dokonce ruší propojení.
Uživatel potřebuje rychle sestavovat jídelníčky pro celý pobyt, vidět obsah
existujících menu, přiřazovat je pobytům a získat nákup podle skutečných porcí.

Menu bude sestava odkazů na existující recepty. Vlastní název má pouze menu
(například „Víkend – méně práce“); názvy jeho jídel se zobrazují z receptů.
Výběr receptu a jeho zařazení do rozpisu budou jedna operace v jednom editoru.

## Potvrzený rozsah a rozhodnutí

| Datum | Rozhodnutí | Zdroj |
| --- | --- | --- |
| 2026-11-02 | Menu znamená celý pobyt jako dnes, nikoli novou knihovnu jednodenních sestav. | Odpověď uživatele |
| 2026-11-02 | Hlavní recept většinou zahrnuje přílohu; samostatná příloha je volitelná. | Odpověď uživatele |
| 2026-11-02 | Přehled menu s náhledy a editor s vyhledáváním, klikáním i drag&drop. | Souhlas s návrhem |
| 2026-11-02 | Menu i pobyt uchovávají pouze návaznost na recept, žádnou kopii receptury. Změna názvu nebo surovin se promítá i do minulosti. | Poslední výslovné upřesnění uživatele |
| 2026-11-02 | Neřešit vydaná jídla, časy podávání, uzavírání ani verze receptur. | Poslední výslovné upřesnění uživatele; nahrazuje dřívější návrh ochrany minulých jídel |
| 2026-11-02 | Hromadné načítání pro editor/náhledy a oprava N+1 v detailu spotřeby jsou schválené. | Výslovný souhlas uživatele |
| 2026-11-02 | Nyní uložit plán; aplikaci implementovat až v jiném vlákně. | Zadání uživatele |

Změna **sestavy šablony** nadále automaticky nepřepisuje sestavu již přiřazeného
pobytu. Pobyt má vlastní odkazy na vybrané recepty a vlastní ruční úpravy.
Změna **samotného receptu** se projeví všude, kde na něj vede odkaz, bez
ohledu na datum. Kopie sestavy při přiřazení není kopií receptur.

Mimo rozsah jsou dietní varianty pro podskupiny hostů, nové skladové pohyby,
automatické odečítání zásob, nové účetní doklady a změny historických cen
nákupů. Přepočet kuchyňských odhadů z aktuální receptury nemění uložené
nákupy, platby, vydané dokumenty ani účetní snapshoty.

## Současný stav a podklady

- `lib/cozy_checkout/meals/menu_planning.ex`: sestavení rozpisu, CRUD variant,
  kompatibilita s pobytem, náhled přiřazení a ochrana ručních úprav.
- `meals/menu_variant.ex`, `menu_variant_item.ex`, `booking_menu.ex`,
  `booking_menu_item.ex`: jeden hlavní recept na podání, texty a kopie sestavy
  pobytu. Aktuální validace vyžaduje úplný rozpis i neprázdný text.
- `recipes/links.ex`, `variant_supplement.ex`, `booking_supplement.ex`:
  vazby doplňků s pořadím, párování přes přesný název, odpojování při změně
  textu, transakční zámky a kontrola souběžných změn.
- `recipes.ex`: hledání dnes načítá celý katalog včetně surovin a filtruje
  v paměti. `recipes/consumption.ex` načítá vybrané recepty jednotlivě (N+1).
- `kitchen/shopping_list.ex`: již hromadně načítá recepty a suroviny,
  sčítá spotřebu, používá dětské koeficienty a zaokrouhluje nákup až po součtu.
  Kontrola chybějících doplňků ale stále porovnává textové názvy.
- `kitchen_costs/reports.ex`: navazující odhady nákladů z receptur; zachovat
  význam historických cen a ověřit popis použití aktuální receptury.
- `lib/cozy_checkout_web/live/meal_planner_live/variants.*`,
  `booking_live/menu.*`, `recipe_live/links.*`, `meal_planner_live/index.*`
  a `print.*`: editor, přiřazování, plánovač a tisk.
- `lib/cozy_checkout_web/components/kitchen_components.ex`: současný souhrn
  připojených receptů a sdílený `searchable_picker/1`.
- Migrace `20261021190000_create_stay_menu_variants.exs` a
  `20261021210000_create_recipe_catalog.exs`: současné tabulky a vazby.
- Testy `test/cozy_checkout/meals/{menu_variants,booking_menus}_test.exs`,
  `test/cozy_checkout/recipes/{links,consumption}_test.exs`,
  `test/cozy_checkout/kitchen/shopping_list_test.exs` a související LiveView testy.

Podkladové JSON soubory obsahují 9 menu a 56 receptů; nejde o audit živé DB.
Příklad neshody: „Kuře na paprice s rýží“ v menu vs. „Kuře na paprice“
v katalogu. Podobný název není důkaz, že recept obsahuje požadovanou přílohu.

Inspirace: [Paprika – knihovna receptů vedle plánovače](https://www.paprikaapp.com/help/windows/)
a [Plan to Eat – nákup z naplánovaných receptů za období](https://learn.plantoeat.com/help/create-a-shopping-list-app).
Jde o inspiraci ovládáním; konkrétní návrh respektuje místní plánování pobytů.

## Navržené ovládání

### Přehled menu

- Kompaktní seznam: název, délka, penze, první/poslední jídlo, krátký výčet
  hlavních receptů a odvozený stav „Připravené“ / „Chybí 2 podání“ / „K dořešení“.
- Hledání podle názvu menu i připojených receptů; filtry délky, penze a stavu.
- Po najetí nebo zaměření klávesnicí náhled po dnech a podáních včetně doplňků.
  Kliknutím lze rozpis ponechat rozbalený; na dotyku je vše dostupné kliknutím.
  Náhled nesmí zmizet při přesunu kurzoru do něj; dlouhé menu má posuvný obsah.
- Akce Nové menu, Upravit, Duplikovat, Přiřadit pobytu; Archivovat v nabídce.
  Při vstupu z konkrétního pobytu zachovat navigační kontext a předvybrat pobyt.
  Při samostatném vstupu nabídnout vyhledávatelný výběr vhodného pobytu.

### Editor menu

- Nahoře název a nastavení rozpisu jako dnes. Na desktopu vlevo dny s podáními,
  vpravo knihovna receptů s vyhledáváním a možností zobrazit suroviny receptu.
- Aktivovat podání a přidat recept tlačítkem nebo přetáhnout recept z knihovny
  do označené oblasti hlavního receptu či doplňků. Text cíle jasně říká, zda
  půjde o přidání doplňku nebo nahrazení hlavního receptu.
- Knihovna se přetažením nemění. Přesun mezi podáními a jejich kopírování mají
  oddělené, pojmenované akce; veškeré drag&drop operace mají tlačítkový ekvivalent.
- Hlavní recept/bufet je jeden; doplňků může být více, v explicitním pořadí.
  Stejný recept nesmí být v jednom podání dvakrát ani současně hlavní a doplněk.
  Mezi různými podáními se opakovat může. Samostatná příloha není povinná.
- Výměna, odebrání, změna pořadí doplňků a vrácení poslední neuložené změny.
  Kopie celého dne, duplikace menu a použití vybraného bufetu na všechny snídaně.
  Kopie dne respektuje podání dostupná v cílovém dni a před přepsáním ukáže dopad.
- Počet vyplněných podání, viditelné nedostatky a možnost uložit rozpracované menu.
  Explicitní Uložit uloží rozpis i vazby atomicky; Zrušit neuložené změny zahodí.
  Odchod s neuloženými změnami upozorní uživatele.
- Změna délky/penze/hranic zachová vazby na shodném dni a podání a před odstraněním
  vyplněných podání ukáže dopad. Aktualizace rozpisu nesmí tiše ztratit recepty.
- Na mobilu se knihovna otevře přes Přidat/Vyměnit recept. Použít existující
  vizuální styl a sdílené komponenty; JavaScript hook bude v `assets/js`.

### Pobyt, plánovač a nákup

- Přiřadit lze připravené menu odpovídající délce, penzi a hranicím pobytu.
  Rozpracované menu se může zobrazit jako nedostupné s důvodem.
- Použít stávající náhled konkrétních dat, porcí, konfliktů a ochrany ručních
  úprav. Nahrazení existující sestavy zůstává explicitní operací.
- Editor podání pobytu použije stejný výběr receptů. Změna odkazů v pobytu
  označí podání jako ručně upravené; přejmenování receptu samo takovou úpravou není.
- Souhrny, plánovač, detail, tisk a nákup zobrazují názvy ze stejného resolveru
  receptových vazeb. Poznámka k podání je samostatná a neovlivňuje spotřebu.
- Z menu pobytu vede akce Zobrazit nákup pro tento pobyt; společný nákup za
  období pro více pobytů zůstává zachován. Neúplné staré menu poskytuje pouze
  částečný výpočet s konkrétními upozorněními, nikdy dojem úplného nákupu.
- Změna receptu se projeví při dalším načtení/přepočtu i pro minulé datum.
  První verze nepotřebuje živé přepisování již otevřených obrazovek přes PubSub.

## Data a pravidla implementace

Zachovat `recipe_id` a tabulky doplňkových vazeb s `position`. Nevytvářet
snapshoty surovin, tabulky verzí receptur, vazby na vydání jídla ani časové úlohy.
Existující `lock_version` a `source_revision` nadále chrání souběžné úpravy
sestavy; nejsou verzí receptury a nemají se kvůli tomuto zjednodušení odstranit.

Oddělit validaci **uložitelného rozpracovaného menu** od **připravenosti
k přiřazení**. Rozpis má vždy jedno podání pro každý očekávaný slot; prázdný
hlavní recept je dovolen při uložení konceptu, nikoli při novém přiřazení.
Připravenost odvozovat z odkazů, dostupnosti receptů a nevyřešených starých položek,
nikoli z ručně přepínaného příznaku. Stávající pobyty s neúplnými vazbami se nemažou.

Pro nový tok se názvy jídel nepřijímají jako nezávislá editovatelná data.
Změny schématu udělat novou migrací, nikoli úpravou historických migrací:

- Umožnit nevyplněné staré `menu_text`, pokud tomu brání DB omezení.
- Doplnit samostatnou volitelnou poznámku podání do šablony i pobytu.
- Zachovat původní `menu_text`/`supplements` pro bezpečný převod jako legacy data.
  Explicitně odlišit dořešené podání od podání čekajícího na kontrolu (např.
  nullable `recipe_links_reviewed_at` u šablon i pobytů). Přesné názvy polí
  ověřit při implementaci; již propojené recepty mají při zobrazení přednost.
- Po dořešení nesmí starý text ovlivňovat zobrazený název, připravenost ani
  nákup. Převod nezaměňuje starý název automaticky za uživatelskou poznámku.

Kontextová operace uloží nastavení, podání, hlavní a doplňkové odkazy v jedné
transakci s kontrolou očekávané revize. Server ověří ID receptů, duplicity,
pořadí, vlastnictví položek i archivaci; ID z drag&drop není důvěryhodné samo o sobě.
Změna textu poznámky už nikdy neodpojí recept. Starý samostatný editor vazeb
přesměrovat nebo sjednotit s novým tokem, aby neobcházel tato pravidla.

Archivované recepty zůstávají viditelné a použitelné ve stávajících vazbách
včetně nákupního výpočtu. Nově je nelze vybrat. Menu s archivovaným receptem
vyžaduje náhradu před novým přiřazením; duplikace takového menu vytvoří koncept
s upozorněním. Zachovat FK, UUID a existující admin PIN ochranu všech cest.

## Převod existujících menu

1. Zachovat stávající odkazy v šablonách i pobytech a původní texty jako podklad.
2. Jednoznačné přesné shody lze propojit; u neúplných, odlišných nebo rozporných
   textů vyžádat kontrolu. Žádné automatické přibližné párování podle názvu.
3. U každé nevyřešené položky ukázat původní text a současné/nabízené recepty.
   Uživatel vybere správné recepty nebo výslovně odstraní zastaralou položku.
   Existující vazby se nesmějí tiše přepsat podle textu.
4. Zkontrolovat zvlášť přílohy: „s rýží“ v názvu není důkaz rýže v receptu.
   Suroviny se nekopírují ani automaticky nedoplňují.
5. Upravit import podkladových variant na nový tok a zachovat jeho idempotenci.
   Převod je opakovatelný a nesmí přepsat již ručně zkontrolované položky.

Převod má pokrýt i menu přiřazená pobytům, ne pouze šablony. Legacy fallback
musí být jasně označený a nesmí se stát druhým trvalým zdrojem názvů.

## Výkon

N+1 v `Consumption.for_booking_item/1` bylo uživateli vysvětleno a jeho oprava
je schválená. Načíst vybrané recepty se surovinami hromadně. Seznam menu načítá
vazby a názvy pro celou stránku dávkově; hover neprovádí dotaz pro každý řádek.
Vyhledávání vrací omezený počet lehkých záznamů bez všech surovin katalogu,
s debounce a možností dalších výsledků. Zachovat hledání bez ohledu na
velikost písmen a diakritiku; SQL strategii/indexy zvolit podle dostupné DB.
Již vybrané recepty zůstávají v editoru viditelné i mimo aktuální výsledky.

## Postup realizace

- [ ] **1. Ověřit aktuální main a dopady:** projít uvedené moduly, všechny čtenáře
  `menu_text`/`supplements`, plánovač, tisk, freezer souhrny a nákladové reporty.
  Potvrdit strategii legacy kontroly a rozpracovaných podání vůči DB constraints.
- [ ] **2. Datový základ a kontexty:** přidávací migrace, atomické uložení vazeb,
  odvozená připravenost, společné zobrazení názvů, bezpečný převod a import.
- [ ] **3. Editor:** knihovna receptů, přidání/výměna/odebrání kliknutím, koncepty,
  kopie dne/menu, bufet pro snídaně a bezpečná změna rozpisu; následně drag&drop,
  pořadí doplňků, undo a mobilní/klávesnicové ovládání.
- [ ] **4. Přehled:** hledání podle menu i receptů, filtry, obsahové náhledy,
  stavy, duplikace a přechod k přiřazení pobytu.
- [ ] **5. Návaznosti:** společný výběr v pobytu, kontrola přiřazení, názvy
  v plánovači/tisku/nákupu, odstranění textového porovnávání u dořešených položek,
  hromadné načítání a zachování přímé cesty k nákupu.
- [ ] **6. Ověření a dokumentace:** regresní testy, ruční průchod desktop/tablet,
  dokumentace skutečné funkce a aktualizace stavu tohoto plánu.

### Průběh implementace

2026-11-02 — první implementační část (výkonový základ):

- Přidáno databázové vyhledávání receptů bez ohledu na velikost písmen a
  diakritiku; výběr vrací nejvýše 30 lehkých záznamů a nabízí další stránku.
  Nevyžaduje novou databázovou extenzi. Základní katalog filtruje stejným SQL
  výrazem před načítáním surovin. Jde o průchod názvy, nikoli indexové hledání.
- Vybrané recepty se surovinami se načítají dávkově v pořadí výběru, včetně
  archivovaných receptů. Detail spotřeby už nenačítá každý recept zvlášť.
- Stávající výběr používá nové hledání; změna výběru ani kalkulátoru neresetuje
  načtené stránky. Vybrané recepty jsou viditelné i mimo výsledky hledání.
- Doplněny regresní testy stránkování, diakritiky, archivace a počtu dotazů.
- Tato část zatím nemění datový model ani pravidla ukládání/přiřazení menu.
  Kroky 1–6 výše zůstávají otevřené; další změny patří do stejného PR.

## Ověření a podmínky dokončení

- Nové menu vznikne pouze výběrem receptů, bez psaní jejich názvů a bez
  samostatné návštěvy editoru vazeb; koncept lze uložit a znovu otevřít.
- Připravenost rozlišuje prázdné hlavní podání, legacy doplněk a archivovaný
  recept; koncept nelze přiřadit obejitím UI. Snídaňový bufet je skutečný recept.
- Kopie a změna rozpisu zachovávají správná ID, pořadí a hranice podání;
  zrušení editace nic nezapíše. Neplatný vstup nebo konflikt vrátí celou transakci.
- Změna názvu receptu aktualizuje všechny souhrny a tisk a nevytvoří falešné
  hlášení „doplněk bez receptu“. Změna poznámky zachová vazby.
- Změna surovin ovlivní výpočet pro budoucí i minulé datum; neexistuje ukládání
  receptury k menu, potvrzování vydání ani časový cutoff.
- Úprava sestavy šablony sama nepřepíše již přiřazený pobyt; explicitní opětovné
  přiřazení zachová ochranu ručních úprav a neaktuální náhled je odmítnut.
- Spotřeba zahrnuje hlavní i doplňky právě jednou. Zachovat počty dospělých/dětí,
  koeficienty, Decimal, převody jednotek, součty napříč pobyty i zaokrouhlení balení.
- Převod zachová existující vazby, upozorní na neshody a chybějící přílohy;
  opakování importu/převodu nepřepíše rozhodnutí uživatele.
- Rozšířit testy kontextů a LiveView v uvedených sadách; regresně ověřit
  historický přepočet, archivaci, PIN, neplatná ID a souběžné editace.
- Ověřit dávkové dotazy při větším počtu menu/receptů; počet dotazů neroste
  po jednotlivých položkách. Ručně ověřit vyhledávání, hover/focus/kliknutí,
  drag&drop, tlačítkové alternativy, mobil a odchod s neuloženými změnami.
- Formátování a testovací režim podle AGENTS.md. Lokální testy standardně
  nespouštět; CI a jeho výsledky ověří uživatel. Nečekat ani nepollovat CI.

## Nasazení, rizika a konfigurace

Nasadit přidávací migrace spolu s kompatibilním čtením starých položek.
Historické texty v této etapě nemažou migrace; nevyřešená data zůstávají dostupná
k opravě. Návrat ke staré aplikaci by nemusel správně interpretovat nové koncepty
a aktuální názvy, proto před rollbackem ověřit kompatibilitu nově uložených dat.
Žádná nová externí služba, tajemství ani konfigurace časů podávání není potřeba.

Změny receptů záměrně mění i zpětně přepočtenou spotřebu a kuchyňské odhady.
UI nesmí tyto odhady vydávat za neměnnou historickou skutečnost. Nákupní checklist
musí dál reagovat na změněná množství svým existujícím fingerprint mechanismem.

## Otevřené otázky a předání dalšímu chatu

Žádná blokující obchodní otázka. Konkrétní neshody legacy jídel se řeší při
kontrole dat, nikoli odhadem v implementaci. Přesné migrační sloupce, způsob
dotazování a případná drag&drop knihovna jsou technická rozhodnutí podle
aktuálního repozitáře; přednost mají existující závislosti a jednoduché řešení.

- Hotovo: analýza kódu, migrací a testů; inspirace; vyjasnění rozsahu a tento plán.
- Zbývá: datový model, atomický editor menu, převod legacy dat, přehled, návaznosti a jejich ověření. Výkonový základ je implementovaný; lokální testy nebyly spuštěny.
- Blokuje: žádná obchodní otázka.
- Nejbližší krok: pokračovat ve stejné implementační větvi a draft PR; dokončit audit čtenářů legacy textů a datový základ podle kroků 1–2.
- Validace plánu: lokální testy se nespouštějí; výsledky CI ověří uživatel.

Předávací zadání: „Implementuj plán `docs/plans/2026-11-02-menu-z-receptu.md`.
Menu a pobyty mají pouze odkazy na recepty; změny receptů platí i do minulosti.
Nezaváděj snapshoty receptur ani evidenci vydaných jídel. Ověř aktuální kód
a postupuj podle nedokončených kroků a AGENTS.md.“

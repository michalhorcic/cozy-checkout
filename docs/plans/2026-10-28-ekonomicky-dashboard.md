# Ekonomický dashboard firmy z ABRA Flexi

- Stav: **návrh**; rozsah a oddělení modulu potvrzené, účetní podklady a živé API čekají na ověření. Implementace nezahájena.
- Vytvořeno: 2026-10-28
- Aktualizováno: 2026-10-28
- Zadání: přehled ekonomiky celé firmy pro uživatele bez účetní specializace; samostatně uspořádaný kód s minimálním dopadem na ostatní aplikaci.
- Související: [Integrace ABRA](../integrations/ABRA_INTEGRATION.md), [ověření s účetní](../integrations/ABRA_ACCOUNTANT_REVIEW.md), [nákladovost kuchyně](2026-10-27-nakupy-a-nakladovost-kuchyne.md).
- Tento PR ukládá plán, nikoli implementaci ani pokyn k nasazení.

## Problém a očekávaný výsledek

Majitel potřebuje rozumět tržbám, nákladům, výsledku hospodaření, penězům
na účtu a v pokladně a neuhrazeným pohledávkám a závazkům. Účetní výsledek
musí být oddělený od příjmů a výdajů peněz. Každá karta vysvětlí význam,
období, zdroj a úplnost dat; detail umožní dohledat účty a podkladové zápisy.
Chybějící nebo neověřená data nesmějí vypadat jako ověřená nula.

## Potvrzený rozsah

- Celá firma, jejíž činnost tvoří v podstatě Jindřichův dům.
- ABRA obsahuje účetnictví od července 2026; počáteční stavy se musí ověřit.
- Hospodářský rok začíná 1. července a končí 30. června. Počátek sledování
  je 1. 7. 2026; zkratka období v dodaných sestavách je `2026`.
- Ubytování a stravování dohromady, bar zvlášť. Výnosy z pronájmu prostor
  ponechat do rozhodnutí samostatně; společné náklady nerozdělovat odhadem.
- Jeden bankovní účet, jedna fyzická hotovost, pouze CZK. V účetnictví jsou
  dva účty hotovosti, jejich vztah se musí ověřit.
- Účetnictví se doplňuje měsíčně. Kompletnost září 2026 není potvrzená.
- Primární rozhraní uživatele je webová ABRA; dostupná je i desktopová.

## Současný stav a ověřené podklady

Na `origin/main` jsou samostatné kontexty `Sales`, `Billing` a moduly `Abra`.
`Abra.Client` používá Req a umí čtení faktur, banky a vazeb i vzdálené zápisy.
`Abra.Bank` udržuje místní zrcadlo jednoho nastaveného bankovního účtu pro
párování pobytových plateb. Jeho životní cyklus a přepínače patří fakturaci,
nikoli ekonomickému reportingu. `Abra.Transfers` řeší stav účetních přenosů.
Stávající statistiky vycházejí ze Sales, nejsou celofiremní výsledovkou.

Ověřené integrační body: `lib/cozy_checkout_web/router.ex` obsahuje admin
pipeline i LiveView `on_mount` s PINem; `admin_navigation.ex` společnou navigaci;
`config/config.exs` registruje Oban fronty a cron. Použijeme stávající Repo,
Req, Oban, Decimal, CurrencyHelper a sdílené komponenty.

### Podklady z analýzy exportů 28. 10. 2026

Uživatel dodal předvahu a soupis nákladů a výnosů, následně jejich aktualizované
XLSX a screenshoty filtrů. Zdrojové soubory ani osobní údaje nepatří do Gitu.
Pro testy vzniknou syntetické, anonymní příklady; tabulka níže uchovává jen
kontrolní agregáty potřebné k vysvětlení otevřených otázek.

| Zjištění | Důsledek |
| --- | --- |
| Předvaha: konec 09/2026, počet měsíců 6; data shodná s původním exportem | Nastavení zasahuje před začátek hospodářského roku; pro červenec–září použít 3 měsíce. Stejný výsledek nepotvrzuje, jak API rozsah ořízlo. |
| Výsledovka: celé období `2026`, CZK, daňové i nedaňové účty | Nelze ji bez dalšího porovnat s předvahou do září; může obsahovat pozdější zápisy. |
| Předvaha: výnosy 225 559,94 Kč, náklady 643 266,77 Kč, rozdíl −417 706,83 Kč | Kontrolní výpočet z exportu, nikoli potvrzený konečný výsledek firmy. |
| Výsledovka: výnosy 357 120,77 Kč, náklady 963 462,72 Kč, rozdíl −606 341,95 Kč | Součet obou stran po doplnění sloupce Zůstatek MD; jiné časové omezení. |
| Odpisy: předvaha 0 Kč, výsledovka 185 384 Kč | Ověřit datum a periodicitu účtování; rozdíl nelze automaticky připsat říjnu. |
| Banka `221001`: počátek 0 Kč, konečný účetní zůstatek −1 236 282,91 Kč | Ověřit počáteční stavy a pohyby proti bankovnímu výpisu. |
| Pokladny `211001` a `211100`: −21 098,90 Kč a 16 680 Kč | Součet −4 418,90 Kč není skutečná fyzická hotovost; sloučení zobrazení nesrovnalost neopraví. |
| Obraty předvahy MD a Dal se shodují; zůstatky početně navazují | Aritmetická shoda nedokazuje úplnost účetnictví. |

## Oddělení modulu a hranice změn

Samostatný kontext ve stávající Phoenix aplikaci, nikoli nový servis,
umbrella aplikace nebo obecná přestavba účetních integrací. Návrh struktury:

```text
lib/cozy_checkout/economics.ex                 # veřejné rozhraní kontextu
lib/cozy_checkout/economics/
  abra_client.ex                              # pouze GET, vlastní kontrakt
  config.ex
  sync.ex
  sync_worker.ex                              # vlastní Oban worker
  reports.ex
  account_mapping.ex
  data_quality.ex
  source.ex                                  # Ecto schémata podle potřeby
  import_run.ex
  snapshot.ex
  account_balance.ex
  monthly_turnover.ex
  open_item.ex
lib/cozy_checkout_web/live/economics_live/
  index.ex
  detail.ex
  settings.ex
  components.ex
test/cozy_checkout/economics/
test/cozy_checkout_web/live/economics_live/
test/support/economics_fixtures.ex
priv/repo/migrations/*_create_economics_*.exs
```

Jména interních souborů lze zjednodušit podle skutečných API odpovědí;
hranice kontextu a odpovědnosti zůstávají. UI volá pouze `Economics`, nikoli
přímo klienta, Repo nebo interní schémata. Žádný ostatní obchodní kontext
nesmí být závislý na Economics. Zrušení modulu neovlivní provozní transakce.

Povolené minimální zásahy mimo modul při implementaci:

| Místo | Jediný potřebný účel |
| --- | --- |
| `router.ex` | Cesty `/admin/economics` a podstránky ve stávající chráněné admin session |
| `admin_navigation.ex` | Odkaz Ekonomika |
| `config/config.exs`, `config/runtime.exs` | Vlastní konfigurace, fronta a plánování synchronizace |
| `priv/repo/migrations` | Pouze nové tabulky s prefixem `economics_` |
| Dokumentace a test support | Popis funkce, syntetické fixtures |

Bez změn schémat, platebních toků, exportů a workerů Sales/Billing/Abra,
bez nových sloupců na objednávkách nebo dokladech a bez použití jejich tabulek
jako úložiště reportingu. Existující `Abra.Client` nereorganizovat kvůli sdílení:
malý vlastní GET klient je zde přijatelný za cenu omezené duplicity transportu.
Sdílet existující infrastrukturní helpery, ne obchodní stav. Grafy první verze
řešit serverově a existujícími prostředky bez globálních JS/CSS změn.

## Uživatelský návrh a výpočty

- Filtry: měsíc, rozsah měsíců, hospodářský rok; přesná data vždy viditelná.
  Při změně roku použít skutečné hranice z ABRY, nikoli rok v názvu období.
- Karty: tržby, další výnosy, náklady, účetní výsledek, banka, hotovost,
  neuhrazené pohledávky a závazky (zvlášť po splatnosti).
- Měsíční vývoj výnosů/nákladů/výsledku, rozpad nákladů, blížící se splatnosti.
  Srovnání s minulým rokem není dostupné, pokud před červencem 2026 chybí data.
- Volitelná následující etapa: skutečné příjmy/výdaje peněz; až po ověření
  banky a pokladen. Vlastní převody se nesmějí počítat jako externí tok.
- Náklady a výnosy vycházejí z účetních zápisů a data účtování, nikoli data
  platby nebo součtu vystavených faktur. Respektovat opravné a záporné zápisy.
- Náklady = MD minus Dal nákladových účtů, výnosy = Dal minus MD výnosových
  účtů; typ účtu ověřit podle účtového rozvrhu. Výsledek = výnosy − náklady.
  Rozlišit výsledek před/po dani podle skutečně zahrnutých účtů; nepoužívat
  automaticky označení čistý zisk nebo EBITDA. Zahrnout i nedaňové náklady.
- DPH, rekreační poplatky, přijaté zálohy, odpočty záloh, pořízení majetku
  a splátky jistiny nejsou automaticky tržbou/nákladem. Žádné přičítání
  lokálních Cozy dokladů k jejich kopiím v ABŘE. Odpisy oddělit od peněz.
- Stavy banky/pokladny vycházejí z ověřeného počátku a pohybů do zvoleného
  dne, ne pouze ze součtu pohybů od spuštění aplikace. Jedna karta hotovosti
  může zahrnout dva potvrzené účetní účty s dohledatelným rozpisem.
- Pohledávky a závazky zobrazovat z otevřených položek k danému dni včetně
  částečných úhrad, dobropisů a starších neuhrazených dokladů; neodvozovat
  splatnost z konečného zůstatku účtu. Nesnižovat vzájemně nesouvisející dluhy.
- Všude Decimal a stávající CurrencyHelper; nezaokrouhlovat dílčí výpočty
  na celé Kč. Měna jiná než CZK vyvolá viditelné upozornění, ne tiché sečtení.

### Výchozí návrh mapování (není účetní schválení)

| Kategorie | Účty / stav |
| --- | --- |
| Ubytování a stravování | `602001`; potvrdit, že zahrnuje stravování |
| Pronájem prostor | `602002`; zatím samostatně |
| Bar | `604001`; potvrdit výhradní použití pro bar |
| Další výnosy | `648100` a další výnosové účty samostatně |
| Potraviny, energie, mzdy | `501100`, `502001`, `521001` |
| Úklid a praní | `501300`, `518400` |
| Účetní/právní služby, opravy | `518200`, `511001` |
| Ostatní služby, odpisy | `518001`, `551001` samostatně |
| Banka, hotovost | `221001`; `211001` + `211100`, zůstatky neověřené |

Nový nebo nepřiřazený účet zůstane v celkovém součtu podle svého typu a zobrazí
se v kategorii Nezařazeno; nesmí tiše vypadnout. Mapování uložit v modulu,
verzovat a zpřístupnit pro kontrolu. Pravidla pro neznámý typ účtu zastaví
publikaci příslušného výsledku jako úplného.

## API a synchronizace

Oficiální dokumentace byla v chatu otevřena webovým nástrojem. Přímý přístup
z vývojového prostředí byl blokovaný síťovou politikou; živá firemní ABRA
nebyla volána. Zpřístupnění dokumentace není ověření firemního API.

Zdroje:

- [Účetní výstupy REST API](https://podpora.flexibee.eu/cs/articles/4971496-ucetni-vystupy-v-rest-api)
- [Pohyby na účtech](https://demo.flexibee.eu/devdoc/pohyb-na-uctech)
- [Stavy účtů](https://podpora.flexibee.eu/cs/articles/4744465-stavy-uctu)
- [Stav úhrad k datu](https://demo.flexibee.eu/devdoc/saldo-k-datu)
- [Obratová předvaha](https://demo.flexibee.eu/devdoc/obratova-predvaha)
- [Účetní období](https://podpora.flexibee.eu/cs/articles/4542020-ucetni-obdobi)

První technický krok je read-only ověření podporovaných evidencí, formátů,
verze, licence a oprávnění v konkrétní firmě. Kandidáti: `ucetni-obdobi`,
účtový rozvrh, `pohyb-na-uctech`/`ucetni-denik`, `stav-uctu`, `hlavni-kniha`,
`saldo-k-datu`; předvaha a výsledovka slouží také ke kontrolnímu porovnání.
Ne všechny tiskové výstupy mají shodný JSON kontrakt nebo parametry.
Dokumentace se v detailech parametrů předvahy liší; přesný kontrakt potvrdit
na používané verzi a uložit anonymizované fixtures. HTTP 200 samo nepotvrzuje,
že server aplikoval filtr: ověřit data a hranice zvoleného období.

Klient smí provádět jen GET, bez přepočtu účetnictví, párování nebo zápisů
v ABŘE. Preferovat samostatného API uživatele s právem číst potřebné evidence.
Návrh konfigurace: `ECONOMICS_ENABLED=false`, `ECONOMICS_ABRA_BASE_URL`,
`ECONOMICS_ABRA_COMPANY_ID`, `ECONOMICS_ABRA_USERNAME`,
`ECONOMICS_ABRA_PASSWORD`. Žádný skrytý fallback na testovací firmu ubytování;
cíl explicitně zobrazit administrátorovi, tajné hodnoty nikdy neukládat do dat.

- Samostatná Oban fronta `economics_sync` se souběžností 1, unikátní job pro
  firmu/rozsah, timeouty a retry přes Oban. Selhání neblokuje bar ani billing.
- Návrh první verze: ruční aktualizace a denní plánování; cron při vypnutém
  modulu neprovádí HTTP. Četnost potvrdit po měření objemu a API limitů.
- Číst omezená období a jen potřebná pole; účetní deník může být drahý
  i při stránkování. UI čte místní snapshot, nikdy nespouští dlouhý HTTP dotaz.
- Explicitně vybrat stav zaúčtování (dokumentované `postingState`) a ověřit
  jeho shodu s kontrolní sestavou. Pro výsledek primárně zaúčtovaná data;
  nezaúčtovaná evidovat odděleně jako předběžná, nepřimíchat bez označení.
- První import zahrne potřebný počátek a starší otevřené položky. Aktualizace
  znovu načte zvolená období i při dodatečných opravách. První verze může
  obnovovat celý sledovaný rok po krátkých intervalech; Changes API není
  předpokládanou zárukou úplnosti odvozených účetních výstupů.
- Sestavovat nový snapshot bokem a zveřejnit jej atomicky až po úplném
  načtení a kontrolách. Výpadek ponechá poslední úspěšná data s upozorněním;
  chybějící řádky odstranit z aktivního obrazu až po kompletním průchodu.
- API negarantuje společný snapshot všech evidencí: ukládat časový rozsah
  importu, provádět součtové kontroly a při rozdílu označit/nepublikovat
  ověřený stav a nabídnout opakování. Neprohlašovat vzdálenou atomicitu.

## Vlastní data a kvalita

Pouze přidávací migrace a tabulky `economics_*`, UUID klíče a timestamps.
Návrh minimálních entit: zdroj s identitou instance/firmy; běh importu
s rozsahem a chybou; snapshot s aktivní verzí; účty a mapování; měsíční obraty,
počátky a zůstatky; otevřené položky; potvrzení úplnosti a kontrolní zjištění.
Přesná granularita podle ověřeného API, bez zbytečných kopií celých dokladů.
Unikátní klíče zahrnou zdroj, snapshot, účet, období a případné dimenze;
identita položek musí být stabilní a nesmí se opírat jen o číslo faktury.

Oprava účetnictví vytvoří novou verzi reportu; nemění místní vydané doklady.
Změna cílové firmy nesmí sloučit data s předchozím zdrojem. Uchovávat nezbytné
reference a součty, ne osobní/mzdové detaily ani celé HTTP odpovědi v logu.
Retenci historických snapshotů stanovit před nasazením; poslední úspěšnou
verzi nesmazat kvůli neúspěšnému importu.

Oddělit tři informace:

1. Technická čerstvost: kdy se data naposledy kompletně načetla.
2. Účetní úplnost: do kterého měsíce ji uživatel po dohodě s účetní potvrdil,
   kdy a na jakém podkladu. Podání DPH ani datum synchronizace ji nenahrazuje.
3. Kontrolní shoda: srovnání banky, hotovosti a sestav, neznámé účty či filtry.

Výchozí stav je neověřený, včetně září. Dodatečná změna potvrzeného měsíce
vyvolá opětovnou kontrolu. Potvrzení úplnosti je záznam v Economics,
nikoli uzamčení období v ABŘE. Zápornou hotovost neskrývat, nenulovat ani
neopravovat automaticky. Banka může být přečerpaná; samotné záporné znaménko
není důkaz chyby, rozhoduje porovnání s výpisem a financováním.

## Otevřené otázky a podklady

Uživatel předá účetní dotazy. Do odpovědi ponechat příslušné ukazatele
neověřené; příprava modulu a syntetických testů na odpovědích nezávisí.

### Text pro účetní

> Připravujeme ekonomický přehled firmy od 1. 7. 2026, hospodářský rok
> 1. 7.–30. 6. Prosím o potvrzení následujících bodů:
>
> 1. Je září 2026 kompletně zaúčtované včetně mezd, odpisů a časového rozlišení?
>    Pokud ne, který měsíc lze považovat za kompletní?
> 2. V předvaze do září má účet 221001 počátek 0 Kč a konečný zůstatek
>    −1 236 282,91 Kč. Jsou převzaté počáteční stavy banky a ostatních účtů?
>    Jaké jsou správné stavy k 1. 7. 2026 a odpovídá banka výpisu k 30. 9.?
> 3. Máme jednu fyzickou hotovost, ale účty 211001 a 211100 vykazují
>    −21 098,90 Kč a 16 680 Kč. Jde o dvě analytiky téže hotovosti?
>    Jak mají navazovat na pokladní evidenci a skutečný stav?
> 4. Obsahuje 602001 ubytování i stravování a 604001 výhradně bar?
>    Jak vykazovat 602002 (pronájem prostor) a 648100 (odměna)?
> 5. V celoročním soupisu jsou odpisy 185 384 Kč, v předvaze do září 0 Kč.
>    K jakému datu a za jaké období jsou odpisy zaúčtované? Účtují se měsíčně,
>    nebo jednorázově, a jak máme interpretovat průběžný měsíční výsledek?
> 6. Odpovídají zůstatky záloh, starých závazků a neuhrazených pohledávek
>    přechodu do ABRY? Jsou starší otevřené položky převedené jednotlivě,
>    aby bylo možné určit jejich splatnost a úhrady?
> 7. Pro kontrolní srovnání prosím o předvahu a výsledovku za shodné období
>    1. 7.–30. 9. 2026 se stejným filtrem zaúčtování, včetně nedaňových účtů.

Od uživatele zbývá získat bankovní zůstatky k 30. 6. a 30. 9. 2026 (stačí
částky), případný evidovaný stav hotovosti ke stejnému datu a rozhodnutí,
zda pronájem zobrazovat samostatně. Historickou hotovost neodhadovat z dnešní.
Technicky zbývá ověřit API přístup, dostupnost požadovaných výstupů a rozsah
oprávnění; hesla předat konfigurací prostředí, nikoli v chatu nebo v Gitu.

## Postup realizace v samostatných PR

- [ ] **1. Kontrakt a podklady:** ověřit GET evidence, formáty, hranice období,
  zaúčtování, počáteční stavy a historické saldo v testovací firmě; zapsat
  odpovědi a syntetické fixtures. Výstupem je přesné mapování API → ukazatel.
- [ ] **2. Izolovaný základ:** kontext Economics, vlastní konfigurace a klient,
  přidávací migrace, vypnutý přepínač, vlastní fronta. Bez změny běžných toků.
- [ ] **3. Import a výpočty:** verzované snapshoty, měsíční obraty, mapování,
  počátky a saldo, idempotence, retry a kontroly kvality; porovnání se sestavou.
- [ ] **4. Admin UI:** vlastní routy a odkaz, filtry hospodářského roku,
  vysvětlivky, rozpad účtů, chyby/čerstvost/úplnost a ruční aktualizace.
- [ ] **5. Ověření a zapnutí:** účetní odsouhlasení jednoho společného období,
  banka a hotovost, provozní měření importu, aktualizace návodu a postup obnovy.
- [ ] **6. Volitelně peněžní toky:** samostatná etapa po ověření počátků,
  převodů, pokladen a rozlišení financování; nesmí zdržet základní reporting.

Mimo první verzi: účetní zápisy, opravy ABRY, změny fakturace a párování,
předpověď zisku, daňová přiznání, rozpočty, automatické dělení společných
nákladů, detailní zisk baru/kuchyně, OCR účtenek a kombinace s budoucími
kalkulovanými náklady kuchyně. Ekonomika nepřebírá plán nákupů surovin.

## Ověření a podmínky dokončení

- Výpočty přes Decimal: záporné opravy, MD/Dal, nedaňové účty, odpisy,
  zálohy a nulové versus chybějící údaje; syntetické známé kontrolní součty.
- Hranice 30. 6./1. 7., červenec–září, pozdější zápis, oprava starého měsíce,
  odlišná zkratka hospodářského roku a absence minuloročních dat.
- `Req.Test`: více stránek, prázdná evidence, 401/403, timeout, 429/5xx,
  neplatná odpověď, ignorovaný filtr, opakování bez duplicit, neúplný import
  zachovávající poslední snapshot, změna firmy, změna/smazání zdrojové položky.
- Historické částečné úhrady a dobropisy; stav k datu se nesmí zaměnit za dnešní.
- PIN ochrana všech obrazovek a případných downloadů, vypnutý modul bez HTTP,
  jeho výpadek neovlivňuje Billing/Sales. Žádný POST/PUT/DELETE do ABRY.
- Kontrola rozsahu diffu: mimo modul jen uvedené registrační body a migrace;
  žádná změna obchodních funkcí stávajících kontextů. Relevantní regresní CI.
- Ruční srovnání stejného období a filtrů s výsledovkou/předvahou, počátků
  a konců banky s výpisem, pokladen s evidencí. Rozdíly vysvětlit, ne tolerovat
  paušální odchylkou. Úplnost potvrdí účetní/uživatel, nikoli automatický test.
- Lokální testy podle AGENTS.md standardně nespouštět; CI ověří uživatel.
  Při implementaci dodržet požadované formátování a zaznamenat limity ověření.

## Nasazení a návrat

Feature je ve výchozím stavu vypnutá. Nejprve migrace vlastních tabulek,
konfigurace zdroje a oprávnění, testovací import, kontrolní porovnání a pak
zapnutí navigace/obsluhy a denního importu. Tajné hodnoty pouze v prostředí.
Běžná deaktivace zastaví nové HTTP synchronizace a skryje funkci; neodstraňuje
data ani nezasahuje do účetnictví. Rollback aplikace lze provést při ponechání
nových tabulek. Mazání tabulek není provozní opravou nekonzistentního importu.

## Rozhodnutí a předání

| Datum | Rozhodnutí | Zdroj |
| --- | --- | --- |
| 2026-10-28 | Celá firma od července 2026, hospodářský rok červenec–červen, CZK | Uživatel |
| 2026-10-28 | Ubytování a stravování dohromady, bar zvlášť, jedna fyzická hotovost | Uživatel; účetní analytiky čekají na vysvětlení |
| 2026-10-28 | Samostatný kontext a vlastní data, minimum zásahů do zbytku aplikace | Výslovný požadavek uživatele |
| 2026-10-28 | Září ani peněžní zůstatky zatím neoznačovat jako ověřené | Analýza exportů a nepotvrzená úplnost |

- Hotovo: průzkum existující integrace, veřejné dokumentace a exportů;
  tento plán a seznam dotazů. Žádná část dashboardu zatím není implementovaná.
- Zbývá: všechny implementační etapy výše.
- Blokuje důvěryhodné ostré výsledky: účetní odpovědi, společný rozsah sestav,
  ověření banky/hotovosti a API konkrétní firmy. Neblokuje přípravu modulu.
- Nejbližší krok: doplnit doručené odpovědi a provést read-only ověření API;
  následně zahájit první implementační PR podle tohoto plánu.

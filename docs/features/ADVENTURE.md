# Cozy Adventure

Volitelná hobby hra pro Michala a Lucku. Obsahuje osobní ruční questy, osobní
i společná XP, vlastní úkoly a opakované šablony, kampaně, dva automatické
pobytové achievementy a audit přepočtů.
Provozní data hra pouze čte; herní akce zapisují výhradně do vlastních tabulek.

## Zapnutí a používání

1. Nasaď migrace `20261111120000_create_adventure_foundation.exs` a
   `20261111130000_add_adventure_campaigns.exs` a
   `20261112120000_add_adventure_tasks.exs` a
   `20261112130000_add_adventure_task_templates.exs` standardním postupem aplikace.
   Přidávají celkem osm tabulek s prefixem `adventure_`; druhá rozšiřuje
   pouze herní XP ledger o společného příjemce a vazbu na achievement.
   Třetí přidává pole vlastních úkolů a povoluje společnou questovou odměnu;
   nepřepisuje UUID, snapshoty ani odměny dosavadních questů. Je záměrně
   nevratná přes `ecto.rollback`, aby nemazala novou historii. Návrat staré
   aplikace po založení nových úkolů vyžaduje samostatné posouzení kompatibility.
   Čtvrtá přidává šablony, verze a vazbu výskytů; původní definice zakládá
   pozastavené, bez přepsání starých instancí. Také uchovává historii nevratným `down`.
2. Nastav `ADVENTURE_ENABLED=true` a restartuj aplikaci. Výchozí hodnota je
   `false`. Vypnutí skryje odkaz v administraci a zablokuje herní stránky i akce;
   herní data a historie zůstanou uložené. Hodinový Oban worker při vypnutí
   neprovádí herní ani provozní dotazy. Fronta `adventure` má souběh 1.
3. Po přihlášení stávajícím admin PINem otevři **Další agenda → Cozy Adventure**
   (`/admin/adventure`) a klikni na **Začít dobrodružství**. Opakování setupu
   nezduplikuje profily a nezmění již uložené profily.
4. Vyber Michala nebo Lucku. Jde o vlastní prohlášení, nikoli osobní přihlášení.
   Prohlížeč si volbu pamatuje v `localStorage` pod klíčem `cozy_adventure_hero`.
   Cookie stejného jména, omezená na `/admin/adventure`, slouží jako roční
   záloha při nedostupném místním úložišti a k převzetí dřívější volby. Oba
   zápisy jsou nezávislé a ověřují se zpětným čtením; selhání jednoho neblokuje
   druhý. Funguje také přes HTTP v lokální síti, bez změny admin přihlášení.
   Po připojení hry se profil obnoví při návratu, přechodu mezi záložkami,
   obnovení stránky i opětovném připojení. Volba se ukládá už při změně selectu,
   server dál ověřuje aktivní profil a neplatnou volbu vymaže. Opožděné potvrzení
   dřívějšího obnovení nepřepíše novější ruční volbu. Vymazání výběru
   uloží také prázdnou místní hodnotu, takže ho neobnoví stará neodstranitelná
   cookie. Blokování obou úložišť zobrazí upozornění; výběr pak platí jen pro
   aktuální stránku. Trvalost nelze zaručit v anonymním režimu či po smazání
   dat webu. Úložiště patří konkrétnímu prohlížeči a originu: IP, jiné jméno,
   port nebo protokol mohou znamenat jinou volbu. Neplatný nebo neaktivní
   profil se neobnoví. Přepnutí profilu zruší rozpracované potvrzení questu.
5. V **Questech** připrav zadání. V **Táboře → Najít další výpravu** přijmi
   nejvýše tři osobní questy. Tlačítkem **Hotovo** otevři potvrzení
   splnění. Poznámka je nepovinná (nejvýše 1000 znaků, bez minimální délky);
   případně ji rozbal přes **Přidat poznámku**. Aktér, čas a odměna se auditují
   i bez poznámky. Neuváděj osobní údaje hostů.
6. Historii XP najdeš pod **Nastavení a audit**. Dashboard zobrazuje až 100
   questů (aktivní vždy před dokončenými) a posledních 20 XP transakcí.

## Herní obrazovka a nápověda

Adventure používá vlastní herní rám bez administračního sidebaru. Odkaz
**Do aplikace** vede zpět do administrace; stávající PIN chrání všechny stránky
i události stejně jako ostatní admin. Hrdina a práce zůstávají uložené při
přechodu mezi hrou a provozními obrazovkami.

| Obrazovka | Úloha |
| --- | --- |
| **Tábor** | Hrát: vybrat hrdinu, přijmout výpravu, pracovat na ní a potvrdit splnění. Tři osobní sloty, společné výpravy, mapa chaty a sezóna. |
| **Questy** | Připravit zadání: části Jednorázové questy, Opakované questy a Historie. Vytváření, editace, termíny, přiřazení, odměny, opakování a archivace. |
| **Nastavení** | Sezóny, pravidla a audit. |

**Najít další výpravu** v táboře otevře nástěnku s čekajícími vlastními úkoly
i splatnými výskyty opakovaných šablon. Při otevření se šablony výslovně
obnoví stejným přepočtem jako v hodinovém workeru. Výběr má části **Pro mě**
(vlastní a volné osobní úkoly), **Společné** a **Všechny**, plus hledání názvu.
Nabídka čte jeden herní dávkový dotaz (nejvýše 100 otevřených položek),
nikoliv pevné čtyři definice. Prázdná nástěnka odkazuje na knihu zadání.
**Přijmout výpravu** přesune osobní quest do slotu vybraného hrdiny;
**Vyrazit společně** ho přesune do společných výprav. Po přijetí se nabídka zavře.

Mapa chaty má šest oblastí: **Recepce**, **Pokoje**, **Kuchyně**, **Bar**,
**Pokladnice** a **Dílna**. Výběr oblasti otevře detail bez dalšího provozního
dotazu; na mobilu je stejná mapa dostupným seznamem tlačítek. Detaily odkazují
do existujících funkcí aplikace, samy nemění provozní stav a nepotvrzují úkol.
Po návratu zůstává výprava rozpracovaná. Kniha zadání neobsahuje duplikované výpravy,
katalog ani sezónní karty a nemá tlačítka k zahájení/splnění. Tábor odkazuje
na část Historie v knize; ta uchovává i dokončené původní katalogové questy.
Sezónní panel se jmenuje Kronika sezóny, aby se nepletl se společnými úkoly.

### Živý tábor (4A)

Recepce a Pokoje ukazují dnešní příjezdy a odjezdy **skupin** a počet osob podle
kalendáře. Příjezd obsazenost zahrnuje, odjezd vylučuje. Nejde o fyzickou
přítomnost, ověření čistoty ani připravenost pokoje. Kuchyně zobrazuje známé
porce snídaní/obědů/večeří; při chybějících podkladech jsou to výslovně pouze
minimální známé počty, ne celková potřeba. Porce nejsou uvařené jídlo.
Zdrojové definice zůstávají stejné jako v Přehledu: kalendář pracuje s aktivními
a budoucími rezervacemi, kuchyň zahrnuje i dokončené nesmazané, nestornované pobyty.

**Služba dne** ukazuje nejvýše čtyři konkrétní podněty z Přehledu s důvodem,
datem příjezdu skupiny a odkazem na pobyt. Zahrnuje probíhající pobyty a výhled
do stejného dne následujícího měsíce (zkrácený na konec měsíce). Datum příjezdu
není datum vzniku závady ani termín nového questu. Další podněty řeší plán jídel.
Prázdný seznam neznamená, že je chata připravena.

Mapa, služba i detaily sdílejí jedinou projekci `Dashboard.overview(today)`.
Načte se jednou po připojení Tábora a pak pouze tlačítkem **Obnovit provoz**.
Počáteční HTTP render, Questy, Nastavení, výběr oblasti/hrdiny a běžný render
nový zdrojový přehled nenačítají. Žádný polling ani dotazy po oblastech.
Vypnutý modul blokuje loader před SQL. Projekce žije jen v socketu, neukládá
se do databáze a neobsahuje hostovská jména, kontakty ani načtené booking/guest
struktury; podněty mají pouze ID pobytu, typ, důvod a datum.

Schválený rozpočet je nejvýše **15 zdrojových SELECTů** na načtení:
timeline rezervace/hosté/pokoje 4, kuchyň 8, obsazenost 1, porce 2, kapacita 0.
Prázdné preloady mohou počet snížit. Jde o opakované, ale dávkové a omezené čtení
bez N+1; počet nesmí růst s počtem skupin, receptů nebo oblastí. Zůstává běžná
konzistence jednotlivých SELECTů, nikoli společný REPEATABLE READ snapshot;
souběžná provozní editace může mezi zdroji krátkodobě vytvořit rozdíl. Ruční
obnova znovu načte celý přehled, ne finanční kroniku.

Pražský den se počítá v paměti podle současných pravidel EU (poslední neděle
března/října v 01:00 UTC), aby dodatečný SQL dotaz na časové pásmo nespotřeboval
rozpočet. Při změně zákonných pravidel je nutné výpočet aktualizovat. Čas načtení
je zobrazen v UTC. Chyba ponechá poslední projekci označenou jako nečerstvou;
bez předchozího výsledku jsou hodnoty neznámé, ne nulové. Stáří alespoň 15 minut
nebo změna pražského dne označí údaje jako starší při dalším renderu. Bez pollingu
se text sám po čase nepřekresluje, proto je vždy viditelný čas a ruční režim obnovy.

Bar a Pokladnice odkazují na existující **Kroniku sezóny**, její datum přepočtu
a původní sklad/fakturaci. Neprovádějí nové skladové ani finanční čtení. Částky
jsou sezónní uložené snapshoty, ne živý stav či dostupný investiční rozpočet;
**Obnovit provoz je nepřepočítává**. Dílna výslovně přiznává, že projekty zatím
neexistují, a nabízí knihu běžných questů. Prohlížení a obnova neudělují XP,
nezakládají questy ani nemění provozní data. Tři osobní sloty, společná práce,
kronika, zapamatování hrdiny, admin PIN i feature flag zůstávají zachované.

Ověření 4A: přidány regresní ExUnit/LiveView scénáře pro projekci, neúplnost,
pražské dny/DST, dotazový strop na malé i velké sadě, zákaz obnovení při UI
událostech, výslovnou obnovu, flag, stavy načítání/chyby a odkazy. Lokální
testy nebyly spuštěny; výsledky CI ověří uživatel. Prošly formatter změněných
Elixir souborů, kompilace s `--warnings-as-errors` a `MIX_ENV=test mix assets.build`.
Použit Elixir 1.20.5 / Erlang 29.1.2 (ERTS 17.1.1), nikoli přesně připnutý
Elixir 1.20.4-otp-29 / Erlang 29.1; shoda formatteru s CI není zaručena.
První kompilace vypsala varování existujících závislostí; aplikace prošla.
Ruční browserové ověření desktopu, 390/320 px a asistivních technologií nebylo
provedeno. Žádná nová migrace, konfigurace ani projektový systém.

Pravidla, identita profilu, definice KPI a omezení jsou za tlačítkem
**Průvodce** v překryvné nápovědě. Lze ji zavřít křížkem, Escape, kliknutím
mimo panel nebo tlačítkem na konci. Dialog drží klávesnicový fokus uvnitř
a po zavření jej vrací na původní ovládací prvek. Stručný stav úplnosti
dat a případné upozornění na dílčí výsledky zůstávají u metrik viditelné.

Ilustrace vznikla pro Cozy Adventure; horské a herní SVG ikony jsou z Lucide
(ISC). Všechny soubory se načítají lokálně z `priv/static/images/adventure/`,
licence a zdroje jsou v jeho `CREDITS.md` a `LUCIDE-LICENSE`. Stylování je
izolované v `assets/css/adventure/`, dialogový hook v `assets/js/adventure/`.

## Původní katalogové questy a zachovaná historie

| Šablona | XP | Opakování |
| --- | --- | --- |
| Připravit další pobyt | 50 | jednou za týden |
| Zkontrolovat otevřené zálohy | 50 | jednou za týden |
| Dokončit týdenní nákupní plán | 100 | jednou za týden |
| Zavést jedno provozní zlepšení | 250 | jednorázově |

Týden začíná v pondělí podle `Europe/Prague`, včetně přechodů letního času.
Převod používá časovou databázi PostgreSQL. Aktivní quest lze dokončit i po
konci jeho týdne; patří stále k původnímu období a zabírá jeden ze tří slotů.
Za opakovanou aktivaci stejné šablony v daném období ani opakované potvrzení
splnění nevznikne další odměna. Jednorázový quest lze splnit jednou za profil.

Definice jsou verzované v `Adventure.Catalog`. Každá instance ukládá snapshot
názvu, odměny, verze a frekvence, takže další změna katalogu nepřepíše historii.
Unikátnost šablony a období platí napříč verzemi katalogu.

Úroveň L začíná při `100*(L-1)*L/2` XP. Úroveň se odvozuje z ledgeru; neukládá
se samostatně. XP nejsou Kč, provozní KPI, odměna zaměstnance ani účetní údaj.
Poznámka a potvrzení představují ruční prohlášení o úkolu, nikoli kontrolu
skutečného stavu rezervace, zálohy či nákupního plánu.

## Vlastní jednorázové úkoly

Ve **Questech → Jednorázové questy** může vybraný hrdina založit úkol pouhým
názvem. Volitelné jsou přiřazení, termín, priorita, kategorie a popis.
Velikost dává výchozích 50 / 100 / 250 XP, vlastní odměnu lze zadat před
rozpracováním (1–10 000 XP). Priorita neurčuje XP.

- Úkol začíná ve stavu **Čeká**. Zásobník může mít více než tři položky.
- V táboře **Najít další výpravu → Přijmout výpravu** přiřadí osobní úkol právě vybranému hrdinovi.
  Předchozí přiřazení a aktér převzetí zůstávají v auditu. Do tří osobních
  rozpracovaných se společně počítají vlastní i katalogové questy.
- Při **Hotovo** vyber skutečného splnitele. Osobní odměnu získá tento
  hrdina, i když byl úkol přiřazen druhému. Přiřazení ani historické
  `profile_id` se nepředefinují na příjemce odměny.
- Společný úkol vyžaduje výslovně vybrané přispěvatele a udělí jednu
  odměnu chatě. Nevytváří osobní kopie XP ani nezabírá osobní slot.
- Zadání lze upravovat pouze ve stavu **Čeká**. Po rozpracování zůstává
  snapshot odměny neměnný. Dokončení, důkaz a ledger jsou v jedné transakci,
  zamčený profil hlídá osobní limit a zamčený úkol souběžná dokončení.
- **Archivovat** otevřený úkol zruší a uvolní slot. Dokončenému zachová
  stav, čas, důkaz i XP; v obou případech uloží aktéra a čas archivace.
  Obnovení a opětovné dokončení archivované práce není dostupné.
- Filtry umožňují moje / volné / společné / všechny, stav a archiv, kategorii,
  termín a hledání názvu. Seznam ukazuje nejvýše 100 výsledků; pro starší práci
  upřesni výběr. Zmeškaný termín nepřiděluje penalizaci.

Vlastní úkoly mají samostatný `Adventure.Tasks`, používají stávající quest
instance a XP ledger. Sloupec `profile_id` zůstává původním vlastníkem pouze
u katalogových questů; nové úkoly používají `assigned_profile_id`, `created_by_id`
a aktéra v důkazu. Historii splněných osobních úkolů vidí skutečný splnitel
v deníku; společná historie je ve společném úkolovníku.

Čtyři původní katalogové definice nadále fungují beze změny UUID a klíčů
odměn. Znovuotevření dokončeného úkolu je odložené spolu s pravidly obnovení
kompenzované odměny. Sezónní finanční přehled zůstává další etapou.

## Opakované šablony

V **Questech → Opakované questy** založ název, denní/týdenní opakování,
vybrané dny týdne, platnost od, kategorii, přiřazení, velikost/XP a působnost.
Změna velikosti předvyplní 50/100/250 XP; částku lze upravit. Nová šablona
začíná pozastavená. Tlačítko **Přidat 7 doporučených šablon** založí jednou
příklady z plánu (pokoje, úklid, jídelníček, nákup, vaření, společné prostory,
bar). Jejich nastavení a spuštění určuje správce. Opakovaný klik zachová úpravy.

**Spustit šablonu** (případně volba Spustit / obnovit) plánuje od dneška nebo pozdějšího data platnosti.
Hodinový `Adventure.RecurrenceWorker` a ruční **Obnovit opakované úkoly**
používají stejné transakční API `Adventure.Templates.generate/1`.
Zobrazení stránky samo nic negeneruje. Přepočet řídí datum v Europe/Prague,
nikoliv délka dne v sekundách; opakovaná hodina při zimním čase nevytvoří
nový výskyt. Nový výskyt je čekající úkol, do osobních slotů vstupuje až
výslovným převzetím a rozpracováním.

- Na šablonu je nejvýše jeden otevřený výskyt. Sedm zmeškaných denních termínů
  vytvoří jednu položku; existující otevřenou položku posune na aktuální termín.
  Původní termín a zaznamenané posuny jsou rozbalitelné u úkolu. Za zmeškání
  nejsou XP ani penalizace; nic se samo nedokončí.
- Po dokončení nebo zrušení se další úkol nabízí nejdříve v následujícím
  plánovaném termínu, který je po místním dni uzavření. Opožděný job, změna
  šablony ani obnovení nevyrobí druhou práci za dnes již uzavřený termín.
- Pozastavení/archivace vyžaduje výslovně **Ponechat**, nebo **Zrušit a
  archivovat** otevřený výskyt. Ponechaný lze dokončit i při pozastavené či
  archivované šabloně. Archivovanou šablonu nelze obnovit; historie zůstává.
- Editace a stavové změny ukládají novou verzi s aktérem. Budoucí výskyt
  dostane aktuální snapshot. Již otevřenému se mění jen termín při posunu,
  jeho zadání, přiřazení a odměna se neupravují. Posuny termínu řídí aktuální
  kalendář a působnost šablony. Editace výskytu samotného
  je blokovaná. Posledních 50 verzí je v historii šablon; všechny zůstávají v DB.
- Template lock a `FOR UPDATE SKIP LOCKED` serializují generování a správu,
  partial unique index vynucuje jeden otevřený výskyt a další unique index
  brání opakovanému založení téhož termínu. Dokončení dále chrání quest lock
  a původní XP ledger. Oban používá vlastní infrastrukturní tabulky pro joby;
  doménové zápisy zůstávají v `adventure_*`.

### Působnost

| Volba | Pravidlo |
| --- | --- |
| Vždy | Podle kalendáře i bez hostů a mimo kampaně |
| Během vybrané kampaně | Jen aktivní kampaň a aktuální den i termín uvnitř jejího období |
| Jen když jsou hosté | Pouze aktuální plánovaný den a prokazatelný `active` pobyt s kladným známým počtem osob; příjezd zahrnutý, odjezd vyloučený |

`Adventure.Sources.Guests` provádí jeden read-only agregovaný SELECT nad
`bookings` pro všechny splatné hostovské šablony. Nekontroluje pobyty po jednom,
nepřipojuje hosty/pokoje a nemění statusy rezervací. Budoucí rezervace není
přítomný host. Rezervace, která už měla začít, ale má stále `upcoming`,
neplatná data, chybějící počty nebo zastaralý aktivní pobyt znamenají
**neznámou** přítomnost, pokud jiný platný aktivní pobyt hosty nepotvrdí.
Zrušené a smazané pobyty se nezahrnují; den odjezdu není obsazený.

Při neznámém/prázdném stavu se dnešní termín nezahodí: hodinový worker nebo
ruční obnova ho během dne znovu ověří. Neověřitelná podmínka je vidět u
šablony a práci lze ručně přidat jako vlastní úkol. Minulou přítomnost hostů
z aktuálního statusu nedomýšlíme; vynechaný hostovský den se zpětně negeneruje.
Odjezd hostů, uzavření kampaně ani nesplněná podmínka otevřený úkol neuzavřou.
Přepočty ukládají jen stav podmínky, místní datum a čas, bez údajů hostů.

### Návaznost původního katalogu

Migrace a opakovatelná inicializace zakládají čtyři pozastavené šablony na
každého hrdinu se stabilním seed klíčem. Původní `profile_id`, quest UUID,
definition snapshot a award key se nemění. Při spuštění šablona převezme
existující rozpracovaný katalogový quest, místo aby založila kopii. Pokud
existuje více starých rozpracovaných týdnů, zachovají se a nevznikne nová
instance, dokud nejsou uzavřené. Již dokončený/zrušený týden se nepřidělí znovu.
Ruční katalogová aktivace sdílí zámek a kontroluje i výskyty šablony.

Původní weekly/once frekvence zůstává u převedených definic neměnná a týdenní
má jeden vybraný den. Pro jinou frekvenci založ novou šablonu. Tím se zachová
původní period key a nelze získat další odměnu výměnou identity definice.
Název, odměnu, přiřazení, působnost a další budoucí nastavení upravit lze.

## Oddělení od provozu

- Veškerá logika a schémata jsou v `lib/cozy_checkout/adventure/`, webová vrstva
  v `lib/cozy_checkout_web/live/adventure_live/`, testy ve vlastních adresářích.
- Context `CozyCheckout.Adventure` a moduly `Adventure.Campaigns`, `Adventure.Tasks`
  a `Adventure.Templates` zapisují
  pouze do tabulek `adventure_*`. Neobsahují cizí provozní FK,
  nevolá provozní mutace, neposílá emaily a nevytváří doklady či účetní operace.
- Jediné integrační body jsou admin router, podmíněný odkaz v navigaci
  a konfigurace vypínače. POS neobsahuje herní prvky.
- `Adventure.Sources.Stays` provádí jeden agregovaný SELECT nad `bookings`
  za rozsah kampaně. Nepřipojuje hosty ani pokoje, nevolá provozní contexty,
  neaktualizuje statusy a neukládá jména, emaily či jiné osobní údaje hostů.
  Zdroj se čte pouze při výslovném přepočtu nebo uzavření kampaně. Zobrazení
  dashboardu používá lokální herní snapshoty a nikdy samo neuděluje XP.
- Sdílený admin PIN chrání všechny tři trasy a LiveView události. Každá herní
  mutace navíc ověřuje vypínač a platný aktivní profil.

## Transakce a opravy

Aktivace, dokončení a opravy zamykají řádek herního profilu. Limit tří aktivních
questů proto platí i při souběžných požadavcích. Dokončení, důkaz a XP se zapisují
v jedné DB transakci (`Ecto.Multi` u původního katalogu). Unikátní `award_key` brání duplicitním odměnám.

`Adventure.reverse_award(profile_id, award_id, reason)` je opravné doménové API
pro chybně přiznané XP, zatím bez UI. Vyžaduje aktivní modul, vlastní profil
odměny a důvod o 10–1000 znacích. Přidá právě jednu zápornou transakci navázanou
na původní odměnu, nepřepisuje ji a neotevře quest k dalšímu získání XP. Není to
penalizace. Produkční obsluhu oprav lze později zpřístupnit ve chráněném UI.

## Sezónní kronika (`season_v1`)

Nové sezóny v Nastavení používají samostatný režim `season_v1`. Cíle jsou
volitelné a žádný přepočet, inkaso ani historický pobyt nepřiděluje automatické XP.
Odměny pocházejí ze skutečných questů. Původní kampaně `stays_v1` a jejich
historické odměny se nepřevádějí ani nekompenzují.

Stačí název a období v Europe/Prague (oba krajní dny včetně). Kapacita je
volitelná stálá hodnota; bez ní zůstávají ostatní metriky dostupné, procentní
obsazenost je **nedostupná**, ne nula. Nová sezóna začíná návrhem. Aktuální či
budoucí období lze po výslovném potvrzení aktivovat, současně nejvýše jedno.
Minulé období lze místo aktivace zapsat jako rovnou uzavřenou historickou
kroniku; neobsadí aktivní místo ani nespustí opakované questy. Zahrnuje celé
zvolené historické období, i před zapnutím hry.

Tábor zobrazuje šest stručných karet a rozbalovací účetní list. Přednost má
aktivní sezóna, jinak poslední uzavřená; jinou lze vyhledat a vybrat v kronice.
Questy zůstávají pouze knihou zadání. V Nastavení jsou návrhy, uzavření a audit
verzí. Otevření stránky ani přepnutí sezóny nečte provozní zdroje a nepřepočítává
výsledky; zobrazuje poslední uložený Adventure snapshot.

### Dva peněžní pohledy

| Pohled | Význam |
| --- | --- |
| Inkaso baru | Platné nezrušené záznamy `Sales.Payment` podle `payment_date`, bez servisních účtů v hlavní kartě; servis zvlášť v detailu |
| Inkaso ubytování | `Billing.Payment` podle `paid_on`: přijaté platby minus refundace v období |
| Vyúčtování pobytů sezóny | Pobyty podle společného data odjezdu rezervace v období; uložený hrubý konečný doklad plus jeho přímé podepsané opravy za všechny plátce |
| Úhrady pobytů sezóny | Všechny evidované příjmy minus refundace účtů daných pobytů k datu přepočtu, i mimo sezónu |

Inkaso se omezuje koncem sezóny a pražským datem přepočtu. Historické přepočty
čtou aktuální evidenci s jasným `as_of`, nikoli tehdejší stav databáze. Barová
platba může zahrnovat spropitné; u částečné úhrady je nelze přesně rozdělit od
prodeje. Smazaná platba není doklad o refundaci. Servisní příslušnost je aktuální
označení účtu, nikoli historická klasifikace. Platba nezmizí jen kvůli smazání
účtu nebo rezervace. Nepoužívají se další kopie pohybů z ABRY.

Listopadová záloha 30 000 CZK a lednový doplatek 70 000 CZK za lednový pobyt
s konečným vyúčtováním 100 000 CZK znamenají zimní inkaso 70 000 CZK,
vyúčtování 100 000 CZK a celkem uhrazeno 100 000 CZK. Zálohová výzva,
daňový doklad přijaté zálohy a odpočet záloh ve snapshotu konečné faktury
nejsou další platba ani další výnos. Refundace a oprava faktury jsou různé události.

Pobyt přes hranici sezóny se peněžně zařadí celý podle odjezdu, zatímco
lůžkonoci se rozdělují jednotlivými nocemi. Vydané finanční záznamy se zachovají
i při pozdějším stornu/smazání rezervace či účtu. Vyúčtování čerpá pouze z vydaných
konečných dokladů a jejich oprav, ne z mutable kalkulace nebo jejího legacy stavu.
Zbývá a přeplatek se počítají jednotlivě po plátcích: přeplatek jednoho nesnižuje
dluh jiného. Detail uvádí i skutečně evidované úhrady plátců bez konečné faktury.

Chybějící konečný doklad není vyúčtování nula. Pokud známé doklady pokrývají jen
část pobytů, součet je označený jako dílčí; bez konečných dokladů je hodnota
nedostupná. Samostatně se evidují chybějící účty, nedokončené rozdělení plátců
a osobní účty, bez odhadování jejich ceny. Inkaso zůstává známým údajem i při
neúplných dokladech. Každá metrika uchovává zdroj, verzi definice, jednotku,
období, `as_of` a vlastní stav úplnosti. Snapshoty obsahují jen agregace,
nikoli údaje hostů. Inkaso, vyúčtování a lůžkonoci se nesčítají; zisk bez úplných
nákladů se nevykazuje.

### Verze a bezpečnost

Výslovný přepočet ukládá nový neměnný snapshot, číslo verze, vazbu na předchozí
verzi, aktéra a metadata sezóny. Po uzavření je pro další přepočet povinný důvod.
Původní výsledky se nepřepisují. Období, kapacita a pravidla po aktivaci či
historickém zápisu zůstávají neměnné; jiné období znamená novou sezónu.
Audit ukazuje posledních 20 přepočtů, starší zůstávají uložené v DB.

Přepočet pořizuje všechny zdroje v jednom REPEATABLE READ snapshotu, aby
souběžná změna pobytu nevytvořila rozporné výsledky. Převzatá transakce musí
mít REPEATABLE READ nebo SERIALIZABLE; slabší explicitní transakce vrátí
`:snapshot_isolation_required`. Při konfliktu serializace se vlastní transakce
opakuje nejvýše třikrát; převzatou transakci opakuje její volající.

Pobytový adaptér a dva nové finanční adaptéry používají dávkové agregace;
počet dotazů nezávisí na počtu pobytů, plátců, dokladů ani dnů. Platby a opravy
se agregují před spojením, aby je řádky dokladů nenásobily. Žádné volání balance
pro každý účet, externí HTTP, provozní zápisy, emaily či účetní hooky. Vypnutý
Adventure modul blokuje i přepočet. Migrace mění pouze Adventure tabulky.

Srovnání sezón, produktové žebříčky, přesné stáří dluhu po opravách, finanční
náklady a zisk zůstávají mimo tuto etapu.

## Původní kampaně (`stays_v1`)

Kampaň je společná sezónní výprava chaty: vymezuje sledované období a ukazuje
postup proti zvoleným cílům. Cíle pobytů, budoucích lůžkonocí a obsazenosti
jsou zatím ukazatele; samy nepřidělují další XP. Odměňují jen dva milníky
za 1 a 10 způsobilých pobytů. Osobní questy fungují nezávisle na kampani.
Údaje se neobnovují automaticky na pozadí; přepočet vyvolá tlačítko nebo
uzavření kampaně. Herní kampaň nemění skutečné rezervace či účetnictví.

Existující návrhy kampaní lze v **Nastavení a auditu** upravovat.
Před aktivací vyber profil a výslovně zaškrtni potvrzení období, cílů a kapacity.
Současně může běžet nejvýše jedna kampaň. Po aktivaci jsou období, kapacita,
cíle a verze pravidel neměnné. Aktivovat nelze již skončené období.

Období je včetně obou hraničních dnů, nejvýše tři roky, pásmo Europe/Prague.
Kapacita je ručně potvrzená stálá hodnota 1–500 lůžek pro celé období.
Provozní systém neposkytuje historii kapacit ani blokací; hra ji nedomýšlí
ze současného seznamu pokojů. Při změnách kapacity zvol odpovídající období
kampaně a ověř její předpoklady. Nejde o nezávisle ověřenou skutečnou účast hostů.

Po aktivaci klikni na **Přepočítat z provozních dat**. Metriky nesměšují minulost
a budoucnost:

| Metrika | Pravidlo `stays_v1` |
| --- | --- |
| Dokončené pobyty | Stav `completed`, platný příjezd/odjezd, odjezd v kampani před dnešním pražským datem |
| Realizované lůžkonoci podle stavů | Osoby × překryv nocí kampaně před dneškem, pouze `active` a `completed` |
| Budoucí rezervované lůžkonoci | Osoby × překryv nocí kampaně od dneška, pouze `upcoming` a `active` |
| Obsazenost uzavřených nocí | Realizované lůžkonoci / (potvrzená kapacita × dosavadní noci kampaně), procenta |

Příjezdová noc se zahrnuje, odjezdová ne. Počet osob zahrnuje dospělé, děti,
kojence i neurčené hosty podle stávajícího kalendáře. Více přiřazených pokojů
nevytvoří další pobyt ani další osobonoci. `cancelled` a soft-deleted rezervace
se zcela vylučují. Cíl budoucích lůžkonocí je aktuální výhled, nikoli kumulativní
součet rezervací za sezonu; s postupem času se může snižovat.

Každý přepočet ukládá zdroj, čas `as_of`, období, pravidla, hranici realizace,
kapacitu a stav úplnosti. Chybějící nebo neplatný odjezd, neznámý počet osob,
zastaralý/neslučitelný status nebo obsazenost nad 100 % označí podklady jako
neúplné. Dílčí čísla jsou v UI označena; z neúplných podkladů se XP nepřiznávají
ani neodebírají. Prázdné období má známý počet pobytů nula, ale bez uzavřených
nocí je procentní obsazenost **nedostupná**, nikoli nula procent.

Uzavření kampaně provede poslední přepočet a uzamkne datum hranice realizace.
Další přepočet oprav je možný i potom. Čte aktuální verze rezervací se stejnou
uzamčenou hranicí; nepředstírá historický provozní snapshot k okamžiku uzavření.
Posledních 50 kampaní a posledních 20 přepočtů je dostupných v administraci;
starší auditní záznamy zůstávají v DB. Kampaně nemají vlastní job ani event hook;
hodinový worker obnovuje pouze opakované úkoly.

## Automatické achievementy a společná XP

- První způsobilý dokončený pobyt po aktivaci: **100 společných XP**.
- Deset způsobilých dokončených pobytů po aktivaci: **250 společných XP**.

Způsobilý pobyt musí splnit definici dokončeného pobytu výše a mít odjezd
**po pražském dni aktivace**. Rezervace nemají čas skutečného dokončení;
vyloučení celého dne aktivace zabraňuje odměnění pobytů dokončených dříve
téhož dne. Historické pobyty mohou být součástí KPI, ale nejsou automaticky
odměněné. Profil, který stiskl přepočet, se ukládá pouze jako aktér auditu.
XP z automatických milníků patří výhradně chatě, nikoli tomuto profilu.

Přepočet zamyká herní kampaň. Snapshot, achievement a XP jsou součástí jedné
DB transakce. Opakování či souběžné požadavky nepřidělí další odměnu.
Při opraveném stornu, smazání, datu nebo statusu se KPI přepočítají. Pokud
úplné podklady již milník nesplňují, je odvolán s novým důkazem a jednou
zápornou kompenzací. Původní důkaz i XP transakce zůstávají zachované.
Odvolaný milník je pro danou kampaň konečný; další splnění jej znovu neodmění.
Tím nelze opakovanými změnami pobytu získávat další XP.

Změny definice vyžadují novou verzi pravidel a samostatnou implementaci;
aktivní kampaň se nikdy tiše nepřevede na jinou definici. Finanční metriky
jsou pouze v nové kronice `season_v1`; skill tree a rekonstrukce zůstávají další etapou.

## Ověření

Přidané testy pokrývají hranice levelů, týden v Praze, idempotentní setup,
limit aktivních questů, atomický rollback odměny, atribuci, opakované dokončení,
kompenzace, souběh na samostatných PostgreSQL spojeních, vypnutí modulu,
admin guard a kontrolu SQL zápisů pouze do herních tabulek.
Navíc ověřují clipping lůžkonocí, více pokojů, příjezd/odjezd, kvalitu dat,
oddělení rezervací a realizace, explicitní aktivaci, společnou atribuci,
opakování přepočtu, rollback při selhání společných XP, audit a souběžné opravy.

Testy se podle pravidel repozitáře spouštějí v CI; výsledek ověřuje správce PR.
Pro ruční kontrolu po CI:

- [ ] Při vypnutém modulu chybí navigace a přímá herní URL přesměruje do adminu.
- [ ] Bez PINu všechny herní URL vedou na přihlášení.
- [ ] Založit profily, vybrat hráče a aktivovat tři questy; čtvrtý se odmítne.
- [ ] Dokončit quest bez poznámky i s krátkou poznámkou, ověřit odměnu a audit.
- [ ] Otevřít Průvodce, ověřit Tab/Shift+Tab, Escape a návrat fokusu.
- [ ] Přepnout profil a ověřit oddělenou historii a XP; obnovit stránku.
- [ ] Vypnout modul a ověřit zachovaná herní data.
- [ ] Založit návrh kampaně, upravit cíle, potvrdit období a kapacitu a aktivovat.
- [ ] Přepočítat a porovnat lůžkonoci s ručně vybranými pobyty bez změn provozu.
- [ ] Ověřit, že aktivace ani zobrazení stránky nepřidávají automatické XP.
- [ ] Ověřit oddělení společných a osobních XP a audit přepočtů.
- [ ] Na testovacích datech ověřit storno, jednorázovou kompenzaci a uzavření.
- [ ] Ověřit mobilní šířku, tabulátor a čitelné textové stavy.
- [ ] Vytvořit pět vlastních úkolů, rozpracovat tři spolu s katalogem a ověřit limit.
- [ ] Dokončit Michalův úkol jako Lucka a ověřit osobní XP i historii.
- [ ] Dokončit společný úkol s explicitními přispěvateli a ověřit jedinou odměnu chatě.
- [ ] Upravit čekající práci, archivovat rozpracovanou i dokončenou a ověřit historii.
- [ ] Ověřit hledání, moje/volné/společné, termín, kategorii a archiv.

Opakované šablony mají další regresní testy pro sedm zmeškaných termínů,
verze a neměnné snapshoty, explicitní pozastavení, DST a přelom roku,
hostovskou/kampaňovou působnost, jediný dávkový pobytový SELECT, návaznost
katalogu, souběžné generování a flag, který zablokuje i SQL dotazy workeru.
Při opravě nahlášeného `BadBooleanError` prošlo lokálně všech 72 testů
Adventure včetně LiveView a souběhů na izolovaném PostgreSQL 17. Kompletní
repozitářovou sadu a výsledky CI dále ověřuje uživatel.

- [ ] Založit a spustit denní šablonu, dvakrát obnovit, ověřit jediný čekající úkol bez XP.
- [ ] Upravit šablonu a ověřit původní snapshot otevřeného úkolu i novou verzi budoucího.
- [ ] Pozastavit s ponecháním, obnovit, poté archivovat se zrušením otevřeného úkolu.
- [ ] Nastavit dny v týdnu a působnost kampaně/hostů včetně neznámých podkladů.
- [ ] Ověřit původní quest dokončený ve stejném týdnu a zachování odměny po převodu.

Ověření herního rozdělení: lokálně prošlo 76 testů Adventure včetně LiveView,
cesty kniha → tábor → výběr → dokončení, osobních/společných slotů, mapy,
vyřazení pevných nabídek a oddělení opakovaných výskytů od editace zadání.

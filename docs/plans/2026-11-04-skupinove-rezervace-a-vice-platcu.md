# Skupinové rezervace, více plátců a jednodušší zakládání pobytů

- Stav: **implementováno v PR — čeká na CI a lokální kontrolu uživatele**
- Vytvořeno: 2026-11-04
- Aktualizováno: 2026-11-04
- Podklad: kontrola kódu na `origin/main` (`dea396c`) a rozhodnutí uživatele
  v tomto chatu.
- Související dokumentace: [Fakturace pobytů](../features/BILLING.md),
  [Stravování a kuchyň](../features/CATERING.md),
  [Integrace ABRA](../integrations/ABRA_INTEGRATION.md),
  [Finanční regresní testy](../development/FINANCIAL_TESTS.md).

Implementace byla zadána uživatelem 4. 11. 2026 s požadavkem na jednu PR.
Nasazení provede uživatel po lokální kontrole. Současná obsluha je popsána
v [návodu fakturace](../features/BILLING.md#rezervace-a-skupiny-s-více-plátci).

## Problém a očekávaný výsledek

Vedoucí přihlásí jednu skupinu, například přibližně 35 osob, z toho 13 dětí.
Obsluha potřebuje jednou rezervovat kapacitu a připravit společné stravování,
ale jednotlivým rodinám nebo osobám vystavit samostatné faktury. Každý plátce
hradí svou část: někdy až po pobytu, jindy nejprve zálohu a následně doplatek.
Termín, ceník a stravování bývají společné; výjimky se mají dát upravit.

Výsledkem bude jedna rezervace s více plátci. Opakované vystavování zjednoduší
předvyplněné údaje a rychlé zadávání jména a počtů osob. Přidání plátce ani
jeho dokladů nevytvoří další rezervaci, obsazenost, pokojovou rezervaci či
kuchyňské porce. Běžný pobyt má jednoho plátce automaticky.

Zakládání rezervace zároveň dostane pohodlnější výběr termínu a kompaktní
volitelné přiřazení pokojů. Dnes velký seznam pokojů zabírá místo, přestože
je obsluha většinou řeší až při pozdější úpravě.

## Současný stav a podklady

Kontrola vychází ze zdrojů a čtení existujících testů; aplikace, produkční data,
skutečné bankovní pohyby ani živá ABRA nebyly v rámci plánování ověřovány.

- `lib/cozy_checkout/bookings/booking.ex` má jednu kalkulaci přes `has_one :invoice`.
  Stravování má vlastní `meal_adults`, `meal_children`, režim a hranice jídel.
  `lib/cozy_checkout/meals/portion_counts.ex` počítá porce nezávisle na fakturách.
- `lib/cozy_checkout/bookings.ex` počítá obsazenost z položek typu `person`
  v `booking_invoices`. Samotné založení rezervace počty ubytovaných neukládá.
- `lib/cozy_checkout/billing.ex` váže odběratele, kalkulaci a finanční saldo na
  `booking_id`. `final_document/1` předpokládá jedinou konečnou fakturu a
  vyúčtování odpočítává daňové doklady záloh za celý pobyt.
- `lib/cozy_checkout/billing/booking_summary.ex` má stejný předpoklad jedné
  faktury a agreguje skutečné platby za rezervaci. Jeho SQL používají i filtry
  seznamu rezervací; víc faktur nesmí rozmnožit řádky ani rozbít stránkování.
- Migrace `20251022185655_create_booking_invoices.exs` a
  `20261022120000_create_booking_billing.exs` vynucují jedinečnou kalkulaci,
  odběratele a konečnou fakturu na rezervaci. Doklady již mají samostatná čísla,
  jedinečné VS, neměnné snapshoty a vlastní identitu účetního přenosu.
- `lib/cozy_checkout/abra/bank.ex` hledá podle VS, ale následně vybírá konečnou
  fakturu a saldo za celý pobyt. `bank_payments.ex`, `final_bank_payments.ex`
  a `final_invoice_export.ex` obsahují další kontroly podle `booking_id`.
  Nestačí proto pouze povolit více faktur v databázi a přidat formulář.
- `lib/cozy_checkout_web/live/billing_live/booking.ex` a
  `booking_live/invoice_component.ex` zobrazují jednu kalkulaci a finanční celek.
- `lib/cozy_checkout_web/live/booking_live/form_component.ex` používá dva
  nativní datumové vstupy a velký seznam pokojů. Při změně příjezdu nastavuje
  odjezd na následující den, a může tak přepsat již zvolenou délku pobytu.
- `lib/cozy_checkout_web/live/booking_live/timeline.ex` načítá kalkulaci,
  počet osob a pokoje po jednotlivých rezervacích (N+1). Hromadné načítání
  dotčených přehledů bylo uživatelem výslovně schváleno.

## Rozsah

Součástí je více plátců pod jednou rezervací, samostatná fakturace a platby
každého plátce, společná kapacita a stravování, přehled rozdělení osob a úhrad,
jednodušší rezervovací formulář a hromadné načítání dotčených přehledů.

Zůstávají současné druhy dokladů, číselné řady, pravidla DPH, PDF, ručně
potvrzované bankovní platby, účetní mapování a princip synchronizace s ABRA.
Nutná je úprava výběru souvisejících dokladů a plateb podle plátce.

Mimo tuto etapu je rozdělování společné zálohy vedoucího mezi různé odběratele,
rozdělení jednoho bankovního pohybu mezi více plátců, automatické přesuny
přeplatků a dodatečné rozdělování již vystavených dokladů mezi nové odběratele.
Nevzniká nový hostovský portál, jiný způsob účetního párování ani podskupiny
stravování. Stávající účetní omezení oprav a vratek se tímto nerozšiřují.

## Navržené řešení

### Rezervace a společné údaje

- Rezervace drží kontakt na vedoucího/hlavního hosta, termín, počty ubytovaných,
  případně pokoje, poznámky a společné stravování.
- Počty ubytovaných zadat už při založení. Použít dnešní věkové kategorie
  dospělí, děti do 2 let a děti do 12 let; celkový počet odvozovat jejich součtem.
  Nezaměňovat tyto kategorie se dvěma kategoriemi porcí pro kuchyň.
- Tyto počty jsou zdroj obsazenosti i v době, kdy ještě nejsou připraveni
  jednotliví plátci nebo vystavené faktury. Nesčítat je znovu s osobami plátců.
- Počty strávníků a současné výpočty jídel zůstávají samostatné. Úprava počtů
  pro fakturaci konkrétního plátce sama nepřepisuje kuchyň ani počty ubytovaných.
- Vytvoření rezervace nevystavuje doklad, nezapisuje platbu ani nic neodesílá
  do účetnictví nebo e-mailem.

### Plátci a rychlé zadávání

1. Běžná rezervace používá jednoho výchozího plátce automaticky; nový technický
   model nesmí přidat další povinnou obrazovku do obvyklého postupu.
2. Před vystavením dokladů lze zvolit **Rozdělit mezi více plátců**. Společné
   počty zůstanou u rezervace; při rozdělení musí být zřejmé, které osoby už
   byly přiřazeny, včetně případného výchozího plátce.
3. **Přidat plátce** otevře kompaktní formulář: jméno/název, počty osob podle
   věkových kategorií, volitelně e-mail a další fakturační údaje.
4. Termín, počet nocí a dohodnuté jednotkové ceny se předvyplní ze společných
   údajů skupiny. Vycházet z uložených cen skupiny, nikoli při každém dalším
   plátci znovu načítat změněný katalogový ceník.
5. Termín, ceny a další položky lze u plátce výjimečně upravit. Stejně jako
   dnes se úprava kalkulace nepromítá do již vystavených dokladů.
6. **Uložit a přidat dalšího** uloží rozpracovanou fakturaci a připraví dalšího
   plátce se společnými předvolbami. Nekopíruje jméno, přijaté platby ani doklady.
   Doplňkové služby a místní poplatky nesmí bez rozlišení zkopírovat celé skupině
   opakovaně; příslušná množství se kontrolují v kalkulaci plátce.
7. Před vystavením zůstává náhled a výslovné vystavení. Tento plán nepožaduje
   automatické hromadné vystavení ani odeslání všech připravených dokladů.

### Doklady a platby plátce

Každý plátce má vlastní kalkulaci a odběratele, případné zálohové výzvy,
daňové doklady k přijatým zálohám, jednu konečnou fakturu, platby a případné
opravy/vratky podle současných pravidel. Odběratele po vystavení chrání dosavadní
pravidla; jeden plátce nemůže čerpat zálohy ani platby jiného.

Podporovat oba běžné průchody: konečná faktura a úhrada po pobytu, nebo vlastní
záloha před pobytem, ZDD, vyúčtování s odpočtem a doplatek. Částečné úhrady se
vyhodnocují za daného plátce. Datum a účetní povaha platby nadále rozhodují,
zda jde o zálohu nebo doplatek; původní kontroly DUZP zůstávají zachované.

### Stav skupiny a dokončení rozdělení

Zobrazit odděleně:

- **Rozdělení osob:** součet přiřazený plátcům vůči počtům rezervace, včetně
  rozpadů kategorií. Rozdíl zvýraznit, ale neblokovat ukládání ani vystavení.
- **Vystavení:** počet aktivních plátců s konečnou fakturou a počet čekajících.
- **Úhrady:** počet uhrazených konečných faktur vůči počtu vystavených. Výzvy,
  ZDD a opravné doklady nejsou další konečné faktury v tomto jmenovateli.

Příklad: **Rozděleno 31/35 osob · 2 plátci čekají na fakturu · 6/8 faktur uhrazeno**.

Akce **Rozdělení dokončeno** výslovně potvrzuje, že obsluha už nečeká další
plátce; lze ji použít i při rozdílu oproti odhadu osob. Jde o organizační údaj,
nikoli o ručně nastavovaný stav zaplacení. Rozdělení musí jít znovu otevřít;
přidání/odebrání plátce nebo změna jeho přiřazených počtů potvrzení zneplatní.
Změna platby sama rozdělení znovu neotevírá.

Celou skupinu označit jako vyúčtovanou a uhrazenou až po dokončení rozdělení,
vystavení konečné faktury všem aktivním plátcům a vypořádání jejich závazků.
Nula plátců nebo nula faktur není stav zaplaceno. Samotné uhrazení všech
dosud vydaných faktur neznamená dokončenou fakturaci skupiny.

Přeplatek jedné rodiny nezakryje dluh jiné. Částečné úhrady, prodlení, přeplatky,
opravy a vratky odvozovat ze skutečných dokladů a finanční evidence plátce;
počítání faktur nenahrazuje tyto výpočty. Po splatnosti je skupina, pokud má
některý plátce neuhrazený splatný závazek. Přehledy a jejich filtry používají
stejná pravidla, s jedním řádkem na rezervaci.

### Jednodušší formulář a výběr termínu

- Základ formuláře: kontakt, termín, počty ubytovaných a stravování. Další
  údaje ponechat kompaktní a dostupné podle potřeby; zachovat dnešní možnosti.
- Jeden český kalendář pro rozsah: první kliknutí příjezd, druhé odjezd,
  zvýrazněný interval a viditelný počet nocí. Na větší obrazovce lze vedle sebe
  ukázat dva měsíce, na mobilu zachovat přehledné dotykové ovládání.
- Zachovat také ruční zadání dat a ovládání klávesnicí. Výběr i serverová
  validace musí shodně rozumět příjezdu, odjezdu a počtu nocí.
- Při samostatném posunu příjezdu zachovat již zvolený počet nocí. Nový rozsah
  určí přímo dvě vybraná data. Odstranit dnešní přepis odjezdu na příjezd + 1
  při každé změně příjezdu. Prázdný nebo neplatný vstup nesmí ztratit další data.
- Pokoje standardně zobrazit jako řádek **Pokoje nepřiřazeny · Vybrat**, nebo
  stručný seznam přiřazených pokojů s akcí upravit. Výběr rozbalit až na požádání,
  jak při založení, tak při úpravě. Sbalení nesmí ztratit vybrané pokoje.
- Zachovat kontrolu dostupnosti pokojů a současnou podporu rozpracovaných
  rezervací bez odjezdu; vystavení nadále vyžaduje platný uzavřený termín.
- Změna termínu nesmí automaticky přecenit existující kalkulace plátců ani
  přepsat jejich vydané doklady. Rozdíly proti společným údajům zobrazit ke kontrole.

## Datové změny a technický směr

Zavést samostatný fakturační celek plátce pod rezervací, například
`billing_accounts`. Jde o pracovní název; konkrétní názvy polí a API se ověří
při implementaci. Plátce není nová rezervace ani povinný záznam ubytovaného hosta.

- Odběratele, kalkulaci, doklady a platby jednoznačně přiřadit fakturačnímu celku.
  Zachovat návaznost na původní rezervaci a kontrolovat shodu vlastnictví na
  serveru i databázovými omezeními. Opravný doklad a jeho zdroj patří témuž plátci.
- Jedinečnost kalkulace, odběratele a konečné faktury přesunout z celé rezervace
  na plátce. Jedinečnost čísel, VS, požadavků a bankovních pohybů zůstává globální.
- Doplnit samostatné počty ubytovaných a potvrzení dokončení rozdělení.
  Společnou kalkulaci/cenové nastavení lze využít jako předlohu; finanční saldo
  skupiny však neodvozovat od odhadované ceny za všechny osoby.
- Kontext `Billing` přijímá jednoznačný rozsah plátce pro náhled, vystavení,
  zálohy, odpočty, saldo, opravy a vratky. Případné kompatibilní vstupy přes
  `booking_id` smějí automaticky vybrat jen jednoznačného výchozího plátce.
- Zachovat transakční zámky, kontrolu zastaralého náhledu, souběžných úprav,
  idempotenci a atomický vznik dokladu, čísla a požadavků pro pracovní úlohy.
- Výjimka termínu/ceny plátce slouží jeho kalkulaci a snapshotu dokladu.
  Nevytváří další kalendářovou rezervaci ani kuchyňský rozpis.
- Dosavadní soukromé pobyty zachovají obsazenost a stravování bez finanční
  evidence. Nový model nesmí odvodit platbu ze starého stavu interní kalkulace.
- Zachovat UUID, soft delete obchodních záznamů, administrátorský PIN a ochranu
  stažení dokladů. Plátce s vydanými doklady nelze odstranit jako pouhý koncept.

### Převod existujících dat

Použít nové přidávací Ecto migrace. Každé existující rezervaci přiřadit jednoho
výchozího plátce a převést k němu stávající kalkulaci, odběratele, všechny doklady
a platby. Zachovat původní ID, částky, daňové a zákaznické snapshoty, čísla, VS,
PDF, účetní exporty i jejich identity a návaznosti bankovních potvrzení.

Počty ubytovaných převzít z dosavadních položek typu `person`. Při nestandardních
názvech kategorií zachovat doložitelný celkový počet a označit nejasný rozpad
k doplnění; věk hostů neodhadovat. Přesný migrační tvar musí zvládnout i rezervace
bez kalkulace, legacy ceny bez DPH, osobní pobyty a soft deleted záznamy.

Historické doklady se nevystavují znovu, nepřepočítávají a neposílají automaticky
znovu do ABRA. Staré rezervace se automaticky nerozdělují podle dalších hostů.
Před vystavením lze rozdělit dosud nefakturovaný pobyt; již vydané dokumenty
nepřevádět na různé odběratele bez samostatného návrhu účetní opravy.

## Hranice změn ABRA a plateb

Zachovat stávající HTTP klient, účetní formáty, mapování, přepínače zapojení,
identitu exportu podle dokladu, pracovní úlohy, ověření vzdáleného stavu,
opakování po výpadku a výslovné potvrzování přijatých bankovních plateb.

Upravit místní rozsah vyhledávání a kontrol:

- VS identifikuje konkrétní doklad a jeho plátce. Vyhledání konečné faktury,
  zbývající částky a případných starších záloh musí zůstat u tohoto plátce.
- Náhled ZDD, odpočty, kontroly oprav/vratek a následné vyúčtování zahrnují
  pouze daného plátce; vystavení faktury jedné rodině neuzavře zálohy ostatním.
- Odpočet ověřuje i shodného plátce zdrojového ZDD, ne pouze shodnou rezervaci.
  Uhrazená záloha se při vyúčtování nepočítá jako nový bankovní příjem.
- Zachovat ochranu před dvojím potvrzením stejného pohybu a možnou ruční
  duplicitou. Dvě různé rodiny mohou platit stejnou částku ve stejný den;
  shodná částka na společné rezervaci sama neznamená duplicitní úhradu.
- Bankovní dialog v rezervaci může zobrazit návrhy všech jejích plátců,
  ale u každého jasně ukáže cílového plátce a doklad. Potvrzení pracuje jen
  s tímto cílem. Dosavadní omezení starého VS a doplatků zůstávají zachována.

Neslibovat nulový zásah do integračních modulů: místní kontroly dnes používají
celý pobyt. Cílem je zachovat princip a účetní kontrakt s přesným rozsahem plátce.

## Výkon

Oprava N+1 je schválená. Pro celou stránku rezervací načíst počty, pokoje,
souhrny plátců, dokladů a úhrad dávkově nebo agregovanými dotazy. Stejně postupovat
v přehledu plátců jedné rezervace. Upravovat dotčené čtenáře, nikoli v této etapě
plošně přepisovat nesouvisející moduly.

Vyhnout se volání `balance`, načítání kalkulace a dotazu na pokoje pro každý
řádek zvlášť. Na seznamy netahat binární PDF. SQL filtry a stránkování zachovají
jeden řádek na rezervaci. Počet dotazů ověřit existujícím záznamníkem dotazů
v `test/support/query_recorder.ex`; nemá růst po jednom s počtem řádků.

## Rozhodnutí

| Datum | Rozhodnutí a důvod | Potvrzení / zdroj |
| --- | --- | --- |
| 2026-11-04 | Jedna skupina zůstává jednou rezervací; více faktur nevytváří nové rezervace. | Původní zadání a odsouhlasení návrhu |
| 2026-11-04 | Každý platí svou část, buď po pobytu, nebo s vlastní zálohou; společná záloha není potřeba. | Odpověď uživatele na otázku o zálohách |
| 2026-11-04 | Termín, ceny a stravování předvyplnit společně, umožnit výjimečné individuální úpravy. | Odpověď uživatele na otázku o společných údajích |
| 2026-11-04 | Skupina drží společné počty pro obsazenost a kuchyň; platby a faktury se vyhodnocují po plátcích. | Odsouhlasený návrh |
| 2026-11-04 | Rozdíl v počtech jen upozorní; rozdělení obsluha dokončí výslovnou akcí i při rozdílu. | Výslovné „1. vyhovuje“ |
| 2026-11-04 | Kalendář s výběrem rozsahu a počtem nocí; zachovat délku při samostatném posunu příjezdu. | Návrh podle popsaných obtíží a následné odsouhlasení uložení plánu |
| 2026-11-04 | Pokoje jsou volitelné a standardně sbalené, s kompaktním souhrnem. | Uživatelská zpětná vazba k formuláři a odsouhlasený návrh |
| 2026-11-04 | Hromadně načítat dotčené přehledy a odstranit nalezené N+1 v časové ose. | Výslovné „2. určitě“ |
| 2026-11-04 | Zachovat současný princip párování a synchronizace ABRA; upravit pouze nutný místní rozsah po plátcích. | Původní požadavek a odsouhlasený návrh |
| 2026-11-04 | Nyní uložit plán; samotnou aplikaci zatím neimplementovat. | „pojďme to dát do plánu“ a původní vymezení zadání |

## Otevřené otázky

Žádná blokující obchodní otázka. Při implementaci určit konkrétní názvy polí,
migraci nestandardních historických kategorií a vhodnou lehkou komponentu
kalendáře podle aktuálního repozitáře. Tyto technické volby nemění odsouhlasený
rozsah. Případné nové požadavky na rozdělení společných záloh nebo již vydaných
dokladů vyžadují samostatné projednání.

## Postup realizace

- [x] **0. Analýza a dohoda:** prozkoumán současný model, formulář, kuchyň,
  doklady a účetní integrace; schválen rozsah a uložen tento plán.
- [x] **1. Ověřit aktuální main a všechny čtenáře:** doplnit inventuru použití
  `booking_id`, jediné kalkulace/konečné faktury a obsazenosti, včetně kalendáře,
  časové osy, dashboardu, statistik a finančních filtrů. Zvolit migrační tvar.
- [x] **2. Data a kompatibilita:** přidávací migrace plátců, počty rezervace,
  dokončení rozdělení, nové vazby a jedinečnosti; bezpečný převod na jednoho
  výchozího plátce a zachování účetní historie.
- [x] **3. Fakturační kontext:** kalkulace a uložené předvolby, odběratelé,
  náhledy, doklady, zálohy, odpočty, platby, opravy a vratky po plátcích;
  izolace vlastnictví, souběhu a idempotence.
- [x] **4. ABRA:** zúžit místní návrhy a ověření na plátce bez změny účetního
  kontraktu; regresní pokrytí záloh, konečných faktur a bankovních doplatků.
- [x] **5. Formulář rezervace:** počty osob, český výběr rozsahu, délka pobytu,
  sbalené pokoje, zachované stravování a atomické uložení rezervace s pokoji.
- [x] **6. Plátci v UI:** rychlé přidávání, společné předvyplnění, výjimky,
  kalkulace a doklady plátce, náhledy a bankovní dialog se zřetelným cílem.
- [x] **7. Souhrny a výkon:** stav rozdělení, vystavení a úhrad, filtry, přehled
  rezervace a hromadné načítání dotčených seznamů včetně časové osy.
- [ ] **8. Ověření a provozní dokumentace:** kontextové a LiveView regrese,
  měření dotazů, ruční desktop/mobil průchod, popis skutečně dodaného chování
  a aktualizace stavu tohoto plánu.

## Ověření a podmínky dokončení

- Jedna rezervace 35 osob je jednou v kalendáři, kapacitě, pokojích a kuchyni,
  a to před rozdělením i po vytvoření více plátců a dokladů. Změna fakturace
  jedné rodiny nepřidá porce ani nezmění počty ostatních.
- Rychlé přidání dalšího plátce zachová společné ceny a termín, vyčistí jeho
  identifikaci a nezduplikuje služby. Individuální výjimka zůstane zachována;
  změna katalogu ani skupiny nepřepíše vydaný snapshot nebo PDF.
- Běžná rezervace s jedním plátcem zachová dosavadní finanční výsledky,
  soukromý pobyt zůstane bez finančních stavů. Převod existující rezervace
  nezmění zůstatky, doklady ani identitu již zařazených účetních úloh.
- Ověřit dva plátce s různými cenami, vlastními dílčími zálohami a samostatným
  vyúčtováním i plátce bez zálohy s úhradou po pobytu. Přeplatek jednoho
  nevyrovná nedoplatek druhého a jeho oprava neovlivní saldo jiné rodiny.
- Dvě stejně vysoké bankovní úhrady ve stejný den od různých plátců se přijmou
  jako dva různé pohyby. Opakované potvrzení téhož pohybu nebo požadavku
  nevytvoří další platbu, ZDD, fakturu ani účetní přenos.
- Cizí plátce/doklad, podvržená vazba, odpočet jiného plátce a zastaralý
  náhled se odmítnou. Jediná konečná faktura je vynucena pro každého plátce
  i při souběhu, více plátců stejné rezervace může mít každý svou fakturu.
- Počet zaplacených faktur funguje s částečnými úhradami, odpočty, splatností,
  opravami a vratkami. Nulový doplatek po vlastní záloze nevyžaduje další příjem.
  Žádné faktury nebo nedokončené rozdělení se netváří jako hotová skupina.
- Rozdíl osob včetně opačných rozdílů kategorií upozorní a nezablokuje vystavení;
  výslovné dokončení funguje i při rozdílu a změna rozdělení je znovu otevře.
- Ověřit rozsah přes hranici měsíců/roku, přestupný den, ruční datum, klávesnici,
  mobil, zachování nocí, otevřený pobyt, sbalení pokojů a konflikt dostupnosti.
  Neplatné uložení nezanechá částečně změněnou rezervaci nebo přiřazení pokojů.
- Seznam, filtry, stránkování a souhrny jsou shodné i při více plátcích.
  Počet dotazů v dotčených přehledech neroste po jednotlivých rezervacích/plátcích.
- Rozšířit zejména sady `booking_billing_test.exs`, `booking_summary_test.exs`,
  `billing_concurrency_test.exs`, `abra_bank_payments_test.exs`,
  `abra_final_invoice_export_test.exs`, `abra_final_bank_payments_test.exs`,
  odpovídající LiveView a obsazenost/kuchyň. HTTP simulovat přes `Req.Test`;
  nevytvářet skutečné doklady ani neposílat hostům e-maily.
- Formátování a testovací režim podle `AGENTS.md`. Lokální testy standardně
  nespouštět, nečekat na CI a nepollovat je; výsledky CI ověří uživatel.
  Ruční průchod a případné živé účetní ověření vykázat odděleně od testů.

## Nasazení a rizika

Budoucí realizace vyžaduje migrace a kompatibilní změnu všech dotčených čtenářů.
Neodstranit stávající ochranu jedné konečné faktury dříve, než je nahrazena
jedinečností na plátce a kontrolami jeho vlastnictví. Při převodu počtů zabránit
dvojímu započtení skupiny, výchozího plátce a dalších plátců.

Před nasazením ověřit rozpracované bankovní a účetní úlohy: jejich původní
doklady, snapshoty, cíle a identity se zachovají. Nová externí služba, účetní
mapování nebo přepínač synchronizace nejsou součástí návrhu.

Po vzniku více faktur pod jednou rezervací není bezpečný návrat ke staré aplikaci,
která očekává jedinou konečnou fakturu. Návrat musí respektovat nově uložená
data; destruktivní mazání plátců a účetních vazeb není způsob rollbacku.

## Realizace a předání

- Základ: čerstvé `origin/main` (`ade1058`), větev
  `feat/group-reservations-multiple-payers`; výsledek v jedné PR.
- Hotovo: kroky 1–7, provozní dokumentace a rozšíření regresních sad.
  Samostatný `billing_accounts` nese přiřazené osoby a výjimku termínu.
  `billing_pricing_template` u rezervace uloží ceny při prvním rozdělení.
  Výchozí plátce slouží první skutečné rodině a zůstává aktivní.
- Inventura čtenářů: `Billing`, `BookingSummary`, čtyři místní bankovní/exportní
  moduly ABRA, kalkulace/odběratel/doklady/platby v LiveView, rezervovací formulář,
  souhrn rezervace, filtry a stránkování, iCalendar, časová osa, obsazenost,
  dashboard a počty rezervací ve statistikách. Kuchyň nadále čte jen rezervaci.
  Exporty a úlohy nadále používají původní identity dokladů.
- Migrace `20261104120000_add_billing_accounts.exs` přidává společné počty,
  plátce a cenové předvolby; zachovává historické identity a snapshoty.
  Kompozitní FK kontrolují rezervaci, plátce, rodiče a platební doklady;
  databázový trigger kontroluje vlastnictví zdrojových odpočtů.
  Migrace odmítá automatický destruktivní rollback.
- Ověřeno na Elixiru 1.20.4 / OTP 29.1: formátování změněných souborů,
  celoprojektové `MIX_ENV=test mix format --check-formatted`,
  `MIX_ENV=test mix compile --warnings-as-errors` a kompilace změněných
  testovacích modulů bez jejich spuštění. Na místním PostgreSQL proběhla migrace
  a kontrola SQL souhrnů, kalendáře a časové osy. `git diff --check` bez chyb.
- Zbývá v kroku 8: uživatel ověří CI a lokální desktop/mobil průchod včetně
  klávesnice. Lokální testy nebyly spuštěny; na CI se nečekalo a jeho stav nebyl
  dotazován. Živá ABRA, skutečné bankovní potvrzení ani e-maily hostům nebyly
  použity. Nasazení, audit historických produkčních dat a provozní záloha
  zůstávají uživateli.

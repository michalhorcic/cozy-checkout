# Cozy Adventure – úkolovník a kronika sezóny

- Stav: etapa 3A implementována v PR #113; etapy 3B/3C čekají na další práci a CI ověřuje uživatel
- Vytvořeno a aktualizováno: 2026-11-12
- Navazuje na: [dosavadní implementační plán](2026-11-11-cozy-adventure.md), [současnou funkci](../features/ADVENTURE.md), PR #112
- Rozsah: správa questů, opakované šablony a sezónní přehled reálného provozu

## Směr a potvrzená rozhodnutí

Questy mají sloužit jako gamifikovaný úkolovník: zapsat práci, vybrat odpovědného,
naplánovat opakování a zaznamenat splnění. Kampaň má být především přehled sezóny.
Zimní sezóna má již dost rezervací; další naplňování kapacity není výchozí cíl hry.
Současná horská grafika a čistá obrazovka zůstávají, vysvětlení patří do Průvodce.

Uživatel potvrdil:

- Jeden společný seznam úkolů s přiřazením hrdinovi nebo jako společný úkol.
- Nejvýše tři právě rozpracované osobní úkoly na hrdinu; zásobník ostatních úkolů může být větší.
- U opakování jednu otevřenou položku, s novým termínem bez hromadění kopií a bez penalizací.
- XP získá skutečný splnitel zvolený v UI, i pokud byl úkol přiřazen někomu jinému.
  Společný úkol odmění chatu jednou; zaznamenají se přispěvatelé.
- U financí odděleně inkaso v období a vyúčtování pobytů sezóny.
- Vyúčtování pobytu přecházejícího hranici sezóny celé podle data odjezdu;
  obsazenost se dál dělí podle jednotlivých nocí.
- U každé opakované šablony volitelná působnost: vždy / během vybrané kampaně /
  jen když jsou hosté.
- Poznámka u splnění zůstává nepovinná, hrdina zapamatovaný v prohlížeči.

Další návrhy v tomto dokumentu jsou doporučený rozsah, nikoli už nasazené chování.
Implementaci uživatel následně zahájil výslovným pokynem pokračovat podle obou plánů.

## 1. Úkoly: seznam práce a tři rozpracované výpravy

Na herní obrazovce zůstane hlavně „Tvoje výpravy“. Správa dostane vlastní místo
v Questech: společný seznam, rychlé přidání a správa opakovaných šablon.

Jednorázový úkol:

- Název je jediný nutný vstup při rychlém založení.
- Volitelné přiřazení Michal / Lucka / volný úkol / společný úkol chaty.
- Volitelný termín, priorita, kategorie a podrobnější popis. Priorita znamená
  naléhavost, nikoli počet XP. Bez povinného psaní poznámek.
- Doporučené kategorie: Provoz, Úklid, Kuchyně, Bar, Údržba, Administrativa.
- Odměna se předvyplní podle velikosti. Návrh: malý 50, střední 100, velký 250 XP;
  velikost a odměnu lze před aktivací upravit. Čísla nejsou hodiny práce ani mzda.
- Rozpracování je výslovná akce; pouhé přiřazení nezabere jeden ze tří slotů.
- Volný úkol lze převzít. Úkoly mimo tři rozpracované zůstávají v zásobníku,
  není nutné je ztrácet nebo rušit kvůli limitu hry.

Základní stavy: čeká → rozpracováno → hotovo; dále zrušeno/archivováno.
Zmeškaný termín je informace, bez záporných XP, streaků a automatického splnění.
Filtry: moje / volné / společné / všechny, stav, termín a kategorie; hledání v názvu.

Při potvrzení je vidět zvolený splnitel. Přiřazení označuje odpovědnost, neurčuje
příjemce odměny po skutečném dokončení jiným hrdinou. U společného úkolu se
výslovně zvolí přispěvatelé; systém je neodvodí z přiřazení ani posledního profilu.
Společná odměna se nekopíruje oběma osobám. PIN a self-report identita se nemění.

Historie uchová původní zadání, odměnu, přidělení, splnitele, přispěvatele a čas.
Archivace nezničí historii. Editace nesmí přepisovat již udělené odměny.
Doporučení pro opravu chybného splnění: auditované znovuotevření a kompenzace;
nové dokončení nesmí zvýšit čistou odměnu nad jednu odměnu téhož úkolu.
Konkrétní postup obnovení kompenzované odměny navrhnout před implementací této akce.

## 2. Opakované šablony

Spravovat název, kategorii, denní/týdenní frekvenci, dny/termín, výchozí přiřazení,
velikost/XP a působnost. Měsíční frekvence a složitá pravidla mohou přijít později.
Šablonu lze založit, upravit, pozastavit a archivovat. Úprava platí pro budoucí
výskyty; snapshot již splněných úkolů a XP ledger zůstávají neměnné.

Pravidla generování v Europe/Prague:

- Nejvýše jeden otevřený výskyt pro šablonu a její přiřazený rozsah.
- Když nastane další termín a výskyt je stále otevřený, aktualizuje se aktuální
  termín, nepřidá se další úkol. První termín a historie posunů zůstávají uložené.
- Nic se samo neoznačí za hotové; za vynechané termíny se neudělí XP.
- Po skutečném splnění vznikne další výskyt nejdříve v následujícím plánovaném
  termínu. Refresh ani opakovaný job nesmí vytvořit další odměnu za stejný termín.
- Pozastavení zastaví budoucí generování. Osud otevřeného výskytu musí být
  výslovná volba při správě, ne tiché smazání.

Působnost se nastavuje po šablonách:

| Volba | Význam |
| --- | --- |
| Vždy | Podle kalendáře i mimo sezónu a bez hostů |
| Během vybrané kampaně | Jen v jejím období a při povoleném provozu šablony |
| Jen když jsou hosté | Read-only kontrola obsazeného dne, podle pravidel kalendáře |

Podmínka „jsou hosté“ nesmí měnit statusy rezervací. Musí rozlišit hosty
od pouhé budoucí rezervace; příjezd zahrnout, odjezd vyloučit. Chybějící údaje
neznamenají prázdnou chatu. Nejasná podmínka se označí a umožní ruční přidání úkolu.
Nesplněný úkol se odjezdem hostů automaticky neuzavře. Jednotlivé výskyty zatím
nevázat povinně na konkrétní skupinu; „před příjezdem každé skupiny“ je možné
pozdější pravidlo, až se výslovně vyřeší překryvy a duplicity.

### Katalog z příkladů uživatele

| Šablona | Frekvence | Doporučená kategorie |
| --- | --- | --- |
| Připravit pokoje | Týdně | Provoz |
| Větší úklid | Týdně | Úklid |
| Připravit jídelníček | Týdně | Kuchyně |
| Nakoupit na příští skupinu | Týdně | Kuchyně |
| Uvařit potřebná jídla | Denně | Kuchyně |
| Zkontrolovat a uklidit společné prostory | Denně | Úklid |
| Zkontrolovat a doplnit bar | Denně | Bar |

Dny, působnost, přiřazení a velikost práce nastaví správce. Založení šablony
samo nic nenakoupí, nepřipraví v jídelníčku ani nepřepíše sklad.
Případný checklist (např. snídaně/oběd/večeře) odměňuje dokončení celého úkolu,
ne každý zaškrtnutý řádek; checklist je rozšíření, nikoli podmínka první verze.

## 3. Kampaň jako kronika sezóny

Základ sezóny: název, období, pásmo, zobrazené metriky a stav návrh/otevřená/uzavřená.
Doporučení: cíle jsou volitelné. Žádné povinné shánění rezervací ani povinný cíl
obsazenosti při založení. Kapacitu potřebuje jen procentní obsazenost; bez ní
zůstanou dostupné ostatní metriky a procento bude nedostupné.

Přehled má umět celé historické období, i před zapnutím hry. Otevírání historické
sezóny nesmí zpětně udělit herní XP. Dobové výsledky a metadata budou snapshoty;
po uzavření se případné opravy ukládají v nové dohledatelné verzi, původní výsledek
zůstane zachovaný. Úprava období či výpočtů vyžaduje jasnou novou verzi.

Doporučení pro herní vrstvu: odměňovat skutečné úkoly. Automatické milníky
za pouhou obsazenost nebo příjmy nejsou povinnou součástí nové sezóny.
Dosavadní odměny za 1/10 pobytů zůstanou v historii; změna produktu není důvodem
je kompenzovat. Nové sezónní přehledy mohou mít tyto milníky výchozí vypnuté.
Toto doporučení se zatím nepropisuje do současných kampaní.

### Peníze: dva samostatné pohledy

| Pohled | Časové zařazení | Co ukazuje |
| --- | --- | --- |
| Evidované inkaso v období | Uložené datum platby/refundace | Evidované příjmy a vratky během sezóny, včetně záloh |
| Pobyty sezóny | Datum odjezdu pobytu v období | Vyúčtování a stav úhrad těchto pobytů, i když byly peníze přijaty mimo sezónu |

Příklad: listopadová záloha 30 000 Kč a lednový doplatek 70 000 Kč za lednový
pobyt s konečným vyúčtováním 100 000 Kč. Zimní inkaso od prosince zahrne
70 000 Kč; vyúčtování zimního pobytu je 100 000 Kč a celkově uhrazeno 100 000 Kč.
Zálohová výzva a daňový doklad zálohy nejsou další inkaso ani další výnos navíc.

Pobyt přecházející hranici sezóny se peněžně celý zařadí podle odjezdu.
Lůžkonoci se rozdělí překryvem nocí. Pohledy se nesčítají do jednoho „výsledku“.
Inkaso není zisk a vyúčtování pobytu není automaticky přijetí peněz.

### Doporučené metriky

| Oblast | První užitečné ukazatele | Omezení |
| --- | --- | --- |
| Ubytování | Realizované lůžkonoci, obsazenost, dokončené pobyty, průměrná délka pobytu | Kapacita a definice pobytu musí být známé; součet účastí není počet unikátních osob |
| Bar | Inkaso dle plateb, rozdělení hotovost/QR, hodnota účtů po slevě, spropitné samostatně | Tržby a platby mají odlišné datum; spropitné nezaměňovat za prodej zboží |
| Fakturace | Přijaté platby, refundace, opravené konečné vyúčtování, uhrazeno/zbývá/po splatnosti | Více plátců na pobyt, zálohy, částečné platby a opravy bez dvojího započtení |
| Srovnání | Minulá srovnatelná sezóna a ukazatele na lůžkonoc | Stejné definice, délka a úplnost; část sezóny neporovnávat bez označení s celou minulou |
| Práce | Splněné úkoly a dokončená zlepšení | Herní self-report, nikoli ověřené provozní KPI nebo odpracované hodiny |

Na hlavní obrazovce doporučuji jen 4–6 karet; podrobnosti přes rozkliknutí.
U peněz vždy rozlišit bar a ubytování a označit typ částky. Nezobrazovat
součet lokálních plateb a stejných pohybů importovaných z ABRY.

Další užitečné možnosti: oblíbené produkty na baru, počet výměn skupin,
inkaso baru / realizovanou lůžkonoc, podíl doplatků uhrazených včas.
Poměrové ukazatele vyžadují známý jmenovatel a srovnatelnou populaci; barové účty
bez vazby na pobyt nebo servisní účty mohou zkreslit „útratu hosta“.
Kuchyňské náklady na porci, marže a zisk až při známém pokrytí nákladů;
kalkulované receptury a neúplné nákupy nejsou skutečný hospodářský výsledek.

## 4. Ověřené zdroje a pravidla čtení

Audit kódu 12. 11. 2026, bez přístupu k produkčním datům:

| Zdroj | Ověřená pole / API | Důsledek pro návrh |
| --- | --- | --- |
| `Sales.Payment` | `amount`, `payment_date`, `payment_method`, `deleted_at`, `order_id` | Inkaso baru má vlastní datum a soft-delete plateb |
| `Sales.Order` | `total_amount`, `discount_amount`, `tips_amount`, `is_service_order`, `status`, `inserted_at` | Ověřit časové zařazení účtů a servisní filtr, tržby oddělit od spropitného |
| `Sales.OrderItem` | Uložené `quantity`, `unit_amount`, `unit_price`, `vat_rate`, `subtotal` | Nepočítat historické částky podle aktuálního ceníku |
| `Sales.get_*_statistics` | Současné statistiky filtrují datum založení účtu | Nelze je bez ověření označit za inkaso podle data platby; otevřený účet může přesahovat sezónu |
| `Billing.Payment` | `kind=receipt/refund`, `amount`, `paid_on`, `billing_account_id`, `booking_id`, vazby na doklady | Inkaso minus refundace, ne součet vystavených dokladů |
| `Billing.Document` | `kind`, `total`, `issued_on`, `tax_date`, `parent_id`, `snapshot`, `lines` | Konečné doklady a jejich opravy; nevzít zálohu/ZDD jako další výnos |
| `Billing.BookingSummary.account_query/0` | Agregace plateb, konečných dokladů a oprav po účtech | Vzor pro více plátců; nepoužívat N+1 volání balance pro každý pobyt |
| `Adventure.Sources.Stays` | Současná read-only pravidla nocí a úplnosti | Zachovat rozlišení realizace a rezervací; změny verzovat |
| `Economics` | Lokální verzované snapshoty a účetní potvrzení | Účetní zisk až z úplných podkladů a odpovídajícího období, bez HTTP z renderu |

Nové čtení patří do `Adventure.Sources.Bar` a `Adventure.Sources.Billing`.
Finanční doklady/platby nesmějí zmizet z historického inkasa jen proto, že se
později smazala nebo stornovala rezervace. Filtry pro pobytové KPI nelze slepě
přenést na finanční historii. U baru ověřit význam smazané platby proti refundaci;
není zde samostatný druh refundace jako v Billing. První kartu přesně označit
jako inkaso z aktuálních platných záznamů, nepředstírat úplný bankovní audit.

Než půjde zobrazit hodnota prodejů baru, ověřit způsob zařazení účtu otevřeného
před sezónou a placeného v sezóně a rozdělení slev/spropitného u částečných plateb.
Nevytvářet domnělou přesnou historii prodejních událostí z aktuálního stavu účtu.
Tyto definice musí být v implementačním PR výslovné; první dodávka může začít
spolehlivým inkasem podle payment_date.

Každá metrika má vlastní zdroj, verzi definice, měnu/jednotku, období, `as_of`
a úplnost. Chybějící faktura nebo chybějící cenová/nákladová data nejsou nula.
Přehled čerpá z evidovaných záznamů, nezaručuje úplnost všech skutečných bankovních
pohybů. Datumová pole patří přímo do lokálních dnů kampaně; UTC timestampy
filtrovat přes hranice dnů v Europe/Prague, od začátku prvního dne po začátek
dne následujícího po konci (horní hranice vyloučená), včetně DST.
Používat Decimal a existující finanční formátování. Žádné údaje hostů do
herních snapshotů, jen potřebné agregace a případné stabilní reference.

## 5. Datový model a přechod

- Zachovat samostatný Adventure context, herní adresáře a tabulky.
- Doplnit spravované verzované šablony; využít stávající quest instance a ledger,
  nepřepisovat historii přesunem definic z kódu do DB.
- Oddělit logicky zadavatele/přiřazení, skutečného splnitele, přispěvatele
  a příjemce XP. Dosavadní profile_id nelze tiše předefinovat.
- Evidovat původní a aktuální termín opakování, další plánovaný termín,
  působnost a klíč výskytu. Unikátní DB pravidlo pro jeden otevřený výskyt.
- Rozšířit vlastní quest stavy pro zásobník a archiv. Sdílené questy musí mít
  právě jednu sdílenou odměnu; upravit současné ledger constraints, které
  zatím povolují shared odměnu pouze od achievementu.
- Při migraci čtyř dnešních šablon zachovat UUID instancí, snapshoty a award_key.
  Již splněný quest v aktuálním týdnu se po migraci nesmí nabídnout jako nová
  neodměněná instance jen proto, že vzniklo nové ID DB šablony.
- Nový sezónní přehled potřebuje vlastní verzi pravidel/režim. Dnešní povinné
  cíle, omezení historické aktivace a automatické milníky neměnit tiše u starých
  kampaní. Původní XP a finanční snapshoty zachovat.

Všechny zápisy jen do Adventure. Dokončení „doplnit bar“ nepřepíše sklad,
„připravit jídelníček“ nezmění stravování a „zkontrolovat úhradu“ nezaúčtuje platbu.
Žádný provozní hook, email, účetní doklad či synchronizace jako vedlejší efekt.

N+1 riziko: finance nesčítat dotazem pro každý pobyt, účet, doklad ani den.
Navrhnout dávkovou agregaci za období po jednotlivých zdrojích, agregovat před
joinem (ne násobit platby počtem řádků faktury). Schválení nových dávkových dotazů
řešit před implementací podle AGENTS.md; dosavadní souhlas se týkal pobytového
adaptéru. V plánování se žádný nový dotaz nad provozními daty nespouští.

## 6. Doporučené dodávky

1. **Etapa 3A – úkolovník:** jednorázové úkoly, přiřazení, velikosti, tři
   rozpracované, společné splnění a historie; spravované denní/týdenní šablony,
   působnost a generování bez hromadění. Nejprve data model a migrační kontinuita.
2. **Etapa 3B – sezónní přehled:** volitelné cíle, historické sezóny, rozšířené
   read-only adaptéry, oddělené inkaso a vyúčtování pobytů, kvalita po metrikách.
   Začít lůžkonocemi, inkasem baru a platbami/vyúčtováním ubytování.
3. **Etapa 3C – porovnání a další karty:** srovnatelné sezóny, poměrové ukazatele,
   produkty, případně checklisty a úkoly před konkrétním příjezdem.
4. **Později:** skill tree, účetní zisk/náklady, rekonstrukce. Nejdřív užitečné
   každodenní úkoly a důvěryhodná sezónní čísla.

Každou dodávku lze ověřit samostatně. Nezačínat automatizací plateb či skladu.

## 7. Akceptační kritéria pro budoucí implementaci

- Založit vlastní úkol bez povinného termínu, odměny ručně zadávané číslem či poznámky;
  přidělit, převzít, dokončit a najít v historii. XP odpovídají skutečnému splniteli.
- V zásobníku více než tři úkoly, ve výpravách nejvýše tři osobní rozpracované.
- Sedm ukázkových opakovaných šablon lze spravovat bez změny kódu.
- Sedm zmeškaných denních termínů vytvoří jednu otevřenou položku, žádné XP navíc;
  původní termín zůstane dohledatelný. DST, přelom týdne/roku a pozastavení fungují.
- Působnost prázdná/obsazená chata a kampaň fungují read-only; neznámý stav se
  nezamění za prázdno, otevřený úkol se odjezdem nesplní sám.
- Dva hrdinové souběžně dokončí stejný společný úkol: jedna odměna chatě,
  žádná automatická osobní kopie. Opakování, editace a opravy neumožní XP násobit.
- Migrace, změna šablony a přepočet zachovají historické odměny a audit.
- Sezóna bez cílů a historická sezóna fungují; grafika zůstává čistá,
  správa a dlouhá vysvětlení jsou mimo hlavní herní obrazovku.
- Příklad záloha 30 000 + doplatek 70 000 vede na 100 000, nikoli 130 000.
  Správně i refundace, oprava faktury, částečná úhrada, více plátců a pobyt
  přes hranici sezón. Chybějící konečná faktura není vyúčtování nula.
- Vydané doklady a skutečné platby se neztratí smazáním rezervace.
- Obsazenost, inkaso a vyúčtování se nesečtou jako jeden typ veličiny;
  bez úplných nákladů se nezobrazí domnělý zisk.
- Počet query nezávisí na počtu pobytů a dokladů; opakování nevytvoří duplicity.
- Ověřit SQL zápisy pouze do Adventure a nepřítomnost provozních hooků/HTTP.
- Vypnutí modulu zastaví generování i přepočty; admin PIN, zapamatovaný hrdina
  a přiznaná self-report identita zůstanou zachované. Bez přístupu z veřejného POS.
- Nové testy podle AGENTS.md, CI a následný ruční checklist. Tento dokument
  zatím nepředstavuje implementaci ani výsledek nových testů.

## 8. První dodávka etapy 3A (12. 11. 2026)

Implementováno: vlastní jednorázové úkoly, přiřazení a převzetí, velikost/XP,
termín, priorita, kategorie a popis; zásobník, společný limit tří rozpracovaných
s původním katalogem; skutečný splnitel, explicitní přispěvatelé a jediná
společná odměna; editace před rozpracováním, archivace a filtrovaná historie.
Správa je v Questech, hlavní tábor ukazuje jen osobní rozpracované výpravy.

Migrace `20261112120000` rozšiřuje stávající herní tabulky bez přepsání
legacy UUID, snapshotů, `profile_id` nebo award keys. Nové přiřazení a zadavatel
mají vlastní FK, splnitel a přispěvatelé jsou v důkazu. Transakční profilový
zámek chrání limit a questový zámek jednu odměnu napříč různými splniteli.
Archivace neotevírá možnost opakovaného získání odměny. Migrace má záměrně
nevratné `down`, protože odstranění polí by zničilo novou historii.

Nové ExUnit/LiveView testy připravené pro CI: limit napříč katalogem a úkoly,
atribuce, společné odměny, souběhy na samostatných spojeních, rollback,
filtry, validace, archivace, flag a zápisy pouze do Adventure. Lokální
ExUnit testy nebyly spuštěny; CI ověřuje uživatel. Prošla kompilace
`MIX_ENV=test mix compile --warnings-as-errors`, sestavení assetů, formátování
celého projektu a migrace na prázdném PostgreSQL 17. V Chromium byl ručně
proklikán přechod založení → rozpracování → dokončení jiným splnitelem
(Michalovo přiřazení, Lucka +100 XP) a společné dokončení s povinnými
přispěvateli (+250 pouze chatě), editace i archivace. Šířky 390/320 px
neměly vodorovný přesah. Souběhové ExUnit scénáře zůstávají pro CI.

Tato první dodávka byla následně ve stejném PR doplněna o opakování níže.
Nové sezónní režimy a finanční adaptéry (etapa 3B) zůstávají další prací.
Před jejich implementací je třeba dle AGENTS.md schválit nové dávkové čtení
provozních zdrojů; souhlas pro působnost podle hostů se týká jen adaptéru
`Adventure.Sources.Guests`. Dosavadní kampaně a jejich milníky se nemění.

## 9. Dokončení etapy 3A ve stejném PR #113 (12. 11. 2026)

Uživatel výslovně zadal další krok ve stejném PR a schválil jeden dávkový
SELECT nad rezervacemi pro všechny splatné hostovské šablony dohromady.
Implementováno:

- Správa denních/týdenních šablon, dny týdne, výchozí přiřazení, velikost/XP,
  popis, kategorie, priorita a působnost. Nová šablona je pozastavená;
  sedm doporučených příkladů lze založit opakovatelnou akcí bez duplikací.
- Verzování každé editace i stavové změny, audit aktéra a snapshot budoucího
  výskytu. Otevřenému zůstává zadání i odměna, posouvá se jen termín.
- Jeden otevřený výskyt vynucený partial unique indexem, unikátní klíč termínu,
  template/quest locks a `SKIP LOCKED` při generování. První termín a historie
  posunů jsou viditelné; dokončení ani XP nevznikají automaticky.
- Hodinový Oban worker ve frontě `adventure` a ruční obnova sdílejí stejný
  přepočet podle místních dnů Europe/Prague. Vypnutý modul blokuje i SQL dotazy
  workeru. Samotný render negeneruje práci. Oban používá infrastrukturní
  tabulky jobů; doménové zápisy zůstávají pouze v Adventure.
- Pozastavení/archivace vyžadují výslovné rozhodnutí ponechat, nebo zrušit
  otevřenou práci. Ponechanou lze dokončit později. Nový výskyt se negeneruje
  za místní den, kdy byla předchozí práce dokončena/zrušena.
- Působnost vždy / vybraná aktivní kampaň v období / prokazatelně přítomní
  hosté. Hostovský adaptér má jeden agregovaný SELECT za celý přepočet,
  nemění statusy a neukládá údaje hostů. Neznámé podklady nejsou prázdná chata.
  Dnešní neověřená či prázdná podmínka se během dne znovu kontroluje;
  minulá přítomnost se zpětně nedomýšlí a otevřené úkoly se odjezdem neuzavřou.
- Migrace `20261112130000` zakládá původní čtyři definice jako pozastavené
  šablony na hrdinu. Nezmění legacy UUID, snapshoty, vlastnictví ani odměny;
  generování převezme otevřenou instanci a respektuje již uzavřený týden.
  Původní frekvence a jeden týdenní den zůstávají u těchto definic omezené
  kvůli kontinuitě period keys; pro novou frekvenci se zakládá nová šablona.
  Změna příjemce nepředefinuje historické `profile_id`.

Podrobný návod, definice přítomnosti a omezení jsou v
[ADVENTURE.md](../features/ADVENTURE.md). Přidané ExUnit/LiveView scénáře
pokrývají sedm zmeškaných dnů, DST a přelom roku, verze, další termín po
skutečném splnění, působnost a její neznámé údaje, explicitní pozastavení,
legacy kontinuitu, souběhy a zápisy pouze do Adventure. Lokální ExUnit
sada nebyla spuštěna dle AGENTS.md; výsledky CI ověřuje uživatel.

Ověření této navazující změny: kompilace s warnings-as-errors, sestavení
assetů a formátování celého projektu prošly na připnutém toolchainu. Migrace
se aplikovala na izolovaný PostgreSQL 17 s existujícími herními daty.
V Chromium byly proklikány založení, přepočet velikosti na XP, spuštění,
opakovaná obnova, pozastavení s ponecháním a sedm doporučených šablon.
Hostovské šablony bez hostů nevytvořily práci, po vložení aktivního testovacího
pobytu vznikly dva výskyty s jediným společným SELECTem; ověřen i vyhledávací
výběr kampaně a týdenní dny. Simulace sedmi zmeškaných dnů zachovala jeden
úkol s původním termínem a historií posunu. Generování nepřidalo XP.
Desktop a šířky 390/320 px byly bez vodorovného přesahu. ExUnit sada zůstává
pro CI podle výše uvedených pravidel.

Po skutečném dokončení opakovaného úkolu a po archivaci jiného otevřeného
výskytu byl v Chromium ověřen i opakovaný přepočet téhož dne: žádná nová
instance ani duplicitní XP, další termín následující den. Agregace času
uzavření používá explicitní UTC typ před převodem na pražský den; regresní
scénáře zahrnují dokončení i zrušení.

### Oprava nahlášených CI pádů (12. 11. 2026)

`Tasks.update/3` řetězilo `or` s nullable `archived_at` a `template_id`;
mezivýsledek `nil` vyvolal `BadBooleanError`. Podmínky nyní používají
explicitní `not is_nil(...)`, stejně jako kontroly rozpracování a dokončení.
Regrese ověřuje editovatelný čekající jednorázový úkol, blokovanou editaci
výskytu šablony a archivované práce. Na žádost uživatele byly lokálně spuštěny
`PGUSER=elixir PGPASSWORD='' mix test test/cozy_checkout/adventure test/cozy_checkout_web/adventure`:
**72 testů prošlo** na izolovaném PostgreSQL 17. Prošla také kontrola
formátování celého projektu. Kompletní sadu a CI ověřuje uživatel.

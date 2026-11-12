# Cozy Adventure – provoz a budování chaty

- Stav: úkolovník a herní rozdělení hotové v PR #113, sezónní kronika v PR #115, zapamatování hrdiny v PR #116; 4A dodána, obecný základ 4B implementován v pracovní větvi; omezená schválená 4C a kompaktní opakování implementovány, předání v oddílu 15; následné schválené zjednodušení projektového UX popisuje oddíl 16
- Vytvořeno a aktualizováno: 2026-11-12
- Navazuje na: [dosavadní implementační plán](2026-11-11-cozy-adventure.md), [současnou funkci](../features/ADVENTURE.md), PR #112
- Rozsah: herní rozhraní nad provozem aplikace, správa questů, rozvoj chaty investičními projekty a kronika skutečných výsledků

## Směr a potvrzená rozhodnutí

Hra má postupně fungovat jako kooperativní budovatelská a provozní strategie
nad skutečnou chatou, ne pouze úkolovník doplněný XP. Questy organizují práci,
sezóna zaznamenává skutečný provoz a investiční projekty mají zanechávat trvalá
vylepšení chaty. Vybrané informace z Přehledu se mají objevit i v herním světě.
Zimní sezóna má již dost rezervací; další naplňování kapacity není výchozí cíl hry.
Horské prostředí a čitelnost zůstávají, ale hra má postupně vizuálně vyjadřovat
stav a rozvoj chaty. Podrobnosti a vysvětlení patří do detailů a Průvodce.

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
- Hra má být postupně rozhraním nad celou aplikací s herními prvky; vybrané
  informace ze současného Přehledu patří i do hry, ne pouze za odkaz do adminu.
- Do questů má být možné zadat investiční akce, které vylepšují celou chatu.
- Provozní aplikace zůstává pro Adventure pouze ke čtení. Rezervace, doklady,
  platby, sklady a další skutečné změny se zadávají existujícími funkcemi aplikace.
  Adventure zapisuje jen vlastní herní a plánovací stav.

Další návrhy v tomto dokumentu jsou doporučený rozsah, nikoli už nasazené chování.
Historický souhlas s implementací se týkal dokončených etap 3A/3B. Nový souhlas
pro omezenou 4A a její dodávku zaznamenává oddíl 13. Následný souhlas s obecným
základem 4B a jeho hranicemi zaznamenává oddíl 14; následné schválení omezené 4C zaznamenává oddíl 15.

> **Aktuální směr (12. 11. 2026 odpoledne):** Tábor je provozovaná a postupně
> vylepšovaná chata, nikoli jen seznam úkolů a odkazů. Oddíl 12 rozpracovává
> nový požadavek na budovatelskou strategii a určuje doporučené další dodávky.
> Oddíly 8–11 jsou historie implementace; jejich tehdejší formulace „později“
> nejsou aktuálním pořadím práce. Konkrétní nové mechaniky v oddílu 12 jsou
> návrhy k odsouhlasení, nikoli nasazené chování nebo automatické schválení kódu.

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
V novém režimu `season_v1` jsou cíle volitelné. Žádné povinné shánění rezervací
ani povinný cíl obsazenosti při založení. Kapacitu potřebuje jen procentní obsazenost; bez ní
zůstanou dostupné ostatní metriky a procento bude nedostupné.

Přehled má umět celé historické období, i před zapnutím hry. Otevírání historické
sezóny nesmí zpětně udělit herní XP. Dobové výsledky a metadata budou snapshoty;
po uzavření se případné opravy ukládají v nové dohledatelné verzi, původní výsledek
zůstane zachovaný. Úprava období či výpočtů vyžaduje jasnou novou verzi.

Nová herní vrstva odměňuje skutečné úkoly. Automatické milníky
za pouhou obsazenost nebo příjmy nejsou součástí `season_v1`.
Dosavadní odměny za 1/10 pobytů zůstanou v historii; změna produktu není důvodem
je kompenzovat. Původní `stays_v1` se nepřevádí; implementovaný stav je v oddílu 11.

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

První finanční čtení bylo implementováno v `Adventure.Sources.Bar`
a `Adventure.Sources.Billing`; další adaptéry se schvalují samostatně.
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

## 5. Datový model a přechod etap 3A/3B

Původní návrh přechodu, jeho realizace je zaznamenána v oddílech 8–11.
Pro další implementaci modelu projektu nejprve vycházet z aktuálních schémat,
nikoli znovu provádět již dokončené migrace níže.

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
řešit před implementací podle AGENTS.md. Již udělený souhlas pro pobyty
a finanční adaptéry 3B zaznamenává oddíl 11; nové zdroje z oddílu 12 mají
samostatnou schvalovací bránu. V plánování se žádný nový provozní dotaz nespouští.

## 6. Dodávky a aktuální pořadí

1. **Hotovo 3A – úkolovník:** jednorázové úkoly, přiřazení, velikosti, tři
   rozpracované, společné splnění a historie; spravované denní/týdenní šablony,
   působnost a generování bez hromadění, včetně migrační kontinuity.
2. **Hotovo 3B – sezónní přehled:** volitelné cíle, historické sezóny, rozšířené
   read-only adaptéry, oddělené inkaso a vyúčtování pobytů, kvalita po metrikách.
   Zahrnuje lůžkonoci, inkaso baru a platby/vyúčtování ubytování.
3. **Hotovo 4A – živý tábor:** převést vybraná data z Přehledu do oblastí
   chaty a nabídnout jasné přechody do stávajících provozních funkcí.
4. **Implementováno 4B – investiční projekty:** dlouhodobé zlepšení chaty rozdělené na
   skutečné questy, plánovaný rozpočet, návaznosti a ruční převzetí výsledku.
5. **Implementována omezená 4C – viditelný rozvoj:** lidsky převzaté projekty
   přidávají obecný milník oblasti a trvalou Kroniku chaty; nemění provozní čísla.
6. **Plán 5A/5B – Služba dne:** ruční návrh skutečného questu z existujícího
   podnětu, ochrana proti duplicitám a návazná práce bez automatického splnění.
   Potvrzená produktová pravidla a schvalovací brány jsou v oddílu 17.
7. **Další priorita 5C – živý Bar:** omezený read-only stav a původní provozní
   odkazy; konkrétní rozsah, zdroje a dávkové čtení ještě vyžadují schválení.
8. **Původní 3C – porovnání a další ukazatele:** srovnatelné sezóny, poměry,
   produkty a případně úkoly před příjezdem. Zůstává v zásobníku, není automaticky
   další implementací před herním provozem a investicemi.
9. **Později:** příprava příjezdů a údržba po výslovném výběru, osobní skill tree,
   klasické osobní přihlášení, úplné účetní
   náklady/zisk, evidence majetku a odpisy. Plánování rekonstrukce může být
   projektem 4B; plné investiční účetnictví se tím nezavádí.

Každou dodávku lze ověřit samostatně. Nezačínat automatizací plateb či skladu.

## 7. Akceptační základ etap 3A/3B

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
- Nové testy podle AGENTS.md, CI a následný ruční checklist. Výsledky již
  provedených ověření jsou v historii níže; návrh nových etap není jejich ověřením.

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
V této fázi ještě zbývaly sezónní režimy a finanční adaptéry; jejich pozdější
schválení a implementaci zaznamenává oddíl 11. Souhlas pro tehdejší působnost
podle hostů se týkal adaptéru `Adventure.Sources.Guests`, nikoli libovolného
nového čtení. Dosavadní kampaně a jejich milníky se nemění.

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

## 10. Herní interface: tábor, kniha questů a svět chaty (12. 11. 2026)

Uživatel požaduje rozhraní, které působí jako hra a skrze skutečné úkoly
pomáhá spravovat chatu. Nestačí přidat XP k administračním kartám. Herní
rozhraní má být každodenní místo pro výběr práce, její plnění, společný postup
chaty a přechody do ostatních částí aplikace. Tuto prioritu zachovat i v dalších
iteracích; nepřidávat stejné funkce na více herních obrazovek bez jasné role.

Potvrzeno uživatelem: v táboře jsou osobní i společné výpravy. Pro přechod
do aplikace chce herní rozcestník na rezervace, kuchyň, bar a finance.

### Jednoznačné role obrazovek

| Obrazovka | Co se zde dělá | Herní podoba |
| --- | --- | --- |
| Tábor | Vybrat hrdinu, najít výpravu, přijmout ji, pracovat na ní a potvrdit splnění; společné výpravy odděleně od tří osobních slotů | Domovská scéna chaty, portrét/XP hrdiny, sloty vybavení, aktivní výpravy, mapa světa a společná sezóna |
| Questy | Vytvářet a upravovat zadání, přiřazení, odměny a termíny; spravovat opakování, pozastavení a archiv; číst historii | Kniha zadání se samostatnými částmi Jednorázové questy / Opakované questy / Historie |
| Nastavení | Sezóny, pravidla a audit | Zázemí hry, bez duplikace plnění úkolů |

**Tábor je herní plocha.** „Najít další výpravu“ otevře nástěnku skutečných
čekajících zadání z knihy questů: vlastní jednorázové úkoly i aktuální výskyty
spravovaného opakování. Při otevření se výslovně obnoví splatné šablony,
bez udělení XP. Pevný katalog čtyř nabídek v UI se odstraní; původní API,
instance a odměny zůstávají kvůli historii kompatibilní. Když nic nečeká,
nabídka vede do knihy zadání, nevytváří fiktivní práci.

Osobní výběr přednostně ukazuje úkoly pro aktuálního hrdinu a volné úkoly.
Nabídka má také Společné a Všechny plus hledání. Přijetí osobního questu
přiřadí práci aktuálnímu hrdinovi a zabere jeden ze tří slotů. Společné mají
vlastní sekci a neobsazují osobní sloty; stále dávají jednu odměnu chatě
s explicitními přispěvateli. Skutečný splnitel se dál volí při potvrzení.

**Questy jsou kniha zadání.** Neobsahují druhou kopii tábora, aktivních výprav,
sezónních karet nebo tlačítek pro zahájení a splnění. Jednorázová část upravuje
jednorázová zadání; opakovaná část upravuje šablony, nikoliv neměnné snapshoty
jednotlivých výskytů. Historie zahrnuje i opakované a společné úkoly. Role
editace vs. hraní je vysvětlená přímo v nadpisu stránky. Úpravy zadání a odměny
zůstávají před rozpracováním, změny šablon pro budoucí výskyty.

### Vzhled a navigace jako hra

- Vlastní herní rám kolem Adventure, ilustrovaná domovská scéna a čitelný HUD.
  Běžný administrační sidebar hru neobklopuje; existující admin PIN a jeho
  kontrola všech LiveView událostí zůstávají zachované. Viditelný vstup
  „Do aplikace“ umožní kdykoliv opustit herní prostor.
- Osobní výpravy představovat třemi viditelnými sloty a kartami přijatých
  questů. Nabídka má podobu nástěnky/svitků s názvem, odměnou, přiřazením,
  termínem a jasnou akcí přijetí. Hlavní obrazovku nezahltit formuláři.
- Správu pojmout jako knihu, s odlišeným záhlavím, částmi a kartami zadání.
  Vstupy a složité operace patří sem, nikoliv do aktivních výprav.
- Mapa chaty má čtyři pojmenované cíle: Recepce → kalendář rezervací,
  Kuchyně → stravovací plán, Bar → barový sklad, Pokladnice → doklady/platby.
  Odkazy skutečně otevřou existující části aplikace. Přechod sám nikdy
  nesplní quest, nevystaví doklad ani nezmění sklad. Po návratu zůstává
  práce uložená a hrdina se obnoví z preference prohlížeče; aktuální řešení
  používá localStorage s cookie zálohou, viz oddíl 12.1.
- Udržet světlé horské téma, materiály papíru/dřeva, konzistentní ikonografii,
  responzivitu, ovládání klávesnicí a možnost omezení pohybu. Herní podoba
  nesmí zhoršit čitelnost, orientaci ani dostupnost hlavních akcí na mobilu.

### Další iterace

Sezónní kroniku, rozvoj chaty a další oblasti navrhovat jako části herního
světa. Herní motivace vychází ze skutečných todos a ověřeného stavu provozu;
nezavádět fiktivní finanční výsledky, automatické splnění za pouhou návštěvu
stránky ani další kopie úkolovníku. Toto zadání nyní zahrnuje mapu oblastí;
konkrétní provozní odkazy na jednotlivých questech lze řešit samostatně podle
potřeby. Sezónní přehled z etapy 3B tento herní rám zachovává; nový směr provozu
a budování rozpracovává oddíl 12.

### Akceptace této změny

- Vytvořit nebo upravit jednorázový quest v knize, přejít do tábora a najít
  stejné zadání přes „Najít další výpravu“, přijmout ho a potvrdit splnění.
- Spustit opakovanou šablonu v knize a vybírat její splatný výskyt ve stejné
  herní nabídce. Pozastavení s ponecháním zachová již otevřenou práci.
- Kniha nemá výpravy ani tlačítka pro zahájení/splnění; tábor nemá editační
  formuláře ani druhý katalog. Obě stránky mají odlišné hlavní nadpisy.
- Společná výprava je v táboře vidět a její přijetí neubere osobní slot.
- Mapa otevře skutečnou provozní stránku a návrat zachová hrdinu i práci.
- Ověřit desktop, 390/320 px, hledání, klávesnici a zavření nástěnky s návratem
  fokusu. Prohlížení nepřiděluje XP a počet dotazů nezávisí na počtu pobytů.

Ověření herního rozdělení: na připnutém Elixir/OTP prošlo **76 lokálních
ExUnit testů** Adventure včetně LiveView a souběhů; testy ověřují oddělené
role stránek, nabídku vlastních i opakovaných úkolů, osobní limit, společné
výpravy, historické původní questy a herní navigaci. Prošly kompilace,
sestavení assetů, formátování celého projektu a `git diff --check`.
V Chromium byla proklikána tvorba a editace zadání v knize, nabídka skutečného
questu v táboře, osobní i společné přijetí, hledání, desktop a 390/320 px.
Escape zavřel nástěnku a vrátil fokus na „Najít další výpravu“. Portál otevřel
barový sklad a po návratu se obnovil Michal i jeho dva obsazené sloty.
Kniha neobsahovala táborové výpravy a tábor neobsahoval editační formuláře.
Tato úprava nemá další migraci ani konfiguraci; mění rozhraní a herní čtení.

## 11. Etapa 3B: sezónní kronika (12. 11. 2026)

Pro novou branch a samostatné PR uživatel výslovně schválil celou etapu 3B,
dávkové read-only agregace provozních tabulek bez N+1 a cílené lokální testy
Adventure. Povolené změny zahrnují pouze Adventure context, herní komponenty
a LiveView, Adventure testy, migraci vlastních herních tabulek a Adventure
dokumentaci. Provozní moduly, sdílené styly/layouty, router a konfigurace jsou
pouze referencí; rozpracované cizí změny zůstávají nedotčené.

Potvrzená pravidla nové dodávky:

- Nový režim `season_v1` nemá automatické XP. Cíle a kapacita jsou volitelné;
  bez kapacity je pouze procentní obsazenost nedostupná. Staré `stays_v1`
  kampaně zachovávají pravidla, UUID, snapshoty a odměny.
- Historická sezóna se zapíše rovnou jako uzavřená, neobsadí jedno aktivní
  místo a nespustí opakované questy. Přehled zahrne celé zvolené minulé období.
- Barová hlavní karta ukazuje platné evidované platby bez servisních účtů;
  servis a hotovost/QR jsou rozlišené v detailu. Platba může zahrnovat spropitné,
  nejde o prodej zboží, audit všech bankovních pohybů ani zisk.
- Inkaso ubytování podle dne platby/refundace je oddělené od vyúčtování
  pobytů podle společného data odjezdu rezervace. Vydané konečné doklady
  a jejich přímé podepsané opravy nezmizí s pozdějším stornem/smazáním pobytu.
  Úhrady daných plátců jsou aktuální k přepočtu, včetně plateb mimo sezónu.
- Chybějící konečné doklady, účty, nehotové rozdělení plátců a neznámé časové
  zařazení se přiznávají jako neúplnost, nikoli nula. Osobní účty jsou zvlášť
  bez odhadu ceny. Dluh a přeplatek se agregují po plátcích, ne vzájemným započtením.
- Oprava uzavřené kroniky vyžaduje důvod a vytváří novou číslovanou verzi
  s vazbou na předchozí, aktérem a snapshotem pravidel. Původní výsledek zůstane
  zachován. Změna období vyžaduje novou sezónu.
- Tábor má šest stručných metrik, výběr historické sezóny a rozbalovací účetní
  list; Nastavení spravuje návrhy, uzavírání a audit. Questy se nerozšiřují
  o další přehled. Render ani přepnutí sezóny neprovádí provozní přepočet.

Nová migrace `20261112140000` se týká pouze Adventure tabulek a chrání
neměnné číslované snapshoty a uzamčená pravidla. Adaptéry `Adventure.Sources.Bar`
a `Adventure.Sources.Billing` agregují platby/doklady před spojením, každý
jedním SQL příkazem. Metadata úplnosti a zdroje jsou samostatná pro každou
metriku; herní snapshoty neobsahují údaje hostů. Žádné provozní zápisy, HTTP,
emaily, skladové změny ani účetní synchronizace.

Porovnání, produkty, náklady/zisk, přesné stáří dluhu po opravách a další
rozšíření 3C nejsou součástí této dodávky. Podrobné definice a omezení jsou
v [ADVENTURE.md](../features/ADVENTURE.md).

Ověření dodávky: 118 cílených Adventure testů prošlo na izolované PostgreSQL 17
databázi, včetně migrace, finančních regresí, čistě herních zápisů a souběžné
změny pobytu mezi zdrojovými agregacemi. Přepočet používá konzistentní
REPEATABLE READ snapshot, ne několik stavů READ COMMITTED. Prošel projektový
formatter, kompilace s `--warnings-as-errors` a sestavení assetů. V Chrome
byl proklikán historický zápis, oprava do nové verze a Tábor na šířkách
1440/390/320 px, bez horizontálního přesahu a JS výjimek. Použit Elixir 1.20.4;
lokální Erlang je 29.1.2, nikoli přesně připnutý 29.1. Celá testovací sada
nebyla spouštěna; výsledky GitHub CI ověří uživatel.

## 12. Další směr: kooperativní budovatelská strategie (12. 11. 2026)

### 12.1 Co je potvrzené a co je návrh

Uživatel chce provozovat a postupně vylepšovat skutečnou chatu skrze herní
rozhraní nad celou aplikací, vidět ve hře část současného Přehledu a zadávat
investiční akce do questů. Provoz je pouze ke čtení; všechny skutečné změny
zůstávají ve stávajících funkcích. To je potvrzený směr této aktualizace.

Mapa a omezený provozní rozsah 4A byly následně výslovně schválené a implementované
podle oddílu 13. Obecný základ projektů s etapami byl následně schválen podle
oddílu 14. Omezená 4C byla následně schválena podle oddílu 15; ostatní rozšíření zůstávají doporučením.

Implementační základ: 3A/3B jsou hotové v PR #113/#115. Oprava preference
hrdiny `76ab72b` byla sloučena v PR #116: localStorage s cookie zálohou,
kontrolou uložení a ochranou proti opožděné odpovědi. Ověřeno 18 JS a 17
LiveView testů a HTTP proklik; podrobnosti v `docs/features/ADVENTURE.md`.
Nejde o osobní přihlášení. Výchozí main při této revizi je `26121f5`;
před další prací znovu ověřit skutečný stav a CI, nebrat hash za budoucí základ.

### 12.2 Herní smyčka a inspirace

Z budovatelských strategií typu Anno/Foundation přebrat srozumitelnou mapu
oblastí, návaznosti vylepšení a viditelný trvalý rozvoj. Z managementových her
krátký přehled „co dnes potřebuje mou pozornost“ a volbu další investice.
Nepřebírat fiktivní těžbu měny, čekací časovače ani trestání za nepřihlášení.

Herní smyčka: **prohlédnout stav → zvolit problém nebo zlepšení → připravit
quest/projekt → udělat skutečnou práci přes existující nástroje → potvrdit
výsledek → vidět změněnou chatu a historii → rozhodnout o dalším rozvoji**.

Hra má tři jasně odlišené vrstvy:

| Vrstva | Příklad | Co smí změnit |
| --- | --- | --- |
| Pozorovaný provoz | Podle kalendáře přijede 12 lidí; menu má neúplné podklady | Jen zobrazení read-only zdroje |
| Práce a plán | Připravit menu; vyměnit bojler; rozhodnout o nabídce | Vlastní Adventure quest, projekt, přiřazení a termín |
| Rozvoj světa | V kronice přibyla nová koupelna; oblast má nový vzhled | Jen herní podobu a historii po výslovném převzetí zlepšení |

Peníze v účetnictví nejsou herní mince, XP nejsou mzda a level není fyzická
kapacita. Zlepšení neudělí smyšlené +10 % příjmů nebo automaticky více lůžek.
Základní funkce aplikace ani potřebný úklid se nikdy nezamknou za XP.

### 12.3 Živý tábor místo dalšího dashboardu

Doporučení: jedna přehledná 2D scéna/mapa chaty, nejprve čitelné oblasti,
nikoli nákladná 3D simulace. Na mobilu stejný svět jako dostupný seznam oblastí;
žádná informace či akce pouze přes hover, barvu nebo drobný objekt na mapě.
Mapa sama nestačí jako výčet odkazů: oblasti mají viditelný stav a rozvoj.

Tábor skládá krátkou službu dne, mapu oblastí, stávající tři osobní výpravy
a společnou práci. Dlouhé tabulky a účetní vysvětlení jsou až v detailu.
Na hlavní obrazovce jen několik důležitých údajů, ne každá metrika z adminu.
Následující tabulka je katalog cílových možností, nikoli závazný rozsah první 4A.

| Oblast světa | Užitečný read-only stav | Kde se skutečně pracuje |
| --- | --- | --- |
| Recepce a pokoje | Dnešní příjezdy/odjezdy, obsazenost podle kalendáře, nejbližší změna skupiny | Kalendář a detail rezervace, existující správa pokojů |
| Kuchyně a jídelna | Snídaně/obědy/večeře, chybějící menu a podklady, další plánovaná služba | Plán jídel, menu pobytu, nákup pro kuchyň |
| Bar a sklep | Evidované zásoby a upozornění, otevřené účty, oddělené inkaso | Barový sklad, účty, platby, statistika |
| Pokladnice a kancelář | Kronika, známé vyúčtování/úhrady, lokálně dostupná ekonomická upozornění | Fakturace, bankovní přehledy, přijaté doklady, ekonomika |
| Dílna a zázemí | Vlastní projekty, údržba, připravené a právě realizované investice | Adventure plán; odkazy na dostupnou evidenci a doklady |

První kandidáti z `Dashboard.overview(today)`: příjezdy, odjezdy, kalendářová
obsazenost, dnešní porce, chybějící údaje a problémy jídelníčků. Zachovat jejich
význam a explicitně předat pražský den. Aktuální helper má výchozí UTC datum;
nezakládat odlišné počty ručním součtem jiných tabulek. Další příjezd nemá
znamenat prokázanou fyzickou přítomnost a připravený jídelníček není uvařené jídlo.
Úklid či technická připravenost jsou ruční evidence práce, ne odvození z rezervace.

Detail oblasti nabídne stav, související questy/projekty a konkrétní odkaz
„Otevřít plán jídel“, „Doplnit sklad“ apod. Odkaz otevře původní stránku,
nikoli kopii formuláře v Adventure. Žádné iframe ani simulovaný klik do adminu.
Zůstane přímá cesta do celé aplikace; herní mapa nemusí najednou pokrýt každou
administrativní agendu. Návrat přes navigaci/prohlížeč zachová herní práci
a profil. Kvůli této etapě nepřidávat tlačítka do sdílených provozních layoutů.

### 12.4 Pozornost a návaznost na questy

Návrh „Služba dne“ shrne pár konkrétních problémů, ne abstraktní skóre zdraví
chaty. Každý podnět má důvod, zdroj, datum a přechod na řešení. Neúplný nebo
starý zdroj je zvláštní stav, ne zelená „vše připraveno“. Není-li stav měřený,
např. čistota pokojů či technický stav kotle, hra ho nesmí sama tvrdit.

Z podnětu lze výslovně připravit quest s odkazem na oblast/podklad. Nic se
nezakládá za každý render ani automaticky pro každou nezaplacenou fakturu.
Opakovaný klik nesmí duplikovat stejnou otevřenou práci; klíč podnětu zahrnuje
typ, referenci a příslušný termín/výskyt. Zmizelý podnět sám nesplní quest,
nepřidá XP a nesmaže historii. Zdrojový stav a self-report splnění jsou dvě věci.
Lze pouze ukázat, že podklad se od zadání změnil; quest potvrdí člověk.

### 12.5 Investice jako dlouhodobé projekty

Doporučení: investiční projekt je plánované zlepšení, ne jeden obří quest
bez konce a ne nový účetní modul. Lze mít více návrhů projektů, ale do tří
osobních slotů vstupují jen skutečně rozpracované úkoly, ne celý projekt.

Základ projektu: název a problém/přínos, oblast chaty, odpovědný hrdina,
volitelný plánovaný termín a orientační rozpočet s měnou a základem ceny
(např. CZK včetně DPH). Rozpočet není povinný pro rychlý nápad. Projekt může
přesáhnout sezónu; nová sezóna ho nekopíruje a nevynuluje hotové kroky.

Navržené stavy: nápad → připraveno ke schválení → schváleno → realizace →
převzato do provozu; samostatně pozastaveno/zrušeno. Schválení je vědomé
rozhodnutí o herním plánu, ne objednávka, rezervace peněz či podpis dodavateli.
Bez schválené investice dál fungují běžné provozní questy i původní aplikace.

Etapy používají existující questy a jejich atribuci/XP. První verzi stačí
seznam kroků s jasnými výstupy; obecný graf závislostí a jeho editor až při
skutečné potřebě. Nezakládat samostatnou kopii úkolovníku pro investice.
Ukazovat „3 z 5 etap“, ne tvrdit „stavba je ze 60 % hotová“ podle počtu checkboxů.

Příklad **Modernizace koupelny**:

1. Zjistit závadu a určit požadovaný výsledek.
2. Získat nabídky a schválit rozsah i plánovaný rozpočet.
3. Domluvit termín mimo hosty; případné změny rezervací udělat v kalendáři.
4. Nákup/objednávku vyřídit mimo Adventure; dostupnou evidenci a přijaté
   doklady zpracovat stávajícími funkcemi aplikace.
5. Realizovat práci a výslovně převzít funkční výsledek.

Dokončené questy samy projekt neuvedou do provozu. Poslední převzetí potvrdí
hrdina, uchová se datum, skuteční přispěvatelé a volitelné reference/popis
výsledku. Faktura nedokazuje montáž, zaplacení ani bezpečnostní revizi. Jde
stále o přiznanou self-report evidenci; příloha není automatické ověření.

Návrh odměn: XP jen za skutečné jednotlivé questy podle dnešních pravidel.
Převzetí projektu přidá trvalý milník/vizuální změnu chaty, ne druhé XP za
tutéž práci. Investice nedává více XP jen kvůli vyšší ceně. Změna tohoto
návrhu odměňování vyžaduje rozhodnutí před implementací a ochranu proti opakování.
Zrušení, přejmenování či znovuotevření nesmí vyrábět další odměny; opravy
zachovají původní záznam a dohledatelnou následnou událost.

### 12.6 Rozpočty a doklady bez druhého účetnictví

Oddělit **plánovaný odhad**, **rozsah skutečně doložených nákladů**, **úhrady**
a **herní dokončení**. Přijatá faktura je evidence dokladu, ne důkaz zaplacení.
První projektová verze může mít pouze plán a odkazy na existující podklady,
bez automatického součtu „skutečně utraceno“. Chybějící doklady nejsou nula.

Pokud se později budou náklady sčítat, nejprve vyřešit explicitní přiřazení
částky/řádku k projektu, rozdělení jednoho dokladu mezi projekty, měnu, DPH,
dobropisy a dvojí započtení kopií dokladu z různých zdrojů. Samotná vazba
na celou fakturu není alokace. Účetní opravy a platby se dál pořizují původním
workflow; Adventure je jen promítne podle zdroje a jeho úplnosti.
Smazaný nebo nedostupný provozní podklad se označí jako nedostupný; nesmí
kaskádově odstranit projekt, převzetí ani jeho historii.

Ekonomický přehled je za firmu, ne nutně jen chatu. Účetní zisk, stav 211/221,
inkaso sezóny a skladové ocenění nejsou „volné peníze na investice“.
Volitelný ručně schválený investiční limit je plán, ne bankovní zůstatek.
Hra při schválení nebo dokončení projektu nic finančně neodečítá.

U baru zachovat nynější **Inkaso baru bez servisu** podle `payment_date`.
Statistika prodeje počítá účty podle `inserted_at`, podle stavových/servisních
filtrů; produktový detail sčítá položky. Datum založení účtu není datum každé
konzumace. Nový pohled na prodej/spotřebu může být samostatný, až bude schválená
definice období, slev, spropitného a přesahujících účtů. Tato revize nepřejmenovává
inkaso na útratu, nesjednocuje výpočty a nepřepisuje staré snapshoty.

### 12.7 Viditelný rozvoj a další vlastní nápady

- **Kniha stavebních plánů:** vlastní nápady i nepovinné vzory (koupelna,
  úspornější osvětlení, zázemí baru, vybavení kuchyně, sušárna). Vzor připraví
  návrh projektu, nic neobjedná. Stejnou roli má i neinvestiční zlepšení procesu.
- **Rostoucí chata:** návrh je vidět jako plán, realizace jako rozestavěná část,
  převzaté zlepšení jako nový prvek scény a zápis do kroniky. Nepřekreslovat
  existující skutečnou chatu jako prázdný pozemek ani uživatele nutit znovu
  „postavit“ dnešní vybavení. Výchozí stav se zavede bez zpětných XP.
- **Více směrů rozvoje:** pohodlí hostů, snazší obsluha, technické zázemí,
  bezpečnost a úspory. Jsou to tematické větve skutečných projektů, ne smyšlená
  procenta komfortu či bezpečnosti. „Nevíme“ a „nebylo kontrolováno“ mají vlastní stav.
- **Stavební okno mezi pobyty:** read-only zobrazení možného termínu podle
  kalendáře jako pomůcka pro plánování, ne rezervace termínu či závazek řemeslníka.
  Nepřítomnost rezervací není automaticky bezpečné potvrzení dostupnosti.
- **Předsezónní výprava:** dobrovolně vybraný seznam skutečné přípravy chaty,
  propojený s existujícími questy. Žádné druhé odměny za stejné kroky ani
  automatické kopie při každém otevření sezóny.
- **Péče o dokončené zlepšení:** po převzetí nabídnout člověku založení/aktivaci
  údržbové šablony. Bez souhlasu nevytvářet novou periodickou práci ani falešný
  technický servisní interval. Využít dnešní pravidlo jednoho otevřeného výskytu.
- **Před a po:** projekt uchová záměr a výsledek; fotografie lze řešit později.
  Očekávaná úspora je hypotéza, ne realizovaný zisk. Pokud jsou později dostupné
  srovnatelné podklady, lze přínos vyhodnotit, nikoli mu připsat každou změnu tržeb.

Případné herní odemknutí nabídne další doporučené plány či vzhled, nikdy
nepovolí provozní funkci, kterou už dnes aplikace umí. Převzetí nového pokoje
nezmění `Bookings.cottage_capacity/0`, pokoje, ceník ani kapacitu staré sezóny.
Herní vývoj přesahuje sezóny, sezónní historie zůstává verzovaná a neměnná.

### 12.8 Zdrojové hranice, výkon a bezpečnost

Ověřeno čtením kódu, bez nových dotazů na provozní data:

- Přehled používá `Dashboard.overview/1` / `timeline/2`, místní výpočty porcí
  a menu. Zdroj umí více oblastí najednou; nepouštět celý přehled pro každý
  objekt mapy. Kalendářová kapacita a realizace sezóny nejsou stejná metrika.
- Kuchyň má menu, nákupní výpočet, ruční mrazák a uložené nákladové reporty.
  Mrazák se sám neodečítá a kalkulované náklady nejsou veškeré skutečné náklady.
- Sklady mají zdroj evidovaných množství/limitů, ale části
  `Inventory.list_bar_stock_products/0` a `get_stock_overview/0` dělají dotazy
  po produktu. To je konkrétní N+1 riziko, ne vhodný přímý loader mapy.
- Přijaté doklady nejsou hotový registr investic; v ověřených agendách nebyl
  nalezen samostatný projektový/majetkový modul. Projektový stav patří do Adventure.
- Ekonomiku číst jen z lokálních uložených dat, respektovat vypnutý modul,
  datum zdroje a neúplnost. Žádný import ABRY, extrakce dokladů, vytvoření účtu
  přes `get_or_create_*`, zajišťování kalkulace či jiný write helper při renderu.

Pro 4A navrhnout jeden sdílený přehled za omezené datumové okno a dávkové
čtení po zdrojích, detaily až pro vybranou oblast. Stejnou agregaci sdílet
mezi mapou, hlášením dne a detailem. Žádné dotazy po pokoji, produktu,
projektu či jednotlivém dni. Před integrací nových zdrojů, včetně opětovného
použití existujících API, předložit konkrétní query rozpočet a schválit
efektivní dávkové řešení podle AGENTS.md. Přímé volání známých N+1 loaderů
není schválenou alternativou. Dřívější souhlas
pro pobyty a finanční 3B nepokrývá libovolné nové skladové či provozní čtení.
N+1 v původním modulu neopravovat změnou mimo Adventure v rámci tohoto zadání.

Dnešní provoz je čerstvý read-only přehled s datem načtení, sezónní kronika
zůstává explicitně přepočítávaným historickým snapshotem. Nepřepočítávat
celou sezónu na každém renderu mapy. Interval a rozsah případné provozní obnovy
navrhnout podle query rozpočtu; navrácení z původní stránky umožní ruční obnovu.
Starší údaj nesmí vypadat jako právě ověřený stav. Žádné hostovské osobní údaje
ani kopie dokladů v herních snapshotech, jen nutné agregace a stabilní reference.

Projekty, etapy, vazby na questy a vizuální události jsou vlastní Adventure data.
Použít stávající ochranu admin PINem a self-report profil, audit, transakce,
unikátní klíče a soft-delete; zachovat UUID, historické questy a XP ledger.
Projekt přispěvatele nepředstírá jako ověřené osobní přihlášení. Vypnutý Adventure
modul nesmí spouštět nové provozní dotazy ani herní joby. Nové rutinní importy,
cron rozesílky a změny globálního layoutu nejsou součástí tohoto návrhu.

### 12.9 Doporučené dodávky a akceptace

**4A – živý tábor, první kandidát pro další implementaci:** jedna společná
scéna oblastí, denní provoz z Přehledu, několik položek pozornosti, detail
oblasti a odkazy na původní formuláře. Zachovat tři osobní sloty, společnou
práci, kroniku a zapamatovaného hrdinu. Bez nového investičního účetnictví,
automatického generování questů z výstrah a bez změny významu barových částek.
Nejmenší doporučený rozsah čerstvých dat: Recepce a Kuchyně ze společného
provozního zdroje; Bar/Pokladnice dál z dosavadní kroniky a odkazů, Dílna zatím
bez předstírání existujícího projektového modulu. Nové skladové a ekonomické
agregace i připravení questu z podnětu lze dodat zvlášť po ověření tohoto základu.

**4B – investiční projekty:** vlastní plán a etapy propojené s questy,
volitelný odhad a reference na podklady, přehled postupu a výslovné převzetí.
Následně schválený rozsah je obecný základ bez předem založené konkrétní investice
(oddíl 14), nikoli přestavba celé aplikace na projektový systém.
Pokročilé závislosti, alokace dokladů a součet skutečných nákladů nejsou podmínkou.

**4C – rozvoj světa:** viditelné změny z dokončených projektů, kronika chaty,
tematické větve plánů a případně údržbové šablony po výslovném schválení.
Vzhled a odměny řešit tak, aby se skutečná práce nezapočetla dvakrát.
Porovnávání sezón z původní 3C lze dál dodat samostatně, neplést oba názvy etap.

Akceptace pro nové dodávky:

- Vybrané denní počty odpovídají zdroji ze současného Přehledu pro shodný
  pražský den, stav a interval. Neúplné porce ani staré údaje nejsou tiché nuly.
- Z oblasti mapy je vidět skutečný stav a cesta k řešení, nikoli jen dekorace.
  Stejné informace jsou dostupné klávesnicí a na mobilu bez hoveru.
- Změna menu/skladu/rezervace/platby proběhne pouze v původním workflow;
  živé provozní údaje se promítnou obnovou přehledu bez nového provozního zápisu.
  Finanční metriky kroniky se změní až výslovným přepočtem; u uzavřené sezóny
  vznikne nová verze s důvodem. Návrat ze stránky plateb sám kroniku nepřepočte.
- Opakované připravení questu z téhož podnětu neduplikuje otevřenou práci.
  Vyřešený podklad sám neudělí XP. Převzetí projektu odliší kroky od výsledku.
- Jeden projekt může přejít přes sezónu a více hrdinů bez kopie historie,
  podruhé přidělených XP či násobení milníků po opakovaném kliknutí.
- Doklad bez úhrady zůstane dokladem, ne zaplacenou investicí. Bez alokace
  nevznikne domnělý součet nákladů ani dostupná investiční hotovost.
- Zlepšení mění pouze Adventure svět; počet lůžek, účetní čísla, sklad a staré
  snapshoty zůstanou stejné. Ruční tvrzení a zdrojově doložený fakt jsou odlišené.
- Query test porovná málo i mnoho oblastí/projektů/produktů: žádné N+1.
  Ověřit pouze Adventure doménové zápisy, žádné HTTP/hooky a blokaci modulem.
- Ověřit původní role Tábora/Questů, admin PIN, obnovu profilu, 390/320 px
  a přístupnost. Testy a CI podle AGENTS.md; plán sám nové testy nenahrazuje.

## 13. Dodaná etapa 4A a předání (12. 11. 2026)

Uživatel výslovně schválil 2D mapu se živým provozem a jediný sdílený read-only
`Dashboard.overview(today Prague)` s rozpočtem nejvýše 15 SELECTů na připojení
Tábora a ruční obnovu. Zdrojový audit: timeline 4, kuchyň 8, obsazenost 1,
porce 2, konstantní kapacita 0; žádné N+1, polling ani zdrojové dotazy z renderu,
výběru oblasti či běžných UI událostí. Schválení zahrnuje opětovné použití
tohoto omezeného dávkového zdroje, nikoli nové skladové/ekonomické adaptéry.

Implementováno ve větvi `feat/adventure-live-camp`, bez commitu/pushe:

- Šest oblastí ve 2D scéně, na mobilu stejná tlačítka jako seznam, ovládání
  klávesnicí a detail oblasti se skutečnými provozními odkazy.
- Recepce/Pokoje: příjezdy/odjezdy skupin a kalendářová obsazenost. Kuchyně:
  známé porce a neúplnost; stručná služba dne s datovanými podněty menu/podkladů.
- Jedna projekce pouze v socketu bez hostovských osobních údajů; načítání,
  chyba, stáří a ruční obnova. Pražský den bez SQL podle současných EU pravidel
  DST; čas načtení UTC. Zdroje mají konzistenci jednotlivých SELECTů, nikoli
  společný transakční snapshot. Podrobné limity jsou v `ADVENTURE.md`.
- Bar/Pokladnice pouze odkazy a stávající sezónní kronika, výslovně ne živé
  finance; provozní obnova kroniku nepřepočítává. Dílna bez projektového systému.
- Zachované tři osobní sloty, společná práce, kronika, preference hrdiny,
  admin PIN a flag. Žádné automatické questy, XP za prohlížení ani provozní zápisy.

Přidány regresní scénáře datové sémantiky, malého/velkého query rozpočtu,
obnovy a její absence při UI akcích, navigace, flagu a stavů. Existující
regrese PINu a profilu zůstávají. **Lokální testy nebyly spuštěny**, CI ověří
uživatel. Prošly formatter změněných Elixir souborů, kompilace s warnings-as-errors
a build assetů. Použit Elixir 1.20.5 / Erlang 29.1.2 (ERTS 17.1.1), odlišný od pinů
1.20.4-otp-29 / 29.1; formatter není potvrzený na připnutém toolchainu.
Browserové ověření 390/320 px, klávesnice a asistivních technologií zbývá.
Žádné migrace ani konfigurace; cizí `rel/env.sh.eex` a `generated_images/`
zůstávají nedotčené. Úplný seznam změn a validační limity předává finální výsledek.

### Historický předávací checklist před schválením 4A

Přečíst tento plán (hlavně oddíl 12), `docs/features/ADVENTURE.md` a aktuální
`AGENTS.md`. Ověřit čerstvý main; 3A/3B a preference hrdiny jsou již implementované,
nezačínat je znovu. Staré formulace „rekonstrukce později“ nezaměňovat za zákaz
projektů podle nového směru. Následující otázky jsou historické; schválená 4A
je vymezená výše, otázky k projektům vyžadují nové rozhodnutí.

Před implementací krátce potvrdit:

1. Hlavní plocha: mapa/ilustrace s viditelným rozvojem, nebo přechodně oblastní karty?
2. První rozsah: které konkrétní informace Přehledu mají přednost v 4A?
3. Investice: projekt s etapami podle návrhu, nebo zatím označený investiční quest;
   který první skutečný projekt a jaká kritéria převzetí?
4. Odměny a peníze: souhlas s XP jen za kroky, vizuálním milníkem bez dalších XP
   a rozpočtem pouze jako plánem; bez automatického účtování či bonusů příjmů?
5. Technický rozsah: konkrétní dávkové zdroje/query rozpočet a souhlas s novým
   čtením. Pouze Adventure změny; provozní moduly, globální CSS/layouty a router
   zůstávají ke čtení, nutnou výjimku nejprve předložit, ne tiše provést.

Příští vývoj má začít malou samostatnou dodávkou podle odsouhlaseného rozsahu,
ne současně mapou, kompletním projekťákem, novým přihlášením a účetnictvím.
Neprovozovat klasické zápisy prostřednictvím herních akcí a nezaměňovat
inkaso baru za statistiku prodeje. Stav cizích rozpracovaných souborů ověřit
a zachovat; `rel/env.sh.eex` a `generated_images/` nejsou součástí této revize.

## 14. Schválený obecný základ 4B (12. 11. 2026)

Uživatel nyní výslovně schválil vlastní Adventure projekty s etapami navázanými
na existující questy, volitelným rozpočtem pouze pro plánování a výslovným
lidským převzetím. Žádná konkrétní investice se neseeduje. XP zůstávají pouze
za existující questy; převzetí nedává další XP a nikdy neproběhne automaticky.
Projekty jsou nezávislé na sezónách a uchovávají audit a historii. Bez účetnictví,
součtu skutečných nákladů, nových provozních zdrojů nebo smyšlených příjmových bonusů.

Samostatně schváleno konkrétní N+1 řešení: seznam projektů nejvýše 2 SELECTy
(100 projektů a všechny etapy joinem na questy), vybraný audit +1 (50 událostí),
výslovné hledání questu 1 (30 výsledků), převzetí nejvýše 4 SELECTy (aktér,
zamčený projekt, etapy/questy dávkou, přispěvatelé dávkou). Render a přepnutí
oblasti 0 dotazů, obnova po mutaci stejným loaderem. Žádný polling ani nový
provozní zdroj. Tím je splněna samostatná schvalovací brána z AGENTS.md;
nepokrývá jiné budoucí zdroje nebo N+1 loadery.

Implementováno ve větvi `feat/adventure-projects` z aktuálního main `fc0842a`:
vlastní schémata a context, migrace tří Adventure tabulek, kniha projektů na
existující questové trase a odkaz z Dílny. Změny a převzetí používají transakce,
zámky a neměnný číslovaný audit. Úpravy plánu a etap jsou před schválením;
po něm lze realizovat, pozastavit, zrušit nebo výslovně převzít. Archiv zachová
historii a XP. Podrobnosti a ruční checklist jsou v `docs/features/ADVENTURE.md`.

Přidány kontextové/LiveView regrese, ponechané pro CI ověřované uživatelem.
Lokální testy ani precommit se nespouštějí. Nezměněny instrukce, sdílený router,
layouty, provozní moduly a zdroje. Cizí `rel/env.sh.eex` a `generated_images/`
zůstávají nedotčené. Vizuální rozvoj 4C, účetnictví a pokročilé závislosti nejsou
součástí této dodávky. Změny zůstávají bez commitu, pushe a PR dle aktuálního zadání.

Ověření: prošel formatter změněných souborů, celoprojektové
`MIX_ENV=test mix format --check-formatted`, kompilace s `--warnings-as-errors`,
`MIX_ENV=test mix assets.build` a `git diff --check`. Lokální Elixir je 1.20.5
/ OTP 29 (ERTS 17.1.1), zatímco piny jsou 1.20.4-otp-29 / Erlang 29.1;
shoda formatteru s připnutým CI není zaručena. Migrace nebyla lokálně aplikována,
ExUnit ani precommit se nespouštěly a browserové ověření desktopu, 390/320 px
a klávesnice zůstává v ručním checklistu.

## 15. Schválená omezená 4C a kompaktní opakování (12. 11. 2026)

Uživatel výslovně schválil obecné vizuální milníky šesti oblastí a trvalou
Kroniku chaty z lidsky převzatých projektů, včetně dřívějších a archivovaných.
Archivace nesmí odstranit milník. Výsledky se zobrazují napříč sezónami,
odděleně od finanční kroniky. Bez dalších XP, bonusů, automatické údržby,
stromu rozvoje nebo individuálních ilustrací.

Samostatně schválena kompaktní správa opakování: výchozí aktivní/pozastavené,
archiv jen výslovným odkazem, krátká tlačítka s ikonou místo stavových selectů,
sbalené podrobnosti a viditelná neznámá podmínka. Pozastavení/archivace vyžadují
dvě explicitní volby ponechat nebo zrušit/archivovat otevřenou práci plus Zpět.
Žádná předvybraná volba; nevratná archivace a serverové validace se nemění.

Schválení N+1: rozvoj nejvýše 2 Adventure SELECTy (úplný agregát všech oblastí
a 100 projektů s převzetím), starší kronika pouze explicitně po 20 výsledcích
s jedním lookahead řádkem, 1 SELECT na stránku. Opakování nejvýše 2 SELECTy
(30 šablon + lookahead, otevřené výskyty dávkou), historie +1 pouze explicitně.
Render, přepnutí oblasti a rozbalení podrobností 0 dotazů; žádný polling nebo
nový provozní zdroj. Provozní rozpočet 15 SELECTů zůstává zachován.

Implementováno na existující `feat/adventure-projects`, navazuje na již
commitnutou a pushnutou 4B `c4b4abf`; čerstvě ověřený main je `fc0842a`.
Nové změny zůstávají bez commitu/pushe dle zadání. Používají stávající přijetí
projektu bez migrace; přímé odkazy otevírají i starší archivovaný detail.
Rozsah pouze Adventure context/web/CSS/testy/dokumentace. Instrukce, sdílené
moduly, router a konfigurace se nemění. Cizí `rel/env.sh.eex` a neversionovaný
`generated_images/` zůstávají nedotčené.

Přidány regrese pro archivované a starší milníky, stránkování, dávkové stropy,
explicitní volby otevřené práce, neznámý stav, přímý detail a lazy historii.
Lokální testy ani precommit se nespouštějí, CI ověří uživatel. Ručně zbývá
ověřit desktop/390/320 px, klávesnici, otevření starších výsledků, zachování
milníku po archivaci a obě volby potvrzení opakované šablony.

Ověření 4C: prošel formatter změněných souborů, celoprojektové
`MIX_ENV=test mix format --check-formatted`, `MIX_ENV=test mix compile --warnings-as-errors`,
`MIX_ENV=test mix assets.build` a `git diff --check`. Instalovaný Elixir je
1.20.5 / OTP 29 (ERTS 17.1.1), piny jsou 1.20.4-otp-29 / Erlang 29.1;
shoda formatteru s připnutým CI tedy není potvrzená. ExUnit ani browserové
ověření nebylo spuštěno; query rozpočty mají přidané regrese pro CI.

## 16. Schválené zjednodušení projektů (12. 11. 2026)

Uživatel výslovně schválil běžný postup **Návrh → Realizace → Převzato**:
jedno tlačítko **Schválit a zahájit**, potom uzamčený plán i kroky; pozastavený
projekt se vrací přímo do realizace. Starší stavy `ready` a `approved` i audit
zůstávají, bez přepisu dat. Převzetí je nadále výslovné lidské potvrzení s výběrem
přispěvatelů, bez dalších XP a bez automatického dokončení projektu.

Schválený **Nový krok** vyžaduje pouze název. V jedné transakci přes existující
`Tasks` vytvoří skutečný čekající quest a připojí etapu; ne druhý úkolový model,
automatické zahájení nebo další odměnu. Očekávaný výstup přebírá název questu,
lze jej upřesnit. Alternativa vyhledá a připojí existující quest. Další nastavení
používají dosavadní validace a odměny; žádné nové provozní zdroje.

Implementace na stávající `feat/adventure-projects` zachovává rozpracovanou 4C
a kompaktní opakování. Projektové karty mají zřetelný stav, oblast a postup;
detail odděluje plán, kroky, další akci, převzetí a sbalený audit. Založení má
název a oblast, ostatní pole jsou nepovinná za rozbalením. Editory se otevírají
na vyžádání a po úspěchu zavírají. Formulář převzetí se ukáže až po dokončení
všech kroků a kliknutí na převzetí. Prázdná metadata se nevypisují, pravidla jsou
v nápovědě. Vlastní izolované CSS zachovává papír/les/zlato, ovládání má dotykové
rozměry, formuláře a karty se skládají i pro 390/320 px.

Data zůstávají nepovinná, bez změny schématu. Zobrazení **12. 11. 2026** sdílí
projekt i převzaté výsledky mapy a Kroniky chaty; přesné časy jsou pouze v
rozbaleném auditu s výslovným UTC. Formátování je čistě v paměti, datumový input
zůstává nativní a lokalizovaný prohlížečem.

Schválené čtecí rozpočty se nemění: projekty 2 + vybraný audit 1, hledání questu
1, převzetí 4, svět 2, šablony 2. Žádné čtení po položce. Inline mutace skládá
existující omezené rutiny (7 SELECTů, nejvýše 8 se zadaným osobním přiřazením),
počet nezávisí na počtu kroků. Otevření/zavření editorů 0 SELECTů. Chyba vrátí
quest, vazbu i audit atomicky. Regrese pokrývají tyto hranice, zamčení,
historické stavy, česká data, nulové XP při založení a starý archivovaný deep link.

Bez nové migrace, konfigurace, commitu nebo pushe. `rel/env.sh.eex`,
`generated_images/`, instrukce a sdílené moduly nebyly upravovány.
Lokální ExUnit ani precommit se nespouštějí, CI ověří uživatel. Ruční browserové
ověření desktopu/390/320 px a klávesnice zůstává k provedení. Lokální toolchain
je Elixir 1.20.5 / OTP 29 (ERTS 17.1.1), nikoli piny 1.20.4-otp-29 / Erlang 29.1;
shoda formatteru s CI proto není potvrzená.

Ověření této úpravy: prošel formatter změněných Elixir/HEEx souborů,
celoprojektové `MIX_ENV=test mix format --check-formatted`,
`MIX_ENV=test mix compile --warnings-as-errors`, `MIX_ENV=test mix assets.build`
a `git diff --check`. Query limity a rollback mají doplněné testy pro CI,
nikoli lokálně změřené výsledky běhu testů.

## 17. Další etapy: Služba dne a živý Bar (12. 11. 2026)

Tato revize rozepisuje další práci, nikoli další implementaci. Uživatel potvrdil
produktová pravidla Služby dne níže a po jejím propojení upřednostnil živý Bar
před přípravou příjezdů a údržbou. Souhlas se zápisem plánu není souhlasem
s implementací, novými zdroji ani novým SQL rozpočtem. Etapy 3A až omezená 4C
se neopakují; stav implementace a ověření zachovávají oddíly 13–16.

### 17.1 Pořadí a hranice dodávek

| Etapa | Výsledek | Stav |
| --- | --- | --- |
| 5A – Podnět na quest | Ze současné Služby dne ručně připravit a potvrdit skutečný quest bez duplicit | Produktová pravidla potvrzena, implementace čeká |
| 5B – Návazná práce | U podnětu rozlišit otevřenou práci a změnu či neověřitelnost zdroje | Navazující rozsah k potvrzení před implementací |
| 5C – Živý Bar | Užitečný read-only stav baru a cesta do původních funkcí | Další priorita po Službě dne; konkrétní zdroje a rozsah neschválené |
| Později – Příprava a péče | Dobrovolná příprava příjezdu a nabídka údržby převzatého zlepšení | Zásobník, ne součást 5A–5C |
| Samostatně – Analytika 3C | Porovnání sezón, poměry a produktové přehledy | Zásobník, nezaměňovat s rozvojem světa 4C |

Nejprve dokončit ověření existující dodávky: uživatel ověří CI, ručně projít
desktop/390/320 px a klávesnici, projekty a jejich převzetí, archivaci bez ztráty
milníku i obě volby pozastavení opakovaných šablon. Zbývá ověření projektové
migrace a přesně připnutého toolchainu. Tento plán netvrdí, že tyto kontroly
již proběhly, ani nepovoluje lokální testy.

### 17.2 5A: z konkrétního podnětu skutečné zadání

**Cíl:** dokončit každodenní smyčku „vidím problém → připravím quest → člověk
udělá práci → člověk potvrdí splnění“. Nezavádět další dashboard ani samostatný
úkolovník Služby dne. Použít existující questy, atribuci, osobní sloty a XP.

Potvrzený první rozsah tvoří pouze existující podněty společné projekce
`Operation`: neúplné/chybějící podklady stravování a problémy jídelníčku.
Přesné typy před implementací ověřit proti `Dashboard.overview/1`; nevymýšlet
nový zdroj nebo vlastní odlišnou definici problému. Příjezdy a odjezdy zůstávají
informací, nikoli důkazem potřeby úklidu či technické nepřipravenosti.

Navržená kompaktní položka služby:

- Stručný důvod a oblast; datum příjezdu pouze jako označený kontext v českém
  formátu. Není to datum zjištění problému ani automatický termín práce.
- **Otevřít podklad** vede do stávajícího pobytu či menu; žádná kopie provozního
  formuláře v Adventure.
- **Připravit quest** otevře krátký předvyplněný návrh, nic ještě nezapisuje.
- Pokud existuje otevřená práce, místo zakládání nabídnout **Otevřít quest**
  s českým stavem. Samotné prohlížení či kliknutí na podklad nic nesplní.

Potvrzený návrh questu:

- Předvyplněný upravitelný název, oblast a stabilní odkaz na podklad.
- Přiřazení a velikost jsou volitelné; další nastavení schovat do podrobností.
  Použít stávající výchozí pravidla `Tasks`, nikoli odměnu podle závažnosti
  systémové výstrahy. Před potvrzením je zřejmé, jaký quest a odměna vzniknou.
- Výchozí stav **Čeká**, bez povinného termínu. Vytvoření nic automaticky
  nerozpracuje ani nezabere osobní slot. Přijetí a splnění probíhá v táboře.
- Zpět/zavření návrhu nemění data. Po úspěchu stručné potvrzení a odkaz na quest,
  ne další povinný průvodce nebo automatický přesun do provozu.

### 17.3 Identita podnětu, souběhy a historie

Uživatel potvrdil **nejvýše jeden otevřený quest pro stejný pobyt a typ problému**.
Identita zahrnuje zdrojový namespace, stabilní ID pobytu a stabilní typ podnětu.
Nezahrnuje text důvodu, pořadí položky, aktuální profil, sezónu ani datum příjezdu.
Posun pobytu nebo změna formulace proto nevytvoří druhé otevřené zadání.

Technický návrh musí před implementací vyřešit:

- Vazbu podnětu na skutečný quest pouze ve vlastních Adventure datech, se
  zdrojovou referencí, verzí definice a minimálním dobovým kontextem. Žádné
  kopie booking/guest struktur, jména hostů, kontakty či obsah dokladů.
- Databázovou ochranu jednoho otevřeného zadání a atomické založení questu,
  vazby i auditu. Dvojklik, retry a dva hrdinové současně vrátí tutéž otevřenou
  práci, nevytvoří druhý quest ani XP. Pouhá kontrola seznamu v socketu nestačí.
- Souhru vazby s dokončením a archivací přes stávající `Tasks`, aby otevřenost
  nezůstávala zastaralá. Konkrétní model, constraint a pořadí zámků navrhnout
  po kontrole aktuálních schémat; tento plán nepředepisuje neověřenou migraci.
- Uchování historického zadání po změně nebo zániku podkladu. Žádná kaskáda
  z provozního smazání nesmí zničit quest, důkaz, vazbu nebo XP.

Zmizelý podnět **sám nesplní ani nezruší quest**. Dokončení potvrzuje člověk
podle běžných pravidel, ne přepočet zdroje. Hotový quest zároveň není důkazem,
že je současný provozní podklad v pořádku.

Po dokončení nebo zrušení se nový quest nikdy nevytvoří obnovou. Pokud problém
přetrvává nebo se vrátí, lze vědomě zvolit **Připravit další řešení**, nejprve
uvidět předchozí práci a potvrdit nové zadání. Původní historie a odměna zůstávají,
nejde o automatické znovuotevření ani opětovné odměnění téhož questu. Při souběhu
tohoto nového pokusu opět platí nejvýše jedna otevřená práce.

### 17.4 5B: návazná práce a pravdivý stav zdroje

V první 5A musí být vidět již existující otevřený quest, aby se nezakládaly
duplicity. Samostatná 5B rozvine orientaci v návazné práci, nikoli další seznam
pro plnění nebo nový stavový automat questů.

Navržené oddělené informace:

- **Práce:** čeká / rozpracováno / dokončeno / zrušeno podle Adventure.
- **Podklad:** podnět potvrzený posledním načtením / podklad se změnil /
  nelze ověřit nebo je zastaralý. Vždy respektovat čas a rozsah poslední obnovy.
- Chybějící položka v omezeném výhledu není důkaz vyřešení. Pobyt mohl změnit
  termín, vypadnout z okna, být smazán nebo zdroj selhal. Nápis „podnět již není
  v aktuálním přehledu“ není potvrzení „vyřešeno“.
- Seznam nejvýše čtyř viditelných podnětů není úplný zdroj pro porovnání.
  Pro vztahy použít celou dostupnou projekci v jejím doloženém rozsahu; pokud
  nestačí pro ověření absence, výsledek přiznat jako neověřitelný.

Navrhnout krátký přístup k otevřené práci i poté, co podnět zmizí z hlavní čtveřice,
bez zaplnění Tábora historií. Počet položek, stránkování a umístění tohoto
souhrnu odsouhlasit před implementací 5B. Přijetí/splnění nadále patří do tábora,
úpravy do knihy questů. Zdrojový stav a lidská práce se neslévají do jedné fajfky.

### 17.5 Výkon, obnova a oprávnění Služby dne

Nové N+1 riziko je čtení vazby/questu nebo pobytu pro každý podnět. Doporučený
směr je **jedno dávkové Adventure čtení pro všechny klíče společné projekce**,
případně samostatný omezený loader návazné práce; žádné dotazy po kartách,
pobytech či jednotlivých dnech. Jde o návrh, nikoli schválený query rozpočet.

Před kódováním předložit konkrétní počet SELECTů pro načtení, ruční obnovu,
otevření návrhu, potvrzení a historii, včetně validačních čtení a souběhů.
Nové provozní čtení není součástí schváleného rozsahu 5A. Dosavadní společné
`Dashboard.overview(today Prague)` má stále nejvýše 15 provozních SELECTů;
nevolat jej z každé karty, při otevření návrhu ani pro kontrolu duplicity.

- Render a přepnutí oblasti neprovádí nové zdrojové dotazy; žádný polling.
- **Obnovit provoz** obnovuje provozní projekci a dávkovou informaci o vazbách,
  nikoli finanční kroniku; přesné složení loaderu schválit před implementací.
- Návrh vychází z poslední známé projekce a uvádí její stáří. Starý či chybující
  zdroj nesmí působit jako právě ověřený; quest je stále ručně potvrzená práce.
- Server nevěří libovolnému ID, typu či URL z klienta. Ověřit původ podnětu,
  povolené typy a bezpečně sestavit interní odkaz; změnu mezi návrhem a zápisem
  nepřekrýt tvrzením o čerstvém ověření. Konkrétní validaci navrhnout bez N+1.
- Stávající admin PIN, aktivní self-report profil a feature flag chrání čtení
  i mutace. Vypnutí modulu blokuje nové čtení i zápisy podle dnešních pravidel.
- Pouze vlastní Adventure data. Nutnou výjimku ve sdílených částech nejprve
  předložit; žádné provozní mutace, HTTP, emaily, skladové či účetní vedlejší efekty.

### 17.6 Akceptace 5A a 5B

- Z existujícího podnětu otevřít krátký návrh, zrušit jej bez zápisu, poté založit
  jeden čekající quest bez termínu a bez obsazení osobního slotu.
- Název, přiřazení a velikost odpovídají potvrzenému návrhu; odkaz vede na správný
  podklad. Datum příjezdu je česky a jasně oddělené od volitelného termínu práce.
- Dvojklik, retry, souběžné založení a stejný podnět po změně textu/příjezdu
  zachovají jediný otevřený quest; ověřit i rollback celé mutace.
- Existující quest lze dohledat a přijmout/splnit běžným způsobem. XP získá
  skutečný splnitel nebo chata podle dosavadního typu, právě jednou za quest.
- Změna menu, zmizení podnětu, posun mimo výhled, zrušení pobytu nebo chyba
  načítání quest samy nesplní, nezruší ani neodmění. Neúplnost není úspěch.
- Přetrvávající problém po uzavření nabídne jen explicitní další řešení
  s historií; opakovaná obnova nevytvoří další práci.
- Porovnat malé a velké množství podnětů: konstantní schválený query rozpočet,
  žádné čtení po položce a žádné SQL z renderu nebo změny oblasti.
- Ověřit pouze Adventure doménové zápisy, absenci provozních hooků/HTTP,
  feature flag a PIN; zachovat soukromí projekce a historii starých questů.
- Přidat kontextové a LiveView regrese; běh testů ponechat CI podle AGENTS.md,
  pokud uživatel výslovně neschválí lokální běh. Ručně ověřit desktop/390/320 px,
  fokus návrhu, návrat po zavření a ovládání klávesnicí.

### 17.7 5C: živý Bar jako další priorita

Uživatel upřednostnil Bar po Službě dne. Nejde zatím o schválení konkrétních
metrik ani libovolného skladového čtení. Před implementací ověřit a předložit:

1. První užitečný rozsah: evidované zásoby a existující limity/upozornění;
   otevřené účty případně jako samostatná následující dodávka. Vybrat několik
   konkrétních údajů, ne kopii skladového či prodejního dashboardu.
2. Přesný význam a úplnost množství, jednotek a limitů. Chybějící limit není
   důkaz dostatečné zásoby; stav evidence není fyzická inventura. Nepřidávat
   domnělé nulové zásoby nebo automatické doporučené nákupy.
3. Dávkový read-only adaptér s konkrétním query rozpočtem ke schválení.
   `Inventory.list_bar_stock_products/0` a `get_stock_overview/0` mají známé
   dotazy po produktu; nepoužít je přímo jako loader mapy a neopravovat kvůli
   tomu svévolně provozní modul mimo Adventure.
4. Ruční obnovu, stáří a chybové stavy, soukromí otevřených účtů a dostupné
   odkazy do původního skladu/účtů. Žádné zásahy do veřejného POS nebo sdílených
   layoutů bez samostatně schválené výjimky.

Živé skladové počty nebudou přejmenováním finanční kroniky. **Inkaso baru bez
servisu** zůstává verzovaným sezónním snapshotem podle `payment_date`, nikoli
aktuálním prodejem, hotovostí na investice nebo ziskem. Obnova baru sama
nepřepočítá kroniku. Zobrazení stavu nic neobjedná, neodečte ze skladu,
neuzavře účet, nezaloží platbu ani automaticky nevytvoří quest či XP.

Případné **Připravit quest** ze skladového upozornění využije vzor 5A až po
samostatném určení identity podnětu a opakování. Klíč pobyt + typ z kuchyně
nelze bez rozhodnutí přenést na produkt, sklad nebo inventurní období.

### 17.8 Zásobník po prioritních dodávkách

- **Příprava příjezdu:** člověkem vybrané kroky, ne automatický úklid za každý
  pobyt. Předem určit překryvy skupin, termíny, duplicity a vazbu na dnešní
  opakované šablony, aby stejná práce nevznikala dvakrát.
- **Údržba převzatého zlepšení:** po převzetí pouze nabídnout člověku založení
  nebo připojení šablony. Žádná automatická aktivace ani smyšlený servisní interval.
- **Další rozvoj světa:** nepovinné vzory projektů, konkrétní ilustrace a fotografie
  před/po až podle reálné potřeby. Milník nikdy nezvyšuje účetní či fyzickou kapacitu.
- **Ekonomika a 3C:** další lokální upozornění, srovnatelné sezóny a produktové
  ukazatele samostatně po definici zdrojů a úplnosti. Skutečné náklady, alokace
  dokladů a zisk nejsou součástí Služby dne ani živého Baru.

Před každou dodávkou znovu ověřit aktuální větev, skutečný stav implementace
a čerstvý main; příprava tohoto plánu nepovoluje změnu větve, cherry-pick,
commit nebo push. Rozpracované změny a cizí soubory zachovat. Tento zápis mění
pouze plán, nikoli instrukce, provozní kód, schémata či konfiguraci.

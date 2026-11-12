# Cozy Adventure – ekonomická strategie a RPG pro Cozy Checkout

- Stav: etapy 1 a 2 implementovány v PR #112, čeká na CI a ruční kontrolu
- Vytvořeno: 2026-11-11
- Aktualizováno: 2026-11-12
- Repozitář: `michalhorcic/cozy-checkout`
- Související dokumentace: `AGENTS.md`, `docs/features/ADMINISTRATION.md`, `docs/features/ECONOMICS.md`, `docs/features/CATERING.md`, `docs/features/BILLING.md`, `docs/plans/2026-10-28-ekonomicky-dashboard.md`

> **Další směr revidován 12. 11. 2026:** [Úkolovník a kronika sezóny](2026-11-12-adventure-todos-a-prehled-sezony.md).
> Pro další implementaci nahrazuje původní návrh pevného katalogu a povinných
> rezervačních cílů: spravované osobní/společné todos, opakované šablony a
> sezónní čísla včetně odděleného inkasa a vyúčtování pobytů.
> Jde pouze o plán; níže zůstává audit a historie současné implementace.

## Problém a očekávaný výsledek

Provoz Jindřichova domu má měřitelné krátkodobé, sezónní i dlouhodobé cíle, ale jejich průběžný rozvoj není motivující ani přehledný. Cozy Adventure má přidat volitelnou herní vrstvu nad reálnými provozními daty: společný postup chaty, osobní profily Michala a Lucky, úkoly, achievementy a sezónní kampaně. Nemá vytvářet účetní pravdu ani komplikovat běžný POS.

Úspěch MVP: správce otevře /admin/adventure, zvolí herní profil, vidí společnou sezónu a svůj postup, splní ruční quest, automatický milník se vyhodnotí z existujících dat a žádná odměna nevznikne duplicitně.

## Současný stav a podklady

### Audit implementace 11. 11. 2026

- Práce vychází z čerstvě staženého `origin/main` (`07f0dd9`).
- `lib/cozy_checkout_web/router.ex`, `admin_auth.ex`, `admin_navigation.ex`:
  sdílený admin PIN, `live_session :admin` a opakované ověření relace při
  událostech. Samostatná osobní autentizace neexistuje.
- `lib/cozy_checkout/bookings/booking.ex`: UUID, `deleted_at`, stavy
  `upcoming/active/completed/cancelled`, počty `adults/children/infants/unclassified_guests`.
  `booking_rooms` je vazba na pokoje, nikoli další pobyt.
- `lib/cozy_checkout/bookings.ex:update_booking_status/1`: `completed` se
  odvozuje od data odjezdu před dneškem (UTC), nikoli od doloženého uskutečnění.
  `get_occupancy_for_range/2` dnes zahrnuje pouze upcoming/active a vylučuje
  soft deletes. Příjezd zahrnut, odjezd vyloučen. Pro historickou realizovanou
  obsazenost nelze toto API převzít beze změny definice.
- `Bookings.cottage_capacity/0` vrací konstantu 45; `Rooms.Room.capacity`
  uchovává kapacitu pokoje, bez historických změn kapacity. Zdroj historické
  kapacity a význam uskutečněného pobytu řeší potvrzená pravidla etapy 2 níže.
- `lib/cozy_checkout/economics/{source,snapshot,confirmation}.ex` a
  `economics.ex`: lokální verzované snapshoty s aktivním zdrojem a potvrzením
  měsíce. V první etapě Adventure tyto kontexty vůbec nevolá.
- `lib/cozy_checkout/application.ex`, `config/config.exs`: Oban existuje,
  Adventure nepřidává worker, cron ani provozní hook. Vypínač je vlastní
  `ADVENTURE_ENABLED`, výchozí false, podle konfigurace v `config/runtime.exs`.
- Provozní model je pro jednu chatu; nenalezen tenant/property scope.
- Riziko N+1 pro budoucí pobytové KPI bylo oznámeno uživateli. Navržený budoucí
  postup je agregace za celé období; uživatel ji při zahájení etapy 2 výslovně
  schválil. `Adventure.Sources.Stays` používá jeden agregovaný SELECT.

### Dodaný rozsah první etapy

Uživatel výslovně zahájil implementaci a potvrdil výběr profilu ve sdílené PIN
relaci. Herní modul je oddělený do `lib/cozy_checkout/adventure/` a vlastního
adresáře LiveView. Viz [aktuální funkce a omezení](../features/ADVENTURE.md).

Logický návrh je zúžen na tři nové tabulky: profily, instance ručních questů
se snapshotem definice a XP ledger. Katalog definic je verzovaný v kódu;
nastavení je samostatný konfigurační vypínač. Tabulky kampaní a achievementů
doplňuje etapa 2. Eventový inbox není pro výslovný přepočet potřeba. Nevznikají žádné provozní FK ani
zápisy mimo adventure_* tabulky. Quest completion i XP používají Ecto.Multi,
profilový zámek a unikátní klíče; opravy jsou kompenzační záznamy.

### Dodaný rozsah druhé etapy

Na výslovnou žádost uživatele je etapa 2 ve stejném [PR #112](https://github.com/michalhorcic/cozy-checkout/pull/112).
Uživatel schválil dávkový SELECT a definici milníků ze stavu `completed`,
odjezdu v kampani po aktivaci a kompenzací při zpětných opravách.

- `Adventure.Sources.Stays` čte pouze `bookings`, bez joinu pokojů či hostů,
  bez aktualizace provozních statusů. Vrací dokončené pobyty, realizované
  lůžkonoci, budoucí rezervované lůžkonoci, procentní obsazenost a metadata.
- Odjezd musí být před aktuálním pražským dnem; pro milníky navíc po celém
  dni aktivace. Chybějící čas skutečného dokončení se nenahrazuje odhadem.
- Kapacita je explicitně potvrzená konstanta kampaně, nikoli domnělá historie
  kapacit pokojů. Bez uzavřených nocí je procento nedostupné. Neúplné podklady
  nepřiznávají ani neodebírají XP. Zdroj a omezení jsou viditelné v UI.
- Kampaň má návrh/aktivní/uzavřená, upravitelné období a cíle před aktivací,
  explicitní potvrzení kapacity a období, nejvýše jednu aktivní instanci.
  Uzavření zmrazí časovou hranici realizace; další přepočet oprav je možný.
- Další tři tabulky ukládají kampaně, achievementy a auditní přepočty.
  Rozšířený XP ledger vynucuje odděleného příjemce profile/shared.
- Dva achievementy (1 a 10 dokončených pobytů) dávají 100/250 XP pouze chatě.
  Přepočet zamyká kampaň a ukládá důkaz i XP atomicky. Unikátní klíče brání
  duplicitám. Při opraveném stornu či změně je milník odvolán a jednou
  kompenzován; odvolaný milník se v této kampani znovu neodměňuje.
- Dashboard čte pouze uložené herní snapshoty. Ruční přepočet a uzavření
  jsou jediné akce čtoucí pobytové údaje. Žádné joby, hooky, emaily či HTTP.
- Aktuální návod, přesné definice a checklist: [ADVENTURE.md](../features/ADVENTURE.md).

Ověřeno v dokumentaci na main dne 2026-11-11:
- Phoenix 1.8, LiveView, PostgreSQL, Oban, Tailwind v4, daisyUI, Docker/Coolify.
- Administrace /admin je chráněná sdíleným PINem, bez identifikace jednotlivých osob. PIN relace nesmí být vydávána za osobní autentizaci.
- Ekonomika firmy je read-only vůči ABRA Flexi, pracuje s verzovanými snapshoty, kontrolou úplnosti a účetními potvrzeními; nedostupné/neověřené údaje nejsou nula.
- Barové a ubytovací finance jsou oddělené; doklady, ceny, DPH a historické snapshoty nesmí být měněny gamifikací.
- Existují rezervace/pobyty, plánování stravování, účetní a nákladové moduly. Konkrétní kontexty, tabulky, stavové přechody a události je před kódováním nutné ověřit přímo v lib/, priv/repo/migrations/ a test/.
- AGENTS.md požaduje kontrolu aktuálního main, existující admin PIN, finanční integritu, UUID, Ecto migrace, Context7 pro externí API, omezení N+1 a PR.

Při vzniku plánu nebyly ověřené konkrétní API a definice. Výsledky následného auditu a přijaté definice uvádějí implementační oddíly výše.

## Produktová pravidla

### Dvě vrstvy progresu
1. **Společná chata**: jedna organizace/instance, sezónní kampaně, rozvojové větve Obchod, Finance, Kuchyně, Provoz, Hosté, společné milníky a projekt rekonstrukce.
2. **Osobní profily**: Michal a Lucka, vlastní XP, level, dokončené osobní questy a příspěvky ke společným cílům. Společné výsledky nejsou rozdělovány na dvě kopie XP.

Herní XP nejsou Kč, odměna ani účetní ukazatel. Reálné KPI se nikdy neodvozují z XP. Výsledek sezóny může být špatný, i když hráč získal hodně XP. Bez streaků a penalizace dovolené.

### Identity a oprávnění
MVP používá ruční výběr aktivního profilu uvnitř existující admin PIN relace. Profil si prohlížeč podle následného zadání pamatuje rok v herní cookie; po připojení LiveView se ověří, že je stále aktivní; nepřidávat fiktivní `user_id` ani účty. Je to **self-report**, nikoliv ověřená identita; zobrazit tuto skutečnost v nastavení. Akce s dopadem na osobní XP zaznamená zvolený profil a způsob atribuce `self_selected`. Automatické události bez spolehlivého aktéra patří pouze společné chatě, nikoliv automaticky poslednímu vybranému hráči. Admin PIN stále chrání všechny stránky a mutace; POS je veřejný a Adventure se v něm nezobrazuje. Individuální přihlášení lze doplnit později samostatným projektem.

### XP, levely, odměny
- XP přidělovat pouze při přechodu quest instance do `completed` nebo při prvním odemčení achievementu, ne při zobrazení dashboardu či každé aktualizaci rezervace.
- Výchozí orientační XP: malé questy 30–50, týdenní 80–150, strategické 200–500, epic 500–1000; přesné hodnoty verzovat v definici. V MVP ruční questy 50/100/250 XP, automatické achievementy 100/250 XP.
- Celkové levely: úroveň L je nejvyšší celé L >= 1, pro které `total_xp >= 100*(L-1)*L/2`; level 1 začíná 0 XP. Žádný strop; level odvozený, ne primárně ukládaný.
- XP transakce mají vlastní ledger, unikátní `award_key`, příjemce (profil nebo chata) a referenci na příčinu. Pro storno se používá kompenzační záznam; historické záznamy se nepřepisují. Záporné XP nepoužívat jako trest; pouze opravné kompenzace chybně udělených odměn.
- Automatický společný milník nesmí zároveň bez atribuce připsat osobní XP. U ručního questů je příjemce osobní profil a případný společný bonus je samostatná explicitní odměna.
- Skill úrovně 1–10 vycházejí ze splněných konkrétních kritérií a důkazů, ne z množství XP. MVP zobrazuje 5 větví jako roadmapu s úrovní `not_evaluated`; automatické odemykání až v další fázi.

### Questy
Typy `manual`, `metric`, `milestone`; scope `personal` nebo `shared`; frekvence `once`, `weekly`, `seasonal`; stavy `available`, `active`, `completed`, `expired`, `cancelled`. Nanejvýš 3 aktivní osobní questy na profil v MVP; společné questy odděleně. Ruční splnění vyžaduje potvrzení, audit aktéra a čas. Automatické questy jsou deterministické a vyhodnocované proti explicitně definovanému zdroji dat; změna zdroje je zaznamenána. Při opakování vzniká nová instance s unikátním obdobím, nikoliv nový bod za každý refresh. Neexistuje tlačítko „získej XP“ bez dokončení questů.

První katalog (konfigurovatelný):
- Ruční osobní: připravit další pobyt (50 XP), zkontrolovat otevřené zálohy (50), dokončit týdenní nákupní plán (100), zavést jedno provozní zlepšení (250). Poznámka je podle následného zadání nepovinná u všech questů.
- Automatické společné achievementy: první dokončený pobyt po aktivaci, 10 dokončených pobytů v kampani, dosažení nastaveného cíle obsazenosti uzavřeného období. Přesné stavy a počítání ověřit v kódu.
- Automatické finanční achievementy odložit, dokud není dostupný úplný a potvrzený účetní snapshot.
- Příklady strategických questů do budoucna: slabý termín obsazen s minimální marží, snížení odpadu, fond rekonstrukce; bez potřebných vstupů pouze návrh, nikdy automatické tvrzení splnění.

### Kampaně
Zimní/letní kampaň má explicitní datum od/do, časové pásmo Europe/Prague, cíle a stav `draft`, `active`, `closed`. Výchozí návrh zimní kampaně 2026-12-01 až 2027-03-31, ale hranice musí uživatel potvrdit před aktivací. Hospodářský rok 1. 7.–30. 6. je nezávislý na herní sezóně.

MVP cíle: počet dokončených pobytů, obsazenost lůžkonocí a rezervované lůžkonoci. Rozlišovat skutečně realizovanou obsazenost a budoucí rezervace; žádné směšování. Den příjezdu a odjezdu musí používat stávající pravidla kalendáře. Kapacita 45 lůžek je konfigurovatelný výchozí návrh, nikoli pevně zakódovaná hodnota; respektovat případné blokace a změny kapacity, pokud je systém podporuje. Zrušené a soft-deleted pobyty vyloučit dle existující domény. Výpočty KPI vracet spolu s `as_of`, definicí, stavem úplnosti a zdrojem.

Finanční KPI lze zobrazit jako samostatnou read-only kartu pouze z existujícího Economics snapshotu, s informací o období, potvrzení a čerstvosti. Bez potvrzeného podkladu stav `unavailable/unverified`, nikdy 0 Kč. Nedělat synchronní HTTP do ABRA z LiveView a nepoužívat účetní výsledek jako automatický quest v MVP.

### Rekonstrukce
Dlouhodobá společná „epic“ linie: finanční plán -> provozní optimalizace -> investiční rezerva -> projekt -> financování -> realizace. Rozpočet 25–30 mil. Kč je scénář, nikoli závazný cíl ani skutečný zůstatek. Stav fondu uvádět jen ze skutečně ověřených dat nebo ručně označené hypotézy; nevydávat účetní bankovní saldo za volné investiční prostředky. V MVP pouze neaktivní roadmapa, bez simulovaných úspor.

## Datový model – návrh migrací

Všechny nové PK UUID, `inserted_at`, `updated_at`, FK, CHECK a unikátní indexy. Názvy sladit se skutečným repo konvencemi.

| Tabulka | Základní pole / constraint |
| --- | --- |
| `adventure_settings` | singleton/tenant key, `enabled`, `timezone`, `rules_version`; unikátní scope |
| `adventure_profiles` | `id`, `display_name`, `slug`, `active`; unique slug per scope |
| `adventure_campaigns` | `id`, `name`, `starts_on`, `ends_on`, `status`, `goals jsonb`, `rules_version`; date check |
| `adventure_quest_definitions` | `id`, `code`, `version`, `kind`, `scope`, `cadence`, `xp`, `conditions jsonb`, `enabled`; unique(code,version) |
| `adventure_quest_instances` | `id`, `definition_id`, `campaign_id nullable`, `profile_id nullable`, `period_key`, `status`, `completed_at`, `evidence jsonb`, `definition_snapshot jsonb`; unique(definition,scope recipient,period_key), řešit NULL-safe unikátnost |
| `adventure_achievement_definitions` | `id`, `code`, `version`, `scope`, `criteria jsonb`, `xp`; unique(code,version) |
| `adventure_achievement_unlocks` | `id`, `achievement_code`, `recipient_type`, `recipient_id nullable`, `campaign_id nullable`, `unlocked_at`, `evidence jsonb`; unique recipient+achievement+campaign NULL-safe |
| `adventure_events` | `id`, `event_key`, `type`, `source_type`, `source_id`, `occurred_at`, `payload jsonb`, `processed_at`; unique(event_key) |
| `adventure_xp_transactions` | `id`, `award_key`, `recipient_type`, `recipient_id nullable`, `amount`, `reason`, `source_type`, `source_id`, `reverses_id nullable`, `inserted_at`; unique(award_key), unique(reverses_id) where not null |

U NULL-scope používat PostgreSQL `NULLS NOT DISTINCT` (pokud verze podporuje) nebo explicitní partial unique indexy. Všechny polymorfní source reference validovat v doménové vrstvě; nepoužívat nespolehlivé volné názvy jako identitu. Nepersistovat osobní údaje hostů v adventure event payloadu. Při multi-property/tenant existenci přidat skutečný scope FK do všech tabulek; před migrací ověřit.

Před vytvořením tabulek Codex posoudí, zda lze některé sloučit bez ztráty auditovatelnosti; návrh je logický kontrakt, nikoli povinnost osmi tabulek.

## Aplikační kontext a API

`CozyCheckout.Adventure` (upravit podle reálného namespace) vlastní pravidla, transakce a dotazy. Navržené funkce:
- `enabled?/0`, `get_dashboard/2`, `list_profiles/0`, `select_profile/2` (session ve webové vrstvě)
- `list_quests/2`, `activate_quest/2`, `complete_manual_quest/3`
- `evaluate_campaign/2`, `evaluate_achievements/2`, `award_xp_once/1`, `reverse_award/2`
- `reconcile_source/2` a `rebuild_progress/1` pro idempotentní opravný přepočet
- oddělené read-only adaptéry `Adventure.Sources.Stays`, `Adventure.Sources.Economics` (a později Catering).

Nepřidávat hook na každý write naslepo. Nejprve zjistit existující doménové transakce, stavové přechody a Oban joby. MVP může použít deterministické dávkové vyhodnocení z DB s `as_of` a explicitní ruční akcí „Přepočítat“; event adapter pro relevantní změny přidat až po identifikaci správných commit pointů. Pro budoucí realtime eventy až po úspěšném commitu, s deduplikací a možností replay. Celá změna stavu quest + XP ledger musí být v jedné Ecto.Multi transakci; concurrent race řešit DB unikátními indexy a zámky/upsert. Oban retry nesmí udělit duplicitní XP.

KPI agregovat v SQL jedním dotazem na rozsah nebo dávkou, ne dotazem pro každý pobyt/den. Cache nebo materializace pouze pokud měření ukáže potřebu. Dashboard načítá lokální DB; žádný vzdálený HTTP request při renderu.

## Obrazovky a UX

1. `/admin/adventure`: hlavička sezóny, společná úroveň/XP, profil switcher, osobní level, maximálně 3 aktivní osobní questy, společné questy, postup kampaně, poslední achievementy. Vše jako volitelný modul.
2. `/admin/adventure/quests`: katalog, filtr osobní/společné, aktivovat, potvrdit dokončení, historie, vysvětlení zdroje a důkazu.
3. `/admin/adventure/campaigns/:id`: cíle, metriky, datum platnosti, kvalita dat, historie a stav kampaně.
4. `/admin/adventure/achievements`: získané a uzamčené achievementy, kritéria.
5. `/admin/adventure/settings`: enable/disable, profily, návrh kampaně, cíle, ruční přepočet a audit.

MVP lze dodat jako dashboard + quests + settings, ostatní detaily v rozbalovacích sekcích nebo druhé fázi. Navigace v admin „Další agenda“; žádná změna veřejného POS. Light theme, existující `Layouts.app`, `.input`, `.icon`, responzivní karty, střídmé progress bary a odznaky, žádné nové JS pro základní funkce. Barva nesmí být jediným indikátorem; klávesnice a čtečky obrazovky. Nedávat rušivé animace ani povinné notifikace.

## Implementační kroky pro Codex

### Etapa 0 – audit před kódováním
- [x] Fetch latest origin/main; zkontrolovat AGENTS.md, router, admin auth, LiveViews, schemas, migrations a testy.
- [x] Najít autoritativní zdroj pobytů, statusů, kapacity, obsazenosti a ekonomických snapshotů; sepsat přesný mapping a zdrojové soubory do tohoto plánu.
- [x] Zkontrolovat existující identitu uživatele, Oban konfiguraci a přepínání feature flags.
- [x] Upozornit na N+1 riziko a schválit dávkový SELECT s uživatelem.
- [x] Vyjasnit otázky pro etapy 1–2; konkrétní kampaň potvrzuje správce v UI před aktivací.

### Etapa 1 – MVP foundation
- [x] Migrace a schémata s DB constraints; bezpečné seed definice a profily bez duplicit při opakování.
- [x] Adventure kontext, XP ledger, level function, atomické splnění ručního questu, audit a deduplikace.
- [x] Admin LiveView dashboard, profil switcher a ruční questy; admin PIN guard, vypnutý modul bez veřejných tras.
- [x] Feature toggle default off; žádná nová externí služba.

### Etapa 2 – automatická data a kampaně
- [x] Read-only stay adapter a definice lůžkonocí / pobytů s testy pro CI.
- [x] Kampaň s konfigurovatelným obdobím, stavem, cíli, as_of a kvalitativním statusem dat.
- [x] Deterministické achievementy a bezpečný re-run/reconciliation.
- [x] Auditovatelná oprava při stornu či změně pobytu; pravidla uzamčená při aktivaci. Joby se nepřidávají.

### Etapa 3 – další implementace, zatím pouze plán

Podrobný rozsah a potvrzené volby jsou v [revizi úkolovníku a sezón](2026-11-12-adventure-todos-a-prehled-sezony.md).

- [ ] 3A: správa jednorázových todos, přiřazení a společné úkoly; denní/týdenní šablony a působnost bez hromadění výskytů.
- [ ] 3B: sezónní přehled s volitelnými cíli, read-only bar a fakturace, oddělené inkaso a vyúčtování podle odjezdu.
- [ ] 3C: srovnatelné sezóny a další ověřené ukazatele.

Tato revize nemění existující herní data ani nepovoluje začít implementovat.

### Etapa 4 – pozdější rozšíření
- [ ] Skill tree s ověřitelnými kritérii.
- [ ] Read-only finanční metriky z Economics, pouze s kvalitou dat a potvrzením.
- [ ] Strategické události a doporučení, případně AI až po definici bezpečných vstupů.
- [ ] Rekonstrukční roadmapa, vizuální evoluce chaty, skutečné individuální účty.

Etapy mají ověřitelná acceptance criteria. Uživatel při pokračování výslovně požádal ponechat etapy 1 a 2 ve stejném PR #112 pro společnou kontrolu.

## Testy a akceptační kritéria

### Unit / property
- XP hranice: 0=>L1, 99=>L1, 100=>L2, 299=>L2, 300=>L3; velké XP, záporný výsledek po korekci ošetřit.
- Opakovaný complete stejného questu vrátí stejný stav bez dalšího XP.
- Weekly quest používá kalendářní týden Europe/Prague; DST a přelom roku.
- Sdílený milník nezvyšuje osobní XP bez prokazatelného přiřazení.
- Neplatné cíle, datum kampaně, XP, profily a duplicitní scope odmítnout.

### DB / concurrency
- Paralelní splnění stejného questu: právě jedna transakce odměny.
- Dva souběžné achievement joby: právě jeden unlock/award.
- Rollback mezi dokončením a XP: nevznikne poloviční stav.
- Replay eventu a opakovaný Oban retry: beze změny výsledku.
- Kompenzace: maximálně jednou, dohledatelná původní odměna.
- Seed opakovaně nezduplikuje profily ani definice.

### Doména a integrace
- Příjezdový den se počítá, odjezdový ne, dle stávajícího kalendáře; test překryvu a více pokojů.
- Zrušený, smazaný, změněný a dokončený pobyt, částečná obsazenost a prázdná sezóna.
- Reconciliation po stornu opraví stav metrik; jednorázový historický achievement má explicitní politiku ponechání/kompenzace.
- Ekonomika disabled/stale/unverified: nikdy nevydávat číslo za potvrzený výsledek; bez HTTP z LiveView.
- Testy nesmí posílat emaily, vytvářet skutečné účetní doklady ani volat produkční ABRA.

### LiveView / bezpečnost
- Bez PINu nelze otevřít ani mutovat Adventure; veřejný POS zůstává nezměněn.
- Profil switcher nepředstírá autentizaci; automatická událost bez aktéra neodmění náhodného hráče.
- Disabled feature: admin navigace a route guard; žádné background side effects.
- Responzivní mobilní layout, klávesnice, textové statusy, CS lokalizace.
- Dashboard omezeným počtem DB queries nezávisle na počtu pobytů (N+1 regresní test).

### Definition of Done MVP
- 2 osobní profily + společný profil chaty.
- Aktivace, dokončení a historie ručních questů; přesný XP ledger a level.
- Jedna konfigurovatelná sezóna a alespoň 2 ověřené read-only pobytové KPI.
- Alespoň 2 automatické achievementy s deduplikací.
- Vypínatelný modul, audit, re-run, bez zásahů do účetních záznamů.
- Dokumentace `docs/features/ADVENTURE.md` po implementaci, CI a manuální checklist.
- Podle AGENTS.md formátování lokálně, testy standardně necháváme CI; PR uvede, co bylo skutečně ověřeno.

## Nasazení a rizika

Feature flag default OFF, migrovat bez přepsání stávajících dat; zapnout až po ověření zdrojů a kontrolních výpočtů. Při vypnutí zůstávají data i audit, neprobíhá evaluace. Rollback aplikace nemá vyžadovat mazání tabulek. Důležité: nezatěžovat rezervační transakce, neodměňovat storna, nedublovat pobyty, nevystavovat osobní data hostů, neprezentovat nepodložené účetní výsledky.

## Rozhodnutí

| Datum | Rozhodnutí | Zdroj |
| --- | --- | --- |
| 2026-11-11 | Kombinace ekonomické strategie a RPG | Zadání uživatele |
| 2026-11-11 | Společná chata i individuální profily | Zadání uživatele |
| 2026-11-11 | Moderní dashboard s RPG prvky | Zadání uživatele |
| 2026-11-11 | Pouze plán, bez implementace | Zadání uživatele |
| 2026-11-11 | Osobní profil v MVP self-selected, nikoliv autentizovaný | Výslovně potvrzeno uživatelem při implementaci |
| 2026-11-11 | Zahájení implementace, samostatný context a adresář, žádné zpětné zápisy do provozu | Zadání uživatele v implementačním chatu |
| 2026-11-11 | Dávkový read-only SQL přepočet bez N+1 | Výslovně schváleno uživatelem |
| 2026-11-11 | Completed pobyty s odjezdem v kampani po aktivaci; opravy odvolají milník a jednou kompenzují společná XP | Výslovně schváleno uživatelem |
| 2026-11-11 | Etapy 1 a 2 ve stejném PR #112 | Výslovný pokyn uživatele |
| 2026-11-11 | Hravá horská grafika, čistá obrazovka, vysvětlení v overlay nápovědě a nepovinné poznámky questů | Následné zadání uživatele |
| 2026-11-12 | Zapamatovat vybraného hrdinu v prohlížeči; roční herní cookie, ověření aktivního profilu při obnovení | Následné zadání uživatele |
| 2026-11-12 | Další etapa: společný úkolovník, spravované opakování bez hromadění a sezónní přehled; dvě finanční perspektivy a vyúčtování podle odjezdu | Výslovně potvrzeno v plánovací diskusi; bez implementace |

## Otevřené otázky

1. Vyřešeno: výběr osobního profilu bez dalšího PINu je pro MVP dostačující, s jasným upozorněním na self-report.
2. Konkrétní zimní období potvrzuje správce v UI před aktivací; výchozí 1. 12.–31. 3. je návrh.
3. Etapa 3A v PR #113 přidává vlastní jednorázové úkoly a spravované opakované šablony, působnost a generování bez hromadění; původní instance a odměny zůstávají zachované. Další postup sezónního přehledu popisuje navazující plán.
4. Vyřešeno: při úplných opravených podkladech milník revoked a jednorázová kompenzace; původní důkaz zachován.
5. Dodáno: chata má vlastní společný XP level, oddělený od osobních profilů.
6. Vyřešeno pro MVP: completed + datum odjezdu dle pravidel výše, kapacita jako explicitní potvrzená konstanta kampaně.

## Průběh a předání dalšímu chatu

- Hotovo ve větvi v PR #112: etapy 1 a 2, samostatný context, šest herních tabulek,
  2 profily, ruční questy, osobní i společné XP, kampaně, read-only pobytové KPI,
  dva achievementy, audit a kompenzace, admin UI, default-off flag a testy pro CI.
- Potvrzeno uživatelem: výběr profilu uvnitř admin PIN relace dostačuje pro MVP.
- Zbývá: CI a ruční checklist dosavadní implementace; další práce podle nové
  [etapy 3 – úkolovník a sezónní přehled](2026-11-12-adventure-todos-a-prehled-sezony.md).
  Skill tree, účetní zisk a rekonstrukce přicházejí až později.
- Před zapnutím zvolit a v UI potvrdit skutečné období a konstantní kapacitu.
- Aktivní kampaně se nepřevádějí tiše mezi verzemi pravidel. Budoucí změny
  definice vyžadují novou verzi a samostatnou implementaci.
- Navazující úprava UI: vlastní ilustrace horské chaty, lokální Lucide SVG,
  čistý tábor a karty questů, sbalený katalog/deník/audit, overlay Průvodce.
  Poznámka ke splnění je nepovinná; aktér a čas auditu zůstávají povinné.
  Ověřeno v Chromium na desktopu a šířkách 390/320 px: dialog, klávesnice,
  návrat fokusu, dokončení bez poznámky i změna XP. Nové ExUnit testy pro CI.
- Při opravě nahlášeného selhání validace XP byly lokálně spuštěny
  `adventure_test.exs` a `xp_transaction_test.exs`: 14 testů prošlo proti
  dočasnému PostgreSQL 17 v Dockeru. Oprava vytváří skutečné změny pro validaci
  částky; rollback test ověřuje i nulový čas dokončení a prázdný důkaz.
  Celou zbývající sadu a CI ověřuje uživatel.

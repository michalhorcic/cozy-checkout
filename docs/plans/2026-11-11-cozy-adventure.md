# Cozy Adventure – ekonomická strategie a RPG pro Cozy Checkout

- Stav: rozpracováno; etapa 1 implementována ve větvi, čeká na CI a kontrolu PR
- Vytvořeno: 2026-11-11
- Aktualizováno: 2026-11-11
- Repozitář: `michalhorcic/cozy-checkout`
- Související dokumentace: `AGENTS.md`, `docs/features/ADMINISTRATION.md`, `docs/features/ECONOMICS.md`, `docs/features/CATERING.md`, `docs/features/BILLING.md`, `docs/plans/2026-10-28-ekonomicky-dashboard.md`

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
  kapacity a význam uskutečněného pobytu je nutné rozhodnout před etapou 2.
- `lib/cozy_checkout/economics/{source,snapshot,confirmation}.ex` a
  `economics.ex`: lokální verzované snapshoty s aktivním zdrojem a potvrzením
  měsíce. V první etapě Adventure tyto kontexty vůbec nevolá.
- `lib/cozy_checkout/application.ex`, `config/config.exs`: Oban existuje,
  Adventure nepřidává worker, cron ani provozní hook. Vypínač je vlastní
  `ADVENTURE_ENABLED`, výchozí false, podle konfigurace v `config/runtime.exs`.
- Provozní model je pro jednu chatu; nenalezen tenant/property scope.
- Riziko N+1 pro budoucí pobytové KPI bylo oznámeno uživateli. Navržený budoucí
  postup je agregace za celé období; implementace a případné schválení
  dávkového řešení zůstávají v etapě 2. První etapa provozní data nenačítá.

### Dodaný rozsah první etapy

Uživatel výslovně zahájil implementaci a potvrdil výběr profilu ve sdílené PIN
relaci. Herní modul je oddělený do `lib/cozy_checkout/adventure/` a vlastního
adresáře LiveView. Viz [aktuální funkce a omezení](../features/ADVENTURE.md).

Logický návrh je zúžen na tři nové tabulky: profily, instance ručních questů
se snapshotem definice a XP ledger. Katalog definic je verzovaný v kódu;
nastavení je samostatný konfigurační vypínač. Tabulky kampaní, achievementů
a eventů budou přidány až s jejich chováním. Nevznikají žádné provozní FK ani
zápisy mimo adventure_* tabulky. Quest completion i XP používají Ecto.Multi,
profilový zámek a unikátní klíče; opravy jsou kompenzační záznamy.

Ověřeno v dokumentaci na main dne 2026-11-11:
- Phoenix 1.8, LiveView, PostgreSQL, Oban, Tailwind v4, daisyUI, Docker/Coolify.
- Administrace /admin je chráněná sdíleným PINem, bez identifikace jednotlivých osob. PIN relace nesmí být vydávána za osobní autentizaci.
- Ekonomika firmy je read-only vůči ABRA Flexi, pracuje s verzovanými snapshoty, kontrolou úplnosti a účetními potvrzeními; nedostupné/neověřené údaje nejsou nula.
- Barové a ubytovací finance jsou oddělené; doklady, ceny, DPH a historické snapshoty nesmí být měněny gamifikací.
- Existují rezervace/pobyty, plánování stravování, účetní a nákladové moduly. Konkrétní kontexty, tabulky, stavové přechody a události je před kódováním nutné ověřit přímo v lib/, priv/repo/migrations/ a test/.
- AGENTS.md požaduje kontrolu aktuálního main, existující admin PIN, finanční integritu, UUID, Ecto migrace, Context7 pro externí API, omezení N+1 a PR.

Neověřeno: konkrétní API pro rezervace a pobyty, jejich stabilní ID, definice obsazenosti, stávající event hooks, možnost rozlišení operátora, přesný model práv. Codex musí tyto body prověřit před implementací, nikoliv domýšlet.

## Produktová pravidla

### Dvě vrstvy progresu
1. **Společná chata**: jedna organizace/instance, sezónní kampaně, rozvojové větve Obchod, Finance, Kuchyně, Provoz, Hosté, společné milníky a projekt rekonstrukce.
2. **Osobní profily**: Michal a Lucka, vlastní XP, level, dokončené osobní questy a příspěvky ke společným cílům. Společné výsledky nejsou rozdělovány na dvě kopie XP.

Herní XP nejsou Kč, odměna ani účetní ukazatel. Reálné KPI se nikdy neodvozují z XP. Výsledek sezóny může být špatný, i když hráč získal hodně XP. Bez streaků a penalizace dovolené.

### Identity a oprávnění
MVP používá ruční výběr aktivního profilu uvnitř existující admin PIN relace. Profil se ukládá do session (případně jako krátkodobá volba v LiveView); nepřidávat fiktivní `user_id` ani účty. Je to **self-report**, nikoliv ověřená identita; zobrazit tuto skutečnost v nastavení. Akce s dopadem na osobní XP zaznamená zvolený profil a způsob atribuce `self_selected`. Automatické události bez spolehlivého aktéra patří pouze společné chatě, nikoliv automaticky poslednímu vybranému hráči. Admin PIN stále chrání všechny stránky a mutace; POS je veřejný a Adventure se v něm nezobrazuje. Individuální přihlášení lze doplnit později samostatným projektem.

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
- Ruční osobní: připravit další pobyt (50 XP), zkontrolovat otevřené zálohy (50), dokončit týdenní nákupní plán (100), zavést jedno provozní zlepšení s poznámkou (250).
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
- [ ] Upozornit na N+1 riziko a navrhnout batch query; před realizací optimalizace vyžadující schválení postupovat podle AGENTS.md.
- [ ] Vyjasnit otevřené produktové otázky níže.

### Etapa 1 – MVP foundation
- [x] Migrace a schémata s DB constraints; bezpečné seed definice a profily bez duplicit při opakování.
- [x] Adventure kontext, XP ledger, level function, atomické splnění ručního questu, audit a deduplikace.
- [x] Admin LiveView dashboard, profil switcher a ruční questy; admin PIN guard, vypnutý modul bez veřejných tras.
- [x] Feature toggle default off; žádná nová externí služba.

### Etapa 2 – automatická data a kampaně
- [ ] Read-only stay adapter a testovaná definice lůžkonocí / pobytů.
- [ ] Kampaň s konfigurovatelným obdobím, stavem, cíli, as_of a kvalitativním statusem dat.
- [ ] Deterministické achievementy a bezpečný re-run/reconciliation.
- [ ] Auditovatelná oprava při stornu, změně pobytu, změně pravidel nebo opakovaném jobu.

### Etapa 3 – rozšíření (mimo MVP)
- [ ] Skill tree s ověřitelnými kritérii.
- [ ] Read-only finanční metriky z Economics, pouze s kvalitou dat a potvrzením.
- [ ] Strategické události a doporučení, případně AI až po definici bezpečných vstupů.
- [ ] Rekonstrukční roadmapa, vizuální evoluce chaty, skutečné individuální účty.

Každá etapa samostatný PR a ověřitelné acceptance criteria; plán samotný nepovoluje zahájení implementace.

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
| 2026-11-11 | Automatické XP pouze z ověřených, deduplikovaných událostí | Návrh, k potvrzení |

## Otevřené otázky

1. Vyřešeno: výběr osobního profilu bez dalšího PINu je pro MVP dostačující, s jasným upozorněním na self-report.
2. Kdy přesně začíná a končí zimní kampaň? Navrženo 1. 12.–31. 3., upravitelné.
3. Mají být ruční questy vytvářeny volně, nebo jen ze šablon? Doporučení: v MVP šablony + jednoduchý jednorázový vlastní quest s limitem XP.
4. Při zpětném stornu pobytu: má být historický achievement ponechán jako dosažený milník, nebo kompenzován? Doporučení: KPI přepočítat, milník označit jako revoked s auditním záznamem, XP kompenzovat jen při prokazatelně chybném přiznání.
5. Má společná chata vlastní XP level, nebo jen skill/milestone progres? Doporučení: vlastní společný XP level, jasně oddělený od osobních.
6. Ověřit aktuální doménový zdroj kapacity a definici `completed stay` v kódu.

## Průběh a předání dalšímu chatu

- Hotovo ve větvi: audit zdrojů, základ etapy 1, samostatný context, migrace,
  opakovatelný setup, 2 profily, šablony questů, atomické XP, opravné API,
  admin dashboard/questy/nastavení, default-off flag, dokumentace a testy pro CI.
- Potvrzeno uživatelem: výběr profilu uvnitř admin PIN relace dostačuje pro MVP.
- Zbývá: CI a ruční checklist, etapa 2 (kampaně, read-only KPI, achievementy,
  reconciliation); etapa 3 beze změny. Kompletní MVP zatím není dodané.
- Před etapou 2 rozhodnout hranice kampaně, význam dokončeného pobytu,
  historickou kapacitu a pravidla kompenzace automatických milníků.
- V první etapě pouze pevné šablony; vlastní questy a společné XP odloženy.
- Testy lokálně nespouštěny podle AGENTS.md; CI ověřuje uživatel.

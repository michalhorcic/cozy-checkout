# Vytěžování dokladů: aktuální stav a další etapa hromadného zpracování

- **Aktualizováno:** 9. 11. 2026 po kontrole implementace a upřesnění s uživatelem.
- **Stav:** jednotlivé doklady, dodavatelské instrukce a dávkové zpracování včetně
  postupné kontroly jsou implementované; skutečný provozní pilot a ověření CI zbývají.
- **Implementace:** původní [PR #100](https://github.com/michalhorcic/cozy-checkout/pull/100)
  byl sloučen 9. 11. 2026. Dávky navazují ve větvi `feat/supplier-extraction-next`
  z `origin/main` (`b741b5e`).
- **Návod současné funkce:** [INCOMING_DOCUMENT_FORM.md](../features/INCOMING_DOCUMENT_FORM.md).
- Tento dokument nahrazuje původní dvoufázový plán. Popisuje skutečný stav,
  opravy z pilotování a zadání pro další vlákno. Historický návrh je v Git historii.

## Implementovaná dávková etapa (9. 11. 2026)

Nové moduly `IncomingDocuments.Batches`, `Batch` a `IncomingDocumentBatchesLive`
implementují přípravu, víceupload, duplicity, společný předpis, explicitní atomický
start, průběh a trvalé dokončení. Migrace `20261109130000` přidává vazby, stav
`staged`, první běh a model; limit nových dávek je konfigurovatelný přes
`INCOMING_DOCUMENTS_BATCH_MAX_FILES` (výchozí 50) a snapshotovaný při vytvoření.
Originály se při startu ani ve výpisech nenačítají. Přehledy mají konstantní počet
dotazů; první běhy se připojují joinem. Číselník se vybírá a validuje pro dávku,
ne pro každý doklad.

Nové extrakce používají frontu `incoming_extraction` (2), původní joby zůstávají
kompatibilní a přenos je v `billing`. Periodická obnova vychází z terminálních
stavů Oban jobů, nikdy ze samotného stáří, a neprovádí AI požadavky. Dokončení se
obnovuje z prvních běhů; pozdější opakování nemění připravenost ostatních.

PIN chrání dávkové routy i kontrolu; členství dokladu a dokončení celé dávky se
ověřují na serveru. Kontrola sdílí `IncomingDocumentFormLive`, včetně historie,
validací a přenosových zámků. Přibyly filtry, odložení/návrat, ochrana neuložených
změn a individuální odeslání s přechodem až po `sent`. Přehled dávek se stránkuje
po 25; přehled položek je omezen uloženým limitem dané dávky. Aktualizace běhu
neobnovuje data ostatních formulářů a otevřený účetní picker se zachovává.

Přidány kontextové a LiveView testy. ExUnit sada nebyla podle AGENTS.md lokálně
spuštěna, nové testovací moduly byly zkompilovány. Prošly formátování, kompilace
s `--warnings-as-errors`, sestavení assetů a migrace na dočasném PostgreSQL 17.
Chromium ověřil pět uploadů po dvou, refresh, start a dokončení přes frontu,
uložení XML a přechod po potvrzeném individuálním přenosu, ochranu neuložené
hodnoty a otevřené sekce, bez JS chyb; šířka 390 px bez vodorovného přesahu.
AI a ABRA byly nahrazené lokálními odpověďmi. Živá přesnost, cena a ergonomie
na skutečných soukromých dokladech nebyly tímto ověřené; provozní pilot zbývá.

Po potvrzeném přenosu do ABRA se navíc automaticky zařadí samostatný job přílohy
uloženého podkladu (PDF/JPEG/PNG). Stav a opakování jsou nezávislé na účetním
importu, existující obsah se ověřuje SHA256 a po nejistém uploadu se automaticky
jen dohledává. Migrace `20261109150000` přidává trvalý stav přílohy. Podrobnosti
jsou v uživatelském návodu; živé přenosy do ABRA agent neprováděl.

Kontrola je následně zjednodušená: jedna stálá akční lišta, společné atomické
uložení hlavičky/DPH/předpisu, kombinované uložení a odeslání s přechodem až po
`sent`, mobilní přepínání formuláře a originálu a rozbalovací pokročilé funkce.
Spuštění dávky současně ukládá společné nastavení. Validační a přenosové guardy
zůstávají zachované; tato úprava nepřidává migraci ani konfiguraci.

Následující zadání zachovává přijatá rozhodnutí a akceptační scénáře pro revizi.

## 1. Zadání pro další vlákno

Uživatel chce najednou nahrát více fotek stejné kategorie, po dokončení nahrávání
výslovně spustit vytěžování a vrátit se k hotovým návrhům. Aplikace zpracuje doklady
na pozadí, oznámí výsledek v aplikaci a nabídne postupnou kontrolu proti originálu.
Uživatel jednotlivé doklady opraví a odešle do ABRY. Počet 10 plateb kartou,
5 faktur nebo 20 hotovostních účtenek byl příklad, nikoli pevně dané limity.

### Potvrzené odpovědi uživatele z 9. 11. 2026

| Otázka | Rozhodnutí |
| --- | --- |
| Fotky a doklady | Jedna fotka = jeden samostatný doklad. Spojování více fotek jednoho dokladu později. |
| Kategorie | Předvyplní společné účetní nastavení dávky; u jednotlivého dokladu půjde upravit. |
| Kdy kontrolovat | Až po dokončení vytěžování celé dávky. |
| Upozornění | Stačí uvnitř aplikace, bez e-mailu nebo jiné externí zprávy. |

Dále platí předchozí požadavky: přesnost má přednost před úsporou počtu dotazů,
položky účtenek řešit později, nepřidávat souhlasové checkboxy a nezavírat
rozbalené sekce při editaci ani při aktualizaci stavů.

### Přijaté pracovní návrhy pro implementaci

Následující jsou technické/productové návrhy tohoto plánu, nikoliv další odpovědi
uživatele. Lze je použít bez opakování již zodpovězených otázek:

- Jedna dávka má jednu kategorii a jednu cílovou firmu ABRA. Pro jinou kategorii
  vznikne další dávka. Zatím tři kategorie odpovídající stávajícím agendám.
- Po spuštění je sestava souborů a výchozí nastavení dávky uzamčené; další soubory
  patří do nové dávky. Není potřeba správa uživatelských kategorií.
- Dokončení vytěžování znamená úspěch **nebo evidovanou chybu** u každého dokladu.
  Chyba jednoho dokladu neblokuje ostatní ani otevření kontroly hotové dávky.
- Každý doklad se odesílá zvlášť explicitním tlačítkem. Hromadné schválení či
  automatické odeslání celé dávky do ABRY není součástí této etapy.
- Návrh provozního limitu je 50 souborů v dávce, stále nejvýše 10 MB na soubor;
  počet má být konfigurovatelný. Uploady i zpracování mají omezený souběh.
- Zachovat PDF/JPEG/PNG. Jeden PDF soubor je jeden doklad i při více stranách;
  nerozdělovat PDF s několika různými doklady ani nespojovat jednotlivé fotky.

## 2. Výchozí stav po PR #100

Tato část zachycuje předání před implementací dávkové etapy popsané výše.

### 2.1 Současný tok jednoho dokladu

1. `/admin/incoming-documents` je seznam, `/admin/incoming-document-form` nový
   formulář, `/admin/incoming-document-form/:id` jeho detail. Staré detailové
   adresy také vedou na nový formulář. Přístup chrání existující admin PIN.
2. Formulář přijímá jeden soubor (`max_entries: 1`), nejvýše 10 MB.
   `IncomingDocuments.upload/5` uloží soukromý originál do DB, hash, šablonu,
   cílovou firmu a externí ID a **ihned** založí extrakční běh i Oban job.
   Neexistuje oddělená příprava dávky před spuštěním.
3. Nový `header_form` běh má identifikaci dodavatele a obecné čtení hlavičky/DPH.
   Pokud se přiřadí profil s neprázdnými instrukcemi, následuje samostatný
   dodavatelský dotaz. Celkem tedy dvě nebo tři AI volání.
4. Samostatný dotaz dostává originál a dodavatelský úkol se stručným systémovým
   kontraktem a striktním JSON schématem. Nedostává obecné zadání ani předchozí
   odpověď. Není to zcela volný chatový dotaz. Vrací řídká pole `field`, `value`,
   `source_text`, případně DPH a nejasnosti. Výslovná hodnota přepíše obecný odhad,
   `null` jej smaže. Obecný, cílený a sloučený výsledek zůstávají v historii.
5. Bezpečně se automaticky páruje české IČO s kontrolním součtem; DIČ jako klíč
   profilu se volí ručně. Profily jsou oddělené podle normalizované URL a firmy
   ABRA. Mají revize, limit 8 000 znaků a ochranu proti souběžnému přepsání.
6. Nové běhy mají položky výchozně vypnuté. API schéma pole `items` vůbec
   nepožaduje; interní prázdné pole se doplní až po validaci. Volitelný přepis
   položek je jen text do poznámky, nikoli položkové účtování.
7. Formulář nabízí hlavičku, návrhy dat a souhrnnou DPH v CZK (0/12/21 %),
   originál, instrukce, historii, účetní předpis a volitelný ABRA dry-run.
   Neúplné údaje lze ručně doplnit. Uložením vzniká validované XML.
8. Explicitní odeslání převádí uložené XML na nativní JSON ABRA. Zachovává externí
   ID, kontrolu duplicitního přenosu, zámky a neměnné `sent_xml`. Nejasný výsledek
   skutečného importu se pouze ověřuje podle externího ID; POST se neopakuje.

### 2.2 Běhy, chyby a obnova

`ExtractionRuns` ukládá generaci, source hash, instrukce, schémata, revizi profilu,
výsledky, model a usage jednotlivých fází. Každá fáze rezervuje placené volání
pod DB zámkem; HTTP probíhá mimo transakci. Pozdní výsledek nesmí přepsat nový
běh, jiný zdroj nebo odeslaný doklad. Oban retry není nový placený pokus.
Po nejisté rezervaci musí další pokus výslovně vyvolat obsluha.

Obsahové opakování s profilem provede dvě volání bez nové identifikace. Nové
určení dodavatele vytvoří úplný běh. Před opakováním se archivuje pracovní návrh
a zneplatní XML/dry-run; návrh lze po neúspěchu vědomě obnovit. Uložení instrukcí
pro příště nevolá AI. Uložení instrukcí a nový běh jsou jedna transakce.

Selhání samostatného dodavatelského dotazu nyní znamená neúspěšný běh. Obecný
výsledek zůstává v historii, ale automaticky se neoznačí jako hotový návrh.
Dávky toto pravidlo zachovají a nabídnou ruční opravu nebo nový běh.

### 2.3 Důležité opravy a poznatky z tohoto vlákna

- **Skutečně použitý model:** aplikace čte `INCOMING_DOCUMENTS_OPENAI_MODEL`,
  nikoli model vybraný v Codexu. V neúspěšném pokusu historie ukázala
  `gpt-4o-mini`, přestože uživatel očekával Sol. Shellový zápis
  `${INCOMING_DOCUMENTS_OPENAI_MODEL:-gpt-6.1-sol}` zachovává již nastavenou hodnotu.
  Pro lokální změnu použít `export INCOMING_DOCUMENTS_OPENAI_MODEL=gpt-6.1-sol`,
  restartovat běžící aplikaci a založit nový běh. Model se nyní připíná od první
  rezervované fáze daného běhu, ne už při vytvoření uploadu.
- Uživatel po nápravě modelu hlásil výrazně lepší výsledek. Nejde o systematicky
  změřenou přesnost. Příklad PENNY byl číslo za `EV-Č` v patičce, zaměňované
  za číslo soudu v hlavičce. Nevkládat konkrétní očekávané číslo do obecných promptů.
- **První běh přerušený, opakování funkční:** DB původně povolovala maximálně
  dvě volání. Úplný běh potřebuje tři, obsahové opakování dvě. Migrace
  `20261106130000` upravila constraint na 0–3. Worker zaznamená bezpečný typ
  výjimky a srozumitelný důvod ihned. Nevracet se k prostému navýšení Oban retry.
- **Zavírající se sekce:** `<details>` mají stabilní ID a
  `phx-mounted={JS.ignore_attributes("open")}`. Aktualizace nesmí obnovovat celý
  editor nebo ničit neuložené opravy. Zachovat i při novém kontrolním rozhraní.
- Souhlasové checkboxy byly odstraněny. Tlačítka vyjadřují akci; validace,
  varování, ochrana neuložených změn a přenosové zámky zůstávají.
- `SourceImages` posílá originál a u dlouhých účtenek překrývající se výřezy,
  pokud je dostupný ImageMagick. Opakované obrazové vstupy mohou být drahé;
  historie ukazuje skutečné usage. Přesnost ani cenu nezaručuje samotná délka promptu.

### 2.4 Nasazení a dosavadní ověření

Po předchozích migracích přijatých dokladů jsou nutné také:

| Migrace | Účel |
| --- | --- |
| `20261106090000` | Dodavatelské profily, extrakční běhy, aktivní vazba a constrainty |
| `20261106120000` | Samostatná dodavatelská fáze a oddělené výsledky |
| `20261106130000` | Povolit tři volání při prvním úplném běhu |

Lokálně je potřeba `mix ecto.migrate`, restart a nový běh; staré neúspěšné běhy
se samy nezopakují. Starší uložené kontrakty zachovávají původní počet fází.
Historii ani zmrazené odeslané doklady nepřepisovat.

Při opravě konkrétního přerušování byly lokálně spuštěny cílené testy s Req.Test:
28 testů běhů, 48 souvisejících testů kontextu/workflow/dodavatelského kontraktu
a 15 testů formuláře prošlo. Následné nesouvisející CI opravy ve stejném PR
(jednodenní pobyty leaderboardu, helper reportů a chybějící validační flash
při zakládání barového účtu) byly ověřeny 21 cílenými testy. Tyto počty nejsou
výsledek celé CI sady. Kompilace s `--warnings-as-errors` a formátování prošly.

Živé OpenAI/ABRA požadavky agent při ověřování neprováděl. Zbývá pilot na více
soukromých dokladech různých dodavatelů, měření oprav, času a usage. Stav CI
ověří uživatel. Úprava tohoto plánu sama nepřidává implementaci ani nové testy.

## 3. Uživatelský průchod dávkou

### Příprava a nahrávání

Na seznamu přijatých dokladů přidat „Nová dávka“ a přehled předchozích dávek;
stávající „Nový doklad“ a ruční formulář zachovat.

1. Vybrat kategorii a případně název dávky (jinak výchozí název podle kategorie
   a času). Zobrazit cílovou firmu a výchozí účetní nastavení.
2. Kategorie mapovat na dnešní agendy:
   **Faktury → `faktura-prijata`**, **Hotově → `pokladni-pohyb`**,
   **Kartou → `zavazek`**. Použít existující šablony a předpisy, nikoli AI výběr.
3. Umožnit společný výběr účetního předpisu z ABRY. Převzít validovaný snapshot
   použitelný pro danou agendu; u jednotlivých dokladů jej lze později změnit.
   Nedávat všem stejné interní číslo `kod` ani společné částky/data. Interní číslo
   nechat standardně přidělit ABŘE. Ostatní výchozí nastavení odpovídá šabloně agendy.
4. Vybrat více souborů, ukázat jednotlivé průběhy, chyby a seznam již uložených
   originálů. Upload sám provede **nula AI volání a nevloží extrakční job**.
   Úspěšně uložené soubory musí přežít obnovu stránky; nedokončený přenos se
   nezobrazuje jako uložený. Soubor s chybou nevrací zpět úspěšné uploady.
5. Před spuštěním lze soubor odebrat a doplnit jiný. Prázdnou dávku nelze spustit.
   Probíhající upload musí doběhnout nebo být odstraněn ze seznamu.
6. „Spustit vytěžování N dokladů“ uzamkne složení a nastavení dávky, ukáže
   skutečně nakonfigurovaný model a založí běhy/joby. Dvojklik je idempotentní.
   Žádný další souhlasový checkbox.

Duplicitní soubor: dnešní `duplicate?/1` pouze varuje a nebrání vložení. Pro
novou dávku navrhujeme stejný hash uvnitř dávky nepřidávat podruhé; opakování
uploadového požadavku vrátí existující položku. U shody s jinou dávkou/dokladem
zobrazit odkaz a stav, standardně nový doklad vynechat. Pokud jej obsluha vědomě
potřebuje znovu, samostatná akce „Přesto přidat“ bez checkboxu. Srovnávat v cílové
firmě; jde o shodu souboru, ne důkaz totožnosti dvou různých fotek téže účtenky.
Stávající jednotlivé uploady nemusí měnit své chování.

### Zpracování na pozadí a upozornění

Po spuštění zobrazit počty: čeká / zpracovává se / vytěženo / chyba. Zavření
prohlížeče nesmí zastavit joby. Neposílat všechny doklady jedním AI dotazem:
každý používá vlastní současný bezpečný tok a vlastní historii.

Kontrolní průchod dávkou se zpřístupní, až všechny její první běhy skončí
úspěchem nebo chybou. Upozornění např. „Dávka Kartou je připravena ke kontrole:
18 vytěženo, 2 vyžadují zásah“ zůstane v přehledu přijatých dokladů i po návratu
uživatele, nebude to jen pomíjivý flash. Pokud selže všechno, nabídnout řešení
chyb, nehlásit úspěšné vytěžení. Čekající nebo běžící job nelze počítat za hotový.

Přehled dávky během běhu umožňuje vidět průběh a důvody chyb; nenabízí postupnou
kontrolu dříve. Při startu průchodu kontrolou znovu ověřit připravenost na serveru.
Následné ruční opakování jednoho dokladu z již připravené dávky neuzamkne znovu
kontrolu ostatních; blokuje práci jen na tom konkrétním dokladu.

### Postupná kontrola a odeslání

- Otevřít první nevyřízený doklad; stabilní pořadí uploadu, ukazatel „3 z 20“,
  stav a přehled zbývajících. Filtrovat nevyřízené, chybné/odložené a odeslané.
- Na větší obrazovce originál vedle formuláře, na malé dostupný přepínač/náhled.
  Umožnit přiblížení originálu pro čísla v patičce. Znovu použít současnou logiku
  hlavičky, DPH, účetního předpisu, instrukcí, historie a chyb.
- Akce „Uložit“, „Předchozí“, „Další“, „Odložit“ a „Nahrát do ABRA a pokračovat“.
  Přechod s neuloženou změnou nabídne uložit / zahodit / zůstat. Nezavádět tiché
  ukládání nevalidních účetních dat ani opakované potvrzování každého pole.
- „Nahrát do ABRA a pokračovat“ je výslovná akce pro aktuální doklad. Navazuje na
  stávající uložení/validace a přenosové guardy. Při neuložených hodnotách
  vyžádá jejich uložení; při chybě zůstane na dokladu. Na další přejde až po
  potvrzeném stavu `sent`, nikoli po pouhém zařazení jobu do fronty.
- Stav `uncertain` viditelně nabídne ověření ABRA bez nového POSTu. Uživatel může
  doklad odložit a pokračovat, ale aplikace jej nesmí vykazovat jako odeslaný.
- Odložený doklad zůstává v DB, dávce a seznamu k dořešení; nejde o schválení,
  smazání ani úspěch. Odeslané doklady lze prohlížet, ne znovu upravovat/odesílat.
- U chyby AI nabídnout existující ruční vyplnění, nový úplný běh nebo obsahové
  opakování, pokud je dostupná identita. Nevracet potichu neúspěšný cílený výsledek
  na obecný odhad. Úprava dodavatelských instrukcí ovlivní až nově vytvořené běhy.
- Kontrola má skončit přehledem skutečně odeslaných a nevyřešených dokladů.
  „Vytěžování dokončeno“ a „vše odesláno“ musí být dva různé údaje.

## 4. Návrh implementace

### 4.1 Data a oddělení uploadu od spuštění

Přidat aditivní Ecto migraci pro `incoming_document_batches`: UUID, název,
agendu, snapshot cíle (`base_url`, `company_id`), společné účetní nastavení,
volbu rozsahu vytěžení, zamýšlený model, `started_at`, `extraction_finished_at`,
časová razítka a případné soft-delete. Hesla/klíče do snapshotu nepatří.

Na doklad přidat nullable `batch_id`, `batch_position` a případné `deferred_at`.
Dávka seskupuje samostatné `Document`, nevlastní kopie jejich výsledků ani
originálů. Starší dokumenty mají `batch_id = NULL`; nezakládat jim dávky zpětně.
FK, index dávky a unikátní pořadí v dávce vynutit v DB. Zachovat namespace cíle
při vytvoření/přiřazení dokladu, nepřesouvat doklady mezi firmami.

Přidat jasný stav dokladu pro uložený originál před spuštěním (návrh `staged`),
včetně DB constraintu. Dnešní `uploaded` znamená čekání na worker a UI jej
považuje za busy; nepoužít jej pro neomezeně rozpracovaný upload. Nový stav musí
řešit i seznam, detail, guardy, odebrání a kompatibilita starých jobů.

Rozdělit v kontextu uložení originálu od zahájení běhu. Zachovat současné
`upload` API pro jednotlivý doklad jako složení obou kroků. Návrhy nových API:
`create_batch`, `add_batch_source`, `remove_batch_source`, `start_batch`,
`batch_progress`, `list_batch_documents`, `defer_document`.
Logiku nenechávat v LiveView.

Při spuštění pod zámkem dávky ověřit stav, soubory, cílovou firmu a AI konfiguraci.
Založit běhy a Oban joby atomicky se změnou stavu dávky, bez síťových požadavků
v transakci. Pro omezenou dávku stačí jedna transakce; selhání zařazení nesmí
zanechat půl dávky spuštěné. Souběžné přidání/odebrání používá stejný zámek.
Nenačítat všechny binární originály do jedné velké kolekce jen pro start.

Společné účetní nastavení připravit validovaně před startem, kopírovat do dokladů
jako snapshot. Nenahrávat účetní číselník jednou pro každý doklad.
`save_accounting/3` dnes pracuje pouze v `review`/vybraném `failed` stavu;
není hotovým API pro nastavení dávky. Sdílet jeho validátory, neobcházet je.

Model pro dávku připnout při explicitním startu do všech prvních běhů a používat
jej i při přípravě obrázků a všech fázích. Aktuální kód jej připíná až při první
rezervaci; tuto mezeru pro čekající dávky odstranit. Změna env při restartu nesmí
část již spuštěné dávky skrytě převést na jiný model. Obecné instrukce a schémata
snapshotovat při založení běhu; profil dodavatele až při jeho identifikaci,
stejně jako dnes. Změna profilu může ovlivnit dosud neidentifikované doklady,
nikoli už uložený snapshot; revizi zobrazovat pro každý doklad zvlášť.

### 4.2 Fronta, obnova a konec dávky

Dnes `IncomingDocumentWorker` běží ve frontě `billing` s paralelismem 2,
společně pro extrakci i přenos. Pro nové extrakce oddělit frontu (návrh
`incoming_extraction`, zpočátku souběh 2); účetní odesílání nechat nezávislé.
Zachovat zpracování již existujících jobů a dosavadní ochrany rezervací/generací.
Neimplementovat smyčku, která znovu vytěží celou dávku při jedné chybě.

HTTP chyby a nejasné rezervace zůstávají viditelné u konkrétního běhu.
Respektovat limity poskytovatele; žádné skryté opakování placeného požadavku.
Samotný Oban retry může pokračovat jen dosud nerezervovanou fází. Nový placený
pokus vyvolává obsluha a založí novou generaci konkrétního dokladu.

Konec dávky odvodit ze stavů všech jejích prvních běhů, ne z počtu úspěchů
ani bezpodmínečného inkrementu čítače. Souběžná poslední dokončení musí nastavit
`extraction_finished_at` idempotentně. Pozdní výsledek staré generace nesmí
přepsat stav novějšího běhu ani znovu oznamovat dokončení dávky.

Zahrnout i havárii procesu/uzlu a vyčerpaný či zrušený Oban job: po obnovení
aplikace se DB stav musí srovnat s joby. Vyřešit dohled/reconciliation, který
po prokazatelném ukončení jobu označí rozpracovaný běh jako přerušený, bez nového
AI volání. Pouhé stáří řádku není důkaz, že stále běžící HTTP požadavek skončil.
Pád při zápisu posledního výsledku nebo ztracená notifikace nesmí nechat dávku
navždy čekat; souhrn lze znovu odvodit z DB.

### 4.3 Rozhraní, upozornění a dotazy

Navržené routy jsou `/admin/incoming-document-batches`, detail `/:id` a kontrola
`/:id/review/:document_id`. Umístit do stávající admin PIN session; ověřit,
že kontrolovaný doklad opravdu patří dávce. Přímé současné routy zachovat.
Znovu použít kontext/formulář, nevytvářet druhou implementaci účetního workflow.

PubSub může po commitu signalizovat změnu; DB je zdroj pravdy. Po reconnectu
načíst souhrn znovu a případně použít omezený fallback polling. Upozornění na hotové
dávky odvodit z uloženého stavu v přehledu přijatých dokladů/dávek, takže přežije
odchod ze stránky. Nepřidávat e-mail, push ani uživatelské účty kvůli notifikacím.

Stavy ostatních dokladů nesmějí znovu inicializovat právě otevřený formulář.
Zachovat focus, neuložené hodnoty a otevřené `<details>`/picker; aktualizovat jen
příslušné assigny/řádky. Načítání dalšího dokladu resetuje data vědomě až při
navigaci. Select nad 30 položek musí používat vyhledávání.

Souhrnné počty získat agregací, seznam stránkovaným omezeným dotazem bez
`original`, XML a velkých JSON/raw odpovědí. Fáze načíst joinem/omezeným preloadem,
ne voláním `get!` a načítáním historie pro každý řádek. Originál načítat až pro
otevřený doklad ze soukromého endpointu, nikoli 50 base64 náhledů do LiveView.
Počet dotazů pro stránku nemá růst s počtem dokladů. Při zjištění skutečného
N+1 postupovat podle AGENTS.md; tento plán nepředjímá výjimku z jeho pravidla.

## 5. Implementační kroky další etapy

- [x] Načíst tento plán, AGENTS.md a návod; fetch aktuálního `origin/main`, ověřit
  stav PR #100 a navázat na skutečně dodaný kód. Pokud je PR sloučený, nová větev
  z main; pokud není, zachovat jeho změny a nesouběžně je nepřepisovat.
- [x] Migrace dávek, nullable vazby/pořadí, stavu před spuštěním a indexů.
- [x] Rozdělení uložení originálu a startu, idempotentní víceupload, duplicity,
  částečné chyby uploadu a společné účetní nastavení.
- [x] Atomický start dávky, snapshot modelu, oddělená fronta a kompatibilita jobů.
- [x] Agregace výsledků, trvalé dokončení a obnova po havárii bez opakování AI.
- [x] Přehled dávek, průběh uploadu/zpracování a trvalé upozornění po dokončení.
- [x] Postupný kontrolní průchod nad současným formulářem, ochrana změn,
  odložení, návrat a přechod po úspěšném individuálním přenosu do ABRY.
- [x] Přidat cílené regresní testy níže, zkontrolovat query chování a formátování/kompilaci
  podle AGENTS.md. Lokální testy jen dle jeho výjimek; ostatní ověří CI.
- [x] Aktualizovat uživatelský návod a tento plán podle skutečné implementace.
- [ ] Ruční pilot několika dávek všech tří kategorií včetně chyby a návratu
  po zavření stránky; zaznamenat rychlost kontroly, přesnost a usage.

## 6. Ověřovací scénáře a podmínky přijetí

Testy AI a ABRA přes Req.Test, žádná skutečná placená volání ani účetní zápisy.
Použít syntetické podklady bez soukromých účtenek v repozitáři.

1. Nahrání několika souborů samo nevytvoří AI request ani extrakční job.
   Refresh zachová úspěšné originály; vadný/velký soubor nezničí ostatní.
2. Dvojklik startu, souběžné starty a opakovaný upload nevytvoří duplicitní
   dokument/běh/job. Konflikt vložení jobu vrátí celou startovací transakci.
3. Kategorie určuje správnou agendu/šablonu a společný předpis. Individuální
   změna neovlivní další doklady. Žádné společné interní číslo ani změna cílové firmy.
4. Každý doklad dostane pouze svůj originál a správný profil; žádná data jiného
   dokladu v promptu. Bez profilu dvě volání, s instrukcemi tři, položky vypnuté.
5. Skutečný model odpovídá snapshotu startu, i po restartu se změněnou env.
   Identifikace, obsah, cílená fáze i příprava obrazů respektují stejnou volbu.
6. Smíšený výsledek (úspěch, neúplná data, HTTP chyba, přerušená rezervace)
   dokončí dávku po ukončení všech běhů a správně rozdělí počty. Totéž při samých
   chybách. Běžící/čekající dokument nezpřístupní kontrolu celé dávky předčasně.
7. Restart workeru, vyčerpaný job, ztracený PubSub event a pád při označení konce
   dávky se dají obnovit z DB; žádný automatický opakovaný placený request.
8. Retry jedné položky připravené dávky nemění hotové návrhy ostatních. Pozdní
   odpověď a duplicitní notifikace nevytvoří druhý výsledek nebo falešné počty.
9. Postupná kontrola zachová pořadí, odložení a uložené opravy po návratu.
   Polling/PubSub nezavírá editor ani nepřepisuje neuložené hodnoty/focus.
   Ověřit také v prohlížeči, nejen porovnáním HEEx atributů v testu.
10. Odeslání je individuální; navigace až po `sent`. Chyba zůstane viditelná,
    `uncertain` pouze ověřuje externí ID, opakovaný klik nevyvolá druhý POST.
    Odeslaný doklad je neměnný. Žádné souhlasové checkboxy nepřibudou.
11. PIN chrání seznamy, detail, akce i originály; cizí document ID v routě dávky
    se odmítne. Starší jednotlivé/ruční doklady a existující joby dál fungují.
12. Počet dotazů při zobrazení stránky je konstantní; binární originály a velké
    výsledky se nenačítají do seznamu. Účetní číselník se nestahuje pro každý řádek.

Hotovo znamená: obsluha připraví dávku, spustí ji jednou, může odejít, po návratu
vidí skutečný souhrn a až po ukončení všech prvních běhů postupně projde návrhy
i chyby. Každý účetní zápis zůstává vědomou akcí pro konkrétní doklad a žádná
chyba jednoho dokladu nevyžaduje nové vytěžení celé dávky.

## 7. Mimo tuto etapu a zbývající nejistoty

Mimo rozsah: více fotek jednoho dokladu, rozdělování PDF, AI určování kategorie,
položkové účtování, automatické schválení/odeslání, externí notifikace, OpenAI
Batch API, vlastní registr kategorií, automatické učení instrukcí, ARES a
automatické zakládání partnerů ABRA. „Dávka“ je aplikační skupina samostatných
běhů přes dnešní Responses API, nikoli změna API poskytovatele.

Potvrzené produktové otázky jsou uzavřené. Pilot má ověřit rozumný počet souborů,
souběh, cenu opakovaných obrazových vstupů, přesnost a pohodlí kontroly.
Před plošným použitím zkontrolovat paměť při nahrávání a růst DB s originály;
pro tento objem zatím zachovat soukromé DB úložiště, neplánovat nevyžádanou
migraci na externí storage. Pouhá shoda hashe neodhalí různé fotky stejného dokladu.

## 8. Mapa kódu pro pokračování

| Soubor | Co zde hledat / změnit |
| --- | --- |
| `lib/cozy_checkout/incoming_documents.ex` | Upload spojený se startem, seznam omezený na 100, uložení/přenos/účetní nastavení |
| `lib/cozy_checkout/incoming_documents/document.ex` | Doklad, soukromý originál, stavy, nová vazba na dávku |
| `lib/cozy_checkout/incoming_documents/extraction_runs.ex` | Zámky, generace, snapshoty, start_locked, rezervace, dokončení/chyby |
| `lib/cozy_checkout/incoming_documents/extraction_run.ex` | Schéma historie běhu |
| `lib/cozy_checkout/incoming_documents/extractor.ex` | Responses API a tři oddělené kontrakty |
| `lib/cozy_checkout/incoming_documents/source_images.ex` | Originál/výřezy, příprava podle modelu |
| `lib/cozy_checkout/incoming_documents/supplier_task.ex` | Řídká cílená odpověď, citace a slučování |
| `lib/cozy_checkout/incoming_documents/accounting.ex` | Validace a převzetí účetního předpisu |
| `lib/cozy_checkout/incoming_documents/header_form.ex` | Hlavička, souhrnná DPH a validace XML |
| `lib/cozy_checkout/workers/incoming_document_worker.ex` | Sdílená billing fronta, bezpečné zachycení výjimek |
| `lib/cozy_checkout_web/live/incoming_document_form_live.ex` | Aktivní seznam/detail, upload, dirty stav, polling, editor a historie |
| `lib/cozy_checkout_web/router.ex` | Aktivní routy pod admin PIN |
| `config/config.exs`, `config/runtime.exs` | Oban fronty a skutečná konfigurace AI/ABRA |
| `test/cozy_checkout/incoming_documents/extraction_runs_test.exs` | Rezervace, chyby, source/model, snapshoty, souběh a query testy |
| `test/cozy_checkout_web/incoming_document_form_live_test.exs` | Formulář, ochrana oprav, otevřené sekce, přímé akce |

`IncomingDocumentsLive` je starší implementace bez aktivní routy; novou kontrolu
nestavět omylem na něm. Přehled v tabulce je mapa, ne požadavek rozšiřovat jeden
velký LiveView: nové dávkové kontexy/komponenty mohou současný formulář sdílet.

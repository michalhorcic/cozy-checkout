# Dvoufázové vytěžování a instrukce podle dodavatele

- **Stav:** implementováno ve větvi; čeká na CI a provozní pilot.
- **Vytvořeno / aktualizováno:** 5. / 6. 11. 2026.
- **Zadání:** nejdříve rozpoznat dodavatele, potom vytěžit doklad s jeho uloženými
  instrukcemi; instrukce editovat přímo ve formuláři přijatého dokladu.
- **Podklad:** větev `codex/prijate-doklady-formular`, implementace do commitu
  `f377546`, [PR #99](https://github.com/michalhorcic/cozy-checkout/pull/99).
- **Současný návod:** [Formulář přijatého dokladu](../features/INCOMING_DOCUMENT_FORM.md).
- Původní plán níže popisuje výchozí stav před implementací. Aktuální postup,
  migraci a ověřovací limity popisuje návod a předání v části 13.

## 1. Problém a výsledek

Dodavatele OpenAI podle dosavadní zkušenosti uživatele poznává spolehlivěji než
rekapitulaci DPH a jednotlivá data. Stejní dodavatelé posílají opakující se formáty,
ve kterých se opakují stejné chyby. Chceme postupně opravovat zadání čtení pro
konkrétního dodavatele, bez ručního přepisování obecných instrukcí pro všechny.

Výsledkem má být tento průchod:

1. Obsluha nahraje PDF/obrázek a vybere agendu jako dnes.
2. Malý první dotaz přečte pouze identitu dodavatele.
3. Server podle identity a cílové firmy vybere uložené instrukce.
4. Druhý dotaz znovu dostane originál, společné zadání a snapshot instrukcí.
5. Stávající formulář nabídne výsledky k opravě, včetně předvyplnění DPH a dat.
6. V nové sekci lze upravit instrukce pro příště nebo je uložit a zopakovat
   vytěžení aktuálního dokladu.

Model zůstává čtečkou originálu. Instrukce nevytvářejí účtovací pravidla,
neschvalují doklad a nespouštějí ABRA. Zápis do účetnictví zůstává ruční akcí.

## 2. Co už máme a na co navázat

| Oblast | Současná implementace | Dopad nové funkce |
| --- | --- | --- |
| Upload, soukromý originál, hash, cílová firma | `IncomingDocuments.upload/4`, `Document` | Zachovat stejné soubory a limity; identita se vztahuje ke konkrétnímu originálu |
| Fronta a opakování | `IncomingDocumentWorker`, `perform/2`, `transcribe/3` | Doplnit dvoufázový průchod pro `header_form`, oddělit běhy a fáze |
| OpenAI | `Extractor.extract/4`, Responses API, Req, `store=false` | Přidat identifikační kontrakt a sestavení druhého zadání |
| Výstup do formuláře | `Transcription.schema/0`, `validate/1` | Druhá fáze dál vrací tento kontrakt, neměnit účetní XML ani JSON API |
| Zadání | `priv/incoming_documents/extraction_instructions_form.md` | Zůstává společný základ; dodavatelský text je řízený doplněk |
| Datové návrhy | `HeaderForm`, `FormSuggestions` | Dál řeší přiřazení polí, souhrny a návrhy dat deterministicky |
| Administrace | `IncomingDocumentFormLive` | Sekce dodavatele, editor, stav a oddělené akce uložení/opakování |
| Odesílání | `ImportPayload`, `Client`, `send_header/3` | Formát JSON, externí ID, kontrola duplicit a zmrazení přenosu zůstávají |
| Současné pokusy | `extraction_attempts`, `extraction_metadata.calls` | Dosud jedna fáze; prosté zvýšení `max_attempts` na 2 neimplementuje dvě různé fáze |

`header_form` nyní dovoluje jedno volání na vytěžení. Skrytý starší režim
`structured` má dvě a `simple_xml` jedno. Oban worker má tři pokusy, což není
povolení třikrát zopakovat placené volání OpenAI. Nový návrh musí toto rozlišit.

V prohledaných kontextech není samostatný registr dodavatelů přijatých dokladů.
`Billing.profile` popisuje naši firmu a `Inventory.PurchaseOrder.supplier_note`
je textová poznámka; ani jedno nepoužít jako číselník protistran.

Uživatel již potvrdil zlepšení přenosu přes JSON i předvyplňování. Nejde o nový
výsledek automatických testů nebo živé kontroly ABRA provedené při psaní plánu.
Historický [plán MVP](2026-11-05-prijate-doklady.md) obsahuje dřívější rozhodnutí;
aktuální datový a přenosový postup popisuje odkazovaný návod formuláře.

## 3. Rozsah a návrhová rozhodnutí

### Součást první etapy

- Dvě jasně oddělené fáze pro nový formulář `header_form`.
- Profily dodavatelů s editovatelnými instrukcemi a revizí.
- Přesné párování primárně podle IČO; bezpečný obecný postup při nejistotě.
- Snapshot použitého zadání a výsledku obou fází pro každý běh.
- Ruční výběr/oprava dodavatele a opakování druhé fáze s novými instrukcemi.
- Srozumitelný stav, chybové hlášení a náklady obou volání v administraci.
- Zachování původních výsledků a ochrana před pozdní odpovědí starého běhu.

### Mimo první etapu

ARES, automatické zakládání partnerů v ABRA, fuzzy spojování firem, automatické
učení instrukcí z oprav, více modelů, prompt management mimo aplikaci, automatické
účetní předpisy a schvalování, položkové účtování, pravidla podle typu dokumentu
uvnitř jednoho dodavatele, hromadné zpětné vytěžování a nový samostatný registr UI.
Žádné automatické přepisování historických nebo odeslaných dokladů.

| Rozhodnutí | Zdroj / charakter |
| --- | --- |
| První dotaz dodavatel, druhý samotné vytěžení | Návrh uživatele odsouhlasený v chatu |
| Instrukce uložené v DB a editovatelné u formuláře | Požadavek uživatele |
| IČO jako hlavní klíč, název jen pomocný | Technický návrh rozvedený níže |
| Instrukce ovlivňují čtení, nikoli účetní výpočty a ABRA | Navazuje na odsouhlasený rozsah formuláře |
| Přesný snapshot zadání a běhy místo přepisování historie | Technický návrh pro dohledatelnost a obnovu |
| Profily oddělené pro každou cílovou firmu ABRA | Navržený výchozí rozsah, nikoli dříve potvrzený obchodní požadavek |

## 4. Rozpoznání a párování dodavatele

### Kontrakt první fáze

Přidat samostatný `SupplierIdentity` kontrakt se striktním JSON schématem:
`name`, `ic`, `dic`, `country_code` jako nullable string, `ambiguous` jako boolean
plus `uncertainties` jako pole textů. Instrukce mají výslovně rozlišovat vystavitele
od odběratele, banky, zprostředkovatele plateb a značky prodávaného výrobku.
Nepotřebujeme položky, data ani DPH. Nepoužívat modelové číselné skóre důvěry jako
jediný podklad automatického párování. Výsledek ověřit lokálně stejně jako dnes
`Transcription`, včetně limitů délky a typu, bez dynamických atomů.

### Pravidla identity

1. Zachovat počáteční nuly; IČO je řetězec. Odstranit pouze povolené mezery a
   popisek, ne libovolné znaky. U českého IČO ověřit osm číslic a kontrolní součet.
2. Vyhledávat ve stejném rozsahu cílové firmy a země. Platné IČO + shoda jediného
   aktivního profilu dovoluje použít jeho instrukce, pokud identita není sporná.
3. DIČ normalizovat na velká písmena bez mezer. Nerozebírat české DIČ fyzické osoby
   na domnělé IČO. Při rozporu IČO a uloženého DIČ nepoužít profil automaticky.
4. Samotný název nestačí k automatickému použití uložených instrukcí. Lze podle
   něj nabídnout kandidáty k ručnímu výběru. Neprovádět automatické slučování.
5. Pokud nelze bezpečně určit zemi/identitu, nebo první výsledek označuje více
   dodavatelů, pokračovat druhým dotazem se společným zadáním bez zvláštních
   instrukcí. U formuláře zviditelnit důvod; nedělat třetí automatický dotaz.
6. Platný výsledek „neznámý dodavatel“ je jiný než HTTP chyba nebo poškozený JSON.
   Při selhání volání první fáze viz pravidla obnovy níže.
7. Druhý výsledek nesmí skrytě přepsat vybranou identitu. Zjistí-li jiné IČO/DIČ,
   zobrazit rozpor, nepřepojovat profil ani nic v něm neukládat. Vyžádat kontrolu
   před použitím výsledku; žádné automatické odeslání do ABRA.

První implementace může automaticky párovat jen validní česká IČO. DIČ jako
náhradní klíč profilu musí být výslovně potvrzené obsluhou; bez něj lze použít
obecné vytěžení. Rozšíření na zahraniční identity není podmínkou pilotu.

## 5. Datový model a migrace

Použít Ecto migrace, UUID, UTC časová razítka, FK a databázové constrainty.
Názvy níže jsou návrh pro implementaci, nikoliv existující tabulky.

### `incoming_supplier_profiles`

| Pole | Význam |
| --- | --- |
| `id` | UUID profilu |
| `base_url`, `company_id` | Namespace cílové ABRA, převzatý z uloženého dokladu |
| `country_code`, `identity_kind`, `identity_value` | Normalizovaná země a klíč `ic`/ručně potvrzené `dic` |
| `name`, `ic`, `dic` | Zobrazovaná identita; žádné odhadované doplňování z názvu |
| `instructions` | Prostý text, navržený limit 8 000 znaků |
| `revision` | Celé číslo pro optimistický zámek, zvýšit při každé změně |
| `deleted_at`, timestamps | Vyřazení bez ztráty návaznosti historie |

Normalizovat základní URL konzistentně se stávající konfigurací (např. koncové
lomítko), nevyvozovat shodu různých hostů. Aktivní unikátní index:
`(base_url, company_id, country_code, identity_kind, identity_value)` s podmínkou
`deleted_at IS NULL`. Stejné IČO nemá mít v jednom namespace více aktivních profilů.
Při souběžném prvním uložení využít constraint a vrátit srozumitelnou kolizi.
Prázdné instrukce znamenají společné zadání; neukládat automaticky prázdné profily
pro každého neznámého dodavatele. Profil vzniká až výslovným uložením obsluhou.

### `incoming_extraction_runs`

Jeden záznam pro každý nový běh, včetně opakování. Navržená pole:

- `id`, `document_id`, `generation`, `mode` (`identify_and_extract` / `extract_only`).
- `source_sha256`, snapshot cílové firmy, `strategy`, stav a `active_step`.
- Výsledek identifikace, normalizovaná identita, způsob výběru (`exact_ic`,
  `manual`, `none`) a nullable `supplier_profile_id`.
- `profile_revision`, **plné znění** použitých dodavatelských instrukcí a hash.
- Přesné společné zadání nebo jeho obsahový snapshot, jeho verze/hash a verze
  výstupních schémat; nestačí jen odkaz na aktuální soubor v `priv`.
- Oddělená metadata obou fází: model, stav, rezervace/attempt token, časy,
  počet pokusů, HTTP stav, bounded raw output, usage a srozumitelná chyba.
- Výsledek druhé fáze, a snapshot předchozího pracovního návrhu při ručním
  opakování, aby opravy nebyly nevratně ztraceny.
- Timestamps; dokončené výsledky běhů a snapshoty dále nepřepisovat.

Na `incoming_documents` přidat nullable `active_extraction_run_id`. Jednoznačně
indexovat generaci v rámci dokladu; FK musí mířit na běh téhož dokladu (constraint
nebo ekvivalentně vynucená vazba, ne jen volný UUID bez ověření). Výběr profilu
aktuálního běhu lze číst přes tuto vazbu; neduplikovat jej nezávisle ve třech místech.

Staré doklady mají vazbu null. Nezakládat jim zpětně fiktivní běhy ani nevolat AI.
Při nasazení zohlednit již zařazené Oban joby bez `run_id`: buď je dokončit
starou větví, nebo pod zámkem jednoznačně převést na nový běh před prvním AI
voláním. Chybějící argument nesmí při každém Oban retry vytvářet další běh.

Původní `extracted_data`, `edited_data` a XML dál slouží aktuálnímu formuláři.
`extraction_metadata` může obsahovat stručný kompatibilní přehled, zdrojem pravdy
pro nový proces je běh. Nezdvojovat do něj všechny binární originály.

## 6. Orchestrace dvou dotazů a obnova

Přidat samostatnou větev orchestrátoru pro `header_form`; nesnažit se nový tok
implementovat obecnou smyčkou stávajícího `transcribe/3`. Staré strategie zachovat.
Návrh rozdělení: `SupplierIdentity`, `SupplierProfiles`, `ExtractionRun`, rozšířený
`Extractor` a kontextové orchestrace v `IncomingDocuments`. Doménová logika
nepatří do LiveView.

### První běh

1. V krátké transakci zamknout doklad, ověřit, že nemá `sent_xml` ani aktivní
   kolidující operaci, založit běh a nastavit aktivní generaci. Job obsahuje
   `document_id` i `run_id`; uniqueness musí rozlišovat běhy a zároveň nedovolit
   dva aktivní běhy stejného dokladu.
2. Připravit obrazové vstupy přes `SourceImages`; pro obě fáze použít stejný
   privátní originál. Výřezy lze v jednom workeru sdílet v paměti. Po restartu je
   případně znovu vytvořit z téhož souboru, nikoliv z jiného uploadu.
3. Rezervovat identifikační volání pod zámkem; síťový požadavek provést mimo
   transakci. Použít stejný konfigurovaný model, malý výstupní limit (návrh 2 000
   tokenů), krátké zadání, `store=false`, bez automatického HTTP retry.
4. Uložit výsledek pouze při shodě `run_id`, fáze, tokenu rezervace a source hashe.
5. Vybrat profil podle části 4. Bezpečně načíst jednu revizi a uložit její text
   do běhu **před** rezervací druhého volání. Změna profilu během volání již
   nesmí změnit toto zadání. Při změně cílové konfigurace firmy nepoužít pravidla
   jiné firmy; zachovat stávající ochranu cíle.
6. Rezervovat druhé volání a odeslat společné zadání + snapshot instrukcí +
   identitu jako kontext + originál. Výstupem je dnešní striktní `Transcription`.
7. Zkontrolovat strukturu, případný rozpor identity a předat výsledky stávajícím
   `HeaderForm`/`FormSuggestions`. Neúplné faktické údaje jsou editovatelný návrh,
   ne důvod automaticky volat třetí dotaz. XML vzniká uložením formuláře jako dnes.
8. Dokončit běh a přepsat aktuální návrh jen při shodě aktivní generace. Pozdní
   výsledek lze uchovat v historii, nikdy jím nepřepsat nový běh nebo odeslaný doklad.

### Limity, chyby a opakování

- Základní běh má nejvýše jedno volání identifikace a jedno vytěžení. Oba pokusy
  se evidují samostatně; pouhý čítač 2 nezabrání dvěma totožným voláním.
- Rozlišit Oban retry od nového běhu vyvolaného uživatelem. Dokončená identifikace
  se při obnově nezopakuje, pokračuje se následující dosud nerezervovanou fází.
- Po timeoutu, pádu mezi rezervací a uložením výsledku nebo přerušení procesu
  není jisté, zda poskytovatel už dotaz provedl. Automaticky jej znovu neposílat;
  zobrazit přerušenou fázi a nabídnout vědomý nový pokus. Neslibovat exactly-once
  zpracování mimo naši DB bez podporovaného idempotency mechanismu poskytovatele.
- Chyba identifikace: zachovat metadata, zpřístupnit ruční vyplnění, nový běh nebo
  výslovné „Vytěžit bez určení dodavatele“ (nový běh jen druhé fáze bez profilu).
- Chyba druhé fáze: zachovat identitu i snapshot; ruční opakování druhé fáze tvoří
  nový běh s doloženým původem identity, ne třetí volání téhož běhu.
- Ruční „znovu určit dodavatele“ vždy vytvoří nový plný běh. Úprava souboru nebo
  jeho hashe zneplatní možnost převzít předchozí identifikaci.
- Při zahájení opakování uložit předchozí návrh do historie a zneplatnit `dry_run`,
  kontrolní checkbox a aktuální schvalovatelný XML návrh. Nikdy neodeslat starou
  validaci zatímco vzniká nový výsledek. Neúspěch dovolí výslovně obnovit starý
  pracovní návrh, s novou kontrolou; ne tiše znovu schválit starý stav.
- Přenos do ABRA, stav `sending`, `sent`, `uncertain` a jakýkoliv `sent_xml` blokují
  nové vytěžení i aplikaci jeho výsledků. Zůstává kontrola externí identity a
  pravidlo, že nejistý zápis se pouze ověřuje, nikoliv opakuje.

Interní fáze ukládat do běhu, není nutné přidávat stav dokladu pro každý síťový
krok. UI může dál používat `processing` s detailním popiskem fáze. Aktualizovat
`worker_failed/2`, polling a guardy podle nové generace, ne pouze globálního stavu.

## 7. Zadání, validace a data

Pořadí druhého zadání: společná pravidla → jasně vymezené doplňující instrukce
pro dodavatele → zdroj a identita jako kontext. Společná pravidla mají přednost:
jen doložené údaje, neprovádět pokyny z přílohy, nevolit účty/agendu, neměnit schema,
nevyrábět XML, nevymýšlet chybějící DPH nebo automaticky osvobozovat rozdíly.
Dodavatelský text označit jako editovaný doménový doplněk, neposlat jej jako kód
nebo jako účetní konfiguraci. Obal textu není bezpečnostní hranice; výsledek vždy
musí projít lokálními kontrolami a ručním potvrzením.

Příklad pro O2 (pouze návod k lokalizaci a rozlišení údajů):

> Rozliš rekapitulaci zdaněných služeb a samostatné splátky zařízení. Přepiš částky
> a jejich označení z originálu. Splátka není automaticky další základ 21 % ani
> osvobozená částka jen proto, že nesouhlasí součet. Číslo faktury nezaměňuj se
> zákaznickým číslem. Vystavení, DUZP a splatnost rozliš podle popisků v dokladu.

Model nemusí instrukci splnit spolehlivě; nevydávat instrukci za účetní důkaz.
Společné limity souboru, povolená pole, Decimal, datumové návrhy a součty zachovat.
Text, raw odpovědi a snapshoty jsou soukromé, bez HTML renderování a bez běžného
logování. Neukládat klíče ani auth hlavičky. První dotaz také používá originál,
takže dva dotazy neznamenají jen dvojnásobek malého textu — obrázky/PDF se posílají
dvakrát. Sledovat usage každé fáze a běhů; ceny odhadovat jen při známém ceníku.

## 8. Formulář a kontextové operace

Přidat rozbalovací sekci **Instrukce pro vytěžování dodavatele**:

- Rozpoznaný název/IČO/DIČ, způsob přiřazení, případné nejasnosti a cílová firma.
- Rozlišit „neznámý dodavatel“, „známý bez instrukcí“ a „použita revize N“.
- Vyhledatelný výběr existujícího profilu a možnost potvrdit identitu pro nový.
  Použít stávající searchable picker, zejména nad 30 položkami.
- Prostý textarea editor, délka, stav neuložených změn a aktuální revize.
- **Uložit instrukce pro příště:** pouze změní profil; nevolá AI, neruší již
  uložený návrh a nepřepisuje doklady téhož dodavatele.
- **Uložit instrukce a znovu vytěžit:** nejprve uloží přes konkrétní revizi,
  potom založí běh `extract_only` s novým snapshotem. Druhá fáze běží nad stejným
  originálem a výslovně zvolenou identitou. Upozornit na nahrazení ručních oprav
  a zrušení kontroly, stejně jako při dnešním opakování.
- **Znovu určit dodavatele:** nový úplný běh. Žádný skrytý první dotaz při každém
  uložení textu nebo opravě pole.
- Rozlišit text aktuálního profilu a přesné instrukce posledního běhu; nová revize
  sama nemění starý výsledek. Historii běhů zobrazit střídmě, detaily až po rozbalení.

Oprava `nazFirmy`/IČO ve finanční hlavičce sama nesmí ukládat instrukce pod nový
profil ani přepojovat původní profil. Změnu příslušnosti potvrdit odděleně; nový
výběr sám neopraví dodavatele v dokladu a nespustí AI. Nezaměnit identitu vystavitele
s naší firmou či cílem importu. Při neuloženém editoru jasně sdělit, že běh používá
poslední uloženou revizi, nebo akci zablokovat a nabídnout výslovné uložení.

Navržená kontextová API: `identify_supplier`, `resolve_supplier_profile`,
`save_supplier_instructions(expected_revision)`, `start_extraction_run`,
`retry_content_extraction`, `restore_draft_from_run`, `list_extraction_runs`.
Finální názvy přizpůsobit kódu. LiveView jen validuje formulářový vstup a volá kontext.
Uložení profilu a následné založení jobu buď koordinovat transakcí, nebo srozumitelně
vrátit „instrukce uloženy, nové vytěžení se nepodařilo zařadit“; nikdy hlásit spuštění
před úspěšným vložením do Obanu.

Stejný admin PIN jako dnes. Profil je možné upravit pro příští doklady i při
prohlížení odeslaného dokladu, ale opakování/výměna výsledku takového dokladu je
zablokovaná. Bez originálu zůstává ruční formulář funkční a AI akce jsou nedostupné.
Před přenosem blokovat neuložené změny samotného dokladu/účtování; oddělit od
neuloženého globálního textu instrukcí, který uložený účetní payload nemění.

## 9. Dotazy a souběh

- Automatické nalezení profilu: jeden indexovaný dotaz pro konkrétní namespace
  a identitu. Detail: doklad + aktivní běh a případný profil hromadně/preloadem.
- Seznam dokladů dál používá omezený výběr bez originálů a velkých JSON snapshotů;
  nepřidávat načítání profilu či historie pro každý řádek. Historii načíst jedním
  stránkovaným dotazem až pro otevřený doklad, nikoliv opakovaně při pollingu seznamu.
- V implementaci doložit kontrolu N+1. Pokud vznikne a bude potřeba měnit řešení,
  postupovat podle aktuálního AGENTS.md, upozornit a nechat schválit nápravu.
- Dvě otevřená okna editoru: kontrola `revision` a srozumitelná kolize místo last-write-wins.
- Dva workery: DB rezervace každé fáze, aktivní run/generation a unikátní job;
  samotná Oban uniqueness neřeší všechny mezery při síťovém volání.
- Změna profilu ve druhém okně během volání: dokončit starý snapshot, v UI uvést,
  že existuje novější revize. Neprovádět automatické nové vytěžení všech dokladů.

## 10. Implementační kroky

- [x] Ověřit aktuální větev a PR, přečíst tento plán, AGENTS.md a současný návod.
- [x] Migrace profilů, běhů a aktivní vazby; constrainty a kompatibilita starých dat.
- [x] Čisté normalizace identity, kontrakt první fáze, přesné párování a kolize.
- [x] Ukládání instrukcí s revizí a snapshots, bez volání modelu při běžném uložení.
- [x] Oddělené metody Extractoru pro identifikaci a obsah, deterministické zadání.
- [x] Orchestrace: rezervace obou fází, run ID v jobu, obnova, limity, stale výsledky.
- [x] Jeden celý tok s existujícím profilem přes Req.Test; zachovat ABRA a formát výstupu.
- [x] UI profil/editor, výběr, obě akce uložení, phase polling, přehled použité revize.
- [x] Ruční oprava identity, neznámý dodavatel, opakování druhé fáze, obnova návrhu.
- [x] Regrese ručního formuláře, starších strategií a již odeslaných dokumentů.
- [x] Testy včetně souběhu a query chování; formátování podle AGENTS.md.
- [x] Návod skutečně dodané funkce a aktualizace stavu tohoto plánu.
- [ ] Provozní pilot O2 a dalšího dodavatele; vyhodnocení přesnosti, usage a nákladů.

## 11. Ověření a podmínky dokončení

Všechny HTTP testy přes Req.Test, bez živých volání OpenAI, zápisů do ABRA nebo
osobních dokladů ve veřejných fixtures. Výchozí pravidlo AGENTS.md ponechává běh
testů CI; lokální běh jen podle jeho výslovných výjimek. Při psaní tohoto plánu
žádné testy spuštěny nebyly.

### Automatické scénáře

1. Známé validní IČO → přesně dva různé requesty, první bez instrukcí dodavatele,
   druhý s přesným snapshotem; oba `store=false`, stejné zdrojové dokumenty.
2. Neznámý dodavatel → druhá fáze obecná; neplatný/nejednoznačný identifikátor,
   jiné IČO odběratele, shodný název firem a rozpor DIČ nesmějí použít cizí profil.
3. Stejné IČO v jiné cílové firmě nesdílí instrukce; unikátní index drží souběžné
   založení. IČO s úvodní nulou se nepoškodí, DIČ se nepřevádí na domnělé IČO.
4. Dvojklik, dvě okna, změna revize během volání, dva workery a pozdní výsledek
   předchozího běhu nezpůsobí více volání nebo přepis novějšího návrhu.
5. Pád před voláním/po rezervaci/po identifikaci/po výsledku druhé fáze: již
   potvrzené kroky se neopakují, nejasné volání vyžaduje ruční obnovu.
6. Uložit instrukce → nula AI volání. Uložit a znovu vytěžit → jedno obsahové
   volání s novou revizí a bez nové identifikace, pokud platí původ zdroje/identity.
7. Změna source hashe, cílové firmy nebo rozpor nového dodavatele zabrání použití
   nepříslušných instrukcí či aplikaci výsledku.
8. Neúplná faktická data zůstávají editovatelná; invalid JSON, HTTP 429/5xx,
   timeout a odmítnutí poskytovatele mají správnou fázi a nepřidají třetí dotaz.
9. Zneplatnění starého dry-runu při opakování, archivace a vědomá obnova návrhu;
   žádné změny `sent_xml`, přepis odeslaného dokumentu ani opakovaný POST ABRA.
10. Uložení budoucích instrukcí ze sent dokladu změní profil, nikoliv doklad;
    ruční formulář bez souboru funguje bez AI; admin PIN chrání nová data i operace.
11. Text obsahující HTML nebo pokyny k přepsání účtů nemění typy/účty/agendu,
    nezpůsobí vykonání HTML a nezruší lokální kontroly.
12. Seznam a detail nemají N+1; metadata/přístupové logy neobsahují API klíč,
    autorizační hlavičky ani neomezené obsahy souborů.

### Pilot a přijetí

Na několika různých dokladech O2 a alespoň jednom dalším opakujícím se dodavateli
porovnat běžné zadání s uloženými instrukcemi. Zachovat různé doklady pro úpravu
instrukcí a pro ověření, aby se úspěch neměřil jen na jediném opraveném vzoru.
Porovnat správnost identity, DPH, splátky mimo DPH, vystavení/DUZP/splatnosti,
ručních zásahů, času a usage. Instrukce nejsou hotové jen proto, že se uložily.

Hotovo znamená: celý tok proběhne, obsluha umí instrukce upravit bez odchodu
z formuláře, další běh použije správnou revizi a její použití lze zpětně doložit.
Neznámý dodavatel neblokuje obecné vytěžení a chyby nezpůsobí neřízená placená
volání ani ohrožení účetních dokladů. Pilotní zlepšení popsat s konkrétními
omezeními, neslibovat plnou přesnost či automatizaci.

## 12. Nasazení, rizika a otevřené body

Migrace je aditivní, bez zpětného přepisování dokumentů. Zpočátku nevyžaduje jiný
API klíč/model; první fáze má vlastní výstupní limit. Pokud bude potřeba řízené
zapnutí, přidat explicitní konfigurační přepínač pro nový header tok a popsat jeho
výchozí stav, nevyužívat existující čítač pokusů jako neviditelný feature flag.
Návrat na starší aplikaci naplánovat přes vypnutí nového toku a dokončení/ukončení
jeho jobů, ne přes destruktivní mazání tabulek se snapshoty.

Před implementací potvrdit nebo vědomě přijmout navržené výchozí volby:

- Profily izolovat pro cílovou firmu ABRA, nebo mají být někdy sdílené? Návrh je
  izolovat, což lze dodat bez čekání na širší sdílený adresář.
- Má první verze podporovat automatický klíč DIČ i mimo ČR? Návrh je CZ IČO,
  jiné případy ručně; tato otázka neblokuje český pilot.
- Je potřeba oddělit pravidla podle agendy/typu dokladu téhož dodavatele?
  Návrh je zatím jediný text s popsanými výjimkami; další členění až po zkušenosti.
- Doba uchování historie a případné vyřazování profilů se musí sladit s existujícím
  provozním ukládáním účetních podkladů. V první verzi historii automaticky nemazat.

Hlavní rizika: chybná identita vybere špatné instrukce; starší text přestane
odpovídat novému layoutu; dvojí obrazový vstup zvýší cenu a odezvu; dlouhé instrukce
zhorší výkon; nekontrolované retry zvýší počet volání. Omezit je přesným párováním,
snapshoty, editorem s limitem, samostatnými rezervacemi a měřením pilotu.

## 13. Předání implementace

**Dodáno:** migrace `20261106090000`, striktní identita a normalizace, firemně
izolované profily s revizemi, dvoufázový orchestrátor `ExtractionRuns`, samostatné
rezervace placených volání, snapshoty, kompatibilita starších jobů, obsahové
opakování, obecné vytěžení, obnova ručního návrhu a editor ve formuláři včetně
vyhledávání a historie. Nové běhy nemění přenosové JSON/XML kontrakty ABRA.

Přijaty návrhové výchozí volby: namespace cílové firmy, automaticky jen české
IČO, DIČ ručně, jeden text na profil, bez automatického mazání historie. Není
přidán přepínač; každý nový běh `header_form` používá dvě fáze. Uložení profilu a
nového obsahového jobu je jedna transakce. Obnovený návrh nemá schvalovatelné XML,
musí znovu projít kontrolou a uložením formuláře.

**Kontrola N+1:** seznam dokladů zůstává jedním omezeným dotazem bez binárních
originálů. Přesné automatické párování používá jeden indexovaný dotaz. Detail
načítá jeden aktivní běh a jeden profil; historii jedním stránkovaným dotazem
pouze při otevření či změně běhu, nikoliv při každém pollingu seznamu. Testy
kontrolují konstantní počet dotazů pro seznam, párování i stránku historie.

**Ověření:** kompilace aplikace s `--warnings-as-errors`, kompilace změněných
testovacích modulů bez spuštění a formátování s připnutým Elixir 1.20.4 / OTP 29.1.
Lokální testy se podle AGENTS.md nespouštěly; výsledek GitHub CI ověří uživatel.
Nebyly provedeny živé AI/ABRA požadavky ani migrace provozní databáze.

**Zbývá:** ověřit CI a provést pilot podle části 11 na skutečných soukromých
podkladech, popsat zlepšení i omezení. Bez pilotu není potvrzena přesnost, odezva
ani cena dvoufázového vytěžování. Funkce se nasazuje standardní aditivní migrací.

**Doplnění rozsahu vytěžování:** formulář nyní ve výchozím stavu vypíná načítání
položek. Viditelný přepínač platí pro všechny nové a opakované běhy. Vypnutí
používá samostatné hlavní zadání a menší API schéma bez `items`, nikoliv jen
skrytí položek ve formuláři. Snapshot rozsahu je součástí běhu a historie.
Stávající běhy zůstávají beze změny; není potřeba další migrace.

**Změna podle následného zadání: samostatný dodavatelský dotaz.** Nové běhy s
neprázdnými instrukcemi mají identifikaci, obecné čtení a další nezávislý dotaz,
který dostane jen originál a úkol z instrukcí. Předchozí odpověď ani obecné zadání
se nepředávají. Řídký výsledek s citací nahrazuje jen výslovně vrácená povolená
pole; null odstraňuje obecný odhad. Původní obecný výsledek i cílená odpověď se
uchovávají zvlášť. Každé volání má samostatnou rezervaci, metadata a usage.
Bez instrukcí třetí volání není. Obsahové opakování s profilem nově znamená dvě
volání bez nové identifikace. Vyžaduje migraci `20261106120000`; starší běhy se
nemění a nepřibývají jim automatická volání. Původní dvoufázový návrh výše je
historický podklad; aktuální postup je v návodu formuláře.

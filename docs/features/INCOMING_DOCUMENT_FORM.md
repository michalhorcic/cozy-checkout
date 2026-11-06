# Ruční formulář přijatého dokladu s návrhy z OpenAI

Jediné uživatelské rozhraní přijatých dokladů: seznam na `/admin/incoming-documents`
a formulář na `/admin/incoming-document-form`. Stejný formulář otevírají i staré
adresy `/admin/incoming-documents/:id`. Původní `IncomingDocumentsLive` zůstává v
kódu, ale nemá přístupnou routu. Jeho položkové kontroly a kontextové API zůstávají.

Formulář používá stejné tři vzory, připojení ABRA, soukromé originály, OpenAI
Responses API a Oban worker. Obsahuje účetní předpis, volitelný dry-run, stažení
XML i potvrzené přímé odeslání; není potřeba přecházet na další obrazovku.

## Stav převzatého řešení

Větev `codex/prijate-doklady` na commitu `d45647a` již obsahuje nahrávání,
strukturovaný přepis nebo přímé XML, editaci přepisu, deterministický sestavovač,
kontrolu pokrytí a součtů položek, účetní číselník, diagnostiku odpovědí ABRA a
create-only import s externím ID. Potíže s neúplnými položkami se v podrobném
režimu správně projevují blokací. Tato alternativa je obchází změnou rozsahu
zpracovávaného dokladu, nikoliv oslabením kontroly položkového režimu.

## Použití

1. Vybrat agendu: přijatá faktura, pokladní výdaj nebo ostatní závazek (karta).
2. Buď vyplnit doklad ručně bez souboru a bez volání OpenAI, nebo nejdříve nahrát
   PDF/JPEG/PNG. U nahrávání se zachovává kontrola duplicity a limit 10 MB.
3. Nová strategie `header_form` vrací návrhy hlavičky a rekapitulace DPH. I při
   `complete=false`, neúplných položkách nebo chybějící celkové částce se zpřístupní
   formulář. Nový běh nejprve určí dodavatele a pak vytěží obecné údaje.
   Pokud má dodavatel neprázdné instrukce, další samostatný dotaz provede jen
   jejich úkol nad originálem. Chybějící položky nedoplňuje opakováním.
   Chybu API lze vyřešit ručním vyplněním stejného formuláře.
4. Zkontrolovat a opravit návrhy proti zobrazenému originálu. Původní vytěžená data
   zůstávají uložená, ruční formulář je uložen zvlášť. Nejasnosti, přečtená měna a
   rekapitulace originálu jsou viditelné. Podporovány jsou tuzemské doklady v CZK
   a souhrnné sazby 0 %, 12 % a 21 %. Jiné sazby nebo měny vyžadují jiné zpracování.
5. Potvrdit kontrolu CZK, údajů a souhrnné DPH. Teprve uložením formuláře vzniká
   validované XML. Součet základů, osvobozené částky a daní musí souhlasit s celkem;
   chybějící DPH se nepřevádí automaticky na osvobozenou částku.
6. Uložením zůstanete ve formuláři. V sekci Účetní nastavení načíst a vyhledat
   předpis z ABRA, případně změnit interní číslo a uložit. Rozpracované změny
   hlavičky se při uložení předpisu neztratí. Před operacemi ABRA musí být obě
   části uložené.
7. Volitelně spustit „Ověřit v ABRA (dry-run)“. Výsledek, chyby, upozornění i
   diagnostika HTML/FreeMarker odpovědí se zobrazují přímo zde. Neúspěšný dry-run
   neznamená úspěšnou validaci, ale neblokuje explicitní přímé odeslání.
8. Potvrdit skutečné vytvoření a kontrolu případného dřívějšího ručního importu,
   poté stisknout „Nahrát do ABRA“. Lokálně se znovu zkontroluje struktura XML,
   součty a povinná data. Schválené XML se pro API deterministicky převede na
   nativní JSON obálku `winstrom` a odešle přes `Req.post(json: payload)` na `.json`,
   stejně jako fungující faktury za ubytování. Přenášejí se stejné částky, kódy,
   poznámka a externí ID; XML ke stažení i uložený schválený XML snapshot zůstávají.
   Prázdné nepovinné hodnoty se vynechají, `ucetni` a `bezPolozek` jsou JSON booleany.
   Desetinné částky a data zůstávají řetězci bez dalšího přepočítávání.
   Skutečný POST neobsahuje parametr `dry-run`; testovací požadavek má
   `dry-run=true`. Neprovádí se automatické zkoušení dalších importních endpointů.

Před skutečným POSTem se hledá stejné externí ID. Pokud už je v ABRA, například
po ručním importu staženého souboru, nový doklad se nezakládá. Odeslané XML se
zmrazí a uloží se způsob schválení a hash payloadu. HTML nebo nejasný výsledek
skutečného importu vede do stavu „Nutno ověřit v ABRA“; další pokus už jen hledá
externí ID, neopakuje POST. Ruční import bez původního externího ID tato ochrana
nedokáže spárovat, proto je součástí potvrzení i kontrola dřívějšího importu.

Po zahájení přenosu je formulář uzamčený. Změny uloženého návrhu ruší předchozí
dry-run. Existující starší návrhy se načtou do nového formuláře a až jeho
potvrzené uložení je převede na bezpoložkový režim; původní řádky se přenesou jako
text do poznámky. Odeslané starší doklady se zobrazí zamčené.

Načítání položek je ve výchozím stavu vypnuté. Přepínačem „Načítat také položky
(orientační přepis)“ je lze výslovně zapnout pro příští nahrání či opakování.
Při zapnutí OpenAI podle možností přepíše položky do `items`, ale použijí se pouze jako
orientační text v `poznam`. Do ABRA neposíláme kolekci `polozkyDokladu`, skladové
pohyby ani ceny jednotlivých položek. ABRA může interně vytvořit své automatické
účetní řádky podle souhrnné DPH; to popisuje její dokumentace bezpoložkových dokladů.

## Předvyplnění DPH a dat

Po vytěžení se rekapitulace rovnou přiřadí do souhrnných polí formuláře.
Sazby lze přečíst i jako `21 %`, `12,0 %` apod.; více řádků stejné sazby se
sečte pomocí Decimal místo přepsání posledním řádkem. Základ a daň se přebírají
z originálu. Pokud z trojice základ/daň/celkem chybí jediná hodnota, lze ji získat
rozdílem zbývajících dvou; daň se nepřepočítává procentem sazby. U 0 % lze převzít
pouze částku celkem. Neúplná, rozporná nebo nepodporovaná sazba se označí k ručnímu
doplnění. Částky mimo DPH se neodhadují jako rozdíl celého dokladu.

Při dokončení vytěžování se nová data promítnou i tehdy, když prohlížeč mezitím
obnovil prázdný formulář a označil jej jako změněný. Případné jednotlivé ruční
opravy se porovnají s naposledy načtenými hodnotami a zachovají nad novými návrhy.

Tlačítko „Převzít rekapitulaci do polí DPH“ umožňuje stejná data znovu použít v
otevřeném návrhu bez OpenAI a bez zápisu do databáze. Přepíše pouze pole sazeb,
pro které má rekapitulace použitelné hodnoty; dodavatele, poznámku a datumová pole
ponechá. Ruční opravy uloženého XML se při běžném znovuotevření nezmění.

Data z originálu ve formátu `5. 11. 2026` se převedou na ISO formát HTML formuláře.
Pro první návrh se použijí tato pravidla:

- Vystavení, DUZP a splatnost se přednostně přebírají z originálu.
- Pokud vystavení chybí, lze jej navrhnout podle doloženého DUZP; pokud chybí DUZP
  nebo splatnost, navrhnou se podle dostupného vystavení.
- Datum zaúčtování se navrhne podle vystavení.
- Datum uplatnění DPH se navrhne podle pozdějšího vystavení a DUZP.
- Bez platného vystavení nebo DUZP se chybějící data nevyplní dnešním datem.

Formulář výslovně uvádí, že jde o návrhy ke kontrole proti skutečnému přijetí,
splatnosti a účetnímu období. Tlačítko „Doplnit prázdná data“ používá aktuální
data ve formuláři a chybějící zdrojová data převezme z vytěženého originálu.
Vyplňuje jen prázdná pole, ručně upravená data zachová; funguje tedy i u staršího
uloženého návrhu, který má všechna data prázdná.
Každé použití předvyplnění označí návrh jako změněný a zruší zaškrtnutou kontrolu.
Před dry-runem či přenosem je potřeba změny potvrdit a uložit.

## Co obsahuje výsledné XML

Společná obálka je `winstrom version="1.0"`. Jeden doklad má `create="ok"`
a `update="fail"` a vlastní `id` ve tvaru `ext:cozy-incoming:<UUID>`. Interní
číslo `kod` může přidělit ABRA; dodavatelské číslo patří do `cisDosle`.

| Agenda / kořen dokladu | Nastavení převzaté z dodaného vzoru | Povinné údaje v novém formuláři |
| --- | --- | --- |
| `faktura-prijata` | `typDokl=code:FAKTURA`, účet 321001, předpis a členění DPH ze vzoru | Dodavatel, číslo původního dokladu, vystavení, splatnost, celkem, odpovídající rekapitulace |
| `pokladni-pohyb` | `typDokl=code:STANDARD`, `typPohybuK=typPohybu.vydej`, `pokladna=code:POKLADNA KČ`, účet 211001 | Dodavatel, číslo původního dokladu, vystavení, celkem, odpovídající rekapitulace |
| `zavazek` | `typDokl=code:1.OST. ZÁVAZ - KARTA`, účet 325000, předpis a členění DPH ze vzoru | Dodavatel, číslo původního dokladu, vystavení, splatnost, celkem, odpovídající rekapitulace |

Při nenulové DPH formulář vyžaduje `duzpPuv` i `duzpUcto`; datumové návrhy podle
výše uvedených pravidel musí obsluha zkontrolovat. Adresa, IČO/DIČ, variabilní symbol, datum účtování,
bankovní spojení a popis lze doplnit. Konkrétní požadavky firmy, účtů a kontrolního
hlášení včetně DIČ ověří ABRA dry-run. Číslo dokladu a dodavatel jsou společné
aplikační požadavky pro dohledatelnost, nikoliv tvrzení o povinnosti ve všech
agendách ABRA. Účetní kódy ve vzorech nejsou univerzální pro jiné firmy.

V každé agendě se přenáší `bezPolozek=true`, `ucetni=true`, `mena=code:CZK`,
`stat=code:CZ`, `statDph=code:CZ` a následující peněžní hlavička (příklad):

```xml
<sumOsv>10.00</sumOsv>
<sumZklSniz>100.00</sumZklSniz><sumDphSniz>12.00</sumDphSniz>
<sumZklSniz2>0.00</sumZklSniz2><sumDphSniz2>0.00</sumDphSniz2>
<sumZklZakl>1000.00</sumZklZakl><sumDphZakl>210.00</sumDphZakl>
<sumCelkem>1332.00</sumCelkem>
<poznam>Orientační přepis položek (bez zaúčtování): ...</poznam>
```

Model nevybírá účetní předpis, účty, typ dokladu ani XML elementy. Text je escapován
stávajícím XML rendererem. Formulář nepřijímá účetní pole nebo položkové kolekce.

## Rozdíl proti přenosu faktur za ubytování

`CozyCheckout.Abra.Client.create_invoice/2` používá nativní JSON přes `json:` na
endpointu `.json`. Přijaté doklady původně posílaly XML přes `body:` s
`Content-Type: application/xml` na `.json`. Oba formáty ABRA dokumentuje, ale
v této instalaci se u XML přenosu objevovala webová FreeMarker odpověď místo
výsledku API, zatímco ruční import stejného souboru fungoval.

Přenos přijatých dokladů nyní kopíruje fungující JSON konvenci ubytování.
`ImportPayload.from_xml/2` používá existující omezený XML parser, nikdy neposílá
raw text jako JSON řetězec a model se převodu neúčastní. Nastavuje `@create=ok`,
`@update=fail` a stávající externí ID. Neprovádí automatický druhý POST v jiném
formátu, pokud první odpověď není jednoznačná. Starší položkové XML se převede na
JSON pole bez XML obálky jednotlivých řádků; souhrnný formulář žádné řádky nepřidává.

Diagnostika požadavku ukazuje skutečný `Content-Type: application/json`, hash
zdrojového XML a hash odeslaného JSON těla. Dry-run i skutečné odeslání používají
stejný převod. Schvalování a zmrazené `sent_xml` nadále pracují se stejným XML
snapshotem, jeho obsah se nepřepisuje.

Tím je odstraněn doložený rozdíl ve formátu požadavku. Bez živého požadavku na
cílovou ABRA není potvrzeno, že právě tento rozdíl způsoboval FreeMarker chybu;
samotné HTML nadále nepovažujeme za úspěch.

## Zdroje ověřené při implementaci

- [ABRA: přijatá faktura](https://podpora.flexibee.eu/cs/articles/4611404-prijata-faktura):
  povinná pole, datum uplatnění DPH, splatnost a bezpoložkové zadání souhrnných částek.
- [ABRA: pokladna](https://podpora.flexibee.eu/cs/articles/4632069-pokladna):
  typ pohybu, pokladna, vystavení, souhrnné částky a poznámka.
- [ABRA: ostatní závazky](https://podpora.flexibee.eu/cs/articles/4569870-ostatni-zavazky):
  číslo došlé, splatnost, DPH a bezpoložkové zadání.
- [ABRA: testovací uložení](https://podpora.flexibee.eu/cs/articles/4720123-testovaci-ulozeni-dry-run).
- Dodané XML v `priv/incoming_documents/{faktura-prijata,pokladni-pohyb,zavazek}.xml`.

Veřejné metadata `demo.flexibee.eu/c/demo/<agenda>/properties.json` při ověření
vracely HTTP 401. Živý import do cílové ABRA ani volání OpenAI nebyly provedeny;
platnost pro konkrétní firmu ověří dry-run nebo výsledek explicitního importu. Dokumentace popisuje
podporovaný postup, nikoliv důkaz akceptace konkrétního payloadu v cílové instalaci.

## Migrace a ověření

Migrace `20261105220000` povoluje prázdný originál, MIME typ a hash u ručně
vytvořených dokladů. Soukromý endpoint originálu u takového dokladu vrací 404.
Existující dokumenty se nemění. Není potřeba nová konfigurace ani závislost.

Přidané testy pokrývají XML všech tří agend, DPH a součty, text položek v poznámce,
částečné vytěžení, ruční vytvoření, souběžné změny, zrušení dry-runu, neměnnost
po schválení, kontrolovaný payload, admin PIN a formulář. Další scénáře pokrývají
přímý přenos bez úspěšného dry-runu, shodu XML se staženým souborem, převzetí
ručně importovaného externího ID bez POSTu, nejistý výsledek po HTML a ověření bez
opakování zápisu. Routové testy ověřují skrytí starého rozhraní a převod starších
návrhů. Změna sjednocení rozhraní nevyžaduje další migraci ani konfiguraci. Lokální testy podle
AGENTS.md nebyly spuštěny; výsledky GitHub CI ověří uživatel. Kompilace a kontrola
formátování byly provedeny s Elixir 1.20.4 / OTP 29.1.

## Instrukce podle dodavatele a historie běhů

V sekci **Instrukce pro vytěžování dodavatele** je rozpoznaná identita, důvod
přiřazení, revize použitá v posledním běhu a samostatný editor aktuálního profilu.
Profily jsou izolované podle URL a cílové firmy ABRA. Koncové lomítko URL se při
párování profilů ignoruje. Automaticky se přiřadí pouze jednoznačně přečtená země
CZ a české IČO s platným kontrolním součtem; počáteční nuly se zachovají. Rozpor
DIČ profil vyloučí. Název ani DIČ samostatně nespouští automatické párování.
Neznámá, zahraniční nebo nejednoznačná identita pokračuje společným zadáním.
Chyba HTTP či neplatná JSON odpověď první fáze naopak běh ukončí.

Existující profil lze vyhledat podle názvu, IČO i DIČ. Výběr sám nemění hlavičku
ani nespouští AI. Pro nový profil obsluha samostatně potvrdí identitu, zemi a klíč
(české IČO nebo ručně potvrzené DIČ včetně prefixu země). Nevznikají automatické
prázdné profily. Instrukce mají limit 8 000 znaků a mohou být prázdné.

- **Uložit instrukce pro příště** mění jen profil, bez AI a bez změny dokladu.
  Funguje i na odeslaném nebo ručním dokladu. Každé uložení zvyšuje revizi;
  druhé okno nesmí přepsat novější text bez jeho načtení a porovnání.
- **Uložit instrukce a znovu vytěžit** atomicky uloží profil a založí nový běh
  bez nové identifikace: obecný obsah a samostatný dodavatelský úkol nad stejným
  originálem a výslovně potvrzeným profilem.
  Selhání zařazení vrátí zpět i změnu instrukcí.
- **Zopakovat jen obsahové vytěžení** převezme identitu předchozího běhu stejného
  originálu a poslední uloženou revizi; znovu provede obsah i dodavatelský úkol.
  **Znovu určit dodavatele** spustí nový
  úplný běh. Neuložené instrukce je nutné před těmito akcemi uložit či znovu načíst.
- **Vytěžit bez určení dodavatele** výslovně založí obsahový běh bez profilu;
  lze ho využít i po chybě první fáze.

Při opakování se předchozí návrh včetně ručních hodnot a účetního nastavení
archivuje. Aktuální XML i dry-run se zneplatní. Po neúspěchu lze z historie
výslovně obnovit předchozí pracovní návrh; před přenosem se musí znovu zkontrolovat
a uložit. Odeslané XML a stavy přenosu opakování i obnovu blokují. Bez originálu
nejsou AI akce dostupné, ruční formulář a editor budoucích instrukcí zůstávají.
Oprava IČO či názvu ve finanční hlavičce nikdy nepřepisuje profil.

Obsahová fáze nesmí přepojit identitu na jiný profil. Při jiném IČO nebo DIČ se
zobrazí rozpor a před uložením formuláře je potřeba zvlášť potvrdit jeho kontrolu
proti originálu. Instrukce nevytvářejí účetní pravidla; společná pravidla,
strukturovaný kontrakt, deterministická kontrola částek a ruční přenos zůstávají.

Každý běh uchovává identitu, kontrakty jednotlivých volání, přesné společné
zadání i samostatné dodavatelské zadání, revizi a hash instrukcí, obecný výsledek,
výsledek cíleného úkolu, výsledný sloučený návrh a samostatné rezervace i metadata.
Historie se stránkuje po deseti bězích a nevybírá velké raw odpovědi.
Usage každého volání je viditelná zvlášť; cenu bez ověřeného ceníku neodhadujeme.
S instrukcemi se originál posílá třikrát (při opakování bez identifikace dvakrát),
bez instrukcí dvakrát. Každé volání přidává i obrazové vstupní tokeny.
Žádné tajné klíče či autorizační hlavičky se do snapshotů neukládají.

Oban retry nevytváří nový běh a neopakuje rezervované placené volání. Po pádu
mezi rezervací a uložením odpovědi není jisté, zda poskytovatel požadavek provedl:
obnovený worker označí fázi jako přerušenou a další pokus musí vyvolat obsluha.
Dokončená identifikace přežije restart, takže lze pokračovat dosud nerezervovaným
obsahovým voláním. Dokončené obecné čtení přežije také restart před samostatným
úlohovým dotazem. Pozdní výsledky starého běhu nesmí přepsat novou generaci,
změněný originál ani odeslaný doklad.

### Nasazení a ověření nového toku

Aditivní migrace `20261106090000` přidává profily, běhy a aktivní vazbu dokladu.
Kompozitní FK zajišťuje, že aktivní běh patří stejnému dokladu. Aktivní identita
profilu, generace dokladu a jediný rozpracovaný běh mají unikátní indexy. Historie
se automaticky nemaže. Dosavadní doklady mají vazbu prázdnou a nevolají zpětně AI.
Starý job bez `run_id` se pod zámkem převede na jediný běh, pouze pokud ještě
nerezervoval staré volání. Již rezervované staré volání vyžaduje ruční obnovu.
Původní strategie `structured` a `simple_xml` zůstávají ve své větvi.

Nový tok platí pro všechny nové `header_form` běhy, nemá další konfigurační
přepínač ani nový klíč/model. Před návratem ke staršímu release je potřeba zastavit
vkládání nových běhů a dokončit či ukončit jejich joby. Tabulky historie nemazat.

Přidané testy přes Req.Test pokrývají dvě různá volání, snapshot revize, přesné
párování a namespace, konflikt editorů, přerušenou rezervaci, obnovení pouze druhé
fáze, pozdní odpověď, historii návrhu, změněný zdroj/cíl, odeslané doklady,
kompozitní FK, konstantní počet dotazů a editor ve formuláři. Lokálně proběhla
kompilace aplikace i změněných testovacích modulů bez spuštění testů a kontrola
formátování s Elixir 1.20.4 / OTP 29.1. Výsledek CI ověří uživatel. Živá OpenAI
ani ABRA se nevolaly. Pilot na několika dokladech O2 a jiného dodavatele zbývá;
zlepšení přesnosti, času a ceny dosud není ověřené.

### Vytěžování bez položek

Přepínač **Načítat také položky (orientační přepis)** je ve výchozím stavu vypnutý,
i při otevření staršího dokladu. Platí pro příští běh: upload, nové určení
vystavitele, opakování obsahu, obecné vytěžení i uložení instrukcí s novým během.
Samotné přepnutí nic nevytěžuje, nemění aktuální návrh a neruší účetní validaci.

Při vypnutí používá obsahová fáze samostatné kratší zadání zaměřené na dodavatele,
celé označené číslo dokladu, variabilní symbol, data, měnu, celkovou částku a DPH.
Pole `items` není v API schématu ani v seznamu požadovaných polí. Výsledek projde
lokální kontrolou tohoto menšího kontraktu; až potom aplikace doplní interní
`items: []`, aby zachovala kompatibilitu formuláře. Nejde tedy pouze o skrytí
položek, které by model dál četl.

Při zapnutí zůstává dosavadní přepis položek do poznámky. Zvolený rozsah určuje
uložený snapshot schématu a společných instrukcí každého běhu a je vidět v jeho
historii. Změna přepínače neovlivní již běžící nebo historický běh, včetně běhů
z předchozí verze aplikace. Starší strategie `structured` a `simple_xml` se nemění.
Není potřeba další migrace, proměnná prostředí ani další placené volání.
Zjednodušení zadání samo o sobě nezaručuje správné rozpoznání každého čísla;
číslo i ostatní údaje je dál nutné kontrolovat proti originálu.

### Samostatné zpracování dodavatelských instrukcí

Pro nové běhy s neprázdným profilem jsou instrukce **samostatný dotaz**. Nejsou
připojené k obecnému zadání. Model dostane původní obrazové vstupy, stručný kontrakt
cíleného čtení a přesný snapshot dodavatelského textu jako uživatelský úkol.
Nedostane předchozí obecnou odpověď, její tip na číslo, obecné zadání ani identitu
jako další úkol. Pro instrukci „Přečti číslo za EV-Č“ tedy řeší pouze tento úkol.

Odpověď je řídký seznam `fields`: pouze řešené pole, jeho hodnota a citovaný
`source_text` z originálu. Povolené jsou hlavní hlavičkové údaje a identita
vystavitele; zvlášť lze vrátit rekapitulaci DPH, pokud ji úkol řeší. Ostatní pole
se nevyplňují. Účty, XML a položky nejsou v tomto kontraktu. Aplikace kontroluje
typy, délky, duplicity i povolené názvy polí bez tvorby atomů.

Výslovně vrácené hodnoty nahradí stejné údaje z obecného čtení. Pokud cílený dotaz
u požadovaného pole vrátí null, aplikace smaže původní obecný odhad; nevrátí se
potichu k chybnému číslu. Ostatní údaje, data, částky a položky zůstanou zachované.
Sloučený přepis znovu projde kontrolou struktury a pak stávajícími ručními
kontrolami formuláře. Změna IČO/DIČ neaktualizuje profil a zachovává výstrahu
rozporu identity s nutností samostatného potvrzení. Citovaný text pomáhá kontrole,
není nezávislým důkazem správnosti modelu.

Historie i sekce dodavatele zobrazují samostatnou odpověď a citaci zdroje;
v historii má volání vlastní model, usage, stav a chybu. Prázdné nebo nepřiřazené
instrukce další dotaz nevyvolají. Neúspěšný cílený dotaz ukončí běh jako chybu:
obecný výsledek je zachovaný v běhu, ale nepoužije se automaticky jako dokončený
návrh. Lze vyplnit formulář ručně, obnovit předchozí návrh či vědomě spustit nový
běh. Po nejasné rezervaci se placené volání automaticky neopakuje.

Nasazení vyžaduje aditivní migraci `20261106120000`: vlastní metadata, odpověď,
společný text cíleného dotazu a obecný výsledek, plus rozšířený constraint fáze.
Původní existující běhy bez kontraktu `supplier_task` si ponechají původní
kombinované zadání a počet volání, i pokud jsou teprve ve frontě. Nový režim se
použije až novým během. Nejsou potřeba nové přihlašovací údaje ani konfigurace.
Před návratem ke starší aplikaci dokončit či ukončit nové joby a ponechat databázové
snapshoty; rollback databáze by odstranil nově přidanou historii.

Testy přes Req.Test ověřují oddělení zadání a předchozí odpovědi, správný snapshot
při změně revize, převzetí cíleného čísla místo obecného odhadu, citaci, chybu
samostatného volání, obnovu po obecném čtení, nejistou rezervaci, souběh a pozdní
výsledek. Lokálně testy nebyly spuštěny; výsledky CI ověří uživatel. Kompilace
aplikace i změněných testovacích modulů a formátování byly ověřeny. Živá OpenAI
ani ABRA nebyla volána; přesnost na skutečných dokladech ještě vyžaduje pilot.

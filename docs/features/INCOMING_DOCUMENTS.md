# Přijaté doklady — pilot

Administrace `/admin/incoming-documents` přijímá jeden doklad v PDF (i více
stran), JPEG nebo PNG, nejvýše 10 MB. Přístup, včetně originálů, chrání stávající
admin PIN. Veřejné POS se nemění.

## Agendy a vzory

- `faktura-prijata`: přijatá faktura, typ `FAKTURA`, účet DAL `321001`.
- `pokladni-pohyb`: pokladní **výdaj**, typ `STANDARD`, pokladna `POKLADNA KČ`,
  účet DAL `211001`.
- `zavazek`: ostatní závazek — platba kartou, typ `1.OST. ZÁVAZ - KARTA`,
  účet DAL `325000`. Nezakládá úhradu ani párování s bankou.

Vzory v `priv/incoming_documents/` vycházejí ze tří dodaných exportů ABRA.
Základní soubory obsahují účetní nastavení původních bezpoložkových dokladů;
identity, automaticky vytvořené účetní řádky, odkazy na původní firmu, dodavatele
a úhrady byly odstraněny. Účetní vzor používá pouze aplikace při sestavení XML.
Model dostává nový originál obrázku/PDF a stručné pokyny pro strukturovaný přepis
JSON (Structured Outputs); účetní pole ani XML negeneruje. Starší opravené doklady
se automaticky neposílají jako příklady ani model netrénují.
Přijatá faktura a karta mají předpis nákupu potravin, pokladna ostatní spotřebu.
Tyto pevné předpisy nejsou univerzální pro libovolný nákup. Pro pilot vybírejte
odpovídající doklady; odlišné účtování zpracujte ručně nebo změňte příslušný vzor
pro další uploady. Každý doklad uchovává vlastní kopii vzoru.

Podporovány jsou kladné doklady v CZK s rozpisem základů a DPH. Základní kontrola
ověřuje součet osvobozené částky, základů a DPH proti celku pomocí Decimal.
Povoluje pouze níže popsanou doloženou haléřovou korekci DPH. Neprovádí měnové přepočty, nezakládá adresářové firmy,
nespouští párování ani skladové vazby a nepřenáší přílohy do ABRA. Údaje dodavatele
zůstávají v hlavičce dokladu. Správnost účtování a chování částek musí ověřit pilot.

## Konfigurace

Modul je ve výchozím stavu vypnutý. Pro pilot nastavte na serveru:

```sh
INCOMING_DOCUMENTS_ENABLED=true
OPENAI_API_KEY=...
INCOMING_DOCUMENTS_OPENAI_MODEL=...
```

Model musí podporovat obrázky, PDF a Structured Outputs přes Responses API. Model není natvrdo
vybraný; chybějící klíč nebo model se zobrazí jako chyba vytěžení.

Připojení ABRA se přebírá **ze stejné konfigurace jako faktury za ubytování**:
`ABRA_ACCOMMODATION_BASE_URL` a `ABRA_ACCOMMODATION_COMPANY_ID` s dosavadním
fallbackem na `ABRA_BASE_URL` / `ABRA_COMPANY_ID`; přihlášení používá
`ABRA_USERNAME` / `ABRA_PASSWORD`. Přepínač synchronizace ubytování není
podmínkou zapnutí přijatých dokladů. Před zapnutím ověřte, že tato konfigurace
ukazuje do testovací firmy (pro pilot `moruska_test_faktury`). UI vždy ukazuje
cílovou firmu. Změna cíle blokuje přenos dříve nahraných dokladů.

Migrace `20261105120000_create_incoming_documents` přidává jednu tabulku.
Migrace `20261105180000_add_incoming_extraction_data` doplňuje přepis JSON,
metadata a trvalý počet pokusů; po aktualizaci spusťte migrace. Runtime Dockeru
a CI obsahují ImageMagick; při lokálním běhu jej nainstalujte pro výřezy fotografií.
Bez něj se použije originál a detail zobrazí upozornění. Výřezy se vytvářejí
v soukromém dočasném adresáři a po přípravě se odstraní, uložený originál se nemění.
Originály jsou uloženy přímo v PostgreSQL (`bytea`), zahrnuty do zálohy databáze,
a nejsou dostupné jako veřejné statické soubory. Databáze může růst přibližně
o velikost originálů; ověřte kapacitu a obnovu záloh před pilotem. Seznam načítá
jen posledních 100 metadat jedním dotazem, bez originálů a XML a bez N+1.
Přenosy používají existující frontu Oban `billing`. Přijaté doklady se soft-delete
sloupcem nejsou fyzicky odstraňovány; UI zatím neposkytuje mazání.

## Kontrola a odeslání

1. Nahrát soubor, zvolit jednu ze tří agend. Stejný SHA-256 upozorní na duplicitu.
2. Oban pošle originál do OpenAI s `store=false`. Dlouhé fotografie doplní
   překrývajícími se označenými výřezy v původním rozlišení; PDF zůstává souborem
   se všemi stránkami. Pokyny uvnitř originálu jsou nedůvěryhodná data.
   Model vrací pouze JSON se všemi řádky, legendou DPH a nezávisle přepsanou
   rekapitulací. Účetní nastavení se mu neposílá.
3. Aplikace ověří JSON, mapuje sazby podle legendy, doplní účetní nastavení
   z uloženého vzoru a sestaví XML. Pomocí Decimal ověří řádky, rekapitulaci a celek.
   Při věcné chybě připustí právě jeden opravný pokus se stejným originálem,
   předchozím JSON a konkrétní chybou. Každé volání se rezervuje v databázi předem:
   nejvýše dvě na jedno výslovné vytěžení, i při obnovení workeru. HTTP chyby,
   neúplné odpovědi a porušení JSON struktury automatický opravný pokus nespouštějí.
   Model nemá nástroje pro zápis do ABRA. XML kontroluje omezený SAX parser bez
   DTD, externích entit, vazeb a cizích identit; externí ID přidává server.
4. Porovnat originál a editovatelná pole. PDF používá prohlížeč se stránkováním
   a zvětšením, fotografie má posuvník zvětšení. Opravy mění XML bez nového
   volání modelu. Po uložení se předchozí dry-run zneplatní; zastaralé úpravy
   z druhého okna odmítne kontrola hashe.
5. Spustit kontrolu XML v ABRA (`dry-run=true`). Chyby blokují schválení,
   upozornění vyžadují samostatné výslovné potvrzení. Potvrdit kontrolu originálu
   a použít „Schválit a odeslat“. Přesně schválené XML se uloží a uzamkne.
6. Po přenosu se uloží odpověď a ID s odkazem do ABRA. Odeslaný doklad se neupravuje.

### Číslo původního dokladu (`cisDosle`)

`cisDosle` identifikuje dodavatelský doklad, zatímco `kod` je interní číslo ABRA
a `varSym` slouží platebnímu styku. ABRA uvádí číslo došlé u přijaté faktury jako
povinné a používá jej také při tvorbě kontrolního hlášení z přijatých faktur,
ostatních závazků a pokladny. Naše aplikace vyžaduje číslo originálu ve všech třech
agendách jako podmínku kontroly; tato aplikační podmínka není tvrzením, že ABRA
technicky vyžaduje stejné pole u každého typu dokladu.

Model prohledává celý originál včetně patičky a hledá číslo faktury/daňového
dokladu/účtenky nebo evidenční číslo. Pro PENNY používá podle uživatelského
pozorování také vodítko `EV-č` (varianty `EV-č:`, `ev. č.`, `ev.č.`).
Označení nebylo potvrzeno veřejným oficiálním návodem PENNY; rozhodující je
skutečný popisek a hodnota na konkrétní účtence. Do pole patří hodnota bez popisku,
se zachovanými počátečními nulami, písmeny, pomlčkami a lomítky. Platební karta,
terminál, autorizační kód, věrnostní karta či reference karetní transakce nejsou
náhradou čísla daňového dokladu. Nečitelné nebo nejednoznačné číslo zůstane prázdné
pro ruční opravu; z data či vzorového dokladu se negeneruje. `varSym` se vytěžuje
samostatně, pokud je na originálu uveden.

Zdroje: [ABRA — přijatá faktura](https://podpora.flexibee.eu/cs/articles/4611404-prijata-faktura),
[ABRA — kontrolní hlášení](https://podpora.flexibee.eu/cs/articles/4585915-kontrolni-hlaseni),
[Finanční správa — časté dotazy ke kontrolnímu hlášení](https://financnisprava.gov.cz/cs/dane/dane/dan-z-pridane-hodnoty/kontrolni-hlaseni-dph/caste-dotazy-a-odpovedi).

### Jednotlivé položky a rekapitulace

Model má přepsat všechny položky účtenky nebo faktury v původním pořadí,
nejvýše 200 položek / 250 kB XML. Zahrnuje také doložené slevy, obaly a zaokrouhlení.
Množství může být vážené a jednotková cena má nejvýše šest desetinných míst.
Sleva se zadává buď procentem `slevaPol`, nebo samostatnou zápornou položkou,
nikoli oběma způsoby zároveň. Sazba každé položky vychází ze značení a legendy
originálu (`typSzbDphK`); neznámou sazbu model nemá odhadovat podle názvu zboží.
Hlavičkové sazby nejsou částky DPH a z originálu se nepřepisují.

Aplikace kontroluje pomocí Decimal množství, cenu, slevu, sazbu a částky řádků.
Součty položek porovnává s rekapitulací DPH i celkem originálu pro každou sazbu.
Při rozdílu ukáže konkrétní částky a import zablokuje. Výjimkou je rozdíl
nejvýše 0,01 Kč na sazbě mezi součtem řádků a souhrnným výpočtem DPH:
celková cena i součet základu a DPH dané sazby musí zůstat přesně shodné a
vytištěný základ musí odpovídat zaokrouhlenému výpočtu z celku sazby. Aplikace
nevymýšlí cenu ani množství, původní položky nemění. Do skutečného payloadu
přidá samostatnou položku `typPolozky.ucetni` bez množství a jednotkové ceny,
s opačnými rozdíly základu a daně a nulovým celkem. Detail ji ukáže a schválení
vyžaduje zvláštní potvrzení; totožná položka musí projít dry-runem ABRA.
Například PENNY 1178,34 Kč / 12 %: 21 řádků dává základ 1052,08 a daň 126,26;
vytištěnou rekapitulaci 1052,09 + 126,25 dorovná základ +0,01 / DPH −0,01.
Větší rozdíl, chybějící řádek či jiný celkový součet se tímto neopraví.
Skladové a adresářové vazby na položkách nejsou povoleny.

V přehledu dokladu lze upravit názvy, množství, jednotkové ceny, typ ceny, sazbu
a procentní slevu. Po uložení se částky přepočítají a znovu porovnají s rekapitulací.
Uživatelská úprava rekapitulace musí odpovídat originálu. Doklady bez skutečných
položek i dřívější bezpoložkové doklady lze nadále ručně zpracovat souhrnem.
Nový automatický přepis vyžaduje alespoň jednu doloženou položku.

Položkový import používá `bezPolozek=false` a kolekci `polozkyDokladu` s elementem
`faktura-prijata-polozka`, `pokladni-pohyb-polozka` nebo `zavazek-polozka` podle agendy.
Kontrolní částky hlavičky zůstávají v aktuální verzi XML v databázi pro porovnání,
ale do ABRA se neposílají: ABRA vypočítá hlavičku z položek. Sekce „XML k odeslání“
ukazuje skutečný payload. Dry-run a schválený přenos používají shodné XML; jeho
hash se před zamčením ověřuje a přesné odeslané XML je uložené v `sent_xml`.
Dříve vydané/odeslané dokumenty zůstávají beze změny.

### Oprava neúspěšného vytěžení

Pokud přepis neprojde kontrolou ani po opravném pokusu, uloží se původní JSON,
konkrétní chyba a sestavené XML, je-li dostupné. Detail nabízí opravu JSON bez
nového volání modelu; opravený přepis musí projít stejnými kontrolami a účetní XML
z něj znovu sestaví server. Původní přepis se zachová. Pro dohledání jsou uložené
verze pokynů (SHA-256), model, počty obrazových vstupů a spotřeba tokenů jednotlivých
volání. Pokyny se udržují v `priv/incoming_documents/extraction_instructions.md`;
nové výjimky doplňujte stručným obecným pravidlem a regresním případem.
Nevkládejte celou historii účtenek do promptu. JSON schéma ověřuje strukturu,
nikoli pravdivost přečtených údajů; kontrola proti originálu zůstává nutná.

U starších výstupů XML a ručních oprav zůstává kompatibilní editor.
Při rozdílu účetního nastavení detail zobrazí tabulku: název pole, hodnota ze
vzoru a hodnota v návrhu. Hlavičkové sazby DPH (`szbDphSniz`, `szbDphSniz2`, `szbDphZakl`) jsou pevné:
server je vždy přebírá ze vzoru, i když model vrátí jiná čísla. Režim `bezPolozek`
určuje přítomnost položek. Ostatní odlišné účetní nastavení zůstává blokované.

V editoru „Opravit výstup vytěžení“ lze upravit XML bez dalšího volání OpenAI.
„Použít účetní nastavení ze vzoru“ přenese pevné hodnoty pouze do návrhu editoru;
částky nemění a měnu nepřepočítává. Následné „Uložit opravené XML“ musí projít
stejným bezpečným parserem, kontrolou účetních polí, povinných údajů, dat a součtů.
Chyby uvádějí konkrétní pole, u nesouladu celku také uvedenou částku, vypočtený
součet a rozdíl. Původní odpověď modelu zůstává zachována.

Úspěšná oprava vrátí doklad ke kontrole s prázdným dry-runem; nespouští import.
Přenos vyžaduje nový dry-run a následné schválení. Již schválené nebo nejisté
přenosy tímto editorem upravit nelze. Návrh v editoru se do úspěšného uložení
uchovává jen na otevřené stránce. Starší neúspěšné pokusy, jejichž XML aplikace
ještě neukládala, vyžadují jednou „Znovu vytěžit“.

### Odpovědi a chyby ABRA

Detail dokladu nabízí samostatně podrobnosti posledního dry-runu a posledního
přenosu: stav HTTP, typ obsahu, chyby a upozornění s polem, cestou, kódem chyby
a hodnotou (pokud je ABRA uvede), a původní tělo odpovědi. Text se zobrazuje
bezpečně jako text, nikoli jako HTML. Výpis těla je omezen na 100 000 znaků;
obsah odpovědi je privátní a nepatří do běžných logů.

HTTP 200 samo nestačí k potvrzení importu. Aplikace vyžaduje úspěch v těle,
očekávaný výsledek a při zápisu platné ID. JSON se zpracuje i při nesprávném
HTTP typu obsahu. XML/HTML, prázdné či nejednoznačné tělo se uloží k diagnostice;
při zápisu zůstává výsledek nejistý a další pokus pouze dohledává externí ID.
Starší neplatné odpovědi, jejichž tělo se ještě neukládalo, zpětně zobrazit nelze.
Nový dry-run může bezpečně doplnit aktuální diagnostiku; nejistý zápis se neopakuje.

Dosud neodeslaný doklad ve stavu „Ke kontrole“ lze výslovně vytěžit znovu,
například pro doplnění položek novým zadáním. Potvrzení upozorní na nahrazení
oprav a zrušení dry-runu. Po zahájení importu tato možnost není dostupná.
Po aktualizaci musí také starší úspěšný dry-run bez hashe přesného payloadu
proběhnout znovu před schválením.

Před síťovým zápisem se trvale uloží stav nejistého výsledku. Timeout, pád workeru
nebo nejednoznačná odpověď nikdy nezpůsobí slepé opakování POST. Další pokus
pouze vyhledává stabilní externí ID v původní firmě. Pokud dokument nenajde,
zůstává „Nutno ověřit v ABRA“ a nový zápis je blokován; obsluha musí stav
vyřešit ručně v ABRA. Tlačítko ověření samo nezakládá nový doklad.
Jednoznačně odmítnutý import vrátí doklad ke kontrole a vyžádá nový dry-run.

Originály, XML a odpovědi se neukládají do běžných logů: kontext vypíná logování
parametrů SQL zápisů, Phoenix filtruje editovaná pole a worker hlásí pouze
obecnou chybu. Nezapínejte ladicí logování těl HTTP požadavků/odpovědí.
Před odesíláním skutečných dokladů ověřte firemní podmínky zpracování dat v OpenAI.

## Stav ověření

Implementace obsahuje regresní testy XML, uploadu, autorizace, oprav, HTTP chyb,
upozornění, změny cíle a nejistého zápisu. HTTP používá výhradně `Req.Test`.
Při implementaci nebyly lokálně spuštěny testy ani proveden skutečný import.
Samostatná kontrola nad ručním přepisem PENNY ověřila 21 řádků + jednu účetní
korekci a přesné výsledné částky ve všech agendách. Tvorba výřezů byla ověřena
na syntetickém dlouhém obrázku a změněné testovací moduly byly zkompilované bez
spuštění. Skutečné vytěžení fotografie přes OpenAI ani akceptace korekce v ABRA
nebyly v tomto kroku ověřeny;
výsledky GitHub CI ověří uživatel. Kompilace a formátování byly ověřeny pomocí
Elixiru 1.20.4 na lokálním OTP 29.1.2; přesná verze OTP 29.1 z `.tool-versions`
nebyla dostupná, takže přesnou shodu toolchainu ověří CI.

Pilot ještě musí projít skutečnými doklady ve všech třech agendách, včetně
vícestránkového PDF, fotografie a účtenky s doloženým zaokrouhlením.
V ABRA je potřeba porovnat částky, DPH, účtování a chování položkového i
bezpoložkového importu.
Za dokončený pilot nelze považovat samotné validní XML nebo úspěšné CI.

API reference: [ABRA — import částek položek](https://podpora.flexibee.eu/cs/articles/4552353-import-castek-polozek-faktury),
[ABRA — validace položek](https://podpora.flexibee.eu/cs/articles/11776385-validace-vypoctu-cen-na-polozkach-rest-api),
[OpenAI — File inputs](https://developers.openai.com/api/docs/guides/file-inputs),
[ABRA — dry-run](https://podpora.flexibee.eu/en/articles/4720123-test-save-dry-run),
[ABRA — create/update](https://podpora.flexibee.eu/en/articles/4725944-setup-change-mode).

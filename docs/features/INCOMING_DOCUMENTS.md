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
a úhrady byly odstraněny. Ve výchozí podrobné variantě účetní vzor používá pouze aplikace při sestavení XML.
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

## Porovnání zadání

Při uploadu lze vybrat „Podrobný přepis → JSON → XML“ (dosavadní výchozí způsob)
nebo „Jednoduché zadání → XML“. U neodeslaného dokladu jsou samostatná tlačítka
pro nové vytěžení oběma způsoby. Nový pokus nahrazuje dosavadní opravy a ruší
dry-run; pro zachování obou výsledků nahrajte stejný originál jako druhý návrh
s jinou variantou a žádný duplicitní doklad neodesílejte.

Podrobné pokyny zůstávají v `priv/incoming_documents/extraction_instructions.md`.
Krátké alternativní pokyny jsou v `priv/incoming_documents/extraction_instructions_simple.md`;
požadavek sestavuje `lib/cozy_checkout/incoming_documents/extractor.ex`.
Jednoduchá varianta pošle celý originál a přesný uložený účetní vzor vybrané agendy,
bez JSON schématu a bez automatických výřezů. Používá jediný rezervovaný API
pokus bez automatického opravného volání. Vrácené XML prochází stejným parserem,
kontrolou účetního nastavení, řádků a rekapitulace; při chybě se zachová pro ruční
opravu. Úspěšný přepis neopravňuje k importu bez dry-runu a schválení.

Obě varianty mají limit `max_output_tokens=24000` a `store=false`. Zvolený způsob,
verze pokynů a spotřeba se ukládají do stávajících metadat; bez nové migrace či
proměnných prostředí. Při neúplné odpovědi se ukáže a uloží také
`incomplete_details.reason`, zejména `max_output_tokens`. Tento důvod může vést
k navýšení limitu; hotová odpověď s chybným množstvím sama vyčerpání limitu
nedokazuje. Zdroj: [OpenAI — reasoning a limity výstupu](https://developers.openai.com/api/docs/guides/reasoning).

Popis deterministického skládání XML a opravného přepisu níže platí pro
podrobnou variantu; společné kontroly, opravy XML a schvalování platí pro obě.
Přesnost obou variant je potřeba porovnat na stejných skutečných dokladech.

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

### Formulář přepisu a stažení návrhu i s chybami

Přepis JSON je zobrazený v přímém formuláři: číslo dokladu, data, dodavatel,
celková částka, rekapitulace DPH, legenda značek a všechny položky. Sazby i řádky
lze přidávat/odebírat. U rekapitulace jsou chyby u konkrétního pole; hláška uvádí
hodnotu nebo výpočet rozdílu. JSON aktuálního návrhu je pod formulářem pro
pokročilé úpravy. Původní odpověď modelu je dostupná odděleně.

Český formát čísel se převádí bez změny hodnot: `1 803,34`, včetně nezlomitelných
mezer, odpovídá `1803.34`. Převod se týká pouze číselných polí; číslo dokladu,
IČO/DIČ a texty se nemění. Nejednoznačné zápisy a skutečně chybějící částky se
neodhadují. Například O2: `1 490,36 + 312,98 = 1 803,34` je platná rekapitulace,
nikoli rozpor DPH. Matematické kontroly zůstávají zachované.

„Uložit návrh a zkontrolovat“ uloží i účetně chybný návrh (pokud má platnou
JSON strukturu). Přepis se nemusí opravit celý naráz. Platný návrh přejde ke kontrole;
chybný zůstane označený chybou a lze jej dál upravovat. Úpravy jsou uložené ve
sloupci `edited_data`, původní `extracted_data` se zachová. Vyžaduje to migraci
`20261105200000_add_incoming_edited_data`. Nové vytěžení ruční návrh vymaže.
Uložení znovu sestaví XML a ruší předchozí dry-run; proto nahrazuje případné
ruční opravy XML. Hash zahrnuje i aktuální XML, aby jiné okno nemohlo přepsat
mezitím provedenou opravu. Schválené/nejisté/odeslané dokumenty tímto měnit nelze.

„Stáhnout XML pro ABRA“ stáhne uložený návrh i přes účetní chyby, pokud jej lze
strukturálně sestavit. Soubor je označen `NEOVERENO-abra.xml`, chráněn admin PINem,
bez cache a poskytován jako příloha. Export sám nevolá OpenAI ani ABRA, nemění
stav a neschvaluje import. Při nesouladu se neprovádí vymyšlené vyrovnání a
částky řádků zůstávají v návrhu tak, jak byly přepsány. Účetní nastavení a externí
ID vždy pochází z aplikace. Pro položkový návrh nejsou exportované kontrolní
součty hlavičky, aby mohla ABRA sestavit hlavičku z položek. Pokud je aktuální XML
validní, export odpovídá běžnému importnímu payloadu; po schválení vrací přesně
uzamčené `sent_xml`. Neuložené opravy je před stažením potřeba uložit.

Neověřený návrh slouží k ruční diagnostice v testovací ABRA; před skutečným
importem ověřte chyby, částky, cílovou firmu a případnou duplicitu. Automatický
zápis z aplikace nadále vyžaduje úspěšnou kontrolu a schválení. Zcela neplatné
XML/JSON či údaje, které nelze mapovat do agendy, se místo souboru zobrazí chybou.

### Neúplné řádky a měna v částkách

U peněžních polí přepisu v CZK se toleruje také označení `Kč` nebo `CZK` před
částkou či za ní: `99.00 Kč`, `99,00 Kč` a `CZK 99.00` se mapují na XML číslo
`99.00`. Označení se neodstraňuje z množství, sazeb, identifikátorů ani textu;
cizí měna či složená jednotka `Kč/kg` se bez jasného významu nepřevádí. Původní
JSON a raw_text zůstávají zachované. V XML ABRA je správně desetinná tečka,
bez mezer a označení měny ([datové typy ABRA](https://podpora.flexibee.eu/cs/articles/4722246-podporovane-typy-promennych)).

Formulář i upozornění před stažením nyní uvádějí pokrytí celkové částky čitelnými
řádkovými částkami (pokud není některá cena výslovně bez DPH), neurčenou sazbu
a neurčený typ ceny. Rozpor se používá také jako zpětná vazba pro opravný přepis,
i když model vrátil complete=true. Rekapitulace DPH se nepovažuje za další položku
nákupu a z její částky se automaticky nevytváří chybějící služba.

Regresní neúplný O2 přepis obsahuje pouze Splátkový prodej 99 Kč, zatímco total
je 1902,34 Kč a rekapitulace 21 % obsahuje gross 1803,34 Kč. Upozornění proto
ukáže rozdíl řádků 1803,34 Kč. V diagnostickém exportu zůstane jediná doložená
položka, číselně očištěná; bez doplnění skutečných údajů nelze vytvořit úplný
import celé faktury. Prázdné typSzbDphK a typCenyDphK nejsou potvrzením nulové
sazby nebo osvobození. Stažení návrhu s upozorněními zůstává možné.

### Účetní předpis, interní číslo a diagnostický dry-run

U každého neodeslaného dokladu je sekce „Účetní nastavení dokladu“.
„Načíst předpisy zaúčtování z ABRA“ čte číselník `predpis-zauctovani` ze stejné
firmy jako přenos. Nabízí jen předpisy použitelné pro danou agendu (`modulFap`,
`modulZav`, `modulPokV`). Výběr používá sdílený vyhledávací picker i pro velké
číselníky. Číselník se načítá pouze na výslovný pokyn, po stránkách 200 záznamů,
nejvýše do bezpečnostního limitu 2000; neúplný výsledek je chyba. Účty se načítají
hromadně, nikoli samostatným dotazem pro každý předpis (bez N+1).

Při uložení se vybraný předpis znovu ověří proti aktuálnímu číselníku. Přenese se
`typUcOp`, nákladový účet `protiUcetVydej` do `protiUcet` a účty DPH. Původní
nákladové/DPH účty ze vzoru se při změně předpisu odstraní; chybějící účet se
neodhadne ani nezůstane účet pro potraviny, ale ponechá se k doplnění/ověření ABRA.
Primární účet závazku/pokladny a ostatní pevné nastavení zůstávají podle zvolené
agendy. U O2 vybírejte vhodný předpis služeb z vaší firmy; aplikace nehádá konkrétní
účet. Vzor i účetní volbu lze zobrazit v detailu. Ruční účetní volba je uložená
odděleně od původního vzoru v `accounting_settings`; vyžaduje migraci
`20261105210000_add_incoming_accounting_settings`. Uložení mění jen účetní
nastavení aktuálního návrhu, zachová již opravené XML údaje a ruší dry-run.

Pole „Interní číslo ABRA“ odpovídá `kod` (nejvýše 20 znaků). Je nepovinné:
prázdné pole jej do importu nepřidá a číslování ponechá ABRA. Dodavatelské číslo
zůstává samostatně v `cisDosle`. Model nikdy nepřiděluje interní číslo; server
přebírá jen explicitní ruční volbu a přepíše/odstraní případný starý `kod` z modelu.
Ruční import může interní číslo vyžadovat; o chování API rozhoduje typ dokladu,
řada a nastavení firmy, které je potřeba ověřit dry-runem, nikoli hádáním čísla.

„Ověřit návrh v ABRA bez zápisu (dry-run)“ funguje i u návrhu, který ještě
neprošel místní kontrolou. Posílá stejný diagnostický XML payload jako stažení,
vždy s `dry-run=true`. Ukáže konkrétní chyby/upozornění a případné vrácené interní
číslo/účty z `results[].content`. Návrh se po kontrole vrátí do původního stavu;
kladná diagnostika nepřidá schvalovací hash ani `ok=true` a neopravňuje k zápisu.
Automatický přenos dál vyžaduje validní aktuální XML a běžnou kontrolu stejného
payloadu tlačítkem „Zkontrolovat aktuální XML v ABRA“.

Interní číslo z dry-runu se nekopíruje do návrhu ani nerezervuje: ABRA jej uvolní
a při skutečném zápisu může přidělit jiné. Stejně tak dry-run neposuzuje věcnou
správnost volby účtu na základě obsahu faktury; předpis musí zkontrolovat obsluha.
Zdroje: [ABRA — testovací uložení](https://podpora.flexibee.eu/cs/articles/4720123-testovaci-ulozeni-dry-run),
[API metadata přijaté faktury](https://demo.flexibee.eu/c/demo/faktura-prijata/properties.json),
[API metadata předpisů](https://demo.flexibee.eu/c/demo/predpis-zauctovani/properties.json).

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
Podrobný automatický přepis vyžaduje alespoň jednu doloženou položku.

Položkový import používá `bezPolozek=false` a kolekci `polozkyDokladu` s elementem
`faktura-prijata-polozka`, `pokladni-pohyb-polozka` nebo `zavazek-polozka` podle agendy.
Kontrolní částky hlavičky zůstávají v aktuální verzi XML v databázi pro porovnání,
ale do ABRA se neposílají: ABRA vypočítá hlavičku z položek. Sekce „XML k odeslání“
ukazuje skutečný payload. Dry-run a schválený přenos používají shodné XML; jeho
hash se před zamčením ověřuje a přesné odeslané XML je uložené v `sent_xml`.
Dříve vydané/odeslané dokumenty zůstávají beze změny.

### Oprava neúspěšného vytěžení

Pokud přepis neprojde kontrolou ani po opravném pokusu, uloží se původní JSON,
konkrétní chyba a sestavené XML, je-li dostupné. Detail nabízí opravu ve formuláři nebo JSON bez
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

HTML odpovědi mají samostatnou čitelnou diagnostiku místo samotného zdrojového
kódu. Rozlišuje se přesměrování, HTTP 401/403, chyba serveru, pravděpodobná
přihlašovací stránka a nečekaná HTML stránka. U konkrétní chyby FreeMarker
(„object“ v `evidence/faktura-prijata/view.ftl`) zobrazí technický výpis od chyby,
bez navigace a skriptů, titulek a verzi uvedenou v HTML. To je chyba vykreslení
odpovědi, nikoli doklad o úspěšné validaci ani identifikace chybného pole faktury.
Text se pouze extrahuje a escapuje; HTML/JavaScript se nevykonává.

Pro nové odpovědi se uloží i metoda, adresa API bez userinfo/query, přepínač
dry-run, požadované Content-Type/Accept a omezené diagnostické hlavičky.
Přesměrovací Location se zobrazuje bez přihlašovacích údajů a query/fragmentu;
Set-Cookie ani Authorization se neukládají. Původní HTML zůstává zvlášť v zavřeném
technickém výpisu. Čitelná diagnostika se počítá i ze starších uložených odpovědí;
u nich nelze zpětně doplnit tehdejší adresu/hlavičky požadavku.

Klient již požaduje `.json` a `Accept: application/json`; vstupní XML má
`Content-Type: application/xml`. To odpovídá [dokumentaci formátů ABRA](https://podpora.flexibee.eu/cs/articles/4719998-podporovane-formaty).
Pokud přesto přijde webová stránka, diagnostika pomůže prověřit adresu, proxy
nebo konkrétní verzi ABRA, ale sama neodstraní chybu na serveru. Není zavedené
automatické opakování POST při HTML odpovědi. Dry-run nesplní schvalovací podmínku;
nejasný skutečný zápis zůstane nejistý a další pokusy pouze dohledávají externí ID.

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
Samostatná reprodukce zadaného úryvku O2 ověřila převod českého formátu a
konkrétní chybu pole při chybějící DPH; nejde o ověření celé faktury O2.
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

## Alternativa: ruční hlavička s návrhy z originálu

Vedle podrobného režimu je dostupný [formulář bez položek](INCOMING_DOCUMENT_FORM.md)
pro všechny tři agendy, včetně souhrnné DPH. Funguje i bez originálu a OpenAI;
vytěžené položky ukládá pouze do poznámky. Odesílání používá stejný dry-run a
schvalovací proces. Vstup: „Nový doklad přes formulář“ na seznamu přijatých dokladů.

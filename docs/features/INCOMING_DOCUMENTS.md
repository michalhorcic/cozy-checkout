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
Jsou bezpoložkové (`bezPolozek=true`); automaticky vytvořené účetní řádky,
identity, interní čísla, odkazy na původní firmu, dodavatele a úhrady byly
odstraněny. Souhrny a dodavatel jsou prázdné, účetní nastavení zůstává ze vzoru.
Přijatá faktura a karta mají předpis nákupu potravin, pokladna ostatní spotřebu.
Tyto pevné předpisy nejsou univerzální pro libovolný nákup. Pro pilot vybírejte
odpovídající doklady; odlišné účtování zpracujte ručně nebo změňte příslušný vzor
pro další uploady. Každý doklad uchovává vlastní kopii vzoru.

Podporovány jsou kladné doklady v CZK s rozpisem základů a DPH. Základní kontrola
ověřuje součet osvobozené částky, základů a DPH proti celku pomocí Decimal.
Nevymýšlí zaokrouhlení, neprovádí měnové přepočty, nezakládá adresářové firmy,
nespouští párování a nepřenáší položky či přílohy do ABRA. Údaje dodavatele
zůstávají v hlavičce dokladu. Správnost účtování a chování částek musí ověřit pilot.

## Konfigurace

Modul je ve výchozím stavu vypnutý. Pro pilot nastavte na serveru:

```sh
INCOMING_DOCUMENTS_ENABLED=true
OPENAI_API_KEY=...
INCOMING_DOCUMENTS_OPENAI_MODEL=...
```

Model musí podporovat obrázky a PDF přes Responses API. Model není natvrdo
vybraný; chybějící klíč nebo model se zobrazí jako chyba vytěžení.

Připojení ABRA se přebírá **ze stejné konfigurace jako faktury za ubytování**:
`ABRA_ACCOMMODATION_BASE_URL` a `ABRA_ACCOMMODATION_COMPANY_ID` s dosavadním
fallbackem na `ABRA_BASE_URL` / `ABRA_COMPANY_ID`; přihlášení používá
`ABRA_USERNAME` / `ABRA_PASSWORD`. Přepínač synchronizace ubytování není
podmínkou zapnutí přijatých dokladů. Před zapnutím ověřte, že tato konfigurace
ukazuje do testovací firmy (pro pilot `moruska_test_faktury`). UI vždy ukazuje
cílovou firmu. Změna cíle blokuje přenos dříve nahraných dokladů.

Migrace `20261105120000_create_incoming_documents` přidává jednu tabulku.
Originály jsou uloženy přímo v PostgreSQL (`bytea`), zahrnuty do zálohy databáze,
a nejsou dostupné jako veřejné statické soubory. Databáze může růst přibližně
o velikost originálů; ověřte kapacitu a obnovu záloh před pilotem. Seznam načítá
jen posledních 100 metadat jedním dotazem, bez originálů a XML a bez N+1.
Přenosy používají existující frontu Oban `billing`. Přijaté doklady se soft-delete
sloupcem nejsou fyzicky odstraňovány; UI zatím neposkytuje mazání.

## Kontrola a odeslání

1. Nahrát soubor, zvolit jednu ze tří agend. Stejný SHA-256 upozorní na duplicitu.
2. Oban pošle originál a očištěný vzor do OpenAI s `store=false`. Pokyny uvnitř
   originálu jsou pouze nedůvěryhodná data. Model nemá nástroje pro zápis do ABRA.
3. Aplikace přijme jen jeden doklad povolené agendy, povolená pole a účetní
   nastavení vzoru. Parser SAX nevytváří atomy z názvů polí a odmítá DTD, externí
   entity, vnořené operace, vazby a atributy polí. Cizí identity a stavy úhrad
   odstraní; vlastní stabilní externí ID a `create="ok" update="fail"` doplní server.
4. Porovnat originál a editovatelná pole. PDF používá prohlížeč se stránkováním
   a zvětšením, fotografie má posuvník zvětšení. Opravy mění XML bez nového
   volání modelu. Po uložení se předchozí dry-run zneplatní; zastaralé úpravy
   z druhého okna odmítne kontrola hashe.
5. Spustit kontrolu XML v ABRA (`dry-run=true`). Chyby blokují schválení,
   upozornění vyžadují samostatné výslovné potvrzení. Potvrdit kontrolu originálu
   a použít „Schválit a odeslat“. Přesně schválené XML se uloží a uzamkne.
6. Po přenosu se uloží odpověď a ID s odkazem do ABRA. Odeslaný doklad se neupravuje.

### Oprava neúspěšného vytěžení

Pokud výstup modelu neprojde kontrolou, uloží se původní XML i konkrétní chyba.
Při rozdílu účetního nastavení detail zobrazí tabulku: název pole, hodnota ze
vzoru a hodnota v návrhu. Číselně stejné sazby DPH (např. `12` a `12.0`) se
považují za shodné; skutečně odlišné nastavení zůstává blokované.

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
Při implementaci nebyly lokálně spuštěny testy ani proveden skutečný import;
výsledky GitHub CI ověří uživatel. Kompilace a formátování byly ověřeny pomocí
Elixiru 1.20.4 na lokálním OTP 29.1.2; přesná verze OTP 29.1 z `.tool-versions`
nebyla dostupná, takže přesnou shodu toolchainu ověří CI.

Pilot ještě musí projít skutečnými doklady ve všech třech agendách, včetně
vícestránkového PDF, fotografie a účtenky s doloženým zaokrouhlením.
V ABRA je potřeba porovnat částky, DPH, účtování a chování bezpoložkového importu.
Za dokončený pilot nelze považovat samotné validní XML nebo úspěšné CI.

API reference: [OpenAI — File inputs](https://developers.openai.com/api/docs/guides/file-inputs),
[ABRA — dry-run](https://podpora.flexibee.eu/en/articles/4720123-test-save-dry-run),
[ABRA — create/update](https://podpora.flexibee.eu/en/articles/4725944-setup-change-mode).

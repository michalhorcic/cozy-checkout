# Integrace s ABRA Flexi

Aplikace jednosměrně odesílá zaplacené barové objednávky jako vydané faktury
do REST API ABRA Flexi. Zálohové výzvy z modulu `Billing` mají samostatný,
ve výchozím stavu vypnutý [ruční export](ABRA_ACCOMMODATION.md).
Tento dokument popisuje současný kód a podklady pro jeho rozšíření;
uživatelský postup fakturace pobytů je v [BILLING.md](../features/BILLING.md).

## Konfigurace

[config/runtime.exs](../../config/runtime.exs) načítá ve všech prostředích nastavení
do `Application.fetch_env!(:cozy_checkout, :abra)`:

| Proměnná prostředí | Význam a současná výchozí hodnota |
| --- | --- |
| `ABRA_BASE_URL` | Kořen serveru bez koncového `/`; výchozí hodnota je konkrétní firemní server v `runtime.exs`. |
| `ABRA_COMPANY_ID` | Firma v cestě `/c/…`; výchozí hodnota je konkrétní firma v `runtime.exs`. |
| `ABRA_USERNAME` | API uživatel; výchozí prázdný řetězec. |
| `ABRA_PASSWORD` | API heslo; výchozí prázdný řetězec. |
| `ABRA_CASH_REGISTER_CODE` | Kód pokladny; výchozí `POKLADNA KČ`. |
| `ABRA_DOCUMENT_SERIES_CODE` | Číselná řada; výchozí `FAKTURA-BAR`. |
| `ABRA_BANK_ACCOUNT_CODE` | Kód bankovního účtu; výchozí `BANKOVNÍ ÚČET`. Prázdná hodnota vynechá účet z payloadu. |

Před nasazením nastavte cílový server, firmu a přístupy výslovně. Chybějící
přístupy integraci nevypnou: job se přesto zařadí a zkusí HTTP požadavek.
Samostatný přepínač vypnutí nyní neexistuje. Hesla patří do prostředí nasazení.

V cílové firmě musí existovat odpovídající číselníky a API uživatel musí mít
oprávnění k importu faktur a hotovostních úhrad. Builder má přímo v kódu typ
faktury `code:BAR`, účetní operaci `code:TRŽBA ZBOŽÍ` a typ hotovostního dokladu
`code:STANDARD`. Konfigurovatelné kódy zadávejte bez prefixu `code:`; builder jej
přidává. Význam těchto záznamů v cílové firmě ověřte s účetní.

## Průchod objednávky

1. `Sales.create_payment/1` nebo `Sales.create_payment_with_order_update/3`
   uloží platbu a přepočítá stav objednávky v transakci. Pokud je výsledný
   stav `paid`, po commitu vloží Oban job s `order_id`. Částečná úhrada export
   nespustí. Samotné `Sales.update_order/2` job nevytváří.
2. `AbraSyncWorker` běží ve frontě `abra_sync` se souběžností 3 a nejvýše pěti
   provedeními jednoho jobu. Na začátku zvýší `abra_sync_attempts` a zavolá
   `Abra.sync_order/1`.
3. `Sales.get_order_for_abra_sync!/1` načte nesmazanou objednávku, hosta,
   rezervaci s hostem, položky s produkty a platby. Smazané položky vyřadí;
   builder ignoruje také smazané platby.
4. `Abra.sync_order/1` odmítne jiný stav než `paid`. Existuje-li už
   `abra_document_id`, vrátí jej bez HTTP volání. Jinak sestaví payload,
   odešle jej a při úspěchu uloží stav `synced`, vzdálené ID, UTC čas
   synchronizace a vymaže chybu.
5. Worker po úspěchu nebo poslední vrácené chybě publikuje na PubSub tématu
   `abra_sync` zprávu `{:abra_sync_updated, order_id}`. Seznam objednávek podle
   ní obnoví příslušný řádek.

## Mapování faktury

[InvoiceBuilder](../../lib/cozy_checkout/abra/invoice_builder.ex) vytváří JSON
`{"winstrom": {"faktura-vydana": [faktura]}}` s jednou objednávkou.

| Pole ABRA | Zdroj / pravidlo |
| --- | --- |
| `id` | `ext:cozy-checkout:order:<UUID objednávky>`; stabilní externí identita. |
| `typDokl`, `rada`, `typUcOp` | BAR, nakonfigurovaná řada, TRŽBA ZBOŽÍ. |
| `varSym` | Číslo objednávky bez nečíselných znaků, posledních nejvýše 10 číslic; stejné pravidlo jako barový QR kód. |
| `datVyst`, `duzpPuv`, `duzpUcto`, `datUcto` | Datum z `order.inserted_at`, tedy vytvoření objednávky, nikoli platby nebo exportu. Bez převodu časového pásma. |
| `popis` | `Účtenka bar <číslo objednávky>`. |
| `nazFirmy` | `order.guest.name`, jinak `order.name`, jinak `Zákazník`. Host rezervace se pro tuto volbu nepoužívá. |
| `polozkyFaktury` | Aktivní položky, slevy a spropitné. |

Builder neposílá adresu odběratele, IČO, DIČ, splatnost, explicitní měnu ani
částky základů a DPH. Neuvedené výchozí hodnoty určuje cílová ABRA.

### Položky a finanční kontroly

- Položky se seskupují podle `product_id`, `unit_amount`, historické
  `unit_price` a historické `vat_rate`; množství se sečte. Odlišná historická
  sazba zůstane na samostatném řádku.
- `nazev` je současný název produktu, případně `Produkt`, doplněný o
  `unit_amount` v závorce. Název není historický snapshot; cena a DPH jsou
  z uložené položky objednávky.
- `mnozMj` a `cenaMj` jsou desetinné řetězce. Jednotková cena se zaokrouhlí
  na dvě místa, `typCenyDphK = typCeny.sDph` znamená cenu včetně DPH.
- Sleva je nejvýše součet položek. Rozdělí se poměrně podle původních sazeb
  DPH do záporných řádků `Sleva` s množstvím 1; podíly se zaokrouhlí na haléře
  a poslední skupina dostane zbytek.
- Kladné spropitné je řádek `Spropitné`, množství 1, sazba 0 %.

| Sazba | `typSzbDphK` |
| --- | --- |
| 21 % | `typSzbDph.dphZakl` |
| 12 % | `typSzbDph.dphSniz` |
| 0 % | `typSzbDph.dphOsv` |

Jiná sazba vyvolá `ArgumentError`. Před HTTP voláním musí součet položek včetně
slev a spropitného přesně odpovídat `order.total_amount`; u zaplaceného účtu
musí této částce odpovídat i součet aktivních plateb. Výpočty používají `Decimal`.
`Abra.sync_order/1` zachytí `ArgumentError` builderu a vrátí chybu synchronizace.

### Úhrady

| Metoda | Export |
| --- | --- |
| `cash` | Součet aktivních hotovostních plateb vytvoří jednu `hotovostni-uhrada`: `typDokl = code:STANDARD`, nakonfigurovaná `pokladna`, `castka` na dvě místa a `datumUhrady` shodné s datem vytvoření objednávky. |
| `qr_code` | Nevytváří hotovostní úhradu. Při neprázdném kódu účtu přidá `bankovniUcet = code:<kód>`; bankovní pohyb páruje účetní v ABRA. |
| Hotovost + QR | Hotovostní úhrada pouze na hotovostní část a údaj o bankovním účtu. |

Ostatní metody nemají zvláštní mapování úhrady. Jednotlivá ID plateb, reference
a skutečná data přijetí se nepřenášejí. Lokální `paid` u QR tedy neznamená
automatické spárování v účetnictví. Zpětné čtení banky ani webhooky zde nejsou.

## HTTP a chyby

[Client](../../lib/cozy_checkout/abra/client.ex) používá `Req.post/2` s JSON tělem,
Basic autentizací, hlavičkou `Accept: application/json` a adresou:

```text
POST <ABRA_BASE_URL>/c/<ABRA_COMPANY_ID>/faktura-vydana.json
```

Požadavek má `retry: false`; opakování řídí Oban se standardním backoffem.
Vlastní HTTP timeout ani vlastní backoff zde nastavený není.

Úspěch vyžaduje HTTP 200 nebo 201 a první záznam `winstrom.results` bez
importních chyb s platným `id`: kladným celým číslem nebo neprázdným řetězcem.
Číselné ID se uloží jako řetězec. Importní chyby i při HTTP 200 jsou neúspěch.
Neplatná struktura/ID vrací `unexpected_response`, importní chyba bez použitelné
zprávy `import_error`. Jiný HTTP status vrací první importní zprávu, jinak
`HTTP <status>`. Síťová chyba se převede přes `Exception.message/1`.
Klient chyby loguje s prefixem `[Abra]`.

## Stav a obsluha

Údaje jsou na `orders`, přidané migrací
[20260819000002](../../priv/repo/migrations/20260819000002_add_abra_sync_to_orders.exs).

| Pole | Význam |
| --- | --- |
| `abra_sync_status` | `nil` = bez výsledku / čeká; `synced` = uložené vzdálené ID; `failed` = poslední vrácená chyba po vyčerpání pokusů. |
| `abra_sync_attempts` | Počet zahájených provedení workeru napříč joby; ruční retry jej nenuluje. |
| `abra_document_id` | ID z ABRA; zabraňuje dalším HTTP požadavkům pro tento účet. |
| `abra_synced_at` | UTC čas úspěšné synchronizace. |
| `abra_sync_error` | Chyba uložená při konečném neúspěchu workeru. |

Administrace `/admin/orders` má sloupec Abra; `/admin/orders/:id` u zaplaceného
účtu sekci Abra Flexi s výsledkem, ID a časem, případně chybou a počtem pokusů.
**Spustit sync** / **Opakovat sync** volá `Sales.retry_abra_sync/1`: vymaže
stav a chybu a vloží nový job. Vzdálené ID ani čítač nemaže. Seznam obnovuje stav
přes PubSub; detail lze znovu načíst. Administrace vyžaduje PIN.

Běžná vrácená chyba při prvních čtyřech pokusech nezapisuje `failed` ani chybu
na objednávku. Poslední vrácená chyba je uloží a worker vrátí `{:cancel, reason}`
(job je `cancelled`, nikoli `discarded`). Neočekávané výjimky, například
nenalezená objednávka, tímto zpracováním neprojdou; jejich historii hledejte
v Oban dashboardu `/admin/system`.

Při potížích zkontrolujte chybu, historii jobu ve frontě `abra_sync`, přístupy,
kódy číselníků a shodu částek. Po opravě použijte ruční opakování.
„Čeká na sync“ samo o sobě nedokazuje existenci čekajícího jobu.

### Duplicity a provozní omezení

Uložené `abra_document_id` brání opětovnému odeslání. Při ztracené odpovědi
nebo souběhu se ochrana opírá o externí ID `ext:cozy-checkout:order:<UUID>`.
Test simuluje vzdálené rozpoznání této identity; nepotvrzuje skutečnou instanci,
zejména opakovaný import vnořené hotovostní úhrady. Ověřte jej v oddělené
testovací firmě. Po timeoutu zkontrolujte vzdálený doklad i úhrady, protože
požadavek už mohl být přijat.

Worker nemá unikátnost Oban jobů ani zámek celého exportu. Platba a vložení jobu
jsou oddělené operace; chyba vložení jobu se nepromítá do výsledku vytvoření
platby. Výsledek `Sales.mark_order_abra_synced/2` se před vrácením úspěchu také
nekontroluje. HTTP import a lokální zápis tedy nejsou atomické.

Integrace neukládá payload ani samostatný audit exportů. Již synchronizovaný
doklad neaktualizuje a neposílá automatická storna, opravy či vratky po lokální
změně dat. Retry s uloženým vzdáleným ID pouze vrátí ID, nevynutí aktualizaci.

## Podklady pro fakturaci pobytů

Tato část je návrh další etapy, nikoli hotová funkcionalita. Barový builder
očekává `Sales.Order`, barové kódy, datum vytvoření účtu a ceny s DPH;
pobytovou kalkulaci mu nelze přímo předat.

Zdroje pro rozšíření: [Billing](../../lib/cozy_checkout/billing.ex),
[Document](../../lib/cozy_checkout/billing/document.ex),
[Payment](../../lib/cozy_checkout/billing/payment.ex),
[Money](../../lib/cozy_checkout/billing/money.ex).

| Existující data | Význam pro budoucí export |
| --- | --- |
| `billing_documents.id`, `kind`, `number`, `variable_symbol` | Identita konkrétního vydaného dokladu a původní číslo/VS. Typy `advance`, `tax_receipt`, `final`, `correction`. |
| `issued_on`, `tax_date`, `due_on` | Datum vystavení, DUZP a splatnost; nepoužívat datum rezervace/exportu. |
| `snapshot`, `lines` | Uložený dodavatel, odběratel, měna, položky a daňové údaje; neexportovat aktuální profil nebo ceník. |
| `snapshot["deductions"]` | Odpočty zdaněných záloh včetně `source_document_id`; zachovat původní základy, DPH a zdrojový doklad. |
| `parent_id` | Vazba opravného dokladu na opravovaný doklad. |
| `billing_payments` | Skutečné příjmy/vratky (`receipt`/`refund`), `paid_on`, metoda `bank`/`cash`/`card`, reference, vazby `document_id` a `tax_document_id`. |

S účetní je potřeba určit cílové evidence, typy dokladů, číselné řady, operace,
zachování lokálního čísla a daňové režimy. Pobytové položky rozlišují zdanitelnou
sazbu 0 % a plnění mimo předmět DPH; nynější barové mapování obojí nepokrývá.

- Zálohová výzva (`advance`) není daňový doklad ani přijatá platba.
- Skutečná záloha a její daňový doklad (`tax_receipt`) jsou propojené záznamy;
  několik plateb může mít několik daňových dokladů.
- Konečná faktura (`final`) odpočítává již zdaněné zálohy. Odpočet není další
  příjem peněz; neuhrazená výzva nic neodpočítává.
- Oprava (`correction`) zachovává vazbu na původní doklad; vratka je samostatný
  pohyb peněz. Nulový doplatek i přeplatek jsou platné stavy.

Rozšíření má používat samostatné stabilní externí identity dokladů, odpočtů
a plateb oddělené od barového prostoru `order`. Potřebuje trvalý stav a historii
synchronizace, bezpečné zařazení jobu spolu s lokálním zápisem, ochranu souběhu
a opakování i řešení částečně dokončeného přenosu. Navazující opravy a odpočty
vyžadují nejprve vzdálené identity zdrojových dokladů. Vydané doklady a uložená
PDF se při tom nesmějí měnit.

HTTP klient a princip Oban retry lze využít; pobytová data potřebují vlastní
mapování a stav. Budoucí směr zůstává z aplikace do účetnictví; automatické
bankovní párování zpět současný kód neposkytuje.

## Kód a ověření

- [Abra](../../lib/cozy_checkout/abra.ex): orchestrace a kontrola uloženého ID.
- [Sales](../../lib/cozy_checkout/sales.ex): zařazení jobů, načítání a ukládání stavů.
- [AbraSyncWorker](../../lib/cozy_checkout/workers/abra_sync_worker.ex): pokusy a PubSub.
- [config/config.exs](../../config/config.exs): fronty Oban.
- [abra-vzor.xml](../../lib/cozy_checkout/abra/abra-vzor.xml): referenční XML; runtime
  jej nenačítá, skutečný přenos vytváří JSON builder.
- [Finanční testy](../development/FINANCIAL_TESTS.md): pokrytí a omezení ověření.

```sh
PGUSER=elixir PGPASSWORD='' mix test test/cozy_checkout/financial/abra_client_test.exs test/cozy_checkout/financial/abra_sync_test.exs test/cozy_checkout/financial/accounting_amounts_test.exs test/cozy_checkout/financial/qr_code_test.exs test/cozy_checkout/financial/sales_money_test.exs
PGUSER=elixir PGPASSWORD='' mix precommit
```

HTTP v testech směruje přes `Req.Test`; Oban běží v manuálním testovacím režimu.
Testy nevytvářejí skutečné doklady. Pokrývají HTTP/importní chyby, timeout,
uložené ID, opakování po ztracené odpovědi, stavy workeru, součty, smíšené sazby,
historickou DPH, slevy, spropitné, soft delete, kombinované úhrady a shodu VS
s QR. Skutečné číselníky a vzdálenou idempotenci je nutné ověřit samostatně.

## Načítání banky pro ubytování (samostatný čtecí blok)

Samostatný přepínač `ABRA_ACCOMMODATION_BANK_ENABLED=true` zapíná načítání
každých 15 minut. Výchozí stav je vypnutý a nezávisí na přepínači exportu
`ABRA_ACCOMMODATION_ENABLED`. Používá stejnou pobytovou cílovou instanci,
firmu, přístupové údaje a `ABRA_ACCOMMODATION_BANK_ACCOUNT_CODE` jako zálohové
výzvy. `ABRA_ACCOMMODATION_ENABLED_FROM` omezuje návrhy na nové pobyty.
Před zapnutím je nutné spustit přidávací migraci bankovních tabulek.

Přehled **Doklady z rezervací → Bankovní pohyby** (`/admin/billing/bank`)
chrání stávající admin PIN. Zobrazuje částku v měně pohybu, datum, VS,
protistranu, vzdálené ID, návrh cílového dokladu, rozdíl a důvod ruční kontroly.
Návrhy se zobrazují i ve fakturaci pobytu. Tlačítko **Načíst banku** zařadí
Oban job; **Obnovit přehled** načte místní stav včetně posledního úspěchu,
chyby a případného neúplného průchodu. Import má vlastní frontové úlohy,
barový export se nemění.

Import pouze čte `banka.json`, řadí podle ID a stránkuje po 100 záznamech.
V databázi uchovává pouze nakonfigurovaný účet, příjmy i výdaje, původní data
pohybu a stav hlášeného párování. Účet bankovního pohybu čte z pole `banka`
(relace `bankovni-ucet`); fakturové pole `bankovniUcet` se zde nepoužívá.
Chyba neplatného pohybu uvádí pořadí záznamu a název odmítnutého pole,
bez hodnot a osobních údajů. Identita je jedinečná podle instance, firmy,
evidence a vzdáleného ID. Stránka a bod pokračování se zapisují atomicky pod
zámkem; opakování aktualizuje stejný pohyb. Každá nová dokončená synchronizace
prochází celou evidenci bez filtru data, takže zahrne i pozdní starší pohyby,
změny a chybějící záznamy. Chybějící záznamy označí až dokončený průchod,
fyzicky je nemaže. Při výpadku pokračuje od uložené stránky.

Jde o vědomou mezietapu oproti Changes API v plánu: úplný průchod je dražší
a stránkování přes offset neposkytuje konzistentní vzdálený snapshot.
Souběžné změny evidence mohou do příštího úplného průchodu způsobit vynechání
nebo označení přítomného pohybu jako chybějícího. Před potvrzováním plateb je
nutné ověřit počáteční synchronizaci, Changes API a úplnost sledování změn
vazeb proti konkrétní testovací firmě. Tento blok tuto záruku neposkytuje.

Návrh vyžaduje příjem v CZK se správným VS vydané výzvy nebo konečné faktury
nového, nesmazaného pobytu. VS se porovnává přesně včetně úvodních nul.
Starý VS výzvy vede ke konečné faktuře stejného pobytu, pokud již existuje.
Rozdíl se počítá proti částce výzvy, nebo zbývající úhradě konečné faktury
po místních platbách a opravách. Již evidované místní platby vyvolají upozornění
na možnou duplicitu. Výdaje, cizí měny, chybějící VS, chybějící pohyby,
nejednoznačnost a hlášené párování zůstávají bez návrhu k ruční kontrole.

**Návrhy nepotvrzují dostupnost částky.** Ani `sparovano=false` nevylučuje
částečné nebo konfliktní párování. Vazby a volnou částku bude muset budoucí
potvrzovací blok ověřit novým čtením přímo v ABRA. Import nevolá
`Billing.record_payment/2`, nevytváří ZDD ani neprovádí vzdálené zápisy.
Stávající ruční evidence skutečných plateb zůstává samostatná.

Zásadní testy jsou v `abra_bank_test.exs` a `abra_bank_live_test.exs`: opakování,
stránkování a výpadek, starší pohyb, změna a chybějící pohyb, účet, měna, směr,
párování, starší pobyty, izolace firem, starý VS a absence finančních zápisů,
PIN ochrana. HTTP se simuluje přes `Req.Test`. Lokální testy nebyly spuštěny;
výsledky CI ověří uživatel. Skutečné API testovací firmy nebylo ověřeno.

## Ruční potvrzení bankovní zálohy a ZDD

Navazující blok dovoluje v přehledu banky výslovně potvrdit **celý bankovní
příjem k jedné zálohové výzvě**. Vyžaduje již úspěšný export výzvy do stejné
firmy, nový pobyt, CZK a shodný VS. Potvrzení je samostatné od importu banky.
Konečné faktury, příjmy bez výzvy, vratky, rozdělení pohybu a přeplatky nad
zbývající částku výzvy tato implementace nepotvrzuje.

Přidávací migrace `20261026160000_create_abra_bank_confirmations.exs` zavádí
jedinečnou vazbu pohybu a místní platby i uložený požadavek na synchronizaci.
Po migraci zůstává potvrzování vypnuté. Pro zkoušení v testovací firmě nastavte:

```sh
ABRA_ACCOMMODATION_ENABLED=true
ABRA_ACCOMMODATION_BANK_CONFIRMATION_ENABLED=true
```

Stávající nastavení instance, testovací firmy, účtu, přístupů a okamžiku
zapojení nových pobytů se používá dál. Import banky má vlastní přepínač.
Čtyři místní číselné řady musí být nastavené; číslo ZDD smí mít nejvýše
20 znaků. Ověření proti skutečné ABRA provádí uživatel na svém lokálu.

### Mapování ze zaslaného XML ZDD

Výchozí kódy byly převzaty z `zdd-doklad-o-platbe.xml`, z hlavičky účetního
souhrnného ZDD (nikoli z neúčetní výzvy ve stejném souboru). Osobní údaje,
číslo vzoru a vzdálené identity se nekopírují. Každou hodnotu lze změnit
proměnnou prostředí:

| Proměnná (prefix `ABRA_ACCOMMODATION_`) | Výchozí hodnota podle XML |
| --- | --- |
| `ZDD_TYPE_CODE` | `ZDD` |
| `ZDD_VAT_CODE` | `01-02` |
| `ZDD_VAT_REPORT_CODE` | `A.4-5.AUTO` |
| `ZDD_OPERATION_CODE` | `ZÁLOHA PŘIJATÁ` |
| `ZDD_PRIMARY_ACCOUNT` | `324999` |
| `ZDD_COUNTER_ACCOUNT` | `324001` |
| `ZDD_VAT12_ACCOUNT` | `343200` |
| `ZDD_VAT21_ACCOUNT` | `343100` |
| `ZDD_OUTSIDE_MODE` | `sumOsv` |

Souhrnné ZDD posílá oddělené základy a DPH 12 % a 21 %. Poplatek v místním
režimu `outside` mapuje podle dodaného vzoru do `sumOsv`; nastavení jiného
`ZDD_OUTSIDE_MODE` jeho export zastaví. Zdanitelná nula se za tento režim
nepovažuje a zůstává nepodporovaná. Druhá snížená sazba se neexportuje.
Vzorek má kladné částky pouze pro 12 % a poplatek; 21% částky a účtování
plnění mimo DPH je potřeba ověřit na konkrétních případech.

Test částek vzoru očekává základ 241 107,14 Kč, DPH 28 932,86 Kč a poplatek
5 495 Kč. Doklad používá vlastní místní číslo, VS, snapshot zákazníka a
částky místního ZDD. Nesdílí řadu `FAKTURA-STANDARD` a nepřebírá vzorové
zaokrouhlení na celé koruny. DUZP i datum účtování jsou skutečným datem
přijetí bankovní zálohy; vystavení má místní datum vystavení. Před ostrým
zapnutím ověřte výsledné DPH a účty v testovací firmě.

### Potvrzení a opakování

1. U návrhu zálohy zvolte **Zkontrolovat přijetí zálohy**. Aplikace načte
   aktuální bankovní pohyb, celý seznam vazeb a zdrojovou výzvu z ABRA.
2. Náhled ukáže částku, datum a cílovou výzvu. **Potvrdit zálohu a vystavit ZDD**
   znovu čte ABRA; při nedostupnosti, změně nebo konfliktu nic místně nezapíše.
3. Pod zámkem pobytu a pohybu vzniknou v jedné místní transakci platba,
   uzamčené ZDD a Oban požadavek. Unikátní vazby a identita požadavku chrání
   opakované potvrzení. Stejná dosud ručně zaevidovaná bankovní platba
   (pobyt, datum, částka) potvrzení zablokuje kvůli možné duplicitě.
4. Worker dohledá ZDD podle stabilního externího ID, případně ho vytvoří,
   ověří celý rozpis částek a účetní nastavení, spáruje existující bankovní
   příjem s výzvou a připojí existující ZDD přes `vytvor-vazbu-zdd`.
   Nevytváří bankovní ani pokladní pohyb. Po každé vazbě zkontroluje výsledek.
5. Po timeoutu znovu čte vzdálený výsledek. Shodné existující úhrady a ZDD vazby
   použije; konfliktní stav nepřepisuje. Místní platba a ZDD při výpadku
   zůstávají uložené, vedle nich je vidět samostatný stav účetního přenosu.

Volnost pohybu se neodvozuje pouze z `sparovano`. Kontrola spojuje
`vazebni-doklady` (cíl a typ vazby) s `vazby` (částka), vyžaduje explicitní
stav storna a úplný seznam relací. Shodná existující úhrada celé bankovní
částky téže výzvě se využije; částečně obsazený pohyb, jiné cíle, neznámé
nebo neúplné vazby se odmítnou. Tyto předpoklady tvaru odpovědí se ještě
musí ověřit vůči používané verzi ABRA. Neznámá odpověď vede k zastavení.

Nové čtení neposkytuje vzdálený zámek: mezi kontrolou a zápisem může zasáhnout
účetní či automatizace firmy. Kontroly v workeru a po operacích odhalují
konflikt; aplikace nepřepisuje místní historii ani neopravuje cizí párování.
Změna, storno nebo nepřítomnost již potvrzeného pohybu při dalším importu
vyvolá stav **Vyžaduje účetní kontrolu**, včetně již přeneseného potvrzení.
Takový konflikt nemá automatické opakování ani tlačítko vrácení platby.
Tlačítko **Znovu ověřit a obnovit přenos** lze použít i po konfliktu.
Nejdřív pouze čte aktuální ZDD, výzvu, pohyb a vazby. Pokud stále neodpovídají
uloženému potvrzení, přenos neobnoví. Pokud všechny kontroly projdou, zařadí
přenos stejného potvrzení; nová místní platba ani nový místní ZDD nevzniká.
Stávající vzdálené ZDD se dál dohledává pod stejnou stabilní identitou.

### Lokální ověření před zapnutím

Na testovací firmě vystavte a exportujte novou výzvu. Připravte bankovní příjem
se stejným VS (např. dílčí zálohu), načtěte ho a potvrďte. V aplikaci i ABRA
ověřte částku a datum platby, právě jeden ZDD, daňové součty a obě vazby.
Zopakujte požadavek i účetní přenos a ověřte, že nepřibyl doklad nebo příjem.
Dále vyzkoušejte již shodně spárovaný příjem, cizí/částečné párování,
výpadek přenosu a dodatečnou změnu potvrzeného pohybu. Vypněte automatizace
firmy, které samy vytvářejí ZDD nebo konkurují explicitnímu párování.

Zásadní testy jsou v `abra_bank_payments_test.exs`: částky XML, dvojí potvrzení,
rollback, čerstvá změna a výpadek, vznik konečné faktury, opakování po ztracené
odpovědi při vytvoření ZDD, úhradě i vazbě, shodné a konfliktní párování,
možná ruční duplicita a vypnutí funkce. HTTP simuluje `Req.Test`; skutečné
účetní doklady v ABRA při testech nevznikají. Projektové testy nebyly lokálně
spuštěny podle AGENTS.md; výsledky CI ověří uživatel.

Přehled `vazebni-doklady` může kromě hran obsahovat i samotný výchozí doklad.
Kontrola vynechá pouze jednoznačnou vlastní položku banky: shodné ID pohybu,
modul banky, prázdný typ a žádné platné ID účetní vazby. Neodvozuje tím volnou
částku; ostatní vazby a jejich částky musí stále projít úplnou kontrolou.
Odmítnutí nově rozlišuje jiný cílový doklad, částečnou částku, chybějící
protějšek a nerozpoznaný typ a uvádí identifikátory pro dohledání v ABRA.


Kontaktní e-mail se na vydané faktuře posílá jako `kontaktEmail`.
Dřívější uložené požadavky mohly obsahovat nesprávný klíč `email`, který ABRA
nepodporuje. Kontrola jeho vrácení již nevyžaduje; jejich uložený payload ani
vydané doklady se nepřepisují. Nové požadavky kontrolují skutečné pole
`kontaktEmail`. Při neshodě ZDD hláška vypisuje názvy odlišných polí bez jejich
hodnot a bez zveřejnění osobních údajů. Chybná částka, daňové nebo účetní
nastavení dál blokují přenos.

## Konečná faktura s odpočty

Na výslovný požadavek uživatele lze připravit a exportovat pracovní vyúčtování
ještě před dodáním schváleného účetního vzoru. Export má samostatný přepínač
`ABRA_ACCOMMODATION_FINAL_ENABLED`, výchozím stavem vypnutý, a používá stávající
připojení k ABRA pro ubytování. Používá stávající detail dokladu a evidenci exportů; přidávací migrace
ukládá neměnné podklady pro kontrolu výsledku a zdrojových ZDD.

[Postup pro účetní, nastavení, příklad a otevřené předpoklady](ABRA_ACCOUNTANT_REVIEW.md).
Přenos zachovává místní finální snapshot a původní základy/DPH jednotlivých
ZDD, posílá skutečné `odpocty-zaloh` se stabilními identitami a kontroluje
výsledné částky, položky i vazby. Nevytváří další bankovní nebo hotovostní
příjem a nepřijímá automatické doporučené změny částek. ZDD musí mít dokončený
přenos do stejného cíle a být stále k dispozici k odpočtu.

Faktura se nejprve vytvoří bez odpočtů a zpětně ověří. Odpočty se pak přidávají
po jednom samostatnou operací na již existujícím dokladu. Po každé operaci
se ověří odpovídající mezistav včetně zbývající částky a zdrojových vazeb.
Do dokončení přenosu tak ABRA může ukazovat celou cenu nebo jen část odpočtů.
Při opakování se čte aktuální stav: hotová faktura se znovu nevytváří a již
ověřený odpočet se znovu neposílá. Stejný uložený export lze použít i po chybě
původního společného požadavku, pokud vzdálený stav projde kontrolami.

V JSON se odpočty posílají jako `"odpocty-zaloh": [{...}]`, bez XML obalu
`odpocet` ([oficiální příklad JSON](https://podpora.flexibee.eu/cs/articles/4729457-odpocet-zaloh-a-zdd-api)).
Starší uložené exporty s tímto obalem lze obnovit beze změny jejich snapshotu;
samostatný požadavek na odpočet se odešle ve správném JSON formátu. Částky
a volby odpočtu ZDD vycházejí z [dokumentace odpočtů](https://demo.flexibee.eu/devdoc/odpocet-zaloh).

Kontrola odpočtu vychází z [čerpání ZDD přes REST API](https://podpora.flexibee.eu/cs/articles/3422294-cerpani-zdd-rest-api):
`vazby/vazba/a` odkazuje na konkrétní odpočtovou položku konečné faktury,
`b` na zdrojové ZDD. V JSON jsou cíle dostupné přes `a@ref` a `b@ref`.
Vazby se čtou také z relace `vazby` každého zdrojového ZDD: relace hlavičky
konečné faktury může být prázdná, protože konec `a` míří na její položku.
Ze zdrojových vazeb se vybírají pouze odpočty do položek právě ověřované
faktury; bankovní vazby a odpočty do jiných faktur se do jejího výsledku
nezapočítávají. Odkazy podporují i prefix `/v2/c/`. Stejná vazba vrácená
z obou stran se započte jednou; nedostupné čtení zdroje přenos zastaví.
Částky se kontrolují z navázaných položek, nikoli ze spárované částky `castka`
na vazbě. Každá odpočtová položka musí mít právě jednu ověřenou vazbu;
základy a DPH se porovnávají samostatně pro každé zdrojové ZDD. Jeden zdroj
může mít několik položek a vazeb (například ubytování a poplatek).
Graf `vazebni-doklady` slouží také ke kontrole cílových dokladů, ale jeho počet
řádků nemusí odpovídat počtu zdrojů. Při nejasných odkazech nebo neúplném
odpočtu se další zápisy zastaví; chyba rozliší odkazy položek, částky a graf.

Typ běžné vydané faktury, účet pohledávky, účetní předpis a daňové členění
vyúčtování nejsou schválené vzorem finální faktury. Výchozí `FAKTURA` je
pracovní návrh kódu typu; musí v testovací firmě existovat, jinak jej nastavte
na skutečný vhodný typ. Zdanitelné sazby jsou omezené na 12 % a 21 %,
poplatek mimo DPH používá dosavadní explicitní mapování. Přeplatky, vratky,
opravy, nepřenesené ZDD a již místně zaznamenané doplatky se zastaví.

Zásadní testy jsou v `abra_final_invoice_export_test.exs`: několik dílčích ZDD,
haléře, poplatek, žádná přijatá záloha, nulový doplatek, vypnutí a ochrana uloženého cíle,
nedokončený nebo vyčerpaný zdroj, timeout bez duplicity a neshoda daně či
zdrojové vazby. Testy skutečné účetní schválení ani živé API nenahrazují.

Položky vydané faktury se načítají přes relaci `polozkyDokladu`; název
`polozkyFaktury` slouží pro zápis položek do faktury. Čtení stránkuje všechny
položky i vazby. Chybějící relace se nepovažuje za prázdný seznam: chyba
obsahuje konkrétní název relace a HTTP stav, aby šla příčina dohledat.

# Přijaté doklady – zadání pro implementaci v Codexu

## Kde začít v novém vlákně

Přečti AGENTS.md, tento plán, existující ABRA klienty a testy zejména pro přenos PDF a ověření vydané faktury. Začni etapou 0. Dokud chybí podklady, můžeš připravit lokální datový kontrakt, validátor a kontrolní obrazovku, ale nevymýšlej XML pole, účetní kódy ani chování cílové firmy. Každou etapu uzavři uvedeným důkazem. Do produkční ABRA v rámci vývoje nezapisuj.

Výchozí návrh je interní modul Cozy Checkout v současném Phoenix release na Coolify. Využij Ecto/PostgreSQL, Oban, Req a stávající admin autentizaci. Přijaté doklady odděl od prodejů, ubytování, banky a GET-only klienta Economics.AbraClient. Pokud zadavatel chce samostatnou aplikaci, rozhodněte před první migrací.

## Rozsah a rozhodnutí

Jedna firma, jeden doklad v souboru, PDF nebo JPEG/PNG, tuzemské běžné doklady v CZK, dvě agendy a zpočátku jeden schválený profil pro každou. Zachovej všechny položky v aplikaci. V ABRA může být dle profilu položkový doklad nebo účetní souhrn, pouze pokud to účetní výslovně potvrdí. Podporuj více sazeb, vážené množství, přiřaditelné slevy a explicitní zaokrouhlení. Smíšené účtování mimo schválený profil, zálohy, dobropisy, cizí měny, reverse charge a nejednoznačné slevy zastav k ručnímu zpracování. Odlož e-mailový příjem, skladové párování, tvorbu dodavatelů a automatické schvalování.

OpenAI čte doklad do JSON. Elixir rozhoduje podle profilu, počítá a skládá XML. Přímé generování XML ze vzoru sice zkrátí první experiment, ale každý pokus přenáší vzor, komplikuje ruční opravy a může změnit účtování nebo přenést identitu starého dokladu. Deterministický export stojí práci jednou pro každou agendu. Oprava JSON ani změna profilu nevyžaduje nové placené vytěžení.

## Etapa 0 – ověřit účetní výsledek před vývojem exportéru

Vyžádej pro každý profil originál a export správně zaúčtovaného příkladu, pro PENNY také předchozí návrh importu. Získej testovací firmu se stejnými číselníky a nastavením, její identifikátor, verzi a oprávnění ke čtení, zápisu a přílohám. Přihlašovací údaje nastav mimo repo. S účetní rozhodni, zda potřebuje v ABRA jednotlivé položky, jak řešit různé druhy nákladů v jednom nákupu, jaké datum se doplňuje při přijetí a jak se má následně párovat karta. Zjisti, kdo schvaluje a jak důvěryhodně zaznamenat jeho identitu, pokud je admin PIN sdílený.

Pro každý profil vytvoř tabulku mapování: význam → zdroj (doklad/profil/uživatel/ABRA) → zapisovatelná vlastnost cílové evidence → povinnost → očekávaná hodnota po načtení. Použij export jako příklad a metadata cílové firmy jako ověření. Z minimálního seznamu povolených polí sestav nový dokument. Nekopíruj export a nemaž z něj dodatečně nežádoucí pole. Zakázat převzetí ID, UUID, interního čísla, auditních údajů, vazeb a stavů úhrad. Číslo od dodavatele zachovat, vlastní interní číslo přidělí Flexi. Kartou zaplaceno je informace z originálu. Nevytvářet úhradu ani měnit saldo podle tohoto údaje.

Profil verzuj jako jednoduchou konfiguraci: cílová firma a agenda, typ dokladu, předkontace, účty nebo pravidlo jejich dědění, členění DPH a KH, středisko, číselná řada nebo dědění z typu, režim položek, povinná data, dovolené sazby a postup zaokrouhlení. První profily: „Ostatní závazky – potraviny kartou“ a „Přijaté faktury – [druh nákladu dle vzoru]“. Reference ověř hromadně vůči cílovým číselníkům pro datum dokladu. Chybějící reference blokuje export. Uživatel volí profil, konkrétního dodavatele při nejednoznačnosti a řeší výjimky. Model dostává jen popis druhu dokladu a co hledat.

### Povinná zkouška PENNY v agendě zavazek

1. Ověř na originálu všech 21 řádků, znaménka slev a jejich sazby. Uchovej vytištěnou rekapitulaci: základ 1 052,09 Kč, DPH 126,25 Kč, celkem 1 178,34 Kč. Odděleně ulož výsledek řádkového výpočtu 126,27 Kč a rozdíl cílová minus vypočtená DPH −0,02 Kč. Při stejném brutto odpovídá rozdíl základu +0,02 Kč. Není to sleva ani zaokrouhlení platby.
2. Nejprve zkus minimální import dle vzoru přes dry-run a porovnej výsledný obsah. Pokud účetní připouští souhrn, vyzkoušej jednu účetní položku za kombinaci sazby a účtování s přesnou vytištěnou rekapitulací. Originál a detail všech 21 řádků zůstávají dohledatelné. Pokud vyžaduje řádky, vyzkoušej rozdělení rozdílu jen mezi dopočítané hodnoty téže sazby: zachovej brutto každého řádku, odeber po haléři ze dvou DPH nejvíce zaokrouhlených nahoru, při shodě dle pořadí. Základ uprav opačně. Vytištěné řádkové daně neměň. Bez dostupných podkladů nebo při nesouladu návrh zastav.
3. Ulož původní a navržené částky, dotčené řádky, metodu, důvod a schválení. Nikdy nepoužívej plošnou toleranci, která propustí libovolný dvouhaléřový rozdíl. Flexi u položkových dokladů kontroluje řádky i součty. Služba zaokrouhli je dokumentována jen pro faktura-prijata a pokladni-pohyb. Pro zavazek její podporu nepředpokládej.
4. Zapiš vybranou variantu pouze do testovací firmy, načti ji zpět a porovnej základ, daň i brutto v každé sazbě, položky, účtování, KH a absenci vazby na úhradu. Účetní ověří výsledek ve Flexi. Dokud neprojde, danou variantu profilu nepovol. Dosavadní XML prošlo jen syntaktickou a aritmetickou kontrolou.

**Hotovo:** pro každou povolenou variantu existuje anonymizovaný vstup, minimální XML, odpověď dry-run, očekávaný zpětný odečet a účetní potvrzení. Neúspěšná varianta má popsaný důvod a zůstává blokovaná.

## Etapa 1 – příjem, uložení a verze

Zaveď kontext např. IncomingDocuments, UUID, časová razítka a migrace. Navržené tabulky:

| Tabulka | Obsah a omezení |
|---|---|
| documents | Firma, originální název, MIME, velikost, SHA-256, privátní klíč souboru, agenda, stav, aktuální revize. Unikátní firma + hash. |
| revisions | Neměnná verze vytěžení nebo opravy, předchozí revize, JSONB s položkami, důvod, autor, čas, verze schématu/promptu/modelu a údaje o spotřebě. |
| transfers | Jeden přenos na dokument a cílovou firmu, stabilní externí klíč, schválená revize, snapshot profilu, identita schvalujícího, XML a jeho hash, oddělené stavy dokladu a přílohy, vzdálená ID. |
| attempts | Operace, pořadí, čas, HTTP stav, výsledek, chyby a varování, chráněná odpověď. Běžný log obsahuje jen provozní metadata. |

Originály ulož mimo veřejný web na trvalý Coolify volume pod interním klíčem, přístup pouze přes autorizovanou route. Kontroluj skutečný formát a limity (návrh 15 MB a 10 stran), odmítni poškozená a zamčená PDF. Originál nikdy nepřepisuj. Zajisti úklid neúplného uploadu. Denně zálohuj DB i originály šifrovaně mimo server, hlídej stáří poslední úspěšné zálohy a vyzkoušej společnou obnovu včetně kontroly hashů.

**Hotovo:** opakovaný i souběžný upload stejných bajtů otevře původní dokument. Veřejný POS nemůže otevřít originál ani náhled.

## Etapa 2 – vytěžení a výpočty

Oban spouští serverový Req požadavek na Responses API. PDF jako input_file s base64, fotografie jako input_image. Bez veřejných URL, nástrojů a oprávnění k ABRA. Použij store=false a text.format s typem json_schema a strict=true. Dokument včetně pokynů vytištěných na stránce je nedůvěryhodný vstup. Nesmí vyvolat akci, změnit pravidla ani určit účet. Doporučený režim API standardně nepoužívá vstupy k trénování bez opt-in, ale store=false neznamená nulovou retenci bezpečnostních logů. Ověř firemní požadavky před pilotem.

### Kontrakt extraction_v1 pro JSON Schema

Kořen je objekt. Každý uvedený klíč dej do required, ve všech objektech additionalProperties=false. Nečitelné nebo neuvedené skaláry mohou být null. Číslo dokladu, IČO i DIČ jsou text kvůli nulám. Peníze, procenta a množství jsou desetinné řetězce bez oddělovačů tisíců, např. „0.735“. Datum ISO YYYY-MM-DD. Pole objektů zachovává pořadí zdroje. Následující názvy jsou výhradně interní, ne názvy polí Flexi.

| Klíč | Typ / vlastnosti |
|---|---|
| supplier | objekt: name, company_id, vat_id |
| header | objekt: document_number, variable_symbol, currency, issue_date, taxable_supply_date, due_date, payment_method_raw |
| items | pole objektů: kind (goods/service/discount/rounding/other), description, quantity, unit, unit_price, price_basis (net/gross/null), vat_rate, net, vat, gross, page, discount_for_line (číslo řádku od 1 nebo null) |
| vat_summary | pole objektů: vat_rate, net, vat, gross |
| totals | objekt: net, vat, gross, payable, payment_rounding |
| issues | pole objektů: path (JSON Pointer), reason (missing/illegible/ambiguous/unsupported), page (od 1 nebo null), evidence (krátký úryvek nebo null) |

AI vrací jen vytištěné údaje. Pokud je slevová cena již zahrnutá, odděl informativní slevu od samostatné záporné položky; přidej k řádku enum effect (included/separate/unknown) a při nejasnosti blokuj součet. Neúplná odpověď, odmítnutí či nesouvisející dokument se nesmí tvářit jako úspěšný přepis. Po síťové chybě/429 omezený retry s odstupem, jinak nabídni ruční doplnění. Nový pokus vytvoří novou revizi a nepřepíše uživatelské opravy.

Elixir opět validuje kontrakt, parsuje Decimal přímo z textu, drží přesnost množství a jednotkových cen a zaokrouhluje jen na určeném kroku. Rozlišuj vytištěné a vypočtené hodnoty. Prověř množství × jednotková cena, režim netto/brutto, slevy přesně jednou, součet po sazbách, základ + daň, součet sazeb a vztah celkem/k úhradě. Neztotožňuj chybějící množství s 1 ani chybějící sazbu s nulou. Kontroly mají cestu k poli, očekávanou hodnotu, skutečnou hodnotu, rozdíl a závažnost. Rozpor částek, neurčené účtování či nečitelné povinné pole blokují schválení.

**Hotovo:** sada ručně přepsaných dokladů rozliší chybný přepis, normální zaokrouhlení a nepodporovaný případ. Model ani platný JSON nemohou samy založit doklad.

## Etapa 3 – kontrolní obrazovka

Admin seznam zobrazí stav, dodavatele, částku, agendu a další potřebný krok. Upload umožní vybrat agendu a odpovídající profil. Detail zobrazí vlevo originál se zoomem a stránkováním, vpravo editovatelnou hlavičku, řádky, rekapitulaci „na dokladu / vypočteno / rozdíl“ a zvlášť účetní nastavení. Klik na problém otevře pole a stránku. Umožni přidat chybějící řádek, odstranit zdvojený a vybrat dodavatele z adresáře. Neshoda profilu s obsahem vede ke změně profilu nebo ručnímu zpracování.

Po opravě ulož revizi a znovu proveď kontroly. Porovnej kandidáty duplicit i mezi agendami podle dodavatele a čísla, podpůrně dle data, měny a částky, také s existujícími doklady Flexi. Shodná částka sama nestačí. Zobraz odkaz na kandidáta a vyžádej vysvětlení rozhodnutí. Seznam načítej hromadně, pozor na N+1 dotazy na přenosy, dodavatele nebo jednotlivé položky.

Stavy kontroly: nahráno → vytěžuje se → ke kontrole → ověřeno dry-run → schváleno, s odbočkami chyba vytěžení a ruční zpracování. Dry-run vždy patří konkrétní revizi, profilu, firmě a XML. Editace zneplatní výsledek. Tlačítko „Schválit a odeslat“ v transakci ověří aktuální revizi, uloží schválené XML a zařadí úlohu. Další klik nevytvoří druhý přenos.

**Hotovo:** změna jednoho řádku po úspěšné simulaci znemožní odeslat starý výsledek. Dva otevřené prohlížeče nepřepíšou práci druhého.

## Etapa 4 – zápis a příloha

1. Z povolených polí sestav XML knihovnou s escapováním. Pošli stejný obsah nejprve na cílovou evidenci s ?dry-run=true. Kontroluj success, chyby, warnings a výsledné content proti schválení připravovaným hodnotám. Neznámé varování blokuj. Simulované číslo nepřebírej.
2. Pro doklad přiděl jednou vlastní ext:COZYIN:<lokální UUID>. Nastav create=ok, update=fail, aby opakování nepřepsalo existující doklad. Zámek a unikátní klíč v DB omezí souběh. Po zahájení přenosu zamkni firmu, agendu a revizi. Každý pokus zaznamenej před voláním, bez dlouhé otevřené DB transakce během HTTP.
3. Po úspěchu načti doklad zpět a potvrď identitu, dodavatele, číslo od dodavatele, částky po sazbách a profil. Po timeoutu, restartu nebo odpovědi „již existuje“ přejdi do stavu „ověřuje se založení“. Hledej podle stejného ext ID ve stejné firmě a agendě, sleduj případné přesměrování jen na důvěryhodný origin. Shoda → ulož skutečné ID a pokračuj. Neshoda → zásah uživatele. Po opakovaném potvrzeném nenalezení lze zkusit stejný create-only požadavek. Při nedostupnosti jen opakuj čtení. Po obnovení DB ze zálohy nejprve proveď porovnání s ABRA.
4. Teprve pro potvrzené ID spusť vlastní úlohu pro přílohu. Ověř v obou agendách seznam příloh, binární PUT na prilohy/new/<jmeno> a GET obsahu. Použij stabilní bezpečný název odvozený z UUID a hashe, správný MIME a nezměněný originál. Před opakováním vyhledej přílohu, stáhni kandidáta a porovnej SHA-256. Shoda → dokončeno. Kolize či nejasný výsledek → ruční kontrola. Binární PUT na new nepovažuj za idempotentní. Po timeoutu neodesílej druhou přílohu, dokud není absence spolehlivě ověřená.
5. Stavy zápisu: čeká / odesílá se / výsledek neznámý / potvrzeno / chyba. Stavy přílohy: čeká na doklad / připravena / výsledek neznámý / připojena / chyba. „Doklad založen, příloha chybí“ nabídne pouze obnovení přílohy. Odděl chyby oprávnění a obsahu od dočasných výpadků. Omez počet pokusů a vypni slepé HTTP retry pro zápisy.

**Hotovo:** simulace ztracené odpovědi po založení, po připojení i po pádu workeru skončí jedním odpovídajícím dokladem a jednou ověřenou přílohou, nebo viditelným stavem vyžadujícím zásah.

## Etapa 5 – pilot a provoz

Připrav 15–25 skutečných dokladů s referenčním přepisem nezávislým na AI. Pokryj PENNY, druhého dodavatele, vícestránkovou fakturu, více sazeb, slevu, váženou položku, rozmazanou fotku, chybějící údaj, druhou fotografii téhož dokladu a instrukci vloženou do dokumentu. Část sady ponech stranou do závěrečného vyhodnocení. Do git ukládej jen anonymizované nebo syntetické fixtures. Automatické testy používají Req.Test včetně chybových odpovědí. Živé zkoušky jen ručně v oddělené testovací firmě s vlastními credentials. V CI nesmí být produkční přístup.

Před pilotem dolož po jednom úplném průchodu každou agendou, reprodukovatelný výsledek PENNY, kontrolu účtování účetní, scénáře duplicit a obnovu ze zálohy. Prvních deset produkčních dokladů jednotlivě porovnej s Flexi. Sleduj čas ruční opravy, chyby povinných údajů, počet blokací, cenu vytěžení a nedokončené přílohy. Automatizaci později povoluj jen pro ověřenou dvojici dodavatel + verze profilu a po období měření bez zápisu.

API klíče jen serverově v Coolify, oddělené pro prostředí, ABRA účet s minimálními právy. Nikdy neloguj obsah dokumentu, base64 ani autentizaci. Při 30–100 dokladech měsíčně postačí malá fronta s omezeným souběhem. Rozpočet počítej ze skutečných usage tokenů pilotu včetně obrázků, výstupu a opakování. Pro představu při 8 000 vstupních a 3 000 výstupních tokenech, rozpočtových sazbách 1 a 5 USD/milion a 20 % opakování vychází cca 0,83–2,76 USD/měsíc. Jde o modelový rozpočet, ne nabídku konkrétního modelu. Přičti případné licenční změny ABRA a zálohovací prostor. Pro pilot vyber dostupný podporovaný vision model se Structured Outputs a zaznamenej přesnou verzi.

## Oficiální podklady ověřené při návrhu

- [OpenAI – souborové vstupy](https://developers.openai.com/api/docs/guides/file-inputs): u PDF vision model získá text i obraz stran. Dokumentovaný limit souborů na požadavek je 50 MB.
- [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs): podporovaná podmnožina JSON Schema, povinné klíče, nullable hodnoty, odmítnutí a možnost věcných chyb.
- [Retence OpenAI](https://developers.openai.com/api/docs/guides/your-data) a [aktuální ceny](https://developers.openai.com/api/docs/pricing).
- ABRA: [dry-run a výsledný content](https://podpora.flexibee.eu/cs/articles/4720123-testovaci-ulozeni-dry-run), [externí identifikátory](https://podpora.flexibee.eu/cs/articles/4725798-identifikatory-zaznamu), [režimy založení a změny](https://podpora.flexibee.eu/cs/articles/4725944-rezim-pro-zalozeni-zmenu), [přílohy](https://podpora.flexibee.eu/cs/articles/4722200-prilohy).
- ABRA: [výpočet DPH](https://podpora.flexibee.eu/cs/articles/4725983-vypocet-dane-z-pridane-hodnoty-dph), [validace položek a slev](https://podpora.flexibee.eu/cs/articles/11776385-validace-vypoctu-cen-na-polozkach-rest-api), [podporované agendy pro zaokrouhli](https://podpora.flexibee.eu/cs/articles/5792983-zaokrouhleni-cen-dokladu-v-rest-api), [rozúčtování včetně zavazek](https://podpora.flexibee.eu/cs/articles/6713877-rozuctovani-dokladu-pomoci-rest-api).

Dokumentace ověřuje možnosti rozhraní. Konkrétní mapování profilů, účetní přijatelnost a skutečný import v cílové konfiguraci jsou výstupy etapy 0.

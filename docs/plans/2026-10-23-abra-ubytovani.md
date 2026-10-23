# Integrace fakturace ubytování s ABRA Flexi

- Stav: návrh; možnosti API doloženy dokumentací, účetní mapování a celý cyklus
  čekají na vzory a ověření v testovací firmě.
- Vytvořeno: 2026-10-23
- Aktualizováno: 2026-10-23
- Související dokumentace / implementace: [Fakturace pobytů](../features/BILLING.md),
  [Integrace ABRA](../integrations/ABRA_INTEGRATION.md),
  [Billing](../../lib/cozy_checkout/billing.ex), [Abra](../../lib/cozy_checkout/abra.ex).
- Implementace nebyla zahájena. Uživatel zajistí napojení na testovací firmu;
  před finálním mapováním jsou potřeba také vzory od účetní.

## Problém a očekávaný výsledek

Obsluha vystavuje doklady a potvrzuje úhrady ubytování v aplikaci. ABRA přebírá
účetní doklady, jejich vazby a potvrzené párování. Běžný pobyt nevyžaduje ruční
práci v Abře.

Aplikace řídí vystavování dokladů. Z Abry pravidelně načítá bankovní pohyby;
všechna spojení zahajuje aplikace, bez webhooků. Nalezená platba sama nezmění
finanční stav rezervace. Původně požadovaná „jednosměrnost“ tedy znamená autoritu
aplikace nad doklady a absenci příchozích volání, nikoli zákaz čtení dat z Abry.

## Současný stav a podklady

Původní průzkum implementace proti `origin/main`, commit `1fe534f`:

- `Billing` již podporuje zálohové výzvy, daňové doklady k přijatým zálohám,
  konečné faktury, opravné doklady a skutečné příjmy i vratky.
- Dílčí zálohy vytvářejí samostatné daňové doklady. Vyúčtování odpočítává
  zdaněné zálohy v původních základech a DPH.
- Doklady uchovávají snapshoty, jedinečná čísla a VS. Vystavení a evidence
  plateb používají transakce, zámky a identifikátory požadavků.
- Barová integrace exportuje zaplacené objednávky přes Req a Oban. Banku
  nečte ani nepáruje.
- Barový builder nelze převzít pro ubytování: neřeší jeho druhy dokladů,
  odpočty, opravy ani rozlišení nulové sazby a plnění mimo DPH.

Relevantní implementace zahrnuje schémata `Billing.Document`, `Billing.Payment`,
výpočty `Billing.Money`, přehled `Billing.BookingSummary`, migraci
`20261022120000_create_booking_billing.exs`, LiveViews fakturace a testy
`booking_billing_test.exs`, `billing_concurrency_test.exs`, `abra_sync_test.exs`
a `abra_client_test.exs`.

### Ověření možností ABRA Flexi API (2026-10-23)

Následný průzkum oficiální dokumentace a čtení metadat veřejné demo firmy
potvrdily potřebné mechanismy pro běžný cyklus. Původní překážka přístupu
k dokumentaci již netrvá. **Nejde o ověření cílové ani testovací firmy:**
nebylo testováno vytváření dokladů, skutečné párování ani účetní shoda.

| Požadavek | Doložená možnost API / zdroj |
| --- | --- |
| Čtení bankovních příjmů a výdajů | Evidence `banka` obsahuje částky, měnu, účet, datum, VS, protistranu a `typPohybuK`. [Vlastnosti](https://demo.flexibee.eu/c/demo/banka/properties.json), [relace](https://demo.flexibee.eu/c/demo/banka/relations.json). |
| Úhrada existujícím pohybem, včetně dílčích plateb | `sparovani` na existující bance či pokladně odkazuje na fakturu; atribut `castka` omezuje hrazenou částku. Nevytváří další bankovní pohyb. [Párování plateb](https://demo.flexibee.eu/devdoc/parovani-plateb). |
| Kontrola existujícího párování | Export vazeb přes `relations` a `includes`; banka nabízí také `vazebni-doklady`. Samotné `sparovano=false` nestačí k prokázání volné platby, protože pohyb může být využit jen částečně. [Čtení vazeb úhrad](https://podpora.flexibee.eu/cs/articles/3422310-pouziti-detail-custom-pro-zjisteni-zpusobu-parovani), [pravidla párování](https://demo.flexibee.eu/devdoc/parovani-plateb). |
| Export místního ZDD a vazba na platbu | `vytvor-vazbu-zdd` propojí existující ZDD s bankovním nebo pokladním dokladem. [Vazby ZDD](https://demo.flexibee.eu/devdoc/vazby-zdd). |
| Vyúčtování záloh bez dalšího příjmu peněz | `odpocty-zaloh` podporuje zdrojový doklad, částky po skupinách DPH a externí ID odpočtu. Relace pro zbývající odpočitatelné částky jsou dostupné od verze 2024.3. [Odpočty](https://demo.flexibee.eu/devdoc/odpocet-zaloh), [částky k odpočtu](https://podpora.flexibee.eu/cs/articles/9148386-castky-k-odpoctu-rest-api). |
| Opravný doklad s vazbou na původní | `vytvor-vazbu-dobropis` vytvoří vazbu hlaviček; správné opravné položky musí dodat integrace. [Dobropisy](https://demo.flexibee.eu/devdoc/dobropisy). |
| Změnový import bez webhooků | Changes API vrací `create`, `update`, `delete`, rostoucí verze a pokračování `next`. Vyžaduje aktivaci; změny se načítají podle verze, nikoli data platby. [Changes API](https://demo.flexibee.eu/devdoc/changes-api). |
| Zachování místního čísla | `kod` vydané faktury je zapisovatelný, v demo metadatech má limit 20 znaků. Ověřit délky a kolize místních čísel. [Vlastnosti faktury](https://demo.flexibee.eu/c/demo/faktura-vydana/properties.json). |

Zjištěná omezení a důsledky pro návrh:

- **ZDD–platba je vazba 1 : 1.** Jeden bankovní či pokladní pohyb nelze
  propojit s více ZDD. Více dílčích plateb s vlastním ZDD je s tím slučitelné;
  rozdělení jednoho pohybu mezi více ZDD tento návrh nepokrývá.
  [Vazby ZDD](https://demo.flexibee.eu/devdoc/vazby-zdd).
- **Odpočet sám nezaručuje shodu původních základů a DPH.** Běžně přebírá
  sazby z konečné faktury; režim `skupPlneni=OTHER` umí převzít sazby ze ZDD.
  Dokumentace doporučuje základy přes `castkyBezDph=true`. Návrh počítá
  s explicitními částkami a kontrolou výsledku, bez automatického přijímání
  úprav faktury přes `prijmoutDoporuceni=true`. Použitelný režim a haléřovou
  shodu je nutné ověřit. Související oprava odpočtů je uvedena ve verzi 2026.5.0;
  ověřit verzi cílové instance. [Odpočty](https://demo.flexibee.eu/devdoc/odpocet-zaloh),
  [změny ve verzi 2026.5.0](https://podpora.flexibee.eu/cs/articles/16537283-desktopova-aplikace-novinky-ve-verzi-2026-5-0).
- **Nezdaněný přeplatek má samostatnou účetní cestu.** Služba `preplatek`
  převede nespárovanou část příjmu do ostatních závazků. Návrh připouští tuto
  pomocnou evidenci; přesné vypořádání s odchozí vratkou určí účetní vzor.
  Nejde o další fakturu hostovi ani o snížení ceny pobytu.
  [Přeplatky přes API](https://podpora.flexibee.eu/cs/articles/6091847-vytvoreni-preplatku-pomoci-rest-api).
- **Vratka k dobropisu vyžaduje ověření směru a znaménka.** Dokumentace
  upozorňuje na úpravy importované bankovní úhrady při párování dobropisů.
  Místní `refund` proto nelze mechanicky převést na běžnou úhradu; ověřit
  skutečné chování používané verze a nastavení.
  [Párování dobropisů](https://podpora.flexibee.eu/cs/articles/4538957-parovani-dokladu).
- **Idempotence není společná pro všechny operace.** Párování je dokumentované
  jako idempotentní. U `hotovostni-uhrada` musí být vlastní stabilní
  `uhrazujiciDokl`; bez něj opakovaný import vytvoří další pokladní doklad.
  Samotné ID faktury úhradu před duplicitou nechrání.
  [Párování](https://demo.flexibee.eu/devdoc/parovani-plateb),
  [hotovostní úhrada](https://demo.flexibee.eu/devdoc/hotovostni-uhrada).
- **Automatizace firmy mohou konkurovat aplikaci.** Pokročilé automatické
  párování umí samo vytvářet zálohy a ZDD. Návrh používá explicitní párování
  a export místních dokladů; zkontrolovat ostatní automatizace a zabránit
  duplicitám. [Pokročilé párování](https://podpora.flexibee.eu/cs/articles/3853613-pokrocile-automaticke-parovani).
- **Režimy DPH nejsou ověřeny pouhou nulovou částkou daně.** Metadata položek
  obsahují `typSzbDphK` a členění `clenDph`; samotné `typSzbDph.dphOsv`
  nedokládá správné rozlišení místní zdanitelné nuly, osvobození a plnění mimo
  předmět DPH. Mapování potvrdí účetní a testovací firma.
  [Vlastnosti položek](https://demo.flexibee.eu/c/demo/faktura-vydana-polozka/properties.json).

Zbývá ověřit licenci, verzi a oprávnění konkrétní firmy. API respektuje práva
uživatele k evidencím i jednotlivým záznamům; dostupnost veřejné dokumentace
nepotvrzuje přístup na cílové instanci.
[Přístupová práva](https://demo.flexibee.eu/devdoc/permissions).

## Rozsah

První etapa zahrnuje:

- Čtyři existující druhy pobytových dokladů, jejich vazby, hotovostní příjmy a vratky.
- Načítání bankovních příjmů i odchozích vratek a ručně potvrzované párování.
- Dílčí platby, pobyty bez zálohy, nulový doplatek a přeplatky.
- Přehled synchronizace, chyb a ruční opakování.

Mimo etapu zůstává:

- Karetní zúčtování, vytváření bankovních příkazů a automatické odesílání peněz.
- Rozdělení jedné bankovní platby mezi více rezervací.
- Migrace starších pobytů a přepisování dokladů podle změn v Abře.
- Automatické potvrzování plateb a obecný redesign fakturace.

## Navržené řešení

### Uživatelský postup

1. Obsluha připraví kalkulaci a údaje odběratele.
2. Vystaví zálohovou výzvu, případně tento krok přeskočí. Vystavení zároveň
   bezpečně zařadí export do Abry.
3. Doklad může odeslat hostovi stávajícím postupem. Stav exportu je viditelný
   samostatně.
4. Aplikace každých 15 minut načte bankovní pohyby z nakonfigurovaného účtu.
   Nabídne také ruční obnovení a zobrazí čas posledního úspěšného načtení.
5. Podle VS nabídne platbu u odpovídající rezervace. Zobrazí částku, datum,
   protistranu, cílový doklad a případný rozdíl.
6. Obsluha potvrdí přiřazení. Teprve tím vznikne místní platba a u zálohy také
   daňový doklad. Následně se synchronizují doklad a vazby na existující
   bankovní pohyb.
7. Konečná faktura obsahuje celou cenu pobytu a odpočty zdaněných záloh.
   Export zachová tyto vazby; nevytváří další příjem peněz.
8. Potvrzením doplatku vznikne úhrada konečné faktury. Nevystavuje se další
   daňový doklad k záloze.

Nulový doplatek nevyžaduje další platbu. Přeplatek zůstává viditelný do vyřešení
vratky.

### Párování a výjimky

- VS slouží k návrhu, nikoli k automatickému schválení. Kontroluje se také
  účet, měna, směr pohybu a jeho dostupnost pro párování.
- Platbu bez správného VS lze ručně přiřadit konkrétnímu pobytu. Nejednoznačné
  a cizí platby zůstávají v přehledu nespárovaných pohybů.
- Jedna bankovní transakce patří v této etapě jednomu pobytu. Více dílčích
  transakcí za stejný pobyt je podporováno.
- Doplatek se starým VS zálohy lze nabídnout u stejného pobytu, ale potvrzuje
  se vůči konečné faktuře.
- Platbu již zaevidovanou nebo spárovanou nesmí opakované načtení vytvořit
  znovu. Existující shodné párování v Abře se využije; konfliktní párování
  vyžaduje ruční řešení.
- Před potvrzením se ověří aktuální vzdálený pohyb. Při nedostupné Abře se
  potvrzení odloží. Toto čtení samo nezabrání souběžnému zásahu účetní před
  dokončením exportu; následná synchronizace musí odhalit konflikt a nabídnout
  jeho řešení bez přepsání místních dokladů a plateb.
- Pozdě objevená záloha před DUZP již vystavené konečné faktury zůstává
  účetní výjimkou podle současných pravidel.
- Potvrzené párování nebude mít jednoduché tlačítko „vrátit zpět“: mohlo již
  vytvořit daňový doklad. Chyba se řeší kontrolovanou účetní opravou.

### Hotovost a vratky

Hotovost se zapisuje ručně v aplikaci se skutečným datem. Export vytvoří právě
jeden odpovídající pokladní pohyb s vlastní stabilní identitou a jeho účetní
vazby; při použití `hotovostni-uhrada` se výslovně vyplní `uhrazujiciDokl`.

Bankovní vratku obsluha nejprve odešle v bance. Po importu odchozího pohybu do
Abry jej v aplikaci přiřadí jako vratku. Aplikace nevytváří druhý bankovní pohyb.

Oprava ceny a vratka peněz zůstávají oddělené. Vrácení zdaněné zálohy vyžaduje
potřebný opravný doklad; prostý nezdaněný přeplatek konečné faktury lze vrátit
bez snížení ceny pobytu. Pro jeho vypořádání může být v Abře potřeba pomocný
ostatní závazek. Vratka přeplatku a úhrada dobropisu mají samostatné mapování.

### Datové změny a rozhraní

- Samostatná evidence synchronizace pobytových dokladů, plateb a vazeb:
  stabilní externí identita, cílová firma, vzdálené ID, stav, pokusy, chyba
  a historie.
- Samostatná evidence načtených bankovních pohybů s jedinečností podle firmy,
  evidence a vzdáleného ID; uchová částku, měnu, účet, datum, VS a informace
  o párování.
- Jednoznačná vazba bankovního pohybu na místní platbu, chráněná databázovým
  omezením.
- Trvalý bod pokračování importu a historie posledních úspěchů a chyb.
- Označení rezervací zapojených do nové integrace. Existující rezervace
  zůstanou mimo ni; nové se zapojí od nastaveného okamžiku spuštění.
- Kontext pro načítání pohybů, návrhy a potvrzení párování a opakování exportu.
  Potvrzení využije stávající finanční pravidla `Billing.record_payment/2`.
- Samostatné pobytové buildery a workery; sdílený HTTP základ s barovou
  integrací. Stávající barové rozhraní zůstane kompatibilní.

Doklady, platba, potvrzené přiřazení a požadavky na synchronizaci se ukládají
v jedné místní transakci. HTTP požadavky probíhají mimo ni.

### Spolehlivost a účetní shoda

- Export používá uložené snapshoty, původní čísla, VS, data, daňové skupiny
  a odpočty.
- Doklady, hotovostní pohyby a odpočty mají vlastní stabilní identity oddělené
  od baru.
- Navazující operace čekají na úspěšný přenos zdrojových dokladů.
- Opakování po timeoutu nejprve ověří vzdálený výsledek; nesmí slepě znovu
  vytvořit úhradu.
- Import používá stránkování a Changes API s trvale uloženým pokračováním.
  Počáteční načtení i navazování verzí se ověří v testovací firmě. Import musí
  zachytit opožděné pohyby se starším datem platby, změny, smazání i změny vazeb;
  ověřit, které evidence změn je pro úplnou detekci nutné sledovat.
- Změna již potvrzeného pohybu v Abře vyvolá konflikt, nikoli přepsání místní
  finanční historie.
- Výpadek exportu nezruší vystavený doklad. V aplikaci se odděleně zobrazí stav
  úhrady a stav účetního přenosu.
- Administrace i bankovní údaje zůstávají pod existující PIN autentizací.
  Přístupy budou v prostředí nasazení.

## Rozhodnutí

| Datum | Rozhodnutí a důvod | Potvrzení / zdroj |
| --- | --- | --- |
| 2026-10-23 | Aplikace čte banku a zapisuje potvrzené párování; bez webhooků. | Uživatel |
| 2026-10-23 | Banka se do Abry importuje automaticky a pravidelně. | Uživatel |
| 2026-10-23 | První etapa podporuje převody a hotovost. | Uživatel |
| 2026-10-23 | Bankovní platby se evidují až nad načteným pohybem. | Uživatel |
| 2026-10-23 | Bankovní převody vratek se provádějí ručně. | Uživatel |
| 2026-10-23 | Hromadné platby mezi rezervacemi se řeší mimo automatizaci. | Uživatel |
| 2026-10-23 | Integrace se týká pouze nových pobytů. | Uživatel |
| 2026-10-23 | Spuštění až po ověření celého cyklu; testovací firma existuje. | Uživatel |
| 2026-10-23 | Výchozí interval načítání 15 minut, CZK, explicitně nakonfigurovaný účet. | Návrhový výchozí stav |
| 2026-10-23 | Nyní pouze uložit plán; pokračovat po pročtení a zajištění vzorů. | Uživatel |
| 2026-10-23 | Doplnit doložené možnosti a omezení API; uživatel zajistí napojení na testovací firmu pro ověřování API a budoucí implementace. Tato aktualizace nezahajuje implementaci. | Uživatel |

## Otevřené otázky

Před implementací účetního mapování doplnit:

- Vzory od účetní: zálohová výzva, daňový doklad k platbě, vyúčtování
  s odpočtem, oprava, hotovostní příjem/výdej a bankovní vratka. Potřebné jsou
  exporty s vazbami, nejen PDF.
- Cílové typy, řady, předkontace, daňové režimy a způsob zachování místního
  čísla dokladu.
- Konkrétní payloady a výsledné vazby doložených API operací v testovací
  firmě, zejména záloha bez předchozí výzvy, oprava ZDD a vratka zdaněné zálohy.
- Přesná shoda odpočtů při různých sazbách, přeplatku a nulovém doplatku;
  rozlišení zdanitelné nuly, osvobození a plnění mimo předmět DPH.
- Mapování vratky nezdaněného přeplatku přes případný ostatní závazek a úhrady
  dobropisu, včetně směru a znamének bankovních a pokladních dokladů.
- Skutečné nastavení automatického párování, tvorby ZDD a dalších automatizací
  cílové firmy. Musí zabránit duplicitám a respektovat místní potvrzení.
- Aktivace a úplnost Changes API včetně změn vazeb, oprávnění API uživatele,
  verze instance a případná licenční omezení.

Tyto body jsou vstupní podmínkou finální technické specifikace, nikoli volbou
ponechanou implementátorovi.

## Postup realizace

- [x] Ověřit obecné možnosti API v oficiální dokumentaci a veřejných metadatech;
  doložit mechanismy, omezení a zbývající nejistoty.
- [ ] Zajistit napojení na testovací firmu (uživatel).
- [ ] Získat vzory a ověřit API i účetní vazby v testovací firmě; výsledné
  mapování doplnit do plánu.
- [ ] Ověřit celý vzorový cyklus včetně opakování po ztracené odpovědi
  a kontroly částek.
- [ ] Přidat evidenci synchronizace, bankovních pohybů a zapojení nových rezervací.
- [ ] Implementovat export všech druhů dokladů a hotovostních pohybů.
- [ ] Implementovat pravidelné načítání banky, návrhy a potvrzení párování.
- [ ] Doplnit vratky, konflikty, přehled chyb a bezpečné opakování.
- [ ] Doplnit testy a provozní dokumentaci.
- [ ] Zapnout integraci až po splnění podmínek dokončení.

## Ověření a podmínky dokončení

Automatické testy přes `Req.Test` pokryjí:

- Zálohu a doplatek, pobyt bez zálohy, více dílčích záloh, nulový doplatek.
- Přeplatek, opravu ceny, bankovní i hotovostní vratku.
- Různé sazby DPH, plnění mimo DPH a přesnost haléřových odpočtů.
- Chybný nebo starý VS, cizí měnu, již spárovaný a změněný pohyb.
- Opakované načtení, dvojklik, souběžné potvrzení, timeout a částečně
  dokončený export.
- Rollback místní transakce, závislosti exportů a nepřístupnost administrace
  bez PIN.
- Vyloučení starých rezervací a regresi barové integrace.

V testovací firmě účetní potvrdí částky, DPH, saldokonto a všechny vazby.
Opakování operací nesmí vytvořit další doklad ani pohyb peněz.

Před zapnutím integrace navíc ověřit proti skutečnému API:

- ZDD bez předchozí výzvy, několik dílčích záloh s vlastními ZDD a omezení 1 : 1.
- Odpočty v původních základech a DPH včetně různých sazeb, haléřových rozdílů,
  nulového doplatku a přeplatku; bez samovolné změny vydaného dokladu.
- Opravu ZDD, vratku zdaněné zálohy, nezdaněného přeplatku a úhradu dobropisu;
  zvlášť bankovní a hotovostní variantu a případné pomocné závazky.
- Opakování každé zápisové operace po ztracené odpovědi, zejména vytvoření
  pokladního pohybu, vazby ZDD, odpočtu a pomocného závazku.
- Počáteční import a pokračování Changes API, pozdě importovaný starší pohyb,
  změnu a smazání pohybu i změnu párování; také souběžný zásah účetní.
- Zachování čísel dokladů a jejich limitů, daňové režimy, oprávnění a nastavení
  automatizací na používané verzi instance.

Lokální testy při přípravě, uložení a doplnění plánu nebyly spuštěny; změna je pouze
dokumentační. Při implementaci proběhnou kontroly standardně v CI podle
pravidel repozitáře a jejich výsledky ověří uživatel.

## Nasazení a rizika

Migrace budou přidávací a nepřepočítají historická data. Integrace bude ve
výchozím stavu vypnutá; banka a export budou mít samostatné provozní přepínače.

Před spuštěním se nastaví cílová firma, číselníky, účet, pokladna, oprávnění
a okamžik zapojení nových rezervací. Testovací a ostré vzdálené identity se
nesmějí zaměnit.

Při problému lze pozastavit import a export. Již potvrzené platby, vystavené
doklady a čekající operace zůstanou zachované. Opětovné zapnutí pokračuje
bezpečně bez nového vystavování.

Největší rizika jsou dvojí vytvoření úhrady, nesprávný odpočet záloh, rozdílné
zaokrouhlení a souběžné zásahy v Abře. Jejich ověření je podmínkou spuštění.

## Průběh a předání dalšímu chatu

- Hotovo: průzkum dokumentace, implementace, migrací a relevantních testů;
  potvrzen rozsah s uživatelem. Návrh uložen do tohoto souboru a odkaz přidán
  do [rejstříku plánů](README.md). Následně ověřena oficiální API dokumentace
  a veřejná metadata; zjištění a omezení doplněna se souhlasem uživatele.
  Implementace integrace nebyla zahájena.
- Zbývá: napojení na testovací firmu, účetní vzory, ověření celého cyklu a přesné
  mapování. Uživatel zajistí napojení pro testování API a budoucí implementace.
- Blokuje: chybějící vzory a dosud nepřipravené napojení na testovací firmu.
  Přístup k dokumentaci již není překážkou; API testovací firmy zde testováno nebylo.
- Nejbližší další krok: po zajištění přístupu ověřit verzi, licenci, oprávnění
  a nastavení testovací firmy, s účetními vzory projít celý cyklus a doplnit
  mapování. Před implementací znovu ověřit aktuální kód; tato dokumentační
  aktualizace není zahájením implementace.

V novém chatu lze navázat například:

> Přečti docs/plans/2026-10-23-abra-ubytovani.md. Napojení na testovací firmu
> je připravené a mám vzory od účetní. Ověř doložené API operace a zbývající
> scénáře v testovací firmě, porovnej výsledky s aktuálním kódem a doplň účetní
> mapování. Zatím nezačínej implementaci.

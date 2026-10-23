# Integrace fakturace ubytování s ABRA Flexi

- Stav: návrh; účetní mapování čeká na vzory a ověření API.
- Vytvořeno: 2026-10-23
- Aktualizováno: 2026-10-23
- Související dokumentace / implementace: [Fakturace pobytů](../features/BILLING.md),
  [Integrace ABRA](../integrations/ABRA_INTEGRATION.md),
  [Billing](../../lib/cozy_checkout/billing.ex), [Abra](../../lib/cozy_checkout/abra.ex).
- Uložení návrhu neznamená zahájení implementace. Uživatel si plán pročte
  a zajistí vzory od účetní; poté se k návrhu vrátíme.

## Problém a očekávaný výsledek

Obsluha vystavuje doklady a potvrzuje úhrady ubytování v aplikaci. ABRA přebírá
účetní doklady, jejich vazby a potvrzené párování. Běžný pobyt nevyžaduje ruční
práci v Abře.

Aplikace řídí vystavování dokladů. Z Abry pravidelně načítá bankovní pohyby;
všechna spojení zahajuje aplikace, bez webhooků. Nalezená platba sama nezmění
finanční stav rezervace. Původně požadovaná „jednosměrnost“ tedy znamená autoritu
aplikace nad doklady a absenci příchozích volání, nikoli zákaz čtení dat z Abry.

## Současný stav a podklady

Ověřeno proti aktuálnímu `origin/main`, commit `1fe534f`:

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

Dostupnost konkrétních bankovních a párovacích API operací pro cílovou firmu
**dosud není ověřena**. Přístup k oficiální dokumentaci při průzkumu blokovala
síťová politika prostředí. Existující testy ani dokumentace repozitáře tuto
schopnost nepotvrzují.

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
  potvrzení odloží.
- Pozdě objevená záloha před DUZP již vystavené konečné faktury zůstává
  účetní výjimkou podle současných pravidel.
- Potvrzené párování nebude mít jednoduché tlačítko „vrátit zpět“: mohlo již
  vytvořit daňový doklad. Chyba se řeší kontrolovanou účetní opravou.

### Hotovost a vratky

Hotovost se zapisuje ručně v aplikaci se skutečným datem. Export vytvoří právě
jeden odpovídající pokladní pohyb a jeho účetní vazby.

Bankovní vratku obsluha nejprve odešle v bance. Po importu odchozího pohybu do
Abry jej v aplikaci přiřadí jako vratku. Aplikace nevytváří druhý bankovní pohyb.

Oprava ceny a vratka peněz zůstávají oddělené. Vrácení zdaněné zálohy vyžaduje
potřebný opravný doklad; prostý nezdaněný přeplatek konečné faktury lze vrátit
bez snížení ceny pobytu.

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
- Import používá stránkování a změnový mechanismus ověřený pro dané API.
  Musí zachytit také opožděně importované pohyby se starším datem platby.
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

## Otevřené otázky

Před implementací účetního mapování doplnit:

- Vzory od účetní: zálohová výzva, daňový doklad k platbě, vyúčtování
  s odpočtem, oprava, hotovostní příjem/výdej a bankovní vratka. Potřebné jsou
  exporty s vazbami, nejen PDF.
- Cílové typy, řady, předkontace, daňové režimy a způsob zachování místního
  čísla dokladu.
- Přesné API operace pro čtení banky, částečné úhrady, párování, odpočty
  a detekci již provedených operací.
- Zda ABRA sama při párování generuje daňové doklady nebo automaticky páruje
  banku. Nastavení musí zabránit duplicitám a respektovat místní potvrzení.
- Způsob zachycení změn a odstranění bankovních pohybů, oprávnění API
  uživatele a případná licenční omezení.

Tyto body jsou vstupní podmínkou finální technické specifikace, nikoli volbou
ponechanou implementátorovi.

## Postup realizace

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

Lokální testy při přípravě a uložení plánu nebyly spuštěny; změna je pouze
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
  do [rejstříku plánů](README.md). Implementace integrace nebyla zahájena.
- Zbývá: uživatelské pročtení návrhu, účetní vzory, ověření API a přesné mapování.
- Blokuje: chybějící vzory a neověřený přístup k API dokumentaci / testovací firmě.
  Existence testovací firmy je potvrzena uživatelem, její API zde testováno nebylo.
- Nejbližší další krok: po dodání vzorů ověřit aktuální kód, projít vzorový
  účetní cyklus a ověřit čtení a párování banky. Poté aktualizovat návrh;
  samotný uložený plán není pokynem k implementaci.

V novém chatu lze navázat například:

> Přečti docs/plans/2026-10-23-abra-ubytovani.md. Mám vzory od účetní;
> porovnej je s plánem a aktuální implementací a doplň účetní mapování
> a otevřené otázky. Zatím nezačínej implementaci.

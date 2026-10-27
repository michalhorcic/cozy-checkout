# Nákupy surovin a nákladovost kuchyně

- Stav: **rozpracováno**; první část implementuje datový a cenový základ,
  uživatelské rozhraní a import zatím nejsou dostupné.
- Vytvořeno: 2026-10-27
- Aktualizováno: 2026-10-27
- Podklad: plán a rozhodnutí potvrzená uživatelem v chatu.
- Související dokumentace: [Stravování, receptury a nákup](../features/CATERING.md).

## Cíl a rozsah

Vytvořit samostatný modul **Nákupy a náklady kuchyně**, který eviduje položkové
nákupy, historii cen a nákladovost receptů a menu rezervací. Napojí se na
existující suroviny, receptury a stravování; nebude vytvářet druhý katalog surovin.

Fotky účtenek zůstanou v ChatGPT. Cozy přijme JSON s přečtenými položkami
a navrženým přiřazením. První verze nepotřebuje OpenAI API ani změnu integrace
ABRA. Souhrnné faktury v ABRA zůstávají samostatnou účetní evidencí.

Výsledky budou označené jako **kalkulované náklady na suroviny**. Nezahrnují
skladové zásoby, skutečný výdej, odpad, práci ani energie.

## Současný stav a napojení

Při plánování byly ověřeny existující kontexty a schémata:

- `Recipes` a `kitchen_ingredients`: stabilní UUID surovin, názvy, archivace
  a základní jednotky kg/l/ks. `Recipes.to_base/3` podporuje převody g → kg
  a ml → l. Katalog se nebude duplikovat ani automaticky měnit importem.
- `Recipe`, `RecipeLine` a `Recipes.Consumption`: receptura má výtěžnost
  `base_servings`; řádky odkazují na suroviny. Výpočet spotřeby už podporuje
  dospělé, děti, dětské koeficienty a doplňky receptů.
- `Meals.MenuPlanning`, `Meals.PortionCounts` a `Kitchen.ShoppingList`:
  přiřazená menu rezervací, konkrétní data jídel, příjezdové a odjezdové porce,
  kontrola neaktuálního menu a neúplných podkladů.
- Menu rezervací odkazují na aktuální receptury. Historickou podobu receptury
  nelze zpětně odvodit; uložený nákladový report proto uchová vlastní snapshot.
- Administrace používá stávající PIN; samostatná účtová autentizace se nepřidává.

## Import a propojení se surovinami

### Předávání podkladů přes ChatGPT

- Cozy nabídne export katalogu do JSONu: stabilní ID surovin, názvy, základní
  jednotky, stav archivace a již potvrzená přiřazení nákupních názvů.
- Uživatel předá export spolu s fotkami účtenky do ChatGPT.
- Součástí modulu bude verzované JSON schéma, vzorový soubor a instrukce pro
  čtení dokladů. ChatGPT vrátí návrh importu; nejasné údaje ponechá prázdné
  a popíše je v upozornění.
- Import nebude obsahovat obrázky ani odkazy, které by Cozy automaticky stahovalo.

Příklad jednoho řádku návrhu; zástupné ID musí při skutečném importu pocházet
z exportu katalogu:

```json
{
  "schema_version": 1,
  "import_id": "550e8400-e29b-41d4-a716-446655440000",
  "receipt": {
    "merchant": "Obchod",
    "purchased_on": "2026-10-27",
    "document_number": "123456",
    "currency": "CZK",
    "total_paid": "59.80"
  },
  "items": [
    {
      "line_number": 1,
      "source_name": "Rajský protlak značka A 140 g",
      "package_count": "2",
      "package_quantity": "140",
      "package_unit": "g",
      "line_total_after_discount": "59.80",
      "proposed_ingredient_id": "<ID protlaku z katalogu>",
      "proposed_ingredient_name": "Protlak",
      "mapping_reason": "Varianta rajského protlaku",
      "warnings": []
    }
  ]
}
```

Částky a množství budou desetinné řetězce. Schéma rozliší balené a vážené zboží;
rozhodující bude celkové nakoupené množství a konečná cena řádku. Příklad výše
ukazuje balené zboží, nikoli celé budoucí validační schéma.

### Pravidla přiřazování

- Vztah je **více nákupních názvů → jedna existující surovina**. Různé značky
  protlaku se mohou propojit se stejným ID.
- Slovník přiřazení bude součástí nového modulu. Klíčem bude obchod
  a normalizovaný nákupní název; zachová se značka i údaj o balení.
  Žádné automatické slučování podle podobnosti.
- Známé přiřazení se předvyplní. Nové návrhy a konflikty musí uživatel potvrdit;
  nakonec potvrdí celý nákup.
- Při rozporu JSONu se slovníkem se zobrazí oba návrhy. Import slovník potichu
  nepřepíše. Rozhodující je platné ID suroviny; název slouží pro kontrolu.
- Množství se ověřuje u každého nákupu. Zapamatované přiřazení nepřebírá
  automaticky starou velikost balení.
- Povolené převody využijí současné kg/g, l/ml a ks. Převody kusů na hmotnost
  vyžadují výslovné množství konkrétního balení; aplikace neodhaduje hustotu
  ani hmotnost kusu.
- Neznámou položku lze ponechat k pozdějšímu přiřazení nebo označit jako zboží
  mimo suroviny. Nepřiřazená položka nevstupuje do cen surovin a je viditelná
  v seznamu k dořešení. Nové suroviny se zakládají stávajícím postupem,
  nikoli automaticky z JSONu.
- Změna slovníku platí pro další importy. Historický řádek se opravuje samostatně.

### Kontrola nákupu

Import otevře editovatelný náhled. Stejný formulář umožní ruční zadání nákupu.

Cozy zkontroluje jednotky, množství, částky a součet dokladu. Zachová i drogerii
a jiné položky mimo receptury. Řádkové slevy zahrne do ceny položky; společnou
slevu uživatel přiřadí dotčeným řádkům, případně ji aplikace poměrně rozdělí
po výslovném potvrzení. Zaokrouhlení dokladu zůstane samostatné.

Opakované `import_id` nevytvoří druhý nákup. Shoda obchodu, data, čísla dokladu
a částky vyvolá kontrolu možné duplicity.

## Data, ceny a reporty

### Samostatný modul

Nový kontext `KitchenCosts` bude vlastnit nákupy, položky, slovník přiřazení,
ruční výchozí ceny a uložené reporty. Položky se napojí cizím klíčem na současné
`kitchen_ingredients`. Nová evidence zůstane oddělená od barových nákupů a skladu.

Uchová původní JSON a potvrzené údaje včetně množství, jednotky a ceny včetně
DPH. Potvrzené nákupy se opravují vytvořením náhradní verze; původní verze
zůstává dohledatelná a přestane vstupovat do nových výpočtů. Uložené reporty
se nemění.

### Výběr ceny

- Cena suroviny k datu jídla = součet cen / součet základních množství
  z potvrzených nákupů za 90 kalendářních dní končících datem jídla.
- Různé značky přiřazené stejné surovině vstupují do společného váženého průměru.
- Bez nákupu v tomto okně se použije poslední starší nákup s upozorněním.
- Bez jakéhokoli předchozího nákupu lze použít ruční cenu s datem platnosti,
  jasně označenou jako odhad. Budoucí nákup se pro minulý den nepoužije.
- Chybějící cena není nula. Zobrazuje se známý mezisoučet a stav
  **Neúplná kalkulace**.
- Výpočty používají `Decimal`; zaokrouhlení probíhá až při prezentaci částek.

### Report nákladů za období

Filtr od–do, nejvýše 366 dní, volitelně jedna rezervace. Rozhodují data
jednotlivých jídel, včetně příjezdových a odjezdových jídel.

Report použije současná pravidla počítání porcí a spotřeby: hlavní recept,
doplňky, výtěžnost receptur a samostatné dětské koeficienty pro snídaně a teplá
jídla. Zahrne dokončené pobyty; vynechá zrušené, smazané a pobyty bez stravy.

Zobrazí:

- celkové kalkulované náklady a počty porcí;
- rozpad podle rezervace, dne, typu jídla, receptu a suroviny;
- průměrný náklad na vydanou porci;
- použitá množství, ceny a jejich zdroj;
- chybějící ceny, receptury, neaktuální menu a další neúplné podklady.

Při uložení vznikne neměnný snapshot receptur, porcí, koeficientů, cen
a upozornění. Nový přepočet vytvoří další verzi. První výpočet minulého období
používá receptury dostupné v okamžiku výpočtu; dřívější neuložené verze receptur
nelze zpětně obnovit.

### Cena u receptu a historie cen

U každého receptu se zobrazí aktuální kalkulace dospělé porce a dětské porce
podle existujících koeficientů. Jde o cenu podle současné receptury a průměrných
nákupních cen, nikoli průměr skutečně vydaných porcí.

Detail suroviny nabídne historii nákupních cen, obchod, balení a trend ceny
za základní jednotku. Součástí bude přehled chybějících a zastaralých cen
— seznam toho, co doplnit jako další.

## Rozhodnutí

Všechna následující rozhodnutí byla potvrzena v chatu dne 2026-10-27:

| Oblast | Přijaté rozhodnutí |
| --- | --- |
| Čtení dokladů | ChatGPT v chatu, poté import JSONu; obrázky se v Cozy neukládají. |
| Napojení | Samostatný modul, více nákupních názvů na jedno stávající ID suroviny. |
| Potvrzování | Známé vazby předvyplnit, nové a konfliktní potvrdit, poté potvrdit celý nákup. |
| Výběr ceny | Vážený průměr podle množství za předchozích 90 dní k datu jídla. |
| DPH | Ceny včetně DPH. |
| Chybějící ceny | Poslední starší nákup s upozorněním; bez nákupu označená ruční cena, jinak neúplný výsledek. |
| Historie reportů | Ukládat neměnné výpočty; přepočet jako novou verzi. |
| Ostatní zboží | Uchovat mimo suroviny kvůli kontrole celého dokladu. |
| Cena porce | Dospělá i dětská podle stávajících koeficientů. |
| Výstupy | Pouze přehledy v Cozy; bez CSV a samostatného PDF v první verzi. |
| Ruční zadání | Ano, společný formulář pro ruční nákup a kontrolu importu. |

## Postup realizace

- [x] V novém vlákně ověřit aktuální `main`, související kontexty a tento plán.
- [ ] Přidat samostatný kontext, migrace, omezení databáze a cenové výpočty.
  - [x] Kontext `KitchenCosts`, potvrzené nákupy a řádky, náhradní verze,
    datované ruční ceny, UUID a databázová omezení.
  - [x] Vážený průměr včetně dne jídla a 89 předchozích dní; starší nákup,
    ruční odhad, chybějící cena a ocenění stávajícího výpočtu spotřeby.
  - [ ] Slovník přiřazení a datový model uložených reportů.
- [ ] Připravit export katalogu, verzované JSON schéma, příklady a instrukce
  pro ChatGPT včetně baleného a váženého zboží a slev.
- [ ] Přidat importní náhled, ruční zadání, potvrzování a verzování nákupů,
  slovník přiřazení a seznam položek k dořešení.
- [ ] Přidat historii cen a aktuální kalkulace porcí u receptů.
- [ ] Přidat reporty za období s rozpadem nákladů a neměnnými uloženými verzemi.
- [ ] Doplnit administraci, PIN ochranu, testy a provozní dokumentaci.
- [ ] Ověřit několik skutečných účtenek a jedno víkendové menu.

Modul dostane vlastní administraci pod stávajícím PINem: nákupy/import,
přiřazení, historie cen a reporty. Do existujících receptů a surovin přibudou
odkazy a cenové údaje.

## Ověření a podmínky dokončení

Testy pokryjí zejména:

- dvě značky protlaku napojené na jednu surovinu, změnu balení a konfliktní návrh;
- vážené zboží, slevy, smíšenou účtenku a duplicitní import;
- vážený průměr podle množství, hranice 90 dní a zákaz použití budoucích cen;
- starší a ruční ceny, chybějící ceny a neúplné kalkulace;
- dětské porce, snídaně, doplňky a pobyt zasahující mimo období;
- neměnnost uloženého reportu po opravě nákupu nebo receptury;
- PIN ochranu, atomické potvrzení a souběžný import stejného nákupu.

Na skutečných dokladech ručně porovnat přepočet ceny za kg/l/ks a cenu jednoho
menu. Podle instrukcí repozitáře poběží testy standardně v CI; lokální spuštění
vyžaduje samostatný pokyn. Testy první části jsou doplněné, lokálně nebyly
spuštěny; výsledky CI ověří uživatel.

## Nasazení a rizika

Nasazení přidá nové tabulky bez doplňování smyšlených historických cen.
První verze nevyžaduje OpenAI API klíč ani změnu ABRA. Hlavními riziky jsou
chybně přečtené množství, nejasná sleva, špatné přiřazení suroviny a neúplné
menu. Řeší je editovatelný náhled, výslovné potvrzení, kontrola součtů a viditelná
neúplnost výsledku. Nákupní cena není důkaz skutečné skladové spotřeby.

## Průběh a předání dalšímu chatu

- Hotovo: opětovné ověření kódu proti čerstvě načtenému `origin/main`
  (`26f12f3`); první část kontextu `KitchenCosts` a migrace `20261027120000`.
  Uložení potvrzeného nákupu je atomické, kontroluje součet včetně samostatného
  zaokrouhlení, jednotky, balení a všechny vazby. Nepřiřazené a ostatní řádky
  zůstávají v dokladu, ale nevstupují do cen surovin. Cena řádku je konečná
  cena po slevách včetně DPH; rozdělování společné slevy ještě není hotové.
  Původní JSON a snapshot názvu/jednotky suroviny zůstávají uložené.
  Oprava vytváří náhradní verzi, původní nákup nemění. Nové výpočty vynechají
  nahrazené verze. Opakované ID importu vrací původní záznam; zámky a unikátní
  indexy chrání souběh. Shodný obchod (bez ohledu na velikost písmen a krajní
  mezery), datum, číslo a částka vyžadují výslovné potvrzení možné duplicity.
  Historické nákupy i ruční ceny blokují změnu základní jednotky suroviny.
  Cenový výpočet vrací zdrojové řádky a upozornění; při více starších nákupech
  v posledním nákupním dni použije jejich vážený průměr.
- Testy první části: balené a vážené zboží, změna balení, dvě značky jedné
  suroviny, smíšený doklad, součty a zaokrouhlení, převody g/ml/ks, atomické
  odmítnutí, opakované importy, duplicity, náhradní verze, neměnnost původních
  dat, 90denní hranice, budoucí ceny, starší a ruční ceny, známý mezisoučet
  a dětský koeficient stávajícího výpočtu. Skutečný souběh samostatných
  databázových spojení a PIN ochrana budoucí administrace ještě čekají na testy.
- Ověření první části: kompilace s `--warnings-as-errors` a projektový
  formatter včetně `MIX_ENV=test mix format --check-formatted` prošly.
  Lokálně je Elixir 1.20.4 / Erlang 29.1.2; přesně připnutý Erlang 29.1 není
  nainstalovaný, shoda formátování s CI proto není ověřená. Lokální testy ani
  migrace nebyly spuštěny; výsledky CI ověří uživatel.
- Zbývá: importní kontrakt a export, slovník, editovatelný náhled a ruční
  formulář, administrace pod PINem, historie cen v UI, kalkulace u receptů,
  reporty a jejich neměnné snapshoty, provozní ověření na skutečných dokladech.
- Blokuje: nic pro zahájení implementace. Ukázkové účtenky budou potřeba
  pro závěrečné provozní ověření čtení a importu.
- Nejbližší další krok: navázat verzovaným JSON schématem, příklady baleného
  a váženého zboží, instrukcemi pro ChatGPT a exportem katalogu; poté přidat
  slovník a náhled. `KitchenCosts.confirm_purchase/2` zatím přijímá pouze
  zkontrolovaná data z interního volání; nejde o parser nedůvěryhodného JSONu.
  Příznaky potvrzení duplicity a náhrady musí předávat obsluha přes aplikaci,
  nikoli importovaný JSON. Potvrzená rozhodnutí v tomto plánu zůstávají beze změny.

Pro nové vlákno lze použít:

> Přečti plán v `docs/plans/2026-10-27-nakupy-a-nakladovost-kuchyne.md`,
> ověř aktuální stav kódu a začni jeho implementaci. Zachovej potvrzená
> rozhodnutí a průběžně aktualizuj stav a dokončené kroky v plánu.

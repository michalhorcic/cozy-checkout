# Fixní a variabilní náklady v Ekonomice firmy

- Stav: **implementace první verze (kroky 1–2) připravena k CI a ručnímu ověření**. Kroky 3–4 zůstávají další etapou.
- Vytvořeno: 2026-10-29
- Aktualizováno: 2026-10-29
- Zadání: samostatná záložka v Ekonomice firmy, měnitelné mapování nákladů a postupné rozšiřování pohledu na náklady a možnosti jejich ovlivnění.
- Potvrzený záměr: nová záložka a uživatelsky upravitelné mapování. Konkrétní pravidla a rozdělení smíšených nákladů níže jsou návrh.
- Související: [Ekonomika firmy](../features/ECONOMICS.md), [ověřený kontrakt ABRA](../integrations/ECONOMICS_ABRA_CONTRACT.md), [původní plán](2026-10-28-ekonomicky-dashboard.md).

## Problém a očekávaný výsledek

Majitel chce vidět, kolik stojí základní provoz domu, které náklady rostou
s provozem a které výdaje vybočují z běžného fungování. U částky musí být
možné dohledat účet, firmu, doklad a pravidlo, které rozhodlo o zařazení.
Mapování musí jít upravit bez změny kódu a bez zásahu do účetnictví ABRA.

První verze má odpovědět:

- Jaké fixní, variabilní a dosud nerozdělené náklady jsou zaúčtované v měsíci?
- Kolik z nich tvoří náklady označené jako mimořádné?
- Co ještě není zařazené nebo potřebuje ruční rozhodnutí?
- Co se změní, když upravím pravidlo, a proč je konkrétní položka zařazená právě takto?

Částka zaúčtovaná v měsíci se může lišit od běžné měsíční zátěže i od
skutečných plateb. Očekávaný měsíční základ ze smluv a pravidelných závazků
bude samostatná následná etapa; nezačne se vydávat za historickou účetní částku.

## Současný stav a ověřené podklady

Na aktuálním `origin/main` již existuje kontext Economics, vlastní GET klient,
verzované účetní snapshoty, denní i historické saldo, potvrzování účetní
úplnosti a PINem chráněné admin obrazovky. Průzkum tohoto plánu vycházel
z implementace, schémat, migrace a syntetických testů v repozitáři.

- `economics/reports.ex` normalizuje pohyby na účtech a rozlišuje nákladové
  účty podle firemního rozvrhu. Náklad se počítá MD minus Dal přes Decimal.
- Snapshot má měsíce a pohyby s účtem, datem účtování, modulem, `idDokl`,
  `idUcetniDenik`, částkami a identifikačními údaji dokladu.
- Identifikace již obsahuje název firmy, lidské číslo dokladu, popis, VS,
  číslo dodavatelského dokladu a protiúčet. Popis je omezený na 500 znaků.
- API již požaduje `firma`; normalizace ale uchovává pouze její popisek,
  nikoli stabilní ID. Jeho získání ze stávající odpovědi se musí ověřit.
- Stabilita `idUcetniDenik` odvozeného účetního výstupu přes opravy není
  doložená. Návrh proto nepoužívá toto ID jako jediný klíč ruční výjimky.
- `AccountMapping` v kódu je jiné rozdělení: Potraviny, Energie, Mzdy apod.
  Má i výnosové kategorie. Tato funkce jej nebude nahrazovat ani přepisovat.
- `Reports.month_fingerprint/1` již odděluje identifikační popisy od
  finančního otisku potvrzení úplnosti. Manažerské mapování zůstane mimo něj.

Firma má účetnictví od července 2026; úplnost podkladů a část finančních
stavů čekají na účetní ověření. Krátká historie nepostačuje k automatickému
odhadu fixní složky energií, sezónnosti nebo běžné spotřeby.

## Rozsah první verze

Samostatná záložka **Nákladovost** na `/admin/economics/costs`.
V ní pohled **Přehled nákladů** a správa **Mapování**. Výběr hospodářského
roku a měsíců používá skutečné hranice ABRY a stávající místní snapshoty.

První verze zahrne:

- Zařazení nákladů, měsíční součty, mimořádné položky a stav nezařazených.
- Editovatelná pravidla, ruční výjimky, náhled dopadu a historii verzí.
- Volitelné ruční procentní rozdělení smíšeného nákladu s označením odhadu.
- Detail firmy, dokladu a použitého pravidla; přechod na stávající účetní pohyby.
- Pracovní návrhy zařazení, které uživatel výslovně přijme; ostatní zůstane nezařazené.

Mimo tuto verzi: automatické účetní opravy, jakékoli zápisy do ABRY, odhad
podílů AI/regresí, automatické rozdělování společných nákladů mezi činnosti,
změny vydaných dokladů, evidence plateb, rozpad souhrnné faktury na zboží,
nové uživatelské účty a integrace s kalkulacemi KitchenCosts/Sales/Billing.
Náklady se z těchto kontextů nepřičítají k jejich kopiím v ABŘE.

## Navržené mapování

### Dvě samostatné informace

**Chování nákladu:** fixní, variabilní, smíšené nebo nezařazené.

**Příznak mimořádné:** náklad výslovně označený za mimořádný. Může být
současně fixní, variabilní i smíšený. Jde o další pohled na stejné částky,
nikoli o další sčítanou kategorii. Výchozí neoznačení neznamená účetní
potvrzení, že každý výdaj je běžný.

Příklad: pravidelný nájem je fixní; jednorázová oprava má označení mimořádné
a její chování se zvolí zvlášť. Potraviny nejsou mimořádné jen proto,
že při větším počtu hostů vzrostla jejich celková částka.

### Pravidla a jejich přednost

Všechna pravidla patří konkrétnímu zdroji ABRA, mají období platnosti,
poznámku s důvodem a přiřazení obou výše uvedených informací.
Účet se vybírá přesně, podle skutečného rozvrhu; neodhaduje se podle názvu.
Platnost je v první verzi po celých kalendářních měsících (od měsíce / do
měsíce včetně), aby se jeden měsíční podklad nemapoval více způsoby podle
různých dnů účtování téhož dokladu.

| Přednost | Rozsah | Příklad |
| --- | --- | --- |
| 1 | Ruční výjimka pro konkrétní nákladový podklad | Tato oprava je mimořádná. |
| 2 | Účet + stabilní firma + text v popisu | Jen pronájem od konkrétní firmy na účtu ostatních služeb je fixní. |
| 3 | Účet + stabilní firma | Paušální účetní služby od této firmy jsou fixní. |
| 4 | Účet + text v popisu | Konkrétní typ předplatného na společném účtu služeb je fixní. |
| 5 | Účet | Potraviny na 501100 jsou po potvrzení pravidla variabilní. |
| 6 | Bez odpovídajícího pravidla | Nezařazeno. |

Všechny podmínky pravidla se musí splnit. Textový filtr je prosté
„popis obsahuje“, bez rozlišení velikosti písmen, nad uloženým popisem;
nepoužívá uživatelské regulární výrazy. Pokud byl popis zkrácen, UI to ukáže.
Výchozí identifikace firmy je ID v rámci zdroje. Po výslovném potvrzení
uživatelem 29. 10. 2026 lze pro podklady bez ID zvolit „Firma podle názvu“:
přesná shoda celého uloženého názvu bez velikosti písmen a okolních mezer,
se samostatným polem `partner_name`. Žádné přibližné ani automatické párování.
Pravidlo platí jen pro podklady, jejichž všechny zápisy nemají ID a mají
shodný název. Přejmenování nebo doplnění ID může vyžadovat nové pravidlo.

Dvě současně platná pravidla se stejnou předností a různým výsledkem vytvoří
**Konflikt mapování**. Takový náklad zůstane nevyřešený a započte se do
nezařazené části. První verze nebude mít skryté „poslední uložené vyhrává“
ani libovolná číselná pořadí. Shodné výsledky lze použít a v detailu dohledat.

### Ruční výjimka a identita podkladu

Výjimka se vztahuje k součtu nákladových pohybů jednoho dokladu na jednom
účtu v jednom účetním měsíci. Klíč je zdroj + modul + `idDokl` + účet + měsíc.
UI jasně ukáže tento rozsah a všechny zahrnuté zápisy; nejde o domnělé
přiřazení jediného produktového řádku faktury.

Klíč nesmí tvořit název firmy, lidské číslo faktury ani samotné ID deníku.
Součástí výjimky bude finanční otisk podkladu. Při změně částek nebo složení
podkladových účetních zápisů se výjimka pozastaví k opětovné kontrole;
nevznikne tiché nové přiřazení podle méně konkrétního pravidla. Přejmenování
firmy a doplnění popisu tento finanční otisk nemění.

Detailní výjimka pro jednotlivý účetní řádek nebo produkt může následovat
po ověření stabilních identifikátorů. Pro první verzi se tato přesnost neslibuje.

### Výchozí návrhy

| Náklad | Návrh před potvrzením | Poznámka |
| --- | --- | --- |
| Potraviny 501100 | Variabilní | Přijetí pravidla uživatelem; měsíční náklad nemusí odpovídat spotřebě zásob. |
| Energie 502001 | Smíšené bez rozdělení | Žádný přednastavený procentní podíl. |
| Mzdy 521001 | Nezařazené | Závisí na smlouvách, paušálech a směnách. |
| Úklid a praní 501300/518400 | Návrh variabilní | Ověřit, zda některá část není paušál. |
| Nájem, telefon, internet | Návrh fixní po určení firmy a účtu | Účet služeb může obsahovat i jiné položky. |
| Účetní služby 518200 | Návrh fixní jen pro potvrzený paušál | Mimořádné služby stejné firmy mohou potřebovat přesnější pravidlo. |
| Opravy 511001, ostatní služby 518001 | Nezařazené | Neoznačovat všechny opravy automaticky jako mimořádné. |
| Odpisy 551001 | Individuálně potvrdit; viditelně nepeněžní | Nepovažovat za aktuální odtok peněz. |

Návrhy nejsou automaticky aktivní pravidla. Je možné přijmout více návrhů
najednou, vždy s náhledem účtů, měsíců a částek, kterých se změna týká.

### Smíšené náklady a součty

Pro smíšený náklad půjde zvolit **zatím nerozdělovat** nebo zadat odhad
fixního podílu 0–100 % s poznámkou. Procento zůstane ruční odhad, zřetelně
oddělený od potvrzeného účetního údaje. Variabilní část je přesný zbytek;
použije se Decimal a zaokrouhlí se až zobrazení. Zobrazené korunové součty
musí dorovnat haléřový zbytek, aby samotné zaokrouhlení dvou složek nezvýšilo
jejich součet nad původní částku.

Kontrolní rovnost pro každé období a všechny záporné opravy:

```text
fixní složka + variabilní složka + smíšené bez rozdělení + nezařazené
= veškeré náklady MD − Dal z vybraného snapshotu
```

Rozdělené smíšené náklady jsou již ve fixní/variabilní složce; nesčítají se
podruhé. Mimořádné tvoří označenou podmnožinu celku. Dobropisy a opravy
zachovají znaménko. Nulový nebo záporný celkový výsledek nesmí způsobit
dělení nulou či zavádějící procenta pokrytí: ukáže se počet nevyřešených
podkladů a jejich absolutní objem, případné pokrytí se počítá z absolutních
hodnot nákladových podkladů, nikoli z čistého součtu po dobropisech.

Paušální měsíční částka se nebude odečítat od každé faktury téhož dodavatele.
Pevná částka za měsíc patří k následnému modelu pravidelných závazků, jinak
by více faktur mohlo stejný paušál započítat několikrát.

## Uživatelský postup

1. Uživatel otevře Nákladovost a vybere účetní období/měsíce. Uvidí fixní
   a variabilní složku, nerozdělené smíšené a nezařazené náklady. Odhadovaná
   část a účetní úplnost jsou viditelné samostatně.
2. Přehled nabízí běžné kategorie (energie, potraviny…), rozpad podle firem
   a přechod na doklady. U každého podkladu je použité pravidlo a jeho verze.
3. V Mapování vytvoří pravidlo nebo z konkrétního podkladu zvolí „Jen tento
   podklad“ / „Pravidlo pro další doklady“. Formulář viditelně obsahuje účet,
   firmu, případný text, platnost od/do, chování, mimořádnost a důvod.
4. Před uložením vidí náhled: které podklady/měsíce se zařadí jinak, jak
   se změní součty a zda vzniknou konflikty. Počáteční mapování může výslovně
   zahrnout již načtené období; přepsání minulého výkladu nebude skryté.
5. Uložení atomicky publikuje novou verzi mapování. Rozpracované změny
   nejsou aktivní a souběžně změněný náhled vyžádá nové přepočítání.
6. V přehledu lze filtrovat mimořádné, nezařazené, konfliktní podklady
   nebo položky s odhadem. Všechny zůstávají dohledatelné v celkovém nákladu.

Seznamy účtů a firem nad 30 položek budou vyhledávatelné; při implementaci
se prověří vhodnost existujícího `KitchenComponents.searchable_picker/1`.
Nevznikne nový obecný formulářový systém ani nová grafová knihovna.

## Data, verze a hranice implementace

Celá funkce patří do Economics a jeho veřejného rozhraní. Ostatní obchodní
kontexty na ní nebudou záviset. Výnosy, peněžní účty, DPH, splátky jistin,
přijaté zálohy a investice se nezařadí mezi náklady jen podle částky faktury;
vstupem jsou výhradně již normalizované nákladové účetní zápisy.

Návrh přidávacích tabulek, s UUID, timestamps, cizími klíči a omezeními:

- `economics_cost_mapping_versions`: zdroj, pořadové číslo verze, stav
  návrh/aktivní/nahrazená, čas publikace a poznámka. Nejvýše jedna aktivní
  verze na zdroj; publikace pod transakčním zámkem a unikátními indexy.
- `economics_cost_rules`: úplné znění pravidel dané verze, účty, stabilní
  partner, případný text, rozsah platnosti, chování, mimořádnost a volitelné
  procento fixní složky. Validace typu, rozsahu 0–100 a dat od/do.
- `economics_cost_overrides`: výjimky dané verze s identitou podkladu,
  finančním otiskem, přiřazením a důvodem. Unikátní cíl v rámci verze.

Publikované verze a jejich pravidla budou neměnné. Úprava vytvoří další
verzi; odebrání pravidla bude zachované v historii, bez fyzického mazání
obchodních záznamů. Smazání rozpracovaných položek bude soft delete.
Audit eviduje čas, důvod a změny; stávající sdílený PIN nezaručuje identitu
konkrétní osoby, nevymýšlí se proto vazba na neexistující Phoenix účet.

Výsledek klasifikace je odvozená vrstva nad zdrojovým snapshotem. Nezapisuje
se do jeho účetních pohybů, nemění `Reports.month_fingerprint`, potvrzení
účetní úplnosti ani historické účetní doklady. Každý zobrazený přehled nese
ID zdrojového snapshotu a verzi mapování; starší publikovanou verzi půjde
zvolit a výklad zopakovat. Náhled změny se vztahuje ke konkrétnímu snapshotu
a výchozí verzi mapování; jejich mezitímní změna zneplatní náhled.

Změna cílové firmy nevynutí přenesení mapování mezi zdroji. Pravidla,
výjimky i jejich identifikátory zůstávají oddělené. Starší snapshot bez
stabilního ID partnera podporuje pravidlo na účet, výjimku na podklad a
nově výslovné názvové pravidlo pro podklady bez ID. Pravidlo na interní ID
stále vyžaduje doplnění tohoto údaje importem.

Všechny nové routy a mutace zůstávají ve stávající admin PIN ochraně.
Účetní data se čtou z místních snapshotů. Pravidla se načtou jedním dávkovým
dotazem pro verzi, výjimky dalším; klasifikace a agregace proběhnou v paměti.
Nevzniknou N+1 dotazy ani nové HTTP požadavky pro každý doklad nebo firmu.
Případnou potřebu cache řešit až podle měření; pokud vznikne, její klíč musí
obsahovat zdroj, snapshot, verzi mapování a rozsah měsíců.

## Postup realizace

- [ ] **1. Kontrakt a základ dat:** ověřit stabilní identitu firmy ze stávající
  GET odpovědi, doložit identitu nákladového podkladu a doplnit metadata
  snapshotu bez změny finančních otisků. Přidávací migrace pro verzované
  mapování, validační schémata a testy izolace zdrojů.
- [ ] **2. První použitelná záložka:** čistý klasifikátor, pravidla a výjimky
  s předností a konflikty; náhled a atomická publikace; editace Mapování,
  nezařazené položky, měsíční součty, označení mimořádných, volitelný ruční
  podíl smíšených a detail podkladů. Syntetické regresní a PIN testy.
- [ ] **3. Běžná měsíční zátěž:** samostatná evidence potvrzených pravidelných
  závazků (nájem, telefon, pojištění…), intervalů a měsíčního ekvivalentu.
  Očekávaný základ versus skutečně zaúčtované náklady; žádné dvojí přičítání
  šablony a účetního dokladu. Způsob částek a služby potvrdí uživatel.
- [ ] **4. Následné možnosti:** odchylky od potvrzeného základu a náklad na
  osobonoc/porci až po ověření odpovídajících provozních dat a období.
  Žádné automatické červené varování jen z růstu při vyšší obsazenosti.
- [ ] Doplnit `docs/features/ECONOMICS.md` podle skutečně dodané první verze,
  ověřit ručně reprezentativní měsíc a zdokumentovat další otevřené položky.

Kroky 1–2 tvoří první implementační rozsah. Kroky 3–4 se samostatně upřesní
po jeho použití; nejsou podmínkou prvního přehledu a nejsou zatím podrobně
navrženou implementací.

## Ověření a podmínky dokončení první verze

- Deterministická přednost pravidel, platnost od/do, stejné firmy různých
  zdrojů, přejmenování firmy, prázdný partner/popisek, text s diakritikou,
  zkrácený popis a konflikty bez tichého přiřazení.
- Přesná kontrolní rovnost všech složek a nákladů původního snapshotu;
  záporné opravy, nula, smíšené 0/100 %, nezařazené, nerozdělené smíšené,
  mimořádné jako podmnožina a stejné částky bez dvojího počítání. Zvlášť
  rozdělení jednoho haléře v poměru 50/50 a jeho záporné opravy.
- Nákladové účty podle typu, oddělení výnosů/DPH/záloh/investic, odpisy
  nezaměněné za aktuální platby. Bez přičítání dat dalších kontextů.
- Výjimka platí pro celý deklarovaný podklad; změna jeho finančního otisku,
  přesun do jiného měsíce nebo zánik vyvolá dohledatelný stav k řešení.
- Identifikační změna a nová verze mapování nezneplatní účetní úplnost;
  starší výklad lze zopakovat volbou původního snapshotu a mapování.
- Souběžná publikace, neaktuální náhled, rollback transakce a starší
  snapshoty bez nových metadat; žádná částečně aktivní sada pravidel.
- PIN všech obrazovek i událostí, vypnutý modul bez ekonomických dotazů,
  žádné HTTP z klasifikace nebo UI a žádné zápisy do ABRY.
- Dávkové načtení pro více účtů a dokladů, přiměřená odezva na skutečném
  objemu a čitelné mobilní zobrazení. Grafy využijí stávající HTML/CSS.
- Testy integrací přes Req.Test se syntetickými podklady. Formatter podle
  AGENTS.md; lokální testy standardně ponechat CI a výsledky ověří uživatel.
- Ručně potvrdit několik pravidel s majitelem, porovnat měsíc s existujícím
  výsledkem Economics a jasně označit neznámé či odhadované složky.

## Otevřené otázky a podklady

- Určit nájem, telefon a další paušály podle účtu a firmy; konkrétní částky
  pro měsíční smluvní základ patří až do kroku 3.
- Potvrdit, které z mezd, úklidu a účetních služeb jsou paušály a které
  závisí na provozu. Bez odpovědi zůstávají příslušné podklady nezařazené.
- Pro energie zvolit prozatím nerozdělovat nebo výslovný ruční odhad.
  Krátká historie a zálohy na energie nedokládají skutečnou spotřebu.
- Ověřit stabilní ID partnera a chování souvisejících dokladových identit
  přes opravy. Odhadované párování podle jména se nezavádí; výslovně zvolené
  přesné názvové pravidlo je samostatná možnost pro podklady bez ID.

Tyto otázky neblokují datový základ a klasifikaci podle účtů. Pravidla
vyžadující neověřená vstupní data se do vyřešení neaktivují.

## Rozhodnutí a nasazení

| Datum | Rozhodnutí | Potvrzení / zdroj |
| --- | --- | --- |
| 2026-10-29 | Zvláštní záložka v Ekonomice firmy, mapování měnitelné uživatelem, postupný rozvoj | Výslovné zadání uživatele |
| 2026-10-29 | Chování nákladu a mimořádnost jako samostatné informace | Návrh tohoto plánu navazující na diskusi |
| 2026-10-29 | Verze mapování, přednost pravidel, náhled změn a stabilní identita firmy | Návrh tohoto plánu |

Po implementaci aplikovat pouze nové migrace `economics_*`, ověřit čtecí
metadata, vytvořit první návrh mapování a porovnat vybraný měsíc. Návrhy
nebudou samovolně publikované. Návrat ke starší aplikaci nevyžaduje mazání
nových tabulek; účetní snapshoty a potvrzení úplnosti se nepřepisují.

## Průběh a předání

- Implementováno: metadata interního ID firmy a zkrácení popisu, nákladové
  účty z rozvrhu, přidávací migrace, čistá klasifikace, verzované publikace,
  náhled pro všechna načtená období, pravidla a výjimky, historie a záložka
  Nákladovost v existující PIN ochraně. Celá první verze je v jednom PR.
- Návrhy existují pouze v otevřené LiveView stránce; do DB vstupují celé
  sady v jedné publikační transakci. Přepnutí záložek je zachová, obnovení
  nebo změna období je zahodí. Samostatné ukládání rozpracovaných návrhů
  mezi návštěvami tato první verze nezavádí.
- Ověřeno lokálně: kompilace aplikace s varováními jako chybami, kompilace
  změněných testovacích modulů bez jejich spuštění a projektový formatter.
  Testy se lokálně nespouštějí podle AGENTS.md; výsledky CI ověří uživatel.
- K dokončení provozního ověření kroků 1–2: skutečný tvar interního ID firmy
  z firemní ABRY, několik pravidel a odhadů s majitelem, reprezentativní
  měsíc, mobilní zobrazení a odezva na skutečném objemu. V implementačním
  běhu nebylo nakonfigurované připojení Economics ani reálný snapshot.
- Interní ID je vyžádané dokumentovaným `use-internal-id=true` ve stávajících
  GET a normalizuje se `firma@internalId`; při absenci zůstávají k dispozici
  účet, text, výjimka a nově výslovné názvové pravidlo. Podrobnosti a omezení jsou v aktualizovaném kontraktu
  ABRA a `docs/features/ECONOMICS.md`.
- Kroky 3–4 (smluvní měsíční základ a provozní ukazatele) se neimplementují
  bez samostatného upřesnění. Nejasné smlouvy samy nevytvářejí aktivní pravidla.

### Doplnění schválené 29. 10. 2026

Uživatel výslovně schválil mapování podle přesného názvu firmy pro podklady
bez interního ID. Implementace používá samostatné nullable pole `partner_name`,
přidávací migraci, kontrolu výlučnosti ID/názvu a stejné verzování i náhled.
Podrobnosti, omezení a označení v UI jsou v `docs/features/ECONOMICS.md`.

# Cozy Adventure: herní svět chaty a kratší cesta k hraní

- Stav: schváleno uživatelem k implementaci; implementace v této větvi, CI ověřuje uživatel.
- Vytvořeno: 2026-11-12
- Základ auditu: `origin/main` `a16b150`, PR #122 a #123.
- Navazuje na [funkci Adventure](../features/ADVENTURE.md) a [roadmapu provozu a budování](2026-11-12-adventure-todos-a-prehled-sezony.md).

## Cíl a potvrzená rozhodnutí

Adventure má být útulná kooperativní budovatelská hra pro Michala a Lucku:
**vidím naši chatu → vyberu práci nebo zlepšení → pokračuji → potvrdím výsledek → vidím svůj přínos**.
Uživatel schválil nové uspořádání i grafiku, ilustrovanou chatu s okolím z mírného
nadhledu, mobil i počítač, krátké návraty i delší plánování a obecná zlepšení
přímo ve scéně. Současná herní pravidla zůstávají.

Tato práce má přednost před návaznou Službou dne 5B a živým Barem 5C. Questy
ze Služby dne 5A už jsou sloučené v PR #122; původní roadmapa obsahovala starší
předávací stav. Projekty i trvalé výsledky už existují, potřebují především lepší
herní prezentaci.

## Audit a principy

Původní ilustrace byla banner, mapa byla pod profilem, seznamy práce a Službou dne.
Karty i vysvětlení měly podobnou váhu, projekty se na mapě projevovaly hlavně
rámečkem a počtem. Hláška „Herní postup uložen.“ nerozlišovala skutečný výsledek.
Mobilní názvy oblastí se lámaly po několika písmenech.

Na skutečných komponentách s ukázkovými daty (3 osobní questy, 1 společný,
4 podněty) měla stránka při 390 px výšku přibližně 4 318 px a mapa začínala
na 2 710 px. Tento původní audit nebyl proklik nasazené databáze.

- Jasný aktuální cíl a dostupný postup: [Xbox Objective clarity](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/109).
- Kontextové ovládání, konkrétní odezva a méně rušivých informací: [NN/g – video games](https://www.nngroup.com/articles/usability-heuristics-applied-video-games/).
- Pokročilé možnosti na vyžádání: [NN/g – Progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/).
- Vlastní volba, zvládnutá práce a spolupráce: [Self-Determination Theory](https://selfdeterminationtheory.org/the-theory/). Důraz na konkrétní společný výsledek je aplikace principu na tento produkt, ne výzkumné tvrzení o této aplikaci.
- Předvídatelná navigace a fokus: [Xbox UI navigation](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/112).

## Implementace

### Herní rám a navigace

- Hlavní navigace Chata / Výpravy / Rozvoj / Kronika; mobil má pevnou spodní navigaci.
- Volitelné `view=world|expeditions|development|chronicle` na existující táborové trase; neplatný parametr znamená `world`.
- Přechody používají LiveView patch a zachovají provozní snapshot i hrdinu. Staré adresy knihy zadání a přímé odkazy na quest/projekt fungují dál.
- Kompaktní profil a oddělený postup chaty; výběr hrdiny po rozbalení profilu. PIN, feature flag a původní persistence se nemění.

### Scéna a kontextové hraní

- Nová lokální SVG ilustrace, pět oblastí a Dílna. Popisky jsou HTML tlačítka, existuje i textový seznam oblastí; žádný engine, hover nebo nutnost zoomování.
- Desktop má scénu a jeden kontextový panel. Výchozí panel nabídne první aktivní osobní quest podle dosavadního pořadí nebo výběr nové výpravy.
- Mobilní detail oblasti/služby má samostatnou plochu, návrat, Escape, fokus uvnitř a obnovení fokusu po zavření. Zbytek hry je během detailu inertní.
- Tři osobní výpravy a souhrn společné práce jsou v kompaktním panelu. Služba dne je vstup s počtem; konkrétní podněty se otevřou v kontextu.
- Výpravy mají Rozpracované / Nabídka. Zadání se rozbaluje v detailu; příjemce XP, přispěvatelé i nepovinná poznámka zůstávají.
- Rozvoj otevírá existující knihu projektů přímo ve hře. Správa zadání zůstává samostatná; běžně je vidět hledání, ostatní filtry jsou pod Filtry.
- Kronika odděluje Zlepšení chaty / Splněné výpravy / Sezóny. Finanční významy se nemění.

### Výsledek a odezva

- Oblast má základní podobu, při 1 převzatém projektu praporek a při 2+ také trofej. Přesné počty zůstávají v detailu; archivované převzaté projekty dál platí. Dílna nedostává milníky místnosti.
- Nové splnění ukáže konkrétní název, přiznaná XP a skutečného příjemce. Změna právě načtené osobní nebo společné úrovně zobrazí další oznámení.
- Nové převzetí projektu ukáže konkrétní výsledek a aktualizuje již načtenou projekci světa. Nepřidává XP.
- Virtuální návratové příznaky `Quest.newly_completed` a `Project.newly_accepted` označují pouze novou změnu uvnitř zamčené transakce. Neukládají se do DB; replay a nové načtení mají `false`. Podpisy business funkcí se nemění.
- Animace jsou krátké, bez zvuku a s podporou omezeného pohybu.

## Data, kompatibilita a výkon

Bez nové migrace, konfigurace, herní měny, pravidel odměn, penalizací, konkrétních
ilustrací jednotlivých projektů nebo nových provozních zdrojů. Provoz se dál jen
čte; skutečná práce používá původní aplikaci.

- Přepnutí již načtených pohledů, oblasti a kontextových panelů má 0 SELECTů.
- První výslovný vstup do Rozvoje použije existující projektový loader (nejvýše 2 SELECTy; při vybraném projektu 1 pro historii). Výsledek se drží v socketu, opakované přepnutí jej nenačítá.
- První otevření Splněných výprav načte existující historii do 100 položek jedním SELECTem; další přepnutí ji použije z paměti. Změna hrdiny nebo splnění cache zneplatní.
- Kronika zlepšení dál načítá stránku pouze výslovným tlačítkem, 1 SELECT na stránku. Obnova rozvoje používá původní 2 SELECTy.
- Převzetí doplní již načtené agregace v paměti, bez dalších dotazů na scénu.
- Zobrazení sezón používá existující výpočet pražského dne v paměti; render už kvůli datu neprovádí SQL. Finanční přepočty zachovávají původní zdroje a pravidla.
- Zdrojový provozní loader zůstává nejvýše 15 SELECTů. Žádný polling ani N+1 po oblastech, kartách, dekoracích nebo etapách.
- U údajů zůstávají čas, ruční obnova a varování o neúplnosti, stáří a nedostupnosti. Neznámý stav není nula.

## Ověření a podmínky přijetí

- [x] Herní rám, pohledy, kompaktní profil a mobilní navigace.
- [x] Scéna, přístupné oblasti, kontextová práce a textový seznam.
- [x] Výpravy, Rozvoj, Kronika a sbalené filtry zadání.
- [x] Dekorace, transakční rozlišení nové změny a konkrétní odezva.
- [x] Regrese připravené pro CI: navigace a cache bez SQL, fallback neplatného pohledu, skutečný příjemce, replay/reconnect, historie, virtuální příznaky a souběh.
- [ ] Výsledky ExUnit v CI ověří uživatel; lokální ExUnit se podle pravidel repozitáře nespouští.
- [ ] Michal a Lucka potvrdí, že se bez výkladu zorientují do 10 sekund.

Browserové ověření používá běžící aplikaci a izolovanou lokální PostgreSQL s
ukázkovými daty, nikoli produkční data. Kontroluje desktop 1440 × 900, mobil
390 × 844 a šířku 320 px, skutečné přijetí/splnění, příjemce XP, přechody do
Rozvoje, převzetí projektu, změnu světa a kroniku. Součástí jsou klávesnice,
fokus/Escape, motivy a omezený pohyb. Konkrétní výsledek ověření je uveden v PR.

Nasazení používá existující Adventure migrace a flag. Návrat změny nevyžaduje
rollback databáze. Pokračování 5B/5C se řeší samostatně po ověření tohoto UX.


## Výsledek ověření implementace

- Běžící Phoenix aplikace nad izolovaným PostgreSQL 17: přijetí výpravy,
  potvrzení splnění za Lucku při hraní za Michala, jediné oznámení odměny a
  žádné opakování po reloadu; projektový krok, výslovné převzetí a dekorace
  po novém načtení; trvalá kronika a splněné výpravy.
- Chromium: šířky 320, 390, 768 a 1440 px bez vodorovného scrollu; mobilní
  scéna a hlavní akce viditelné na 390 × 844. Ověřen také hrdina bez aktivní
  práce, vymazání/opětovný výběr profilu, Escape/fokus u detailu a Průvodce,
  light/noir a režim omezeného pohybu. Nešlo o test s asistivní čtečkou.
- Prošly kompilace aplikace s `--warnings-as-errors`, asset build,
  celoprojektový `MIX_ENV=test mix format --check-formatted`, kontrola syntaxe
  nového JS a `git diff --check`. Použit přesně připnutý Elixir 1.20.4 / Erlang 29.1 (ERTS 17.1);
  verze Erlangu ověřena také v souboru runtime `OTP_VERSION`.
- Lokální ExUnit ani Node test suite nebyly spuštěny; připravené regrese a
  souběhové scénáře musí ověřit CI. CI nebylo sledováno.
- Neověřeno browserem: všechny varianty neúplných/chybujících zdrojů,
  blokování obou úložišť, skutečný čtečkový průchod a 200% zvětšení textu.
  Pro tyto stavy zůstávají zachované regrese a manuální akceptace.

### Oprava po hlášeném CI (12. 11. 2026)

Sedm hlášených pádů mělo dvě příčiny: inline nabídka se vykreslovala také ve
skrytém pohledu Výpravy současně s modalem, takže měla duplicitní ID; starší
profilové aserce hledaly jméno a úroveň v původním XP panelu. Inline nabídka nyní
vzniká pouze při `view=expeditions`, zatímco ostatní pohledy používají modal.
Profilové testy kontrolují jméno a úroveň u avatara a XP odděleně.

Přidána regrese pro otevření, zavření a přepínání obou umístění nabídky. Lokálně
spuštěny soubory `test/cozy_checkout_web/adventure/index_test.exs` a
`test/cozy_checkout_web/adventure/projects_test.exs`: **47 testů prošlo**.
Tento cílený běh nahrazuje předchozí omezení lokálního ověření pro tyto dva
soubory; ostatní testovací sady zůstávají na CI. Bez nových dotazů, migrace,
konfigurace nebo změny herních pravidel.


### Jedna chata s odkrytým interiérem (12. 11. 2026)

Uživatel následně vybral první ze tří výtvarných alternativ: jednu chatu jako
otevřený domeček pro panenky. Dosavadní samostatné domky nahrazuje jediná budova
se společnou střechou, průběžnými stropy a dvěma podlažími. Nahoře jsou pokoje,
účetní koutek (Pokladnice) a pracovní stůl s nástěnkou projektů (Dílna); dole
recepce, kuchyně a bar. Členění je stylizované, bez tvrzení o skutečné dispozici.

Mění se lokální SVG, polohy HTML popisků, jejich pořadí pro klávesnici a alternativní
text. Pět oblastí i projektové centrum, detail, seznam oblastí a dekorace převzatých
výsledků používají stejné události i data. Žádné nové dotazy, pravidla ani migrace.

Browserem ověřeny šířky 320/390/1440 px, popisky bez překryvu a vodorovného
scrollu, otevření všech šesti oblastí, mobilní návrat a zachování hlavní akce na
první obrazovce 390 × 844. Výtvarná změna nepřidává business logiku ani nové testy;
lokální ExUnit se v této dodávce neopakuje. Předchozí cílený běh 47 testů je uveden
výše, nové CI ověří uživatel.

# Cozy Adventure

Volitelná hobby hra pro Michala a Lucku. Obsahuje osobní ruční questy, osobní
i společná XP, vlastní úkoly a opakované šablony, kampaně, dva automatické
pobytové achievementy a audit přepočtů.
Provozní data hra pouze čte; herní akce zapisují výhradně do vlastních tabulek.

## Zapnutí a používání

1. Nasaď migrace `20261111120000_create_adventure_foundation.exs` a
   `20261111130000_add_adventure_campaigns.exs` a
   `20261112120000_add_adventure_tasks.exs` a
   `20261112130000_add_adventure_task_templates.exs` standardním postupem aplikace.
   Přidávají celkem osm tabulek s prefixem `adventure_`; druhá rozšiřuje
   pouze herní XP ledger o společného příjemce a vazbu na achievement.
   Třetí přidává pole vlastních úkolů a povoluje společnou questovou odměnu;
   nepřepisuje UUID, snapshoty ani odměny dosavadních questů. Je záměrně
   nevratná přes `ecto.rollback`, aby nemazala novou historii. Návrat staré
   aplikace po založení nových úkolů vyžaduje samostatné posouzení kompatibility.
   Čtvrtá přidává šablony, verze a vazbu výskytů; původní definice zakládá
   pozastavené, bez přepsání starých instancí. Také uchovává historii nevratným `down`.
2. Nastav `ADVENTURE_ENABLED=true` a restartuj aplikaci. Výchozí hodnota je
   `false`. Vypnutí skryje odkaz v administraci a zablokuje herní stránky i akce;
   herní data a historie zůstanou uložené. Hodinový Oban worker při vypnutí
   neprovádí herní ani provozní dotazy. Fronta `adventure` má souběh 1.
3. Po přihlášení stávajícím admin PINem otevři **Další agenda → Cozy Adventure**
   (`/admin/adventure`) a klikni na **Začít dobrodružství**. Opakování setupu
   nezduplikuje profily a nezmění již uložené profily.
4. Vyber Michala nebo Lucku. Jde o vlastní prohlášení, nikoli osobní přihlášení.
   Prohlížeč si volbu pamatuje v `localStorage` pod klíčem `cozy_adventure_hero`.
   Cookie stejného jména, omezená na `/admin/adventure`, slouží jako roční
   záloha při nedostupném místním úložišti a k převzetí dřívější volby. Oba
   zápisy jsou nezávislé a ověřují se zpětným čtením; selhání jednoho neblokuje
   druhý. Funguje také přes HTTP v lokální síti, bez změny admin přihlášení.
   Po připojení hry se profil obnoví při návratu, přechodu mezi záložkami,
   obnovení stránky i opětovném připojení. Volba se ukládá už při změně selectu,
   server dál ověřuje aktivní profil a neplatnou volbu vymaže. Opožděné potvrzení
   dřívějšího obnovení nepřepíše novější ruční volbu. Vymazání výběru
   uloží také prázdnou místní hodnotu, takže ho neobnoví stará neodstranitelná
   cookie. Blokování obou úložišť zobrazí upozornění; výběr pak platí jen pro
   aktuální stránku. Trvalost nelze zaručit v anonymním režimu či po smazání
   dat webu. Úložiště patří konkrétnímu prohlížeči a originu: IP, jiné jméno,
   port nebo protokol mohou znamenat jinou volbu. Neplatný nebo neaktivní
   profil se neobnoví. Přepnutí profilu zruší rozpracované potvrzení questu.
5. Ve **Výpravách → Spravovat zadání** připrav zadání. V **Chatě → Najít další výpravu** přijmi
   nejvýše tři osobní questy. Tlačítkem **Hotovo** otevři potvrzení
   splnění. Poznámka je nepovinná (nejvýše 1000 znaků, bez minimální délky);
   případně ji rozbal přes **Přidat poznámku**. Aktér, čas a odměna se auditují
   i bez poznámky. Neuváděj osobní údaje hostů.
6. Historii XP najdeš pod **Nastavení a audit**. Dashboard zobrazuje až 100
   questů (aktivní vždy před dokončenými) a posledních 20 XP transakcí.

## Herní styl a množství informací

Adventure je především HRA: má bavit, dávat základní přehled o dění na chatě
a pomáhat plánovat práci. Není to další obrazovka hlavní aplikace.
Při dalších úpravách zachovávat příjemný herní zážitek: krátké názvy, pár
podstatných čísel, jasný další krok a co nejméně vysvětlujícího textu.
Nadbytečný text škrtat, ne ho automaticky schovávat do dalších rozbalování.
Ani rozbalovací prvky nemají zaplnit hru. Metodika a technická omezení patří
především do dokumentace či Průvodce, podrobná provozní evidence do hlavní aplikace.
Informaci o neznámém či starém stavu zachovat stručně, bez opakovaných poučení.
Datum a čas zobrazovat lidsky a krátce (např. „Právě načteno“, „Před 5 min“), bez surových timestampů,
sekund, mikrosekund a technických údajů v běžném herním pohledu.

Karty Recepce a Pokojů nyní ukazují dnešní počty bez vysvětlování kalendářové
obsazenosti. Kuchyně neobsahuje dovětek o plánovaných a uvařených porcích.
Pokladnice má částky a datum přepočtu hned viditelné; metodika a vysvětlivky
jsou společně pod jediným zavřeným polem **Jak číst čísla**. Období sezóny
a datum přepočtu používají český formát **DD. MM. YYYY**.

## Herní obrazovka a nápověda

Adventure používá vlastní herní rám bez administračního sidebaru. **Do aplikace**
vede do administrace; PIN dál chrání všechny stránky a události. Profil se
vybírá po rozbalení avatara a zůstává zapamatovaný původním mechanismem.
Osobní XP a společný postup chaty jsou oddělené.

| Pohled | Úloha |
| --- | --- |
| **Chata** | Ilustrovaný svět, výběr oblasti, kontextová práce, tři osobní výpravy a souhrn společných. |
| **Výpravy** | Rozpracované osobní a společné questy; Nabídka otevře výběr další práce. Spravovat zadání vede do knihy. |
| **Rozvoj** | Existující projekty a jejich kroky přímo v herním rámci. |
| **Kronika** | Zlepšení chaty, splněné výpravy a oddělené sezónní výsledky. |
| **Nastavení** | Sezóny, pravidla a audit; sekundární odkaz v horním panelu. |

Na mobilu je hlavní navigace dole. Vstup do hry ukáže scénu a pokračování,
nikoli všechny seznamy pod sebou. Na počítači je vedle scény jeden kontextový
panel. Výběr oblasti nebo Služby dne na telefonu otevře samostatný detail
s návratem, Escape, řízeným fokusem a inertním zbytkem hry. Alternativní seznam
oblastí je dostupný přes **Seznam oblastí**. Žádná funkce nevyžaduje hover.

Pohled určuje `view=world|expeditions|development|chronicle` na
`/admin/adventure`; chybějící či neplatný parametr znamená `world`. Přepínání
používá patch stejného LiveView a zachovává provozní snapshot. První vstup do
Rozvoje výslovně načte dosavadní projektový seznam (do 2 SELECTů, při vybraném
projektu 1 pro historii), další přepínání použije cache v socketu. Splněné
výpravy načtou při prvním otevření historii jedním SELECTem, nejvýše 100 položek;
přepínání cache nepřenačítá, změna hrdiny a splnění ji zneplatní. Původní adresy
knihy, projektů a přímých questových odkazů zůstávají funkční.

**Najít další výpravu** otevře nástěnku s čekajícími vlastními úkoly a splatnými
opakováními. Používá původní výslovnou obnovu šablon a jeden dávkový seznam
nejvýše 100 otevřených položek, s hledáním a filtry Pro mě / Společné / Všechny.
Přijetí osobního questu obsadí slot, společného přidá společnou práci. Po přijetí
se nabídka zavře. Vytváření a editace jsou v samostatné knize zadání; hledání je
viditelné, ostatní filtry jsou pod **Filtry**. Správa neopakuje herní mapu.

Mapa obsahuje Recepce, Pokoje, Kuchyně, Bar, Pokladnice a Dílnu. Dílna je
vstup do společných projektů, není šestou vylepšovanou místností. Obecné projekty
patří Celé chatě. Oblasti používají existující projekci a při výběru nedotazují
provoz ani neudělují XP. Lokální SVG ilustrace ukazuje **jednu chatu s odkrytým interiérem**: pokoje
a účetní/projektové koutky v patře, recepci, kuchyni a bar v přízemí. Jde
o stylizované herní členění, nikoli skutečný stavební půdorys. Popisky jsou HTML
tlačítka u odpovídajících místností; tabulátor prochází horní a pak dolní řadu
zleva doprava. Stejné kotvy platí na mobilu i počítači. První převzaté zlepšení oblasti přidá praporek, dvě a více také trofej.
Přesný počet, skutečné výsledky a přispěvatelé zůstávají v detailu; archivovaný
převzatý projekt se dál počítá. Dekorace není provozní stav ani finanční bonus.

Po novém splnění se zobrazí konkrétní název, skutečná XP a jejich příjemce.
Nová právě načtená osobní nebo společná úroveň dostane oznámení. Nové převzetí
projektu zobrazí výsledek a doplní již načtený svět v paměti, bez dalších dotazů
nebo XP. Návratové virtuální příznaky `newly_completed` a `newly_accepted`
vznikají uvnitř existujících zamčených transakcí jen při nové změně. Neukládají
se do databáze a replay i reload vracejí `false`; souběh tak neoslaví dvakrát.
Oznámení lze zavřít, krátká animace respektuje omezení pohybu; zvuk není přidán.

Načítání, stáří, neúplnost a chyby zdrojů zůstávají viditelné u údajů. Sezónní
přepočty a provozní obnova jsou dál odlišné akce. Zobrazení sezón používá již
existující výpočet pražského dne v paměti, nikoli SQL při renderu. Přepínání
načtených pohledů, oblastí a kontextových panelů má 0 SELECTů; žádný nový polling,
N+1, provozní zdroj, migrace nebo konfigurace nebyly přidány.

Samostatný schválený plán a akceptace jsou v
[herním UI/UX plánu](../plans/2026-11-12-adventure-herni-ui-ux.md). Historické
implementační poznámky níže popisují předchozí iterace; aktuální navigace je výše.

### Zjednodušené rozhraní

Tábor řadí obsah podle práce: osobní a společné výpravy, Služba dne, mapa.
Úvodní ilustrace je nižší, opakovaná vysvětlení a nulové ukazatele rozvoje
na mapě nejsou v hlavním pohledu. Rozvoj oblasti, Kronika chaty a finanční
Kronika sezóny jsou sbalené; finanční odkaz z Baru/Pokladnice příslušnou
kroniku otevře. Čas ruční obnovy, starší či neúplná data a finanční omezení
zůstávají u souvisejících údajů. Pravidla jsou v Průvodci.
Ruční rozbalení Kroniky sezóny přetrvá i při hledání a změně vybrané sezóny.

Kniha má stručné přepínače **Questy / Opakování / Projekty / Historie**.
Aktivní volba má kontrastní zelenou výplň a výslovné `aria-pressed="true"`;
ostatní mají `false`. Totéž platí pro nabídku výprav. Nový quest zvýrazňuje
název, přiřazení a velikost; další nastavení a popisy jsou rozbalitelné.
Chyba formuláře otevře i volitelné položky, aby validace nezůstala skrytá.

Dílna otevírá jedinou společnou knihu projektů. Uložený klíč `workshop`
se v projektech a kronice zobrazuje jako **Celá chata**, bez migrace nebo
přepisování historických snapshotů. Dílna nemá vlastní počty zlepšení ani
rám rozvinuté oblasti. Odkaz z konkrétní oblasti předá `project_area` a
předvyplní ji při založení projektu; nemění dosavadní projekty.

Kniha odděluje rozpracované projekty od sbalené skupiny **Převzaté a archiv**.
Po výběru se seznam sbalí a zůstane detail s návratem na seznam; první otevření
detailu přesune fokus na jeho nadpis. Každý otevřený krok má vlastní odkaz
do tábora s `quest_id`. Po výběru/obnovení hrdiny otevře přesně daný quest,
nezahájí ho a nepřidělí XP. Používá dosavadní detail a akce přijetí/splnění.
Tento výslovný přechod přidává nejvýše jeden Adventure SELECT na quest;
neplatné UUID žádný. Sbalení seznamů, návrat na seznam, render a změna oblasti
nepřidávají dotazy; seznamy a kroky zůstávají dávkové. Existující iterativní
generování při otevření nabídky výprav nebylo v této UX úpravě měněno.

Přidáno pět LiveView regresních scénářů pro aktivní přepínače, pořadí obsahu,
sbalené podrobnosti a validační chyby, roli Dílny a předvyplnění oblasti,
oddělení historie, návrat bez dotazů a přímý přechod na quest bez zahájení/XP.
Lokální testy nebyly spuštěny; výsledky CI ověří uživatel. Prošly formátování
celého projektu, kompilace s `--warnings-as-errors` a `MIX_ENV=test mix assets.build`
na Elixiru 1.20.5 / OTP 29, nikoli přesně připnutém Elixiru 1.20.4-otp-29 /
Erlangu 29.1. Browserové ověření desktopu, mobilu a fokusu nebylo provedeno.

### Živý tábor (4A)

Recepce a Pokoje ukazují dnešní příjezdy a odjezdy **skupin** a počet osob podle
kalendáře. Příjezd obsazenost zahrnuje, odjezd vylučuje. Nejde o fyzickou
přítomnost, ověření čistoty ani připravenost pokoje. Kuchyně zobrazuje známé
porce snídaní/obědů/večeří; při chybějících podkladech jsou to výslovně pouze
minimální známé počty, ne celková potřeba. Porce nejsou uvařené jídlo.
Zdrojové definice zůstávají stejné jako v Přehledu: kalendář pracuje s aktivními
a budoucími rezervacemi, kuchyň zahrnuje i dokončené nesmazané, nestornované pobyty.

**Služba dne** ukazuje nejvýše čtyři konkrétní podněty z Přehledu s důvodem,
datem příjezdu skupiny a odkazem na pobyt. Zahrnuje probíhající pobyty a výhled
do stejného dne následujícího měsíce (zkrácený na konec měsíce). Datum příjezdu
není datum vzniku závady ani termín nového questu. Další podněty řeší plán jídel.
Prázdný seznam neznamená, že je chata připravena.

Mapa, služba i detaily sdílejí jedinou projekci `Dashboard.overview(today)`.
Načte se jednou po připojení Tábora a pak pouze tlačítkem **Obnovit provoz**.
Počáteční HTTP render, Questy, Nastavení, výběr oblasti/hrdiny a běžný render
nový zdrojový přehled nenačítají. Žádný polling ani dotazy po oblastech.
Vypnutý modul blokuje loader před SQL. Projekce žije jen v socketu, neukládá
se do databáze a neobsahuje hostovská jména, kontakty ani načtené booking/guest
struktury; podněty mají pouze ID pobytu, typ, důvod a datum.

Schválený rozpočet je nejvýše **15 zdrojových SELECTů** na načtení:
timeline rezervace/hosté/pokoje 4, kuchyň 8, obsazenost 1, porce 2, kapacita 0.
Prázdné preloady mohou počet snížit. Jde o opakované, ale dávkové a omezené čtení
bez N+1; počet nesmí růst s počtem skupin, receptů nebo oblastí. Zůstává běžná
konzistence jednotlivých SELECTů, nikoli společný REPEATABLE READ snapshot;
souběžná provozní editace může mezi zdroji krátkodobě vytvořit rozdíl. Ruční
obnova znovu načte celý přehled, ne finanční kroniku.

Pražský den se počítá v paměti podle současných pravidel EU (poslední neděle
března/října v 01:00 UTC), aby dodatečný SQL dotaz na časové pásmo nespotřeboval
rozpočet. Při změně zákonných pravidel je nutné výpočet aktualizovat. Čas načtení
je zobrazen v UTC. Chyba ponechá poslední projekci označenou jako nečerstvou;
bez předchozího výsledku jsou hodnoty neznámé, ne nulové. Stáří alespoň 15 minut
nebo změna pražského dne označí údaje jako starší při dalším renderu. Bez pollingu
se text sám po čase nepřekresluje, proto je vždy viditelný čas a ruční režim obnovy.

Pokladnice navíc ukazuje inkaso vybrané sezóny: ubytování po vratkách a bar
bez servisních účtů, odděleně a s datem přepočtu. Používá stejný výběr sezóny
jako kronika (jinak aktivní nebo první dostupnou), již načtené snapshoty a
kvalitu podkladů každé metriky. Bez sezóny nebo přepočtu ukazuje vysvětlení,
ne nulu; chybějící metrika je nedostupná. Nejde o zisk ani dostupný zůstatek.
Odkazy z Pokladnice a Baru otevřou přímo Kronika → Sezóny a zachovají výběr
sezóny i načtený provoz bez dalších dotazů.

Bar a Pokladnice odkazují na existující **Kroniku sezóny**, její datum přepočtu
a původní sklad/fakturaci. Neprovádějí nové skladové ani finanční čtení. Částky
jsou sezónní uložené snapshoty, ne živý stav či dostupný investiční rozpočet;
**Obnovit provoz je nepřepočítává**. Dílna nabízí vlastní knihu projektů (4B).
Prohlížení a obnova neudělují XP,
nezakládají questy ani nemění provozní data. Tři osobní sloty, společná práce,
kronika, zapamatování hrdiny, admin PIN i feature flag zůstávají zachované.

Ověření 4A: přidány regresní ExUnit/LiveView scénáře pro projekci, neúplnost,
pražské dny/DST, dotazový strop na malé i velké sadě, zákaz obnovení při UI
událostech, výslovnou obnovu, flag, stavy načítání/chyby a odkazy. Lokální
testy nebyly spuštěny; výsledky CI ověří uživatel. Prošly formatter změněných
Elixir souborů, kompilace s `--warnings-as-errors` a `MIX_ENV=test mix assets.build`.
Použit Elixir 1.20.5 / Erlang 29.1.2 (ERTS 17.1.1), nikoli přesně připnutý
Elixir 1.20.4-otp-29 / Erlang 29.1; shoda formatteru s CI není zaručena.
První kompilace vypsala varování existujících závislostí; aplikace prošla.
Ruční browserové ověření desktopu, 390/320 px a asistivních technologií nebylo
provedeno. Žádná nová migrace, konfigurace ani projektový systém.

Pravidla, identita profilu, definice KPI a omezení jsou za tlačítkem
**Průvodce** v překryvné nápovědě. Lze ji zavřít křížkem, Escape, kliknutím
mimo panel nebo tlačítkem na konci. Dialog drží klávesnicový fokus uvnitř
a po zavření jej vrací na původní ovládací prvek. Stručný stav úplnosti
dat a případné upozornění na dílčí výsledky zůstávají u metrik viditelné.

Ilustrace vznikla pro Cozy Adventure; horské a herní SVG ikony jsou z Lucide
(ISC). Všechny soubory se načítají lokálně z `priv/static/images/adventure/`,
licence a zdroje jsou v jeho `CREDITS.md` a `LUCIDE-LICENSE`. Stylování je
izolované v `assets/css/adventure/`, dialogový hook v `assets/js/adventure/`.

## Otevřená práce Služby dne (5B)

V kontextovém panelu Služby dne jsou **Podněty / Otevřená práce**. Druhá
záložka ukazuje čekající a rozpracované questy obou hrdinů i společné chaty,
i když původní podnět zmizel z projekce nebo není mezi čtyřmi kartami.
Archivovaná a dokončená práce patří do historie, nikoli do tohoto seznamu.
Seznam má 20 položek na stránku, řazení od nejstarších (`inserted_at`, `id`),
a jednu položku navíc pro zjištění další stránky. Nezjišťuje celkový počet.

Stav **Práce** vychází z questu. Stav **Podklad** se zvlášť porovnává s celou
poslední provozní projekcí, bez nového ověřování provozu. Přítomný podnět je
potvrzený posledním načtením; změna důvodu nebo příjezdu se označí jako změna.
Nepřítomný podnět je neověřitelný, nikoli vyřešený: mohl vypadnout z výhledu,
změnit termín nebo zaniknout. Stará projekce, načítání a chyba obnovy nikdy
nepotvrzují aktuální podklad. Datum načtení a rozsah zůstávají v panelu/detailu;
podrobné vysvětlení seznamu se rozbaluje na vyžádání.

Z načtené stránky lze otevřít quest i historii původního podnětu, i když pobyt
již v aktuální projekci není. Přijetí, skutečný splnitel, přispěvatelé, poznámka,
ruční potvrzení, tři osobní sloty a idempotence zůstávají beze změny. Mobilní
kontextový panel během dialogu uvolní fokus a po zavření jej vrátí na původní
ovládací prvek, pokud stále existuje. Žádný nový stavový automat nebo zápis do provozu.

### Schválené dávkové čtení 5B

- Mount bez otevření práce: žádný přidaný dotaz. První otevření záložky,
  změna stránky a **Obnovit práci**: po jednom Adventure SELECTu, nejvýše 21 řádků.
- Přepnutí načtených záložek/pohledů, změna oblasti, render i porovnání podkladu:
  0 SELECTů. Změna hrdiny ponechá společný seznam v paměti.
- **Obnovit provoz**: původních nejvýše 15 provozních SELECTů + původní dávka
  vazeb (nejvýše 1) + 1 Adventure SELECT pouze pokud již byla práce otevřena
  nebo její načtení selhalo. Stejně se seznam obnoví při chybě zdrojového loaderu,
  pokud je Adventure DB dostupná; zdroj zůstane neověřitelný.
- Po úspěšném vytvoření, zahájení, dokončení nebo archivaci questu: nejvýše
  1 další SELECT pouze pro již otevřený seznam; stávající loadery se nemění.
  Potvrzení návrhu s přiřazením a obnovou má tedy nejvýše 8 SELECTů (bez přiřazení 7),
  pokud již byl seznam otevřen; jinak platí původních 7/6.
- Obnova a úspěšná mutace vrací seznam na první stránku, aby po odebrání položky
  nezůstal hráč na prázdné poslední stránce. Běžné přepnutí záložek stránku zachová.
- Detail a historie nadále po jednom existujícím SELECTu na výslovné otevření.
  Neznámé klientské ID/zdroj se odmítnou bez čtení. Při chybě seznamu zůstane
  poslední obsah s upozorněním; explicitní obnova umožní opakování.

Bez N+1 po kartách/pobytech, bez pollingu, migrace, konfigurace nebo nových
provozních zdrojů. Živý Bar 5C je samostatná budoucí práce.

## Služba dne na quest (5A)

Ze stávajícího podnětu Služby dne lze **Připravit quest**. Ilustrovaná karta
nabízí dvě volby: **Pro všechny** vytvoří volný osobní quest k převzetí,
**Pro mě** jej přiřadí aktuálnímu hrdinovi a rovnou zahájí. Nejde o společný
quest s odměnou chatě. Název a velikost lze změnit; méně častá nastavení
zůstávají v původních volitelných podrobnostech. Výchozí odměna je 50 XP,
kategorie Kuchyně, bez termínu. Vytvoření ani zahájení neuděluje XP.

Při volbě **Pro mě** proběhne vytvoření i zahájení v jediné transakci. Plné tři
sloty vrátí celý zápis zpět a nechají návrh otevřený. Stejný request nezaloží
kopii a existující cizí práci automaticky nepřevezme. Při úspěchu se dialogy
zavřou a Chata ukáže novou aktivní výpravu v pokračování. Stejný návrat platí
při ručním převzetí existujícího questu. U volného questu se nabídne jeho karta.
Obnova provozní evidence ani její automatické změny se nespouštějí.

Pro nové zahájení se používá původní profilový zámek `FOR NO KEY UPDATE`,
zdrojový zámek a stejná kontrola slotů jako při běžném převzetí. Oproti volné
tvorbě přibývá ověření přiřazení, zamčení questu a jediná agregace aktivních
výprav; nikoli dotazy po jednotlivých questech. Návrat do Chaty obnoví běžnou
herní projekci a vazby podnětů, bez nového provozního čtení. Historie používá
původní stránkovaný dotaz, nově má podobu Kroniky výprav: odznak stavu, název,
XP a krátké datum. Grafika využívá existující ilustraci chaty a herní ikony.

Kartička questu ukazuje název, stav, XP a přiřazení, případně skutečný termín.
Odkaz na pobyt má krátké datum příjezdu; u data z jiného roku zůstává i rok.
Stav podkladu je jediný krátký řádek, bez timestampů, opakovaného důvodu a
rozbalování původu. Dobový kontext v datech zůstává zachovaný. Upozornění na starší
nebo chybující zdroj zůstává stručné. Příjezd není termín práce. Obnova zdroje questy nikdy nesplní ani nezruší. Zmizelý
podnět není důkaz vyřešení a existující quest zůstává v běžné evidenci práce.

Identita je namespace `operation_v1`, UUID pobytu a typ `details` nebo `menu`.
Chybějící a neaktuální jídelníček sdílejí typ `menu`. Změna důvodu, termínu
příjezdu, hrdiny nebo sezóny proto nevytvoří jinou otevřenou práci. Existující
otevřený quest se nabídne místo nového zadání. Po uzavření se další práce
připravuje jen výslovně, s upozorněním na předchozí řešení a potvrzením nového.
Historie podnětu se otevírá na vyžádání po 20 záznamech.

Migrace `20261112160000_add_adventure_duty_quests.exs` rozšiřuje pouze
`adventure_quests`. Zdrojová pole a dobový kontext jsou součástí stejného
atomického INSERTu jako quest. Uchovají typ, referenci, verzi, důvod, příjezd,
rozsah a čas načtení; neukládají booking/guest struktury ani osobní údaje hostů.
Zdroj nemá FK do provozních tabulek. Audit vzniku tvoří neměnná zdrojová metadata,
aktér založení a čas; SQL trigger brání dodatečnému přepsání zdrojových polí.
Pořadí jednotlivých řešení určuje `source_attempt`, nikoli náhodné UUID nebo
čas zaokrouhlený na sekundy. Předchozí řešení je vlastní Adventure reference.
`down` je záměrně nevratné kvůli zachování historie.

Částečný unikátní index chrání jednu nearchivovanou práci ve stavech čeká nebo
rozpracováno. Otevřenost se nepřepisuje do druhé tabulky: dokončení/archivace
přímo mění quest a tím i účast v indexu. Založení zamyká nejprve aktivní profil,
režimem `FOR NO KEY UPDATE`, pak transakční advisory zámek zdrojové identity.
Profilový zámek tak serializuje akce hrdiny, ale neblokuje FK kontrolu přiřazení
druhému souběžnému zadavateli. Ostatní questové mutace tento
zdrojový zámek neberou. Dvojklik a souběh vracejí otevřenou práci. Idempotentní
klíč potvrzení vrátí původní quest i po uzavření. Nové řešení vyžaduje potvrzení
posledního uzavřeného zadání; zastaralé potvrzení se odmítne. Platí dosavadní
pravidla skutečného splnitele a jediného XP udělení za quest.

### Schválené čtení 5A

| Akce | Provozní SELECTy | Adventure SELECTy přidané 5A |
| --- | --- | --- |
| Připojení Tábora / Obnovit provoz | Nejvýše 15, původní loader | Nejvýše 1 dávka vazeb |
| Render, výběr oblasti, otevření/změna/zavření návrhu | 0 | 0 |
| Potvrzení návrhu včetně validací a zámku | 0 | Nejvýše 4, s přiřazením 5 |
| Cílená obnova po potvrzení | 0 | Nejvýše 2: nabídka questů a vazby |
| Historie podnětu | 0 | 1 na stránku, 20 + jeden řádek pro další stránku |
| Otevření konkrétního questu | 0 | Nejvýše 1 |

Dávka pracuje se všemi klíči celé projekce, ne jen se čtyřmi viditelnými kartami,
a vrací otevřené nebo poslední zadání včetně počtu historických řešení. Prázdná
projekce nepotřebuje SQL. Žádné dotazy po pobytu, kartě nebo historii jednotlivé
karty při renderu. Čtyři čtení potvrzení jsou aktivní aktér, advisory zámek,
idempotentní požadavek a otevřená/poslední práce. Volitelné přiřazení přidává
ověření aktivního profilu. Celé potvrzení s obnovou má strop 6, resp. 7 SELECTů;
nevolá obecný loader celého Tábora. Transakční příkazy a zápisy nejsou SELECTy,
zámkový SELECT se do rozpočtu počítá. Dosavadní herní loadery jsou samostatné.

Server vybírá podnět ze své projekce a drží zdrojový klíč, potvrzení historie
i request key; nepřebírá identitu nebo URL z formuláře. Odkazy skládá interně.
Zůstávají admin PIN, aktivní self-report profil a feature flag. Bez nových
provozních zdrojů, hooků, HTTP, emailů, změn skladu či financí, konfigurace,
routeru nebo sdílených komponent. Souhrn návazné práce 5B a živý Bar 5C nejsou
součástí této dodávky.

Ověření 5A: přidáno 17 kontextových testů, dvě regrese na samostatných databázových
spojeních (včetně deterministického souběhu s přiřazením druhému zadavateli) a
šest LiveView scénářů. Opraven filtr Adventure LiveView telemetrie na skutečný
název tabulky `booking_menu_supplements`, aby neztrácel jeden zdrojový SELECT.
**Lokální testy nebyly spuštěny**, CI ověří uživatel; query stropy jsou tedy
testová očekávání, nikoli výsledky lokálního běhu. Prošly celoprojektové
`MIX_ENV=test mix format --check-formatted`, kompilace s `--warnings-as-errors`,
`MIX_ENV=test mix assets.build` a `git diff --check`. Použit Elixir 1.20.5 / OTP 29,
nikoli připnutý Elixir 1.20.4-otp-29 / Erlang 29.1; přesná shoda s CI neověřena.
Modul nové migrace prošel samostatnou kompilací bez startu aplikace, migrace
nebyla lokálně aplikována. Browserové ověření zůstává neprovedené:

- [ ] Otevřít a zavřít návrh bez zápisu, zkontrolovat fokus a Escape.
- [ ] Založit čekající quest bez termínu, vybrat jinou velikost a vlastní XP.
- [ ] Z druhého prohlížeče potvrdit tentýž podnět, ověřit jednu otevřenou práci.
- [ ] Splnit quest běžným způsobem, otevřít historii a výslovně připravit další řešení.
- [ ] Změnit podklad v původní aplikaci, obnovit provoz a ověřit nezměněný quest.
- [ ] Ověřit neúspěšnou obnovu, starší podklad, desktop/390/320 px a klávesnici.

## Projekty a etapy (4B)

Migrace `20261112150000_add_adventure_projects.exs` přidává pouze vlastní tabulky
`adventure_projects`, `adventure_project_stages` a `adventure_project_events`.
Nezakládá žádnou konkrétní investici. `down` je záměrně nevratné, aby rollback
nesmazal historii převzetí; návrat starší aplikace je třeba posoudit zvlášť.
Žádná nová konfigurace nebo změna routeru.

Z **Dílny → Otevřít knihu projektů** nebo **Questy → Projekty** lze vytvořit
vlastní plán. Úvodní formulář má pouze název a oblast (výchozí Celá chata); problém/přínos,
odpovědný hrdina, nepovinný termín, orientační rozpočet, měna (třípísmenný ISO kód),
základ ceny a textová reference jsou pod **Další podrobnosti**.
Po úspěšném vytvoření i úpravě se editor zavře a zůstane detail uloženého projektu,
nikoli nový prázdný formulář. Reference se nepovažuje za ověřený doklad ani se automaticky
neotevírá/nenačítá. Neuvádět osobní údaje hostů.

- Rozpočet je nepovinný nezáporný odhad s nejvýše dvěma desetinnými místy,
  nikoli skutečný náklad, hotovost, účetní alokace nebo rezervace peněz. Nezadaný
  odhad není nula. Nic se nesčítá s finanční kronikou a nevzniká domnělý zisk.
- Běžný postup je **Návrh → Realizace → Převzato**. Jediné výslovné tlačítko
  **Schválit a zahájit** schválí a zahájí projekt; nezahájí jeho questy.
  Historické stavy `ready` a `approved` i jejich audit zůstávají zachované,
  bez hromadného převodu; také tyto plány lze přímo zahájit.
  Schválení není objednávka, platba nebo souhlas dodavatele.
- V návrhu a historicky připraveném plánu lze editovat zadání a etapy. Po
  schválení a zahájení jsou uzamčené, také během pozastavení; lze pozastavit,
  přímo obnovit realizaci nebo zrušit. Projekt nemá
  obecný graf závislostí ani automatický stav odvozený z questů.
- Etapy se v UI nazývají **Kroky projektu**. **Nový krok** vyžaduje pouze název;
  ve společné transakci vytvoří skutečný čekající quest přes `Adventure.Tasks`
  a připojí jej k projektu. Nezavádí druhý úkolový model ani automatické zahájení.
  Za rozbalením jsou dosavadní pravidla přiřazení, působnosti odměny osobní/společná,
  termínu, velikosti/XP, kategorie, priority a popisu, ne nový provozní zdroj.
- Alternativa **Připojit existující quest** vyhledá spravovaný quest podle názvu; lze použít i
  konkrétní již existující výskyt opakování, nikoli automaticky další výskyty.
  Stejný quest se do jednoho projektu nepřipojí dvakrát. Vazba nevytváří další
  práci, nepřiděluje XP a nezabírá osobní slot. Quest se přijímá a plní v táboře.
  Očekávaný výstup se bez dalšího psaní převezme z názvu questu; lze jej upřesnit.
  Kroky jsou nejprve čitelné karty s českými stavy, nikoli trvale otevřené formuláře.
  Editace/přidání se otevírá na vyžádání a po úspěchu se zavře.
- Odpojení etapy uchová řádek, původní snapshot i audit; opětovné připojení
  obnoví tutéž vazbu a její výstup. Výstup lze samostatně upravit před schválením.
  Zobrazuje se počet dokončených etap, nikoli procento skutečně provedené stavby.
- **Převzít výsledek** se nabídne pouze v realizaci, po dokončení všech kroků.
  Teprve jeho kliknutí otevře formulář **Převzít bez dalších XP**. Projekt musí mít
  alespoň jednu etapu a všechny její questy musí být dokončené. Člověk navíc
  výslovně zaškrtne převzetí a vybere skutečné přispěvatele; výsledek/reference
  je nepovinný. Hotové questy samy převzetí nikdy neprovedou. Archivovaný
  dokončený quest zůstává platnou historií; zrušený není splněná etapa.
- Převzetí uloží aktéra, přispěvatele, čas, popis a dobové snapshoty etap a
  questových důkazů. Jde o přiznaný self-report, ne technickou, bezpečnostní
  nebo účetní kontrolu. Nepřidává XP, kapacitu, příjmy ani herní finanční bonus.
- Převzaté projekty se nepřepisují ani neotevírají znovu. Převzatý nebo zrušený
   projekt lze archivovat s historií. Nová sezóna nevytváří kopii, nevynuluje
   etapy a nepřepisuje převzetí. Trvalé milníky a Kroniku chaty doplňuje 4C níže.

`Adventure.Projects` serializuje změny zámkem projektu; validuje aktivního aktéra
a atomicky ukládá změnu a číslovaný audit. Unikátní request key chrání založení,
unikátní vazba a pořadí etapy brání duplicitám. Převzetí zamyká všechny připojené
questy jedním dávkovým čtením. Opakované převzetí vrací původní výsledek a
nevytváří další událost ani odměnu. Auditní tabulka odmítá SQL UPDATE/DELETE.
Zápisy zůstávají pouze v Adventure, bez provozních hooků, HTTP nebo nových zdrojů.
Admin PIN, feature flag, zapamatovaný profil a původní questové XP zůstávají.

Karty a detail používají vlastní izolované styly `assets/css/adventure/projects.css`
v dosavadních barvách papíru, lesa a zlata. Pravidla jsou sbalená v nápovědě,
prázdná metadata se neukazují. Termíny zůstávají nepovinné v původním schématu;
datum je česky, např. **12. 11. 2026**, včetně převzetí v mapě a Kronice chaty 4C.
Přesné časy jsou pouze v rozbaleném auditu s výslovným **UTC**. Formátování je
čistě v paměti, žádné dotazy na datum/pásmo; kalendářový vstup je nativní, lokalizovaný
prohlížečem. Bez nové migrace, konfigurace nebo změny provozních dat.

### Schválené čtení projektů

- Seznam/filtrování: nejvýše **2 SELECTy**, až 100 nejnovějších odpovídajících
  projektů včetně archivu a všechny jejich neodpojené etapy jedním joinem na
  questy. Starší projekt lze dohledat názvem. Profily se znovu nenačítají.
- Výběr detailu: **1 SELECT** pro posledních 50 auditních událostí. Starší
  události zůstávají v DB. Seznam a etapy se znovu nenačítají.
- Hledání questu: **1 SELECT** na výslovně odeslané neprázdné hledání,
  nejvýše 30 výsledků, žádný neomezený select.
- Převzetí: nejvýše **4 SELECTy** v transakci (aktér, zamčený projekt,
  všechny etapy/questy, přispěvatelé dávkou). Žádné čtení po jednotlivé etapě.
- Po mutaci nebo **Obnovit projekty** stejný loader do 2 + 1 SELECTů.
  Render a přepnutí oblasti 0 nových projektových dotazů; žádný polling ani
  provozní zdroj. Provozní snapshot a sezónní kronika se tím neobnovují.
- Inline vytvoření používá existující omezené transakční rutiny, bez dotazu po
  jednotlivé etapě: **7 SELECTů**, při validaci zadaného osobního přiřazení
  nejvýše **8**. Chyba při tvorbě questu nebo vazby vrátí celou změnu včetně auditu.
  Otevření/zavření editorů a formuláře převzetí má **0 dotazů**.

Přidány kontextové a LiveView regrese pro validace, opakování, stavové přechody,
archiv a audit, zachování questové historie/XP, lidské převzetí, dávkový rozpočet,
čistě Adventure zápisy, feature flag, PIN a průchod knihou projektů. Lokální
testy nebyly spuštěny; výsledky CI ověří uživatel. Ručně ověřit po migraci:

- [ ] Založit plán bez rozpočtu, upravit ho a připojit skutečný quest s výstupem.
- [ ] Odpojit a znovu připojit etapu, ověřit původní vazbu a audit.
- [ ] Jedním kliknutím schválit a zahájit, pozastavit a přímo obnovit realizaci.
- [ ] Vytvořit krok pouze názvem; ověřit čekající quest a výstup bez dvojího psaní.
- [ ] Splnit quest v táboře, obnovit projekty a ověřit, že ještě není převzato.
- [ ] Výslovně převzít s přispěvateli; opakování nepřidá XP ani další převzetí.
- [ ] Archivovat, vyhledat historii a ověřit desktop, 390/320 px a klávesnici.

## Rozvoj světa a Kronika chaty (4C)

Pět oblastí mapy rozlišuje plány, realizaci a počet **převzatých zlepšení**;
Dílna je vstup do společné knihy projektů, ne šestá vylepšovaná oblast.
Převzatá oblast dostává obecný praporek, od dvou výsledků i trofej; konkrétní
projekty nemají individuální ilustrace. Milník vzniká pouze z lidského převzetí projektu, ne dokončením
questů, schválením plánu nebo návštěvou stránky. Zahrnuje také projekty převzaté
před dodáním 4C a archivované výsledky. Archivace milník neodstraní.

Detail oblasti ukazuje související projekty, jejich stav a převzaté výsledky
s datem, potvrzujícím hrdinou, přispěvateli a rozbalitelnými výstupy etap.
Odkaz otevře přímo existující detail projektu i pro starý archivovaný projekt.
Základní seznam je omezen na 100 naposledy změněných projektů celého světa;
počty na mapě jsou úplné a nejsou odvozené z tohoto omezeného seznamu.

**Kronika chaty** je trvalá historie zlepšení napříč sezónami, oddělená od
finanční **Kroniky sezóny**. Načte se pouze tlačítkem **Otevřít výsledky napříč
sezónami**; zobrazuje 20 převzatých projektů na stránku, včetně archivu, od
nejnovějšího převzetí. **Starší výsledky** výslovně načtou další stránku.
Záznam představuje vlastní prohlášení, ne technické nebo účetní ověření.

Schválené čtení: rozvoj světa má přesně **2 Adventure SELECTy** (agregace všech
oblastí + omezený seznam projektů s uloženým převzetím). Samostatná stránka
kroniky má **1 SELECT**, nejvýše 21 řádků včetně jednoho pro indikaci další
stránky. Render, rozbalení detailů a přepnutí oblasti mají **0 dotazů**.
Rozvoj se načte při vstupu do Tábora, při obnovení herního stavu po akci a
tlačítkem **Obnovit rozvoj**; bez pollingu. Obnova rozvoje nemění provozní
snapshot ani finanční kroniku. Provozní rozpočet 15 SELECTů zůstává beze změny.

Žádná další XP, provozní bonusy, změny kapacity, automatická údržba, strom
rozvoje ani nové provozní zdroje. Používá existující přijetí 4B, bez nové migrace
a konfigurace. Admin PIN, feature flag a profil zůstávají zachované.

## Původní katalogové questy a zachovaná historie

| Šablona | XP | Opakování |
| --- | --- | --- |
| Připravit další pobyt | 50 | jednou za týden |
| Zkontrolovat otevřené zálohy | 50 | jednou za týden |
| Dokončit týdenní nákupní plán | 100 | jednou za týden |
| Zavést jedno provozní zlepšení | 250 | jednorázově |

Týden začíná v pondělí podle `Europe/Prague`, včetně přechodů letního času.
Převod používá časovou databázi PostgreSQL. Aktivní quest lze dokončit i po
konci jeho týdne; patří stále k původnímu období a zabírá jeden ze tří slotů.
Za opakovanou aktivaci stejné šablony v daném období ani opakované potvrzení
splnění nevznikne další odměna. Jednorázový quest lze splnit jednou za profil.

Definice jsou verzované v `Adventure.Catalog`. Každá instance ukládá snapshot
názvu, odměny, verze a frekvence, takže další změna katalogu nepřepíše historii.
Unikátnost šablony a období platí napříč verzemi katalogu.

Úroveň L začíná při `100*(L-1)*L/2` XP. Úroveň se odvozuje z ledgeru; neukládá
se samostatně. XP nejsou Kč, provozní KPI, odměna zaměstnance ani účetní údaj.
Poznámka a potvrzení představují ruční prohlášení o úkolu, nikoli kontrolu
skutečného stavu rezervace, zálohy či nákupního plánu.

## Vlastní jednorázové úkoly

Ve **Questech → Jednorázové questy** může vybraný hrdina založit úkol pouhým
názvem. Volitelné jsou přiřazení, termín, priorita, kategorie a popis.
Velikost dává výchozích 50 / 100 / 250 XP, vlastní odměnu lze zadat před
rozpracováním (1–10 000 XP). Priorita neurčuje XP.

- Úkol začíná ve stavu **Čeká**. Zásobník může mít více než tři položky.
- V táboře **Najít další výpravu → Přijmout výpravu** přiřadí osobní úkol právě vybranému hrdinovi.
  Předchozí přiřazení a aktér převzetí zůstávají v auditu. Do tří osobních
  rozpracovaných se společně počítají vlastní i katalogové questy.
- Při **Hotovo** vyber skutečného splnitele. Osobní odměnu získá tento
  hrdina, i když byl úkol přiřazen druhému. Přiřazení ani historické
  `profile_id` se nepředefinují na příjemce odměny.
- Společný úkol vyžaduje výslovně vybrané přispěvatele a udělí jednu
  odměnu chatě. Nevytváří osobní kopie XP ani nezabírá osobní slot.
- Zadání lze upravovat pouze ve stavu **Čeká**. Po rozpracování zůstává
  snapshot odměny neměnný. Dokončení, důkaz a ledger jsou v jedné transakci,
  zamčený profil hlídá osobní limit a zamčený úkol souběžná dokončení.
- **Archivovat** otevřený úkol zruší a uvolní slot. Dokončenému zachová
  stav, čas, důkaz i XP; v obou případech uloží aktéra a čas archivace.
  Obnovení a opětovné dokončení archivované práce není dostupné.
- Filtry umožňují moje / volné / společné / všechny, stav a archiv, kategorii,
  termín a hledání názvu. Seznam ukazuje nejvýše 100 výsledků; pro starší práci
  upřesni výběr. Zmeškaný termín nepřiděluje penalizaci.

Vlastní úkoly mají samostatný `Adventure.Tasks`, používají stávající quest
instance a XP ledger. Sloupec `profile_id` zůstává původním vlastníkem pouze
u katalogových questů; nové úkoly používají `assigned_profile_id`, `created_by_id`
a aktéra v důkazu. Historii splněných osobních úkolů vidí skutečný splnitel
v deníku; společná historie je ve společném úkolovníku.

Čtyři původní katalogové definice nadále fungují beze změny UUID a klíčů
odměn. Znovuotevření dokončeného úkolu je odložené spolu s pravidly obnovení
kompenzované odměny. Sezónní finanční přehled zůstává další etapou.

## Opakované šablony

V **Questech → Opakované questy** založ název, denní/týdenní opakování,
vybrané dny týdne, platnost od, kategorii, přiřazení, velikost/XP a působnost.
Změna velikosti předvyplní 50/100/250 XP; částku lze upravit. Nová šablona
začíná pozastavená. Tlačítko **Přidat 7 doporučených šablon** založí jednou
příklady z plánu (pokoje, úklid, jídelníček, nákup, vaření, společné prostory,
bar). Jejich nastavení a spuštění určuje správce. Opakovaný klik zachová úpravy.

**Spustit / obnovit** plánuje od dneška nebo pozdějšího data platnosti.
Hodinový `Adventure.RecurrenceWorker` a ruční **Obnovit opakované úkoly**
používají stejné transakční API `Adventure.Templates.generate/1`.
Zobrazení stránky samo nic negeneruje. Přepočet řídí datum v Europe/Prague,
nikoliv délka dne v sekundách; opakovaná hodina při zimním čase nevytvoří
nový výskyt. Nový výskyt je čekající úkol, do osobních slotů vstupuje až
výslovným převzetím a rozpracováním.

- Na šablonu je nejvýše jeden otevřený výskyt. Sedm zmeškaných denních termínů
  vytvoří jednu položku; existující otevřenou položku posune na aktuální termín.
  Původní termín a zaznamenané posuny jsou rozbalitelné u úkolu. Za zmeškání
  nejsou XP ani penalizace; nic se samo nedokončí.
- Po dokončení nebo zrušení se další úkol nabízí nejdříve v následujícím
  plánovaném termínu, který je po místním dni uzavření. Opožděný job, změna
  šablony ani obnovení nevyrobí druhou práci za dnes již uzavřený termín.
- Pozastavení/archivace vyžaduje výslovně **Ponechat**, nebo **Zrušit a
  archivovat** otevřený výskyt. Ponechaný lze dokončit i při pozastavené či
  archivované šabloně. Archivovanou šablonu nelze obnovit; historie zůstává.
- Editace a stavové změny ukládají novou verzi s aktérem. Budoucí výskyt
  dostane aktuální snapshot. Již otevřenému se mění jen termín při posunu,
  jeho zadání, přiřazení a odměna se neupravují. Posuny termínu řídí aktuální
  kalendář a působnost šablony. Editace výskytu samotného
  je blokovaná. Posledních 50 verzí je v historii šablon; všechny zůstávají v DB.
- Template lock a `FOR UPDATE SKIP LOCKED` serializují generování a správu,
  partial unique index vynucuje jeden otevřený výskyt a další unique index
  brání opakovanému založení téhož termínu. Dokončení dále chrání quest lock
  a původní XP ledger. Oban používá vlastní infrastrukturní tabulky pro joby;
  doménové zápisy zůstávají v `adventure_*`.

### Kompaktní správa

Výchozí seznam obsahuje aktivní a pozastavené šablony, nejvýše 30 na stránku.
Archiv otevře pouze výslovný odkaz **Otevřít archiv šablon**; má vlastní
stránkování a nenabízí editaci ani obnovení. Každý řádek má krátká tlačítka
s ikonou: **Upravit**, **Spustit / obnovit**, **Pozastavit**, **Archivovat**.
Podrobnosti a otevřené výskyty jsou sbalené; neznámá podmínka zůstává viditelná
mimo ně. Další termín i stručný stav jsou vidět bez rozbalení.

Pozastavení a nevratná archivace nejprve otevřou potvrzení se dvěma výslovnými
tlačítky: **ponechat otevřený úkol**, nebo **zrušit a archivovat otevřený úkol**.
**Zpět** nic nezmění. Žádný předvybraný osud práce ani stavový select.
Dosavadní serverové validace, verzování a životní cyklus zůstávají zachované.

Každá stránka potřebuje nejvýše **2 SELECTy**: omezený seznam šablon (30 + jeden
řádek pro indikaci další stránky) a dávku všech jejich otevřených výskytů.
Žádné dotazy po šabloně. Historie verzí se čte **+1 SELECTem až po explicitním
Načíst historii změn šablon**; samotný render ani rozbalení podrobností nečtou DB.
Generování se nemění, zobrazení seznamu samo práci nevytváří.

### Působnost

| Volba | Pravidlo |
| --- | --- |
| Vždy | Podle kalendáře i bez hostů a mimo kampaně |
| Během vybrané kampaně | Jen aktivní kampaň a aktuální den i termín uvnitř jejího období |
| Jen když jsou hosté | Pouze aktuální plánovaný den a prokazatelný `active` pobyt s kladným známým počtem osob; příjezd zahrnutý, odjezd vyloučený |

`Adventure.Sources.Guests` provádí jeden read-only agregovaný SELECT nad
`bookings` pro všechny splatné hostovské šablony. Nekontroluje pobyty po jednom,
nepřipojuje hosty/pokoje a nemění statusy rezervací. Budoucí rezervace není
přítomný host. Rezervace, která už měla začít, ale má stále `upcoming`,
neplatná data, chybějící počty nebo zastaralý aktivní pobyt znamenají
**neznámou** přítomnost, pokud jiný platný aktivní pobyt hosty nepotvrdí.
Zrušené a smazané pobyty se nezahrnují; den odjezdu není obsazený.

Při neznámém/prázdném stavu se dnešní termín nezahodí: hodinový worker nebo
ruční obnova ho během dne znovu ověří. Neověřitelná podmínka je vidět u
šablony a práci lze ručně přidat jako vlastní úkol. Minulou přítomnost hostů
z aktuálního statusu nedomýšlíme; vynechaný hostovský den se zpětně negeneruje.
Odjezd hostů, uzavření kampaně ani nesplněná podmínka otevřený úkol neuzavřou.
Přepočty ukládají jen stav podmínky, místní datum a čas, bez údajů hostů.

### Návaznost původního katalogu

Migrace a opakovatelná inicializace zakládají čtyři pozastavené šablony na
každého hrdinu se stabilním seed klíčem. Původní `profile_id`, quest UUID,
definition snapshot a award key se nemění. Při spuštění šablona převezme
existující rozpracovaný katalogový quest, místo aby založila kopii. Pokud
existuje více starých rozpracovaných týdnů, zachovají se a nevznikne nová
instance, dokud nejsou uzavřené. Již dokončený/zrušený týden se nepřidělí znovu.
Ruční katalogová aktivace sdílí zámek a kontroluje i výskyty šablony.

Původní weekly/once frekvence zůstává u převedených definic neměnná a týdenní
má jeden vybraný den. Pro jinou frekvenci založ novou šablonu. Tím se zachová
původní period key a nelze získat další odměnu výměnou identity definice.
Název, odměnu, přiřazení, působnost a další budoucí nastavení upravit lze.

## Oddělení od provozu

- Veškerá logika a schémata jsou v `lib/cozy_checkout/adventure/`, webová vrstva
  v `lib/cozy_checkout_web/live/adventure_live/`, testy ve vlastních adresářích.
- Context `CozyCheckout.Adventure` a moduly `Adventure.Campaigns`, `Adventure.Tasks`
  a `Adventure.Templates` zapisují
  pouze do tabulek `adventure_*`. Neobsahují cizí provozní FK,
  nevolá provozní mutace, neposílá emaily a nevytváří doklady či účetní operace.
- Jediné integrační body jsou admin router, podmíněný odkaz v navigaci
  a konfigurace vypínače. POS neobsahuje herní prvky.
- `Adventure.Sources.Stays` provádí jeden agregovaný SELECT nad `bookings`
  za rozsah kampaně. Nepřipojuje hosty ani pokoje, nevolá provozní contexty,
  neaktualizuje statusy a neukládá jména, emaily či jiné osobní údaje hostů.
  Zdroj se čte pouze při výslovném přepočtu nebo uzavření kampaně. Zobrazení
  dashboardu používá lokální herní snapshoty a nikdy samo neuděluje XP.
- Sdílený admin PIN chrání všechny tři trasy a LiveView události. Každá herní
  mutace navíc ověřuje vypínač a platný aktivní profil.

## Transakce a opravy

Aktivace, dokončení a opravy zamykají řádek herního profilu. Limit tří aktivních
questů proto platí i při souběžných požadavcích. Dokončení, důkaz a XP se zapisují
v jedné DB transakci (`Ecto.Multi` u původního katalogu). Unikátní `award_key` brání duplicitním odměnám.

`Adventure.reverse_award(profile_id, award_id, reason)` je opravné doménové API
pro chybně přiznané XP, zatím bez UI. Vyžaduje aktivní modul, vlastní profil
odměny a důvod o 10–1000 znacích. Přidá právě jednu zápornou transakci navázanou
na původní odměnu, nepřepisuje ji a neotevře quest k dalšímu získání XP. Není to
penalizace. Produkční obsluhu oprav lze později zpřístupnit ve chráněném UI.

## Sezónní kronika (`season_v1`)

Nové sezóny v Nastavení používají samostatný režim `season_v1`. Cíle jsou
volitelné a žádný přepočet, inkaso ani historický pobyt nepřiděluje automatické XP.
Odměny pocházejí ze skutečných questů. Původní kampaně `stays_v1` a jejich
historické odměny se nepřevádějí ani nekompenzují.

Stačí název a období v Europe/Prague (oba krajní dny včetně). Kapacita je
volitelná stálá hodnota; bez ní zůstávají ostatní metriky dostupné, procentní
obsazenost je **nedostupná**, ne nula. Nová sezóna začíná návrhem. Aktuální či
budoucí období lze po výslovném potvrzení aktivovat, současně nejvýše jedno.
Minulé období lze místo aktivace zapsat jako rovnou uzavřenou historickou
kroniku; neobsadí aktivní místo ani nespustí opakované questy. Zahrnuje celé
zvolené historické období, i před zapnutím hry.

Tábor zobrazuje šest stručných karet a rozbalovací účetní list. Přednost má
aktivní sezóna, jinak poslední uzavřená; jinou lze vyhledat a vybrat v kronice.
Questy zůstávají pouze knihou zadání. V Nastavení jsou návrhy, uzavření a audit
verzí. Otevření stránky ani přepnutí sezóny nečte provozní zdroje a nepřepočítává
výsledky; zobrazuje poslední uložený Adventure snapshot.

### Dva peněžní pohledy

| Pohled | Význam |
| --- | --- |
| Inkaso baru | Platné nezrušené záznamy `Sales.Payment` podle `payment_date`, bez servisních účtů v hlavní kartě; servis zvlášť v detailu |
| Inkaso ubytování | `Billing.Payment` podle `paid_on`: přijaté platby minus refundace v období |
| Vyúčtování pobytů sezóny | Pobyty podle společného data odjezdu rezervace v období; uložený hrubý konečný doklad plus jeho přímé podepsané opravy za všechny plátce |
| Úhrady pobytů sezóny | Všechny evidované příjmy minus refundace účtů daných pobytů k datu přepočtu, i mimo sezónu |

Inkaso se omezuje koncem sezóny a pražským datem přepočtu. Historické přepočty
čtou aktuální evidenci s jasným `as_of`, nikoli tehdejší stav databáze. Barová
platba může zahrnovat spropitné; u částečné úhrady je nelze přesně rozdělit od
prodeje. Smazaná platba není doklad o refundaci. Servisní příslušnost je aktuální
označení účtu, nikoli historická klasifikace. Platba nezmizí jen kvůli smazání
účtu nebo rezervace. Nepoužívají se další kopie pohybů z ABRY.

Listopadová záloha 30 000 CZK a lednový doplatek 70 000 CZK za lednový pobyt
s konečným vyúčtováním 100 000 CZK znamenají zimní inkaso 70 000 CZK,
vyúčtování 100 000 CZK a celkem uhrazeno 100 000 CZK. Zálohová výzva,
daňový doklad přijaté zálohy a odpočet záloh ve snapshotu konečné faktury
nejsou další platba ani další výnos. Refundace a oprava faktury jsou různé události.

Pobyt přes hranici sezóny se peněžně zařadí celý podle odjezdu, zatímco
lůžkonoci se rozdělují jednotlivými nocemi. Vydané finanční záznamy se zachovají
i při pozdějším stornu/smazání rezervace či účtu. Vyúčtování čerpá pouze z vydaných
konečných dokladů a jejich oprav, ne z mutable kalkulace nebo jejího legacy stavu.
Zbývá a přeplatek se počítají jednotlivě po plátcích: přeplatek jednoho nesnižuje
dluh jiného. Detail uvádí i skutečně evidované úhrady plátců bez konečné faktury.

Chybějící konečný doklad není vyúčtování nula. Pokud známé doklady pokrývají jen
část pobytů, součet je označený jako dílčí; bez konečných dokladů je hodnota
nedostupná. Samostatně se evidují chybějící účty, nedokončené rozdělení plátců
a osobní účty, bez odhadování jejich ceny. Inkaso zůstává známým údajem i při
neúplných dokladech. Každá metrika uchovává zdroj, verzi definice, jednotku,
období, `as_of` a vlastní stav úplnosti. Snapshoty obsahují jen agregace,
nikoli údaje hostů. Inkaso, vyúčtování a lůžkonoci se nesčítají; zisk bez úplných
nákladů se nevykazuje.

### Verze a bezpečnost

Výslovný přepočet ukládá nový neměnný snapshot, číslo verze, vazbu na předchozí
verzi, aktéra a metadata sezóny. Po uzavření je pro další přepočet povinný důvod.
Původní výsledky se nepřepisují. Období, kapacita a pravidla po aktivaci či
historickém zápisu zůstávají neměnné; jiné období znamená novou sezónu.
Audit ukazuje posledních 20 přepočtů, starší zůstávají uložené v DB.

Přepočet pořizuje všechny zdroje v jednom REPEATABLE READ snapshotu, aby
souběžná změna pobytu nevytvořila rozporné výsledky. Převzatá transakce musí
mít REPEATABLE READ nebo SERIALIZABLE; slabší explicitní transakce vrátí
`:snapshot_isolation_required`. Při konfliktu serializace se vlastní transakce
opakuje nejvýše třikrát; převzatou transakci opakuje její volající.

Pobytový adaptér a dva nové finanční adaptéry používají dávkové agregace;
počet dotazů nezávisí na počtu pobytů, plátců, dokladů ani dnů. Platby a opravy
se agregují před spojením, aby je řádky dokladů nenásobily. Žádné volání balance
pro každý účet, externí HTTP, provozní zápisy, emaily či účetní hooky. Vypnutý
Adventure modul blokuje i přepočet. Migrace mění pouze Adventure tabulky.

Srovnání sezón, produktové žebříčky, přesné stáří dluhu po opravách, finanční
náklady a zisk zůstávají mimo tuto etapu.

## Původní kampaně (`stays_v1`)

Kampaň je společná sezónní výprava chaty: vymezuje sledované období a ukazuje
postup proti zvoleným cílům. Cíle pobytů, budoucích lůžkonocí a obsazenosti
jsou zatím ukazatele; samy nepřidělují další XP. Odměňují jen dva milníky
za 1 a 10 způsobilých pobytů. Osobní questy fungují nezávisle na kampani.
Údaje se neobnovují automaticky na pozadí; přepočet vyvolá tlačítko nebo
uzavření kampaně. Herní kampaň nemění skutečné rezervace či účetnictví.

Existující návrhy kampaní lze v **Nastavení a auditu** upravovat.
Před aktivací vyber profil a výslovně zaškrtni potvrzení období, cílů a kapacity.
Současně může běžet nejvýše jedna kampaň. Po aktivaci jsou období, kapacita,
cíle a verze pravidel neměnné. Aktivovat nelze již skončené období.

Období je včetně obou hraničních dnů, nejvýše tři roky, pásmo Europe/Prague.
Kapacita je ručně potvrzená stálá hodnota 1–500 lůžek pro celé období.
Provozní systém neposkytuje historii kapacit ani blokací; hra ji nedomýšlí
ze současného seznamu pokojů. Při změnách kapacity zvol odpovídající období
kampaně a ověř její předpoklady. Nejde o nezávisle ověřenou skutečnou účast hostů.

Po aktivaci klikni na **Přepočítat z provozních dat**. Metriky nesměšují minulost
a budoucnost:

| Metrika | Pravidlo `stays_v1` |
| --- | --- |
| Dokončené pobyty | Stav `completed`, platný příjezd/odjezd, odjezd v kampani před dnešním pražským datem |
| Realizované lůžkonoci podle stavů | Osoby × překryv nocí kampaně před dneškem, pouze `active` a `completed` |
| Budoucí rezervované lůžkonoci | Osoby × překryv nocí kampaně od dneška, pouze `upcoming` a `active` |
| Obsazenost uzavřených nocí | Realizované lůžkonoci / (potvrzená kapacita × dosavadní noci kampaně), procenta |

Příjezdová noc se zahrnuje, odjezdová ne. Počet osob zahrnuje dospělé, děti,
kojence i neurčené hosty podle stávajícího kalendáře. Více přiřazených pokojů
nevytvoří další pobyt ani další osobonoci. `cancelled` a soft-deleted rezervace
se zcela vylučují. Cíl budoucích lůžkonocí je aktuální výhled, nikoli kumulativní
součet rezervací za sezonu; s postupem času se může snižovat.

Každý přepočet ukládá zdroj, čas `as_of`, období, pravidla, hranici realizace,
kapacitu a stav úplnosti. Chybějící nebo neplatný odjezd, neznámý počet osob,
zastaralý/neslučitelný status nebo obsazenost nad 100 % označí podklady jako
neúplné. Dílčí čísla jsou v UI označena; z neúplných podkladů se XP nepřiznávají
ani neodebírají. Prázdné období má známý počet pobytů nula, ale bez uzavřených
nocí je procentní obsazenost **nedostupná**, nikoli nula procent.

Uzavření kampaně provede poslední přepočet a uzamkne datum hranice realizace.
Další přepočet oprav je možný i potom. Čte aktuální verze rezervací se stejnou
uzamčenou hranicí; nepředstírá historický provozní snapshot k okamžiku uzavření.
Posledních 50 kampaní a posledních 20 přepočtů je dostupných v administraci;
starší auditní záznamy zůstávají v DB. Kampaně nemají vlastní job ani event hook;
hodinový worker obnovuje pouze opakované úkoly.

## Automatické achievementy a společná XP

- První způsobilý dokončený pobyt po aktivaci: **100 společných XP**.
- Deset způsobilých dokončených pobytů po aktivaci: **250 společných XP**.

Způsobilý pobyt musí splnit definici dokončeného pobytu výše a mít odjezd
**po pražském dni aktivace**. Rezervace nemají čas skutečného dokončení;
vyloučení celého dne aktivace zabraňuje odměnění pobytů dokončených dříve
téhož dne. Historické pobyty mohou být součástí KPI, ale nejsou automaticky
odměněné. Profil, který stiskl přepočet, se ukládá pouze jako aktér auditu.
XP z automatických milníků patří výhradně chatě, nikoli tomuto profilu.

Přepočet zamyká herní kampaň. Snapshot, achievement a XP jsou součástí jedné
DB transakce. Opakování či souběžné požadavky nepřidělí další odměnu.
Při opraveném stornu, smazání, datu nebo statusu se KPI přepočítají. Pokud
úplné podklady již milník nesplňují, je odvolán s novým důkazem a jednou
zápornou kompenzací. Původní důkaz i XP transakce zůstávají zachované.
Odvolaný milník je pro danou kampaň konečný; další splnění jej znovu neodmění.
Tím nelze opakovanými změnami pobytu získávat další XP.

Změny definice vyžadují novou verzi pravidel a samostatnou implementaci;
aktivní kampaň se nikdy tiše nepřevede na jinou definici. Finanční metriky
jsou pouze v nové kronice `season_v1`; osobní skill tree zůstává další etapou.
Plánování zlepšení chaty nyní pokrývají vlastní projekty 4B bez investičního účetnictví.

## Ověření

Přidané testy pokrývají hranice levelů, týden v Praze, idempotentní setup,
limit aktivních questů, atomický rollback odměny, atribuci, opakované dokončení,
kompenzace, souběh na samostatných PostgreSQL spojeních, vypnutí modulu,
admin guard a kontrolu SQL zápisů pouze do herních tabulek.
Navíc ověřují clipping lůžkonocí, více pokojů, příjezd/odjezd, kvalitu dat,
oddělení rezervací a realizace, explicitní aktivaci, společnou atribuci,
opakování přepočtu, rollback při selhání společných XP, audit a souběžné opravy.

Testy se podle pravidel repozitáře spouštějí v CI; výsledek ověřuje správce PR.
Pro ruční kontrolu po CI:

- [ ] Při vypnutém modulu chybí navigace a přímá herní URL přesměruje do adminu.
- [ ] Bez PINu všechny herní URL vedou na přihlášení.
- [ ] Založit profily, vybrat hráče a aktivovat tři questy; čtvrtý se odmítne.
- [ ] Dokončit quest bez poznámky i s krátkou poznámkou, ověřit odměnu a audit.
- [ ] Otevřít Průvodce, ověřit Tab/Shift+Tab, Escape a návrat fokusu.
- [ ] Přepnout profil a ověřit oddělenou historii a XP; obnovit stránku.
- [ ] Vypnout modul a ověřit zachovaná herní data.
- [ ] Založit návrh kampaně, upravit cíle, potvrdit období a kapacitu a aktivovat.
- [ ] Přepočítat a porovnat lůžkonoci s ručně vybranými pobyty bez změn provozu.
- [ ] Ověřit, že aktivace ani zobrazení stránky nepřidávají automatické XP.
- [ ] Ověřit oddělení společných a osobních XP a audit přepočtů.
- [ ] Na testovacích datech ověřit storno, jednorázovou kompenzaci a uzavření.
- [ ] Ověřit mobilní šířku, tabulátor a čitelné textové stavy.
- [ ] Vytvořit pět vlastních úkolů, rozpracovat tři spolu s katalogem a ověřit limit.
- [ ] Dokončit Michalův úkol jako Lucka a ověřit osobní XP i historii.
- [ ] Dokončit společný úkol s explicitními přispěvateli a ověřit jedinou odměnu chatě.
- [ ] Upravit čekající práci, archivovat rozpracovanou i dokončenou a ověřit historii.
- [ ] Ověřit hledání, moje/volné/společné, termín, kategorii a archiv.

Opakované šablony mají další regresní testy pro sedm zmeškaných termínů,
verze a neměnné snapshoty, explicitní pozastavení, DST a přelom roku,
hostovskou/kampaňovou působnost, jediný dávkový pobytový SELECT, návaznost
katalogu, souběžné generování a flag, který zablokuje i SQL dotazy workeru.
Při opravě nahlášeného `BadBooleanError` prošlo lokálně všech 72 testů
Adventure včetně LiveView a souběhů na izolovaném PostgreSQL 17. Kompletní
repozitářovou sadu a výsledky CI dále ověřuje uživatel.

- [ ] Založit a spustit denní šablonu, dvakrát obnovit, ověřit jediný čekající úkol bez XP.
- [ ] Upravit šablonu a ověřit původní snapshot otevřeného úkolu i novou verzi budoucího.
- [ ] Pozastavit s ponecháním, obnovit, poté archivovat se zrušením otevřeného úkolu.
- [ ] Nastavit dny v týdnu a působnost kampaně/hostů včetně neznámých podkladů.
- [ ] Ověřit původní quest dokončený ve stejném týdnu a zachování odměny po převodu.

Ověření herního rozdělení: lokálně prošlo 76 testů Adventure včetně LiveView,
cesty kniha → tábor → výběr → dokončení, osobních/společných slotů, mapy,
vyřazení pevných nabídek a oddělení opakovaných výskytů od editace zadání.

### Živý sklad baru (5C)

Detail Baru má samostatný read-only přehled evidence skladu. Na připojení hry
načte jedním agregovaným SELECTem nesmazané sledované produkty a součet jejich
barových pohybů. Další čtení spouští pouze **Obnovit** v detailu Baru. Přepínání oblastí,
obnova provozu ani minutová kontrola stáří sklad znovu nenačítají. Sezónní kronika
se touto akcí nepřepočítává.

Přehled počítá sledované produkty, evidované stavy ≤ 0, kladné stavy na kladném
limitu nebo pod ním, produkty bez pohybů a produkty bez kladného limitu.
Seznam upozornění zahrnuje i chybějící evidenci a nenastavené limity. Produkt bez
pohybů nemá domnělou nulovou zásobu. Nulový limit nezaručuje dostatečnou zásobu.
Objemové jednotky ml/L/cl používají stejné uložení jako existující sklad
(součet v ml, zobrazení v L); ostatní množství zůstávají v produktové jednotce,
při chybějící jednotce v pcs podle původního skladu. Limity už jsou v zobrazované
jednotce. Množství ani jednotky se mezi produkty nesčítají.

Čas načtení se zobrazuje relativně („Právě načteno“, „Před 5 min“); úplný UTC čas
zůstává jen ve strojovém atributu `datetime`. Hlavní přehled ukazuje tři stručné
počty a nedostatky/chybějící evidenci; nenastavené limity připomíná krátký počet.
Pro úplnou evidenci a nastavení slouží odkaz do původního skladu, bez dalšího
rozbalování v Baru. Zbytečné desetinné nuly se nezobrazují.
Od 15 minut se zobrazí zastarání, kontrolované každou minutu
bez SQL. Při chybě zůstane poslední úspěšný přehled s upozorněním; bez něj je stav
neznámý. Jde o evidenci, nikoli fyzickou inventuru. Panel nepíše do skladu,
neotevírá účty, nevytváří questy ani XP. Odkaz vede do původního admin skladu
se zachovanou PIN autentizací.

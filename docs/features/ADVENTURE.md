# Cozy Adventure

Volitelná hobby hra pro Michala a Lucku. Obsahuje osobní ruční questy, osobní
i společná XP, kampaně, dva automatické pobytové achievementy a audit přepočtů.
Provozní data hra pouze čte; herní akce zapisují výhradně do vlastních tabulek.

## Zapnutí a používání

1. Nasaď migrace `20261111120000_create_adventure_foundation.exs` a
   `20261111130000_add_adventure_campaigns.exs` standardním postupem aplikace.
   Přidávají celkem šest tabulek s prefixem `adventure_`; druhá rozšiřuje
   pouze herní XP ledger o společného příjemce a vazbu na achievement.
2. Nastav `ADVENTURE_ENABLED=true` a restartuj aplikaci. Výchozí hodnota je
   `false`. Vypnutí skryje odkaz v administraci a zablokuje herní stránky i akce;
   herní data a historie zůstanou uložené. Nevznikají žádné background joby.
3. Po přihlášení stávajícím admin PINem otevři **Další agenda → Cozy Adventure**
   (`/admin/adventure`) a klikni na **Založit herní profily**. Opakování setupu
   nezduplikuje profily a nezmění již uložené profily.
4. Vyber Michala nebo Lucku. Jde o vlastní prohlášení, nikoli osobní přihlášení.
   Prohlížeč si volbu pamatuje jeden rok v cookie `cozy_adventure_hero`,
   omezené na `/admin/adventure`. Po připojení hry se profil obnoví i při
   přechodu mezi záložkami a po obnovení stránky. Vymazání výběru nebo cookies
   volbu odstraní. Neplatný nebo neaktivní profil se neobnoví. Přepnutí
   profilu zruší rozpracované potvrzení questu.
5. Aktivuj nejvýše tři osobní questy. Tlačítkem **Hotovo** otevři potvrzení
   splnění. Poznámka je nepovinná (nejvýše 1000 znaků, bez minimální délky);
   případně ji rozbal přes **Přidat poznámku**. Aktér, čas a odměna se auditují
   i bez poznámky. Neuváděj osobní údaje hostů.
6. Historii XP najdeš pod **Nastavení a audit**. Dashboard zobrazuje až 100
   questů (aktivní vždy před dokončenými) a posledních 20 XP transakcí.

## Herní obrazovka a nápověda

**Tábor** ukazuje ilustrovanou chatu v horách, osobní i společnou úroveň,
aktivní questy a právě běžící kampaň. Katalog dalších questů a deník jsou
rozbalovací; ve **Questech** je katalog otevřený. Starší kampaně, návrhy,
zdrojové podklady a audit jsou v **Nastavení**, podrobnosti auditu sbalené.

Pravidla, identita profilu, definice KPI a omezení jsou za tlačítkem
**Průvodce** v překryvné nápovědě. Lze ji zavřít křížkem, Escape, kliknutím
mimo panel nebo tlačítkem na konci. Dialog drží klávesnicový fokus uvnitř
a po zavření jej vrací na původní ovládací prvek. Stručný stav úplnosti
dat a případné upozornění na dílčí výsledky zůstávají u metrik viditelné.

Ilustrace vznikla pro Cozy Adventure; horské a herní SVG ikony jsou z Lucide
(ISC). Všechny soubory se načítají lokálně z `priv/static/images/adventure/`,
licence a zdroje jsou v jeho `CREDITS.md` a `LUCIDE-LICENSE`. Stylování je
izolované v `assets/css/adventure/`, dialogový hook v `assets/js/adventure/`.

## Osobní questy

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

## Oddělení od provozu

- Veškerá logika a schémata jsou v `lib/cozy_checkout/adventure/`, webová vrstva
  v `lib/cozy_checkout_web/live/adventure_live/`, testy ve vlastních adresářích.
- Context `CozyCheckout.Adventure` a jeho modul `Adventure.Campaigns` zapisují
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
v jedné `Ecto.Multi` transakci. Unikátní `award_key` brání duplicitním odměnám.

`Adventure.reverse_award(profile_id, award_id, reason)` je opravné doménové API
pro chybně přiznané XP, zatím bez UI. Vyžaduje aktivní modul, vlastní profil
odměny a důvod o 10–1000 znacích. Přidá právě jednu zápornou transakci navázanou
na původní odměnu, nepřepisuje ji a neotevře quest k dalšímu získání XP. Není to
penalizace. Produkční obsluhu oprav lze později zpřístupnit ve chráněném UI.

## Kampaně a provozní metriky

Kampaň je společná sezónní výprava chaty: vymezuje sledované období a ukazuje
postup proti zvoleným cílům. Cíle pobytů, budoucích lůžkonocí a obsazenosti
jsou zatím ukazatele; samy nepřidělují další XP. Odměňují jen dva milníky
za 1 a 10 způsobilých pobytů. Osobní questy fungují nezávisle na kampani.
Údaje se neobnovují automaticky na pozadí; přepočet vyvolá tlačítko nebo
uzavření kampaně. Herní kampaň nemění skutečné rezervace či účetnictví.

V **Nastavení a auditu** založ návrh kampaně. Návrh lze upravovat. Výchozí
zimní období 1. 12. 2026 – 31. 3. 2027 a kapacita 45 jsou pouze návrhy.
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
starší auditní záznamy zůstávají v DB. Žádný Oban job ani event hook nevzniká.

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
aktivní kampaň se nikdy tiše nepřevede na jinou definici. Obsazenostní
achievement, skill tree, finanční metriky a rekonstrukce zůstávají další etapou.

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

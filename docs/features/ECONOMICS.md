# Ekonomika firmy

Economics je samostatný kontext pro čtení firemního účetnictví ABRA Flexi.
Nezávisí na Sales, Billing, bankovním zrcadle ani kalkulacích KitchenCosts.
Do ABRY provádí výhradně GET; nemění účetnictví, doklady ani platby.

## Konfigurace a první import

Výchozí stav je vypnuto. Nastavte explicitně:

```sh
ECONOMICS_ENABLED=true
ECONOMICS_ABRA_BASE_URL=https://vas-server.example
ECONOMICS_ABRA_COMPANY_ID=identifikator_firmy
ECONOMICS_ABRA_USERNAME=uzivatel_pro_cteni
ECONOMICS_ABRA_PASSWORD=heslo_z_bezpecneho_uloziste
```

Žádná hodnota se automaticky nepřebírá z provozní ABRY. Pro lokální ověření
lze výslovně namapovat již načtené `ABRA_*` z `rel/env.sh.eex` na stejnojmenné
`ECONOMICS_ABRA_*`; soubor s lokálními tajnými hodnotami necommitovat.
Použít API účet s právy číst účetní období, `ucet`, pohyby, předvahu a saldo.
Vyžadováno HTTPS. Před zapnutím aplikujte novou migraci; vznikají pouze
`economics_sources`, `economics_import_runs`, `economics_snapshots` a
`economics_confirmations`. Žádná existující obchodní tabulka se nemění.

`Economics.request_sync()` zařadí aktuální hospodářský rok podle skutečných
hranic v ABŘE; volitelné argumenty jsou kódy období. Počátek podpory je
1. 7. 2026; dřívější a budoucí období nelze importovat. Jednotlivý import
čte celý vybraný rok do konce aktuálního měsíce. Pozdější změny starších měsíců
se tak projeví při opakovaném importu.

Samostatná Oban fronta `economics_sync` má souběžnost 1, nejvýše 5 pokusů a
30minutový timeout. Cron ve 04:00 UTC obnovuje aktuální a dříve importovaná
období. Vypnutý modul neprovádí HTTP. Při změně cíle se staré ruční joby
zruší, nové importy a dotazy používají oddělený zdroj. Starší souběžný import
nesmí přepsat novější; zveřejnění chrání generační číslo a databázový zámek.

## Význam dat a kontrol

Čtecí kontrakt a živé kontrolní agregáty popisuje
[ECONOMICS_ABRA_CONTRACT.md](../integrations/ECONOMICS_ABRA_CONTRACT.md).
Pohyby se načítají měsíčně, `posted` a `unposted` zvlášť. Náklady jsou
MD − Dal nákladových účtů a výnosy Dal − MD výnosových účtů z firemního rozvrhu.
Nedaňové účty se nevylučují. Kategorizační mapování verze 1 je v
`Economics.AccountMapping`; neznámé kategorie jsou Nezařazeno a zůstávají
v součtech. Neznámý druh účtu, cizí měna, chybné datum, neúplná stránka,
ignorovaný filtr či nesoulad s předvahou zastaví publikaci nového snapshotu.
Prázdná měna u tuzemského pohybu se zobrazuje jako upozornění. Nezaúčtované
řádky nevstupují do výsledku; pokud nemají účet nebo úplná pole, nelze
jejich předběžné součty určit a nejsou vydávané za nulu.

Každý měsíc se kontroluje proti předvaze (`pocetMesicu=1`) po účtech a obou
stranách. Počátek předvahy se v tomto případě vztahuje k vybranému měsíci,
nikoliv automaticky k začátku roku. Kontroluje se počátek + MD − Dal = konec.
Zdroje nemají zaručený společný okamžik: časový rozsah importu je uložen,
kontroly snižují riziko souběžných změn, ale nedokazují vzdálenou atomicitu.

Banka a hotovost jsou účetní zůstatky analytik `221*` a `211*` z předvahy.
Nejde o potvrzení skutečné banky ani fyzické hotovosti; záporné hodnoty se
zachovávají. Podkladové analytiky a počátky jsou součástí reportu. Vztah
pokladen, počáteční stavy a bankovní výpis čekají na účetní ověření.

Historické pohledávky/závazky jsou předběžné: `sumCelkem − juhSumDat`, pouze
pokud `sumCelkemAkt` souhlasí s `sumCelkem`. Při rozdílu není celkový ukazatel
dostupný. Dnešní `zbyvaUhradit` se nepoužívá. Dobropisy jsou oddělené záporné
položky, nesnižují nesouvisející dluhy. Starší otevřené doklady se čtou bez
spodního omezení data. Částečné úhrady, dobropisy a import starších dluhů
vyžadují další nezávislé účetní srovnání před ostrým zapnutím.

## Obsluha v administraci

Po zapnutí je v hlavní navigaci vedle Dokladů položka **Ekonomika firmy**
(`/admin/economics`). Přehled, `/admin/economics/settings` i detail účtu
`/admin/economics/accounts/:account` chrání existující admin PIN a LiveView
session. Vypnutý modul přesměruje přímé otevření na admin přehled.

1. Na stránce Zdroj a úplnost zkontrolujte server a identifikátor firmy.
   Tlačítkem Načíst celé období zařaďte `current` nebo skutečný kód období
   z ABRY. Hesla se ve formulářích nezadávají ani nezobrazují.
2. Po dokončení jobu klikněte na Obnovit přehled. Obrazovka čte pouze místní
   snapshot a nespouští síťové dotazy. Chyba importu je viditelná i vedle
   posledních úspěšných dat.
3. Vyberte hospodářský rok a jeden či více měsíců; prázdné od/do znamená
   celý dostupný rozsah. Změna roku použije skutečné hranice jeho snapshotu.
4. Detail čísla účtu ukáže data účtování, strany MD/Dal, firmu, číslo dokladu,
   krátký popis a reference zápisů ABRA. Tabulka salda řadí položky podle
   splatnosti; dobropisy jsou oddělené od kladných pohledávek a závazků.
5. Na stránce Zdroj a úplnost lze po dohodě s účetní potvrdit jednotlivý
   ukončený měsíc a uvést podklad. Výchozí stav všech měsíců je Neověřeno.

Graf měsíčního vývoje se vykresluje serverově, bez nového JavaScriptu.
Peníze formátuje existující CurrencyHelper. Chybějící bankovní/pokladní
účty nebo nepodporované saldo se zobrazují jako Nedostupné, nikoli nula.

## Verze a úplnost

Nový snapshot vzniká bokem a publikuje se atomicky až po všech kontrolách.
Neúspěch ponechá poslední úspěšnou verzi. Identický import obnoví jen čas
kontroly, nevytvoří duplicitní report. Starší verze zůstávají zachované;
automatické mazání není zapnuté. Retenci a velikost reálných importů je nutné
stanovit před produkčním nasazením. Ukládají se finanční pole, reference
a omezené identifikační údaje dokladů (firma, čísla, krátký účetní popis).
Adresy, kontakty, volné poznámky a celé původní HTTP odpovědi se neukládají.

Technická čerstvost, shoda s předvahou a účetní úplnost jsou oddělené.
Potvrzení úplnosti vyžaduje uzavřený kalendářní měsíc a text podkladu
(minimálně 10 znaků). Jde o místní záznam po dohodě s účetní, nikoli uzamčení
ABRY. Změna finančních dat měsíce jeho potvrzení zneplatní; záznam zůstane
pro dohledání. Doplnění či změna identifikačních popisů potvrzení nemění.
Potvrzení úplnosti neověřuje banku, fyzickou hotovost ani kontrakt salda.

Deaktivace přepínačem zastaví nové importy a skryje navigaci. Data zůstanou
uložená. Návrat ke starší aplikaci nevyžaduje mazání nových tabulek.

## Úvodní přehled, úkoly a grafy

Při zapnutém Economics přibývají na úvodním `/admin` čtyři karty: výsledek
posledního potvrzeného ukončeného měsíce (s výnosy a náklady), pohledávky po
splatnosti, závazky splatné od data salda do 14 dnů včetně a účetní zůstatek
banky z posledního dostupného měsíce, jehož konec není v budoucnosti. Banka
má přesné datum a zůstává neověřená proti výpisu; potvrzení úplnosti ji
neoznačuje jako ověřenou. Chybějící potvrzený měsíc nebo bankovní podklad
znamená Nedostupné, nikoli nulu. Skutečná hotovost se na úvod nepřidává.

Sekce Vyžaduje pozornost je přesunutá nahoru. Vedle provozních úkolů ukazuje
částku a počet otevřených pohledávek a závazků po splatnosti, blížící se
závazky, selhání importu, neaktuální/nepodporované saldo, chybějící splatnosti
a změny dříve potvrzených měsíců. Každá položka vede k podkladům nebo správě
zdroje. Nepotvrzený měsíc a záporný výsledek samy nevyvolávají červený alarm.

Pro každodenní rozhodování každý úplný import nově čte také
`saldo-k-datu?datum=<dnešek>&dleUcto=true`. Normalizované položky a datum
ukládá atomicky jako `current_saldo` uvnitř existujícího payloadu snapshotu;
nevzniká nová tabulka ani migrace. Měsíční historické saldo zůstává oddělené.
Selhání kteréhokoli čtení, včetně denního salda, ponechá předchozí snapshot.
Rozšíření začne fungovat po prvním novém importu; starší snapshot bez tohoto
pole je podporovaný a zobrazí výzvu k aktualizaci.

Denní část je v Ekonomice pod nadpisem Denní splatnosti. Odkazy z úvodního
přehledu rovnou zvolí pohledávky po splatnosti, závazky do 14 dnů nebo již
prošlé závazky. Splatnost v den salda ještě není po splatnosti. Záporné
položky se nesnižují proti nesouvisejícím dluhům a chybějící splatnosti se
počítají zvlášť. Celé saldo zůstává předběžné do účetního ověření kontraktu.
Starší saldo zachovává své datum a vlastní 14denní okno a výslovně upozorní,
že od té doby mohly přijít úhrady. Obrazovka nic nestahuje z ABRY.

Souhrn hlavního přehledu načítá zdroj, všechny aktivní snapshoty, potvrzení
a poslední běh čtyřmi dotazy nezávisle na počtu účtů nebo dokladů. Výběr
potvrzeného měsíce a upozornění probíhá v paměti. Vypnutý Economics neprovádí
žádný z těchto dotazů. Přehled se obnovuje existujícím minutovým intervalem;
ABRU aktualizuje pouze ruční nebo denní Oban import.

V Ekonomice přibyly dva serverové HTML/CSS grafy podle stávajícího přístupu
v Ekonomice pobytů, bez nové knihovny a JavaScriptu:

- Měsíční výnosy/náklady ve sdružených sloupcích a výsledek kolem nulové osy
  ve stejném měřítku. Kliknutí na měsíc zvolí jeho účty. Potvrzení úplnosti
  je označené u každého měsíce; přesné částky zůstávají v přilehlé tabulce.
- Náklady podle kategorií v sestupném pořadí. Rozbalení kategorie ukáže účty
  s odkazy do účetních zápisů. Záporné opravy jsou na opačné straně nuly.

Výpočty měřítek používají Decimal, nula nemá vymyšlenou minimální výšku.
Grafy a ovládání mají textové popisy, viditelné hodnoty a podporují klávesnici;
barva není jediný nositel významu.

## Identifikace dokladů a pohybů

Denní podklady k řešení, historické saldo a detail účtu ukazují vedle částek:
firmu, lidské číslo dokladu, typ dokladu, popis z ABRY, variabilní symbol,
číslo dodavatelského dokladu a u pohybů také protiúčet. Technické ID ABRA
zůstává dostupné pro dohledání. Z bankovních a pokladních analytik lze
kliknout do stejných detailů pohybů jako z výsledkových účtů.

Údaje se přebírají přímo z `saldo-k-datu` a `pohyb-na-uctech` během běžného
stránkovaného GET importu. Nevzniká další požadavek pro každý doklad ani
přímé dotazy z obrazovky. `nazFirmy` má přednost před popiskem reference
`firma@showAs`; prázdné hodnoty zůstávají neuvedené. Popis má nejvýše 500
znaků a název firmy 200 (při zkrácení je přidaná výpustka). Jde o účetní
popis dodaný ABROU; souhrnný doklad se automaticky nerozpadá na produktové
řádky. Formátování bezpečně escapuje vložené HTML.

Starší snapshot bez identifikačních polí dál funguje a nabídne aktualizaci.
Údaje se doplní po aktualizaci z ABRY pro příslušné období. Popisy jsou
součástí nové verze snapshotu, ale jsou vyloučené z otisku finančního
potvrzení. Výpočet tohoto otisku je kompatibilní se staršími potvrzeními
bez popisů; změna firmy nebo popisu sama nevyžaduje znovu potvrdit částky.
Změny účetních částek, účtů, salda a ostatních finančních podkladů jeho
platnost nadále ruší.

## Nákladovost: fixní a variabilní náklady

Záložka **Nákladovost** (`/admin/economics/costs`) používá stejný admin PIN
jako ostatní Economics. Čte pouze místní snapshoty. Součet fixní složky,
variabilní složky, smíšených bez rozdělení a nezařazených odpovídá nákladům
MD − Dal; mimořádné jsou samostatně označená podmnožina těchto částek.
Dobropisy zachovávají znaménko. Odpisy na nákladových účtech `551*` jsou
viditelně nepeněžní. Nejde o platby ani o očekávaný smluvní měsíční základ.

Přehled obsahuje měsíční součty, kategorie, firmy a rozbalovací podklady
se všemi zahrnutými zápisy a použitými pravidly. Podklady lze filtrovat
na mimořádné, nevyřešené, konfliktní a odhadované; seznam má stránky po 50.
Firmy bez stabilního ID se neslučují podle názvu. Podíl pokrytí vychází
z absolutních hodnot podkladů, nikoli z čistého výsledku po dobropisech.
Nulový absolutní objem nemá vypočtené procento. Účetní úplnost se zobrazuje
samostatně a mapování ji nemění.

### Práce s mapováním

1. Vyberte aktuální snapshot požadovaného období a aktivní verzi mapování.
   V záložce Mapování vytvořte pravidlo, případně v detailu podkladu zvolte
   **Jen tento podklad** nebo **Pravidlo pro další doklady**.
2. Pravidlo používá přesný nákladový účet, volitelně interní ID firmy a text
   „popis obsahuje“ bez rozlišení velikosti písmen. Všechny podmínky se musí
   splnit. Uveďte důvod a celé měsíce platnosti od/do včetně. Konec může být
   prázdný. Nové snapshoty uchovávají nákladové účty z rozvrhu; starší nabízejí
   nákladové účty doložené pohyby. Účty a firmy se vybírají vyhledáváním.
3. Zvolte chování, samostatný příznak mimořádné a případný ruční odhad
   fixního podílu 0–100 % (nejvýše šest desetinných míst). Pro smíšené
   bez podílu se částka nerozděluje. S podílem je variabilní složka přesný
   zbytek; zobrazení dorovnává haléřové zaokrouhlení.
4. **Uložit položku do návrhu** zatím nemění aktivní přehled. Návrh žije
   pouze v otevřené stránce; obnovení nebo změna období jej zahodí. Přepnutí
   Přehled nákladů / Mapování jej zachovává. Lze upravovat a odebírat pravidla
   i výjimky a hromadně přidat pracovní návrhy pro dosud nemapované účty.
   Žádný návrh se nepřijímá automaticky.
5. Vyplňte důvod publikace a přepočítejte náhled. Náhled ukáže dopad na
   všechna načtená aktivní období, měsíční složky před/po, změněné podklady
   a konflikty. Publikace tak výslovně může změnit výklad minulých měsíců.
6. Tlačítko **Publikovat tuto verzi mapování** atomicky zveřejní celou sadu.
   Změna snapshotů nebo aktivní verze od náhledu publikaci odmítne; náhled
   také vyprší po hodině. Obnovte data a připravte jej znovu.

Přímo v Mapování je vedle formuláře seznam nevyřešených podkladů pro
vybrané období a měsíce (na mobilu nad formulářem). Lze hledat podle firmy,
čísla dokladu, účtu nebo popisu a listovat po 20 podkladech. Z podkladu
zvolte pravidlo nebo výjimku; vedle formuláře zůstane jeho identifikace.
Po uložení položky se seznam přepočítá podle celého rozpracovaného návrhu,
takže zmizí i další doklady pokryté stejným pravidlem. Další podklad si
uživatel vybírá ručně. Konflikty a pozastavené výjimky zůstávají k řešení;
po úpravě nebo odebrání pravidla se může podklad znovu objevit.
Pravidla a výjimky jsou pod formulářem ve sbalené sekci se dvěma tabulkami.
Pravidla ukazují účet s názvem, firmu, textovou podmínku, platnost, chování,
rozdělení a mimořádnost. Výjimky ukazují číslo dokladu a firmu, účet, měsíc,
zařazení a stav (platná, pozastavená kvůli změně či přesunu, chybějící podklad).
U smíšených je výslovně Nerozděleno nebo ruční odhad obou procentních složek.
Důvod a technické reference jsou v rozbalovacím detailu příslušného řádku.
Společné hledání prochází obě tabulky včetně důvodů. Pravidla se řadí podle
účtu a firmy, výjimky podle měsíce a dokladu. Na mobilu se řádky zobrazují
pod sebou s popisky jednotlivých sloupců. Názvy pocházejí z načtených dat;
chybějící údaje se nedohledávají po jednotlivých dokladech přes API.
Více změn lze připravit a poté publikovat v jediné verzi. Průběžný seznam používá už
načtené podklady bez dalších SQL nebo HTTP dotazů a nemění publikované součty.

Přednost: výjimka, účet + firma + text, účet + firma, účet + text, účet.
Rozdílné výsledky stejné přednosti vytvoří konflikt a částku nezařadí.
Shodné výsledky zůstanou dohledatelné se všemi odpovídajícími pravidly.
Textový filtr pracuje nad uloženým popisem; detail upozorní na zkrácení.

Výjimka se vztahuje na celý podklad **zdroj + modul + idDokl + účet + měsíc**,
nikoli na produktový řádek. Finanční otisk zahrnuje částky a složení zápisů;
změna podkladu výjimku pozastaví bez přechodu na obecné pravidlo. Zaniklé
nebo přesunuté podklady jsou dohledatelné v Mapování. Přejmenování firmy
ani změna popisu tento otisk nemění. Novou kontrolu změněného podkladu
zahajte opět z jeho detailu; pouhá editace důvodu výjimky otisk neobnoví.

### Identita, historie a nasazení

Import pohybů a salda nově žádá `use-internal-id=true` podle
[dokumentace ABRA](https://podpora.flexibee.eu/cs/articles/4713911-sestavovani-url).
Z `firma@internalId` (případně explicitní číselné reference `firma`) se
ukládá interní `partner_id` v rámci zdroje. Kódy a jména se za interní ID
nevydávají. Pokud ho server neposkytne nebo jde o starší snapshot, pravidla
na tuto firmu nelze nově vytvořit. Ověření odpovědi konkrétního firemního
serveru a několika pravidel s majitelem zůstává součástí nasazení.

Nová přidávací migrace `20261029180000_create_economics_cost_mapping`
vytvoří `economics_cost_mapping_versions`, `economics_cost_rules` a
`economics_cost_overrides`, včetně UUID, cizích klíčů, omezení, unikátních
indexů a ochrany publikovaných položek proti přepsání či smazání. Publikace
zamyká zdroj stejně jako import. Odebrání pravidla vytvoří další úplnou
verzi; předchozí řádky zůstávají v historii. Nepublikovaný návrh se do DB
neukládá. Není potřeba nová konfigurace ani přepis starých snapshotů.

V horním výběru lze kombinovat historický snapshot s publikovanou verzí
mapování (nebo volbou Bez pravidel) a zopakovat tehdejší výklad. Historický
pohled neumožňuje editaci. Historie obsahuje čas a důvod; sdílený PIN
neidentifikuje konkrétní osobu. Pravidla a výjimky se načítají po dávkách,
klasifikace neprovádí SQL ani HTTP pro jednotlivé podklady.

Pro první použití aplikujte novou migraci, obnovte import vybraného období,
zkontrolujte interní ID firem, výslovně přijměte návrhy a porovnejte náklady
s původním přehledem. Živé ověření, měření odezvy na skutečném objemu a
potvrzení smluv/podílů s majitelem nejsou nahrazeny syntetickými testy.
Pravidelné smluvní závazky a provozní jednotkové ukazatele jsou další etapa.

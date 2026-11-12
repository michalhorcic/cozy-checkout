# Cozy / Noir — nová grafická podoba Cozy Checkout

- Stav: připraveno k implementaci v navazujícím vlákně
- Vytvořeno: 2026-11-12
- Aktualizováno: 2026-11-12
- Rozsah tohoto PR: pouze plán; aplikace se nemění.

## Problém a očekávaný výsledek

Sjednotit Cozy Checkout do klidného, kontrastního vizuálního stylu inspirovaného
černobílou estetikou videoklipu Bat for Lashes — All Your Gold. Zachovat rychlou
obsluhu penzionu a jednoduchý dotykový samoobslužný bar. Uživatel schválil
barevnost návrhu a hlavičku s horami a chce tento směr implementovat.
Produktové fotografie výslovně nejsou potřeba a v implementaci se nepoužijí.

## Současný stav a podklady

Ověřeno v aktuálním GitHub main při přípravě plánu:
- `lib/cozy_checkout_web/live/dashboard_live.ex`: příjezdy, odjezdy,
  obsazenost, časová osa pobytů, stravování, provozní a ekonomická upozornění.
- `lib/cozy_checkout_web/admin_navigation.ex`: existující hlavní a skupinová
  navigace, aktivní položky a podmíněná dostupnost modulů.
- `lib/cozy_checkout_web/live/pos_live/order_selection.html.heex`:
  výběr nebo založení účtu po výběru pobytu; tento krok zůstává.
- V lokálním checkoutu dále prohlédnuty
  `assets/css/app.css` a `lib/cozy_checkout_web/components/layouts.ex`:
  Tailwind v4, daisyUI, centrální paleta, světlý motiv a sdílené layouty.
  Před implementací ověřit jejich aktuální verzi na main.

Referenční grafika:
[Cozy noir chalet management UI.png](https://chatgpt.com/library?file_id=libfile_b57d32bf31d4819180e26373f09a6175&account_id=personal).

Odkaz na grafiku může vyžadovat účet vlastníka. Text tohoto plánu je samostatně
použitelný podklad; nedostupnost obrázku neblokuje začátek. Obrázek ukazuje
administrativní přehled nahoře, POS dole a paletu vpravo. Je to výtvarná reference,
nikoli zdroj skutečných dat, cen, oprávnění nebo schválených nových funkcí.
Např. „Připsat na pokoj“, názvy navigace, uživatelský profil a stavy rezervací
v obrázku neopravňují měnit dosavadní chování.

Inspirace: https://vimeo.com/50388107 a https://www.youtube.com/watch?v=EXK0Ejzin4c.
Přebírá se atmosféra, kontrast a práce s přírodní krajinou; nepřebírat záběry,
podobu interpretky ani hudbu do aplikace.

## Rozsah

- Sdílená paleta, typografie, tlačítka, formuláře, tabulky, dialogy a navigace.
- Světlé pracovní plochy, uhlová navigace a horská černobílá hlavička.
- Administrativní dashboard, rezervace/kalendář, stravování, sklad,
  ekonomika/doklady a veřejné POS obrazovky.
- Responzivní návrh pro desktop, tablet i telefon; zachování tiskových výstupů.
- U existujícího Cozy Adventure sladit základní plochy, typografii a navigaci;
  zachovat čitelnost herních stavů a smysluplné herní prvky.

Mimo rozsah: nové obchodní funkce, změny datového modelu a finančních pravidel,
přestavba přihlašování, změny API, přepracování vydaných PDF, produktové fotografie,
video na pozadí, hudba, nový dark-mode přepínač a rozsáhlé animace.
Nezavádět technologickou migraci ani nový UI framework.

## Navržené řešení

### Barevné tokeny

| Role | Hodnota | Použití |
| --- | --- | --- |
| Charcoal | `#171918` | Hlavní text, navigace, primární tlačítka |
| Slate | `#5B605F` | Sekundární text, neutrální stavy |
| Chalk | `#F3F2EE` | Hlavní světlé pozadí |
| Bílá | `#FFFFFF` | Formuláře, dialogy a vybrané pracovní plochy |
| Amber | `#D6A366` | Jemný akcent a upozornění, ne běžný text |

Odvozené odstíny hranic, hover/focus/disabled a sémantické barvy doplnit
centrálně. Amber na světlém pozadí není vhodný pro malý text: použít tmavý text
a amber podklad nebo linku. Chyby a úspěch mají vlastní dostatečně kontrastní
sémantické odstíny; monochromatický styl nesmí skrýt význam finančních stavů.
Barvu vždy doplnit textem či ikonou.

Mapovat stávající `primary`, `secondary`, `tertiary`, `accent` a daisyUI
tokeny na nový systém po auditu jejich použití. Neprovádět slepou globální
náhradu: existující třídy používají paletu i pro významové stavy.
Nové barvy nevkládat jednotlivě jako hex hodnoty do HEEx.

### Typografie a tvarosloví

- Referenční dvojice: Playfair Display pro velký titul obrazovky,
  Inter pro navigaci, formuláře, tabulky a POS.
- Běžné podnadpisy a husté datové sekce upřednostňují čitelný sans-serif.
  Display serif použít střídmě, ne na každou část formuláře.
- České znaky, lokálně hostované WOFF2, licence uložená spolu s fonty;
  fallback serif/sans-serif a `font-display: swap`.
- Finanční hodnoty a tabulky s tabulárními číslicemi.
- Jemné oddělovací linky, malé zaoblení přibližně 6–10 px, minimum stínů.
- Případná textura jen v fotografii; bez zrnění přes textové a datové plochy.
- Krátké hover/focus přechody; bez animací při běžném zadávání dat.
  Respektovat `prefers-reduced-motion`.

### Hlavička a fotografie hor

- Jedna původní nebo řádně licencovaná fotografie Krkonoš; černobílá úprava,
  mlha, horské hřebeny, výrazný kontrast a tmavší překryv za světlým titulkem.
- Administrativní hlavička na desktopu přibližně 100–140 px vysoká,
  na telefonu kompaktnější. Nemá vytlačit obsah pod první obrazovku.
- Obsah: malé „JINDŘICHŮV DŮM“ a název aktuální sekce. Hlavní akce a datum
  mohou být pod fotografií na světlé ploše.
- POS má nízkou horskou hlavičku se značkou, aby produkty zůstaly na dosah.
- Statický optimalizovaný lokální asset, varianty pro malé obrazovky,
  explicitní rozměry/rezervovaný prostor a pevný tmavý fallback.
- Nepoužívat celý konceptový obrázek jako pozadí ani jeho UI výřezy.
  Fotografii dodat jako samostatný asset. Před produkcí vyřešit původ/licenci;
  dočasná barevná plocha dovoluje pokračovat bez blokování ostatních úprav.
- Hlavička je dekorativní; titul zůstává HTML text. Tisk fotografii vynechává.

### Administrace a navigace

- Tmavá levá navigace na desktopu, světlý hlavní obsah.
- Použít existující datové zdroje navigace, aktivní stavy, route a feature flags.
  Neskrýt moduly kvůli zkrácenému seznamu v grafice.
- Zachovat dostupnost současných podnavigací stravování a fakturace bez dvou
  konkurenčních plnohodnotných sidebarů; použít společný shell a vhodnou
  sekční navigaci odvozenou ze současných komponent.
- Mobilní navigace sbalitelná a přístupná klávesnicí, s viditelným názvem sekce,
  správným focus managementem a dostatečně velkým ovládáním.
- Nevytvářet profilové/přihlašovací funkce podle nápisu „Michal a Lucka“ v návrhu.

### Přehled provozu

- Přehledové metriky příjezdů, odjezdů a obsazenosti jako vzdušný pás.
- Stávající časová osa pobytů vlevo a stravování/upozornění v pravém sloupci
  na široké obrazovce; na telefonu logické pořadí v jednom sloupci.
- Zachovat dnešní zdroje dat, obnovování přehledu, odkazy a skutečné významy
  hodnot. Nepřebírat statické počty ani přidávat neexistující stavy z obrázku.
- Časová osa musí zachovat rozlišení pobytů i bez barvy, označení dneška
  a čitelnost při horizontálním posunu na menším zařízení.
- Nový seznam „Dnešní příjezdy“ z grafiky není povinná nová funkce;
  nepřidávat nový dotaz nebo výpočet jen kvůli kopii obrázku.

### POS bez fotografií produktů

- Upravit všechny tři současné kroky:
  `guest_selection`, `order_selection`, `order_management`.
- Zachovat výběr pobytu, účtu, produktové zkratky, kategorie, množství,
  účtování a současné platební/potvrzovací postupy.
- Produktové dlaždice obsahují především velký název, variantu/objem a cenu.
  Bez fotografie i bez prázdného prostoru po fotografii; jednoduchá ikona
  pouze pokud pomáhá orientaci.
- Ovládací cíle alespoň 44 × 44 CSS px, hlavní POS akce ideálně 48–56 px.
- Aktivní kategorie zřetelně odlišit; nepoužívat pouze hover.
- Účet a celková částka jsou stále snadno dostupné. Na desktopu může být účet
  v pravém sloupci, na telefonu přehledná souhrnná lišta bez překrytí obsahu.
- Kontrastní primární akce používá skutečný název a význam dnešní operace.
  Nezavádět nové hromadné potvrzování či připsání na pokoj podle obrázku.

### Bezpečnost, finance a výkon

Jde o prezentační změnu. Zachovat admin PIN, veřejné POS, LiveView eventy,
validace, transakce, historické snapshoty, Decimal a CurrencyHelper.
Nevytvářet migrace, nové background joby ani externí služby kvůli vzhledu.
Vydané dokumenty a uložená PDF zůstávají beze změn.

Neměnit dotazy a preloady jen pro redesign. Pokud audit odhalí N+1 nebo změna
layoutu bude vyžadovat jiná data, popsat konkrétní problém a navržené řešení
a nechat si jeho úpravu schválit dle AGENTS.md. Do té doby pokračovat
nezávislými prezentačními změnami.

## Rozhodnutí

| Datum | Rozhodnutí | Zdroj |
| --- | --- | --- |
| 2026-11-12 | Implementovat grafický směr Cozy / Noir | Výslovný požadavek uživatele po zobrazení konceptu |
| 2026-11-12 | Zachovat schválenou paletu a hlavičku s horami | „Barvy super… hlavička s horama a zbytek barev je paráda“ |
| 2026-11-12 | Vynechat fotografie produktů | „Fotky produktů nejsou potřeba“ |
| 2026-11-12 | Nyní uložit pouze plán, implementaci předat dál | „Sepiš plán a předám dál“ |

Konkrétní rozměry, fonty a technické rozdělení níže jsou návrh realizace
odvozený z konceptu, nikoli samostatně potvrzené obchodní požadavky.

## Otevřené otázky

- Finální fotografie hor: použít vhodnou vlastní fotografii uživatele, nebo
  samostatný asset s doloženou licencí. Neužívat video jako zdroj assetů.
- Nemusí se znovu schvalovat paleta ani absence produktových fotografií.
  Zbývající běžné implementační detaily řešit podle kódu a tohoto plánu.

## Postup realizace

- [ ] Načíst aktuální AGENTS.md, fetch origin/main a založit implementační větev
  z jeho aktuálního commitu; případné změny mezitím znovu porovnat.
- [ ] Inventarizovat layouty včetně root, admin shell, POS, billing/food
  navigací, core komponent, Adventure CSS, tiskových stylů a odpovídajících testů.
  Ověřit existující asset pipeline a theme bootstrap.
- [ ] Při práci s API Tailwind v4, daisyUI, Phoenix nebo LiveView použít Context7;
  pokud dokumentaci nepokrývá, ověřit v oficiální dokumentaci či zdroji.
- [ ] Zavést centrální paletu a typografii v assets/css; zachovat významové
  stavy a kompatibilitu existujících tokenů.
- [ ] Připravit samostatný licenčně použitelný horský asset a sdílenou
  hlavičku. Písmo hostovat lokálně, nezavádět závislost na externím CDN.
- [ ] Upravit sdílené layouty a navigaci pomocí současných komponent:
  Layouts.app, Layouts.pos, .input, .icon. Zachovat autentizační hranice.
- [ ] Jako první ucelenou etapu dokončit dashboard a všechny tři POS kroky
  včetně textových produktových dlaždic; ověřit desktop/tablet/telefon.
- [ ] Sladit rezervace/kalendář, stravování, sklad, finance, doklady a Adventure
  včetně dialogů, vyhledávacích selectů a validačních chyb. Select nad 30 položek
  musí nadále podporovat vyhledávání.
- [ ] Odstranit zbylé původní barevné konflikty a duplicitní CSS;
  zachovat tiskové výstupy a nezměněné chování PDF.
- [ ] Provést níže uvedené ověření, aktualizovat stav plánu a dokumentaci
  skutečně dodaného vzhledu; commit, push a PR s jasným rozsahem a limity.

## Ověření a podmínky dokončení

- Vizuální kontrola šířek přibližně 390, 768, 1024 a 1440 px.
  Bez nechtěného horizontálního scrollu, kromě záměrně posuvného kalendáře.
- Dashboard: metriky, časová osa, stravování, upozornění, odkazy a nová rezervace.
- POS: výběr pobytu/účtu, založení účtu, kategorie/zkratky, přidání/odebrání
  a změna množství, kontrola ceny a dokončení současného účtovacího toku.
  Dlouhé názvy, prázdný účet, mnoho produktů a validační/chybové stavy.
- Admin: aktivní navigace, přímé odkazy a feature flags, formuláře a dialogy,
  filtrování a přehlednost hustých finančních tabulek.
- Klávesnice, viditelný focus, čitelné disabled stavy, popisky formulářů;
  kontrast WCAG AA: běžný text 4,5:1, velký text a relevantní UI prvky 3:1.
- Bez síťového požadavku na produktové fotografie či externí fontový CDN;
  funkční fallback hlavičky i fontů. Žádný posun obsahu po načtení fotografie.
- Ověřit tisk a pohled na existující dokumenty bez změny archivovaných PDF.
- Aktualizovat existující LiveView testy jen tam, kde se mění struktura nebo
  přístupné ovládání. Zachovat testované interakce a stabilní ID.
  Nepřidávat testy pouhé hodnoty barev ani kopie CSS implementace.
- Testy standardně ponechat GitHub CI dle AGENTS.md; lokálně je spustit jen
  na výslovnou žádost nebo pro nezbytnou reprodukci závady. CI nepollovat.
- Použít přesně toolchain z .tool-versions a požadovaný mix formatter
  včetně celoprojektové kontroly před commitem. Provést build assets
  podle aktuálních skriptů repozitáře. V PR pravdivě uvést provedené kontroly
  a neověřené části.

## Nasazení a rizika

Bez plánovaných migrací, nových runtime env proměnných a změn rozhraní.
Hlavní riziko je příliš široký zásah do sdílených barevných tokenů a layoutů:
ověřit také formuláře, modaly, finanční stavy, POS a podnavigace mimo dashboard.
Případný návrat přes revert prezentačních commitů, bez zásahu do databáze.
Optimalizovat fotografie a fonty; nesnížit rychlost dotykového POS.

## Průběh a předání dalšímu chatu

- Implementace pokračuje ve stejné větvi `docs/cozy-noir-redesign-plan`
  a PR #114; aktuální `origin/main` je již jejím předkem. AGENTS.md se nemění.
- Hotovo: nové tokeny, sdílená navigace a hlavička, dashboard, všechny tři POS
  kroky a sladění Adventure. Bez migrací, runtime konfigurace, změn autentizace,
  finanční logiky či dotazů; redesign nepřidává N+1 dotazy.
- Výchozí vzhled je **Cozy Noir**. Přepínač **Původní / Cozy Noir** v administraci,
  stravování a POS uchovává volbu pouze v prohlížeči pod
  `localStorage["cozy-design"]`, synchronizuje záložky a aplikuje se před
  vykreslením. Při zablokovaném úložišti funguje přepnutí v otevřené stránce.
- Nové styly jsou v `assets/css/noir.css` a `assets/css/noir-workspaces.css`,
  omezené na obrazovku. Dosavadní tiskové styly a archivovaná PDF se nemění.
- Inter, Playfair Display i původní Open Sans a Libre Baskerville jsou lokální
  WOFF2 s češtinou a přiloženými OFL licencemi. Google Fonts CDN se nepoužívá.
- Hlavička používá lokální černobílou fotografii **Hills in Mist**,
  Martin Vorel / LibreShot, Horní Malá Úpa, Krkonoše, zveřejněnou pod CC0.
  Zdroj, licence a úpravy jsou v
  `priv/static/images/cozy-noir-mountains.LICENSE.txt`.
  WebP má přibližně 101 KiB pro desktop a 13 KiB pro mobil; fallback je tmavý.
- POS zůstává bez produktových fotografií. Účty jsou nativní tlačítka,
  kategorie mají `aria-pressed`, názvy produktů se zalamují, mobil má dostupný
  součet a odkaz na účet. Události, stabilní ID a finanční výpočty jsou zachovány.
  Responzivní skládání katalogu a účtu je sdílené oběma tématy; opravuje také
  původní přetékání dlouhého názvu účtu a nulovou šířku katalogu na mobilu.
  Dialog nového účtu má pojmenovanou dialogovou roli, přesun a uzamčení focusu,
  zavření přes Escape a návrat na otevírací tlačítko; ověřeno na obou šířkách.
- Doplněny LiveView testy přepínačů, přístupných účtů a stavů kategorií.
  ExUnit testy se lokálně nespouštějí; výsledky CI ověří uživatel, CI se nepolluje.
- Chrome smoke kontrola na 390 a 1440 px ověřila obě témata, uložení volby,
  navigaci, dlouhé názvy v POS, lokální fonty a fungování při zablokovaném
  `localStorage` i `sessionStorage`. Zkontrolovány POS, dashboard, stravování,
  příchozí doklady, ekonomika a barové účty. Bez horizontálního přetékání,
  konzolových výjimek či neúspěšných HTTP odpovědí ve finální kontrole.
  Kvůli zastaralému lokálnímu testovacímu schématu proběhl náhled v oddělené
  dočasné databázi s aktuálními migracemi a syntetickými produkty/účtem,
  bez zásahu do stávajících dat, skutečných plateb nebo odesílání e-mailů.
  Prázdné finanční a stravovací přehledy nenahrazují kontrolu reálných dokladů.
- Prošel build assetů, kompilace bez varování a celoprojektová kontrola
  formátování na dostupném **Elixiru 1.20.5 / OTP 29.1.2**.
  Dokumentace prošla přes `.venv-docs/bin/mkdocs build --strict`.
  Připnutý **1.20.4-otp-29 / Erlang 29.1** není nainstalovaný,
  proto není ověřena přesná shoda formatteru s CI.
- Zbývá před finálním nasazením: ověření CI uživatelem a provozní průchod
  placením, tiskem a hustými tabulkami nad reprezentativními daty.

### Zadání pro navazující vlákno

> Přečti docs/plans/2026-11-12-cozy-noir-redesign.md a aktuální AGENTS.md.
> Implementuj schválený redesign Cozy / Noir: charcoal/slate/chalk paleta,
> černobílá horská hlavička a světlé pracovní plochy. Produktové fotografie
> nepoužívej. Začni sdílenými tokeny/layouty, dashboardem a všemi POS kroky,
> pak sjednoť ostatní obrazovky. Zachovej současné obchodní a finanční chování,
> admin PIN a veřejné POS. Vycházej z aktuálního origin/main, průběžně aktualizuj
> plán a vytvoř PR s výsledky ověření.

# Fakturace pobytů

Zálohové výzvy lze po nastavení integrace ručně přenést do ABRA z detailu
dokladu. Nastavení, limity první části a ověření popisuje
[export zálohových výzev](../integrations/ABRA_ACCOMMODATION.md).

## První spuštění

1. Spusťte migrace standardním nasazením. Migrační skript nic nevystavuje,
   nepřenáší staré stavy do plateb a nemění historické ceny ani částky.
2. V **Další agenda → Finance a přehledy → Nastavení fakturace** doplňte skutečné
   sídlo, DIČ, zápis v rejstříku a český bankovní účet dodavatele. Předvyplněný
   název a IČO nejsou kompletní fakturační profil.
3. S účetní nastavte čtyři číselné řady pro aktuální rok: zálohové výzvy, doklady
   k přijaté platbě, konečné faktury a opravné daňové doklady. Číslo je označení +
   čtyřmístný rok + pořadí doplněné nulami. Po prvním použití se řada uzamkne.
   Zálohové výzvy používají označení `COZY-ZF` (např. `COZY-ZF202600009`).
   Migrace zachová již vystavená čísla a nastaví tento prefix pro další výzvy.
   Pro nový rok je potřeba předem založit nové řady. Barové doklady mají vlastní
   původní číslování a jejich nastavení se nemění.
4. V **Ceník ubytování** založte sezony. Kalendář žlutě označuje dny bez ceny.
   Začátek a konec platí včetně; překryvy blokuje i databázové omezení.
5. Ověřte `RESEND_API_KEY` a `EMAIL_FROM_ADDRESS` (ověřený odesílatel v Resend).
   Pro práci s doklady není ABRA ani přístup do účetnictví potřeba.

Volitelná proměnná `CHROME_EXECUTABLE` určuje cestu k prohlížeči (CI ji nastavuje
podle instalace Chrome).

Výchozí splatnost je 14 dnů, měna CZK, jazyk čeština. API přístupy nikdy nepatří
přímo do databáze profilů ani do Git repozitáře.

## Běžný postup

V rezervaci otevřete **Kalkulace, doklady a platby**. Kalkulace eviduje kategorie
hostů a počty nocí; pouze položky typu Osoby určují obsazenost. Odběratelem může
být host, firma nebo škola. Povinné je pouze jméno nebo název odběratele.
Adresu, zemi, IČO, DIČ a fakturační e-mail lze volitelně doplnit pod **Další údaje**;
prázdné údaje se na dokladu nezobrazují. Pro odeslání e-mailem vyplňte příjemce
v odesílacím formuláři.

Nová kalkulace používá koncové ceny včetně DPH podle dne příjezdu pro celý pobyt,
ve výchozí sazbě 12 %. Polopenze je zahrnuta v jedné ceně; nápoje se účtují na
baru. Další služby mají vlastní sazbu. Místní poplatek přidávejte ručně jako
službu s režimem **Mimo předmět DPH**, odpovídající cenou a počtem osobonocí.
Zdanitelná sazba 0 % a plnění mimo předmět DPH jsou odlišné režimy.

Není-li ceník, cena zůstane nevyplněná. Lze ji doplnit ručně. Změna sezony nebo
dne příjezdu nic sama nepřecení. **Použít aktuální ceník – náhled** zobrazí změny;
potvrzení zkopíruje nové ceny, sazbu i počet nocí do kalkulace. Vystavených dokladů
se úprava nedotkne.

Zálohová výzva není daňovým dokladem a neznamená přijatou platbu. Výchozí návrh
je 50 % ceny pobytu, lze zadat jiné procento nebo částku (částka má přednost).
Nové výzvy v náhledu, detailu i PDF ukazují rozpis dospělých a dětských kategorií,
počet osob, nocí, jednotkovou cenu s DPH a celkovou cenu každé položky. Zahrnou
se i objednané služby. Pod celkovou cenou pobytu je výpočet požadované zálohy:
například **50,00 % z 14 250,00 CZK = 7 125,00 CZK**, nebo údaj o záloze zadané
přímo částkou. Základ a výše DPH se na výzvě nerozepisují. K úhradě i v QR platbě
zůstává pouze požadovaná záloha.

Rozpis a způsob výpočtu se při vystavení ukládají s dokladem; pozdější změna
kalkulace je nepřepočítává. Starší výzvy bez tohoto uloženého rozpisu zachovají
původní souhrnný text. Již uložená PDF se nemění.

Každá skutečně přijatá záloha před dokončením pobytu se zapisuje s datem, částkou,
způsobem a referencí. Vznikne vlastní daňový doklad k přijaté platbě. Platba může
být bez výzvy; několik dílčích plateb vytvoří několik daňových dokladů.

Konečnou fakturu před vystavením zkontrolujte v náhledu, včetně DUZP a splatnosti.
Budoucí DUZP není podporováno. Zálohy se odpočítají v původních základech a DPH,
neuhrazené výzvy nic nesnižují. Finální doklad může mít nulový doplatek nebo
přeplatek. Další skutečné příjmy se přiřazují konečné faktuře. Pozdě objevenou
platbu před DUZP nelze tiše zaevidovat jako doplatek; vyžaduje účetní opravu.

Původní interní kalkulace jsou označené **ceny bez DPH**, včetně starého čísla a
stavu. Neznamenají existenci skutečného dokladu ani peněz. Jejich přecenění je
vědomý krok; další služby při převodu zachovají svou koncovou jednotkovou cenu
zaokrouhlenou na haléře. Historické vystavené doklady se z těchto záznamů nevytvářejí.

Soukromý pobyt dál počítá osoby do kapacity a zachovává stravování, ale je bez
finanční evidence. Označuje se v kalkulaci tlačítkem **Označit soukromý pobyt**;
pokud už existují vydané doklady, tento přepínač není dostupný. Soukromé pobyty
nezobrazují nedoplatek, stav úhrady ani formuláře pro doklady a platby.

V seznamu rezervací se stav dokladů a úhrad odvozuje ze skutečně vydaných dokladů
a ručně zaznamenaných plateb, včetně oprav a vratek. Zálohová výzva neznamená
přijetí peněz a ani plně přijatá záloha neznamená konečnou fakturu. U konečné
faktury se zobrazuje stav úhrady, číslo dokladu, nedoplatek nebo přeplatek a při
kladném nedoplatku po datu splatnosti také **Po splatnosti**. Datum splatnosti
samo se ještě nepovažuje za prodlení. Změna kalkulace nezmění částku vydané
faktury. Filtr **Doklady a úhrady** používá stejná pravidla jako zobrazení.
V řádku je pouze kompaktní štítek stavu úhrady (před vyúčtováním stav zálohy).
Číslo dokladu, částky a podrobnosti jsou v plovoucí kartě po najetí myší,
při zaměření klávesnicí nebo po klepnutí na štítek. Odtud lze otevřít evidenci
pobytu. Kartu zavře Escape nebo kliknutí mimo ni. Finanční stav nelze ručně přepsat.
Přehled se aktualizuje při otevření seznamu nebo změně filtru. Bankovní párování
zatím není zapojené.

## Opravy a vratky

V detailu faktury nebo daňového dokladu k platbě lze vystavit snížení či zvýšení
ceny s uvedením částky a důvodu. Rozdíl se rozděluje podle původních daňových
skupin. Plná oprava zachová původní zaokrouhlení. Po konečném vyúčtování se
opravuje konečná faktura, nikoli již odpočtený daňový doklad zálohy.

Změna dodavatele v nastavení nemění kopie na dokladech. Odběratele po prvním
vystavení nelze přepsat; změnu identifikace musí řešit účetní opravou. Vystavené
doklady se v administraci neupravují, nemažou ani nevracejí do konceptu.

Vratku evidujte až po skutečném odeslání peněz a po potřebné opravě dokladu.
Nezdaněný přeplatek konečného vyúčtování lze vrátit přímo. Aplikace neprovádí
bankovní převody; zrušení rezervace také automaticky nevrací peníze.

## PDF, pošta a provoz

Kalkulace pobytu zůstává na samostatné stránce dostupné z rezervace. Přehled
**Doklady** na této stránce nabízí u každého dokladu přímo **Stáhnout PDF**
a **Odeslat e-mailem**. Odeslání otevře dialog s předvyplněným příjemcem,
předmětem a zprávou; údaje lze před potvrzením změnit. Je potřeba potvrdit
souhlas s elektronickou podobou dokladu. Zpráva se zařadí do fronty bez
opuštění kalkulace. **Detail a historie** nadále zpřístupňuje historii pokusů
a opravy dokladu.

PDF vytváří ChromicPDF s lokálním Chromium, bez externích fontů či vzdálených
podkladů. Docker runtime obsahuje Chromium a fonty DejaVu. Dokumenty A4 se ukládají
jako binární data v PostgreSQL spolu s SHA-256. Opakované stažení a e-mail vždy
použijí původní soubor, nikoli aktualizovanou kalkulaci nebo aktuální firemní profil.

### Lokální spuštění PDF a mailboxu

Na lokálním počítači musí být nainstalovaný Google Chrome nebo Chromium. Na macOS
je běžná cesta `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`.
Pokud se automaticky nenajde, spusťte aplikaci s explicitní cestou:

```sh
CHROME_EXECUTABLE="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" iex -S mix phx.server
```

Po změně cesty nebo aktualizaci nastavení rendereru aplikaci restartujte.
Renderer se spustí až při prvním PDF. Používá vlastní dočasný profil a jednu
browserovou instanci, takže funguje také s běžným Google Chrome 136+ a již
otevřeným osobním prohlížečem. Chrome 136+ vyžaduje samostatný profil pro
`remote-debugging-pipe`: https://developer.chrome.com/blog/remote-debugging-port.
Profil se při řádném zastavení aplikace odstraní.

Vytváření PDF běží mimo databázovou transakci. Pád nebo timeout Chromia vrátí
zachycenou chybu, kterou zobrazí stažení i podrobnosti e-mailového pokusu.
V developmentu zůstává stderr Chromia v terminálu viditelný. Hotové PDF se uloží
pod krátkým zámkem; souběžné požadavky vždy dostanou původní uložené bajty.

Development používá `Swoosh.Adapters.Local`: zpráva se zobrazí v `/dev/mailbox`
až po úspěšné přípravě přílohy. Nepotřebuje Resend API klíč. Pokud původní úkol
vyčerpal pět pokusů (`discarded`), po opravě odešlete zprávu z detailu dokladu
znovu; samotný restart vyčerpaný úkol neobnoví.

Bankovní údaje musí být platný český účet (nejvýše deset číslic základního čísla,
až šest číslic předčíslí a čtyři číslice kódu banky). Nesprávný účet se nově
neuloží jako IBAN. U starších dokladů s nesprávným uloženým údajem se nevytváří
neplatný QR kód. Oprava profilu nemění již vystavený doklad; u nesprávné zálohové
výzvy vystavte novou výzvu s opravenými údaji.

Fronta Oban `billing` má souběžnost 2. Generování PDF i e-mail se opakují až
pětkrát. Při chybě prvotního generování lze PDF znovu připravit stažením. E-mail
vyžaduje zaznamenaný souhlas s elektronickou podobou. Každé vědomé nové odeslání
má vlastní záznam; opakování stejného úkolu používá stejný idempotency key Resend.
Resend omezuje dobu platnosti svého idempotency key; po nejasné síťové chybě a
pozdním ručním obnovení úkolu zkontrolujte historii poskytovatele.

Stav **Odesláno** znamená přijetí poskytovatelem, nikoli potvrzené doručení.
Přehled historie obnovte tlačítkem; technické chyby a vyčerpané úkoly najdete
v Oban dashboardu. Nefunkční odesílání nebrání stažení dokladu.

Databázové zálohy musí obsahovat tabulky `billing_*` včetně PDF. Nastavte jejich
uchování nejméně podle zákonné desetileté lhůty a pravidelně ověřujte obnovu
souborů i kontrolních součtů. Neprovádějte automatické mazání těchto dat spolu
s rezervací. Stažení PDF i všechny stránky fakturace vyžadují správní relaci.

## Ověření a další etapa

```sh
PGUSER=elixir PGPASSWORD='' mix test test/cozy_checkout/financial test/cozy_checkout_web/live/financial test/cozy_checkout_web/billing_live_test.exs
PGUSER=elixir PGPASSWORD='' mix precommit
```

Nové testy ověřují sezony, chybějící ceny, zálohy, haléřové odpočty, opravy,
vratky, izolaci obsazenosti, skutečné vícestránkové PDF, přílohy e-mailů,
autorizaci i souběh oddělených databázových spojení. E-mailový test používá
Swoosh test adapter; neodesílá zprávy hostům. Pro produkční kontrolu použijte
vlastní testovací rezervaci a vlastní testovací e-mailovou adresu.

Integrace pobytových dokladů do ABRA Flexi je druhá etapa; nynější export
barových účtů zůstává zachovaný. Budoucí export má použít stabilní ID dokladů,
odpočtů a plateb a přenášet vazby jednosměrně z aplikace do účetnictví.
Současné barové mapování, provozní omezení a podklady pro tuto etapu popisuje
[ABRA_INTEGRATION.md](../integrations/ABRA_INTEGRATION.md).

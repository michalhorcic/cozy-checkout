# Přijaté doklady – jednoduché MVP

**Stav:** implementace připravena k CI a pilotnímu ověření. **Aktualizováno:** 5. 11. 2026.
Implementace a provozní nastavení: [Přijaté doklady — pilot](../features/INCOMING_DOCUMENTS.md).

## Cíl a přijatá rozhodnutí

Uživatel nahraje obrázek nebo PDF, vybere agendu a nechá OpenAI vytvořit
importní XML podle uloženého vzoru. Před odesláním porovná vytěžená pole
s originálem a případně je opraví. Teprve na jeho pokyn aplikace odešle XML
přes API do ABRA Flexi.

Začneme v testovací firmě ABRA, na skutečných dokladech doladíme vzory a program.
První doklady v ostrém provozu budeme pečlivě ručně kontrolovat v aplikaci i ABRA.
Není cílem předem vyřešit všechny účetní výjimky.

Modul bude součástí stávající administrace Cozy Checkout. Použije současné
admin přihlášení, Ecto/PostgreSQL, Req a Oban. Nebudeme vytvářet samostatnou aplikaci.

## Průchod MVP

1. **Nahrát soubor a vybrat agendu.** Jeden soubor obsahuje jeden doklad;
   může to být vícestránkové PDF nebo JPEG/PNG. První agendy jsou přijaté faktury,
   pokladní výdaje a ostatní závazky pro platby kartou. Každá má jeden uložený
   vzor importního XML.
2. **Vytvořit XML pomocí OpenAI.** Server pošle originál, vzor vybrané agendy
   a stručné pokyny. OpenAI vrátí cílové XML pro import do ABRA Flexi.
   Zavedeme přímé generování XML, bez samostatného univerzálního JSON kontraktu
   a bez vlastního kompletního účetního exportéru.
3. **Zkontrolovat a opravit.** Vlevo náhled originálu se zvětšením a stránkováním,
   vpravo editovatelná pole načtená z vytvořeného XML: dodavatel, číslo dokladu,
   data, částky a DPH, případně položky podle vzoru. Zobrazíme také agendu a účetní
   nastavení převzaté ze vzoru. Uživatel může opravit hodnoty a prohlédnout XML.
   Opravy se promítnou přímo do XML, které bude odesláno; kvůli opravě pole
   se OpenAI znovu nevolá. Stačí jednoduché mapování polí pro všechny tři konkrétní vzory.
4. **Odeslat do ABRA.** Tlačítko „Schválit a odeslat“ odešle zkontrolované XML
   do nastavené firmy. Před zápisem provedeme ABRA dry-run nad stejným XML;
   chyby a varování zobrazíme uživateli, při neúspěchu neodesíláme. Upozornění
   vyžaduje kontrolu a výslovné potvrzení. Po změně XML se dry-run opakuje.
5. **Ukázat výsledek.** Uložíme odpověď ABRA a identifikátor založeného dokladu.
   Uživatel vidí úspěch s odkazem na doklad, nebo srozumitelnou chybu a další krok.

## Vzory a základní pojistky

- Vzory připravíme ze správných příkladů pro cílové agendy a vyzkoušíme je
  v testovací firmě. Pro začátek stačí soubory v konfiguraci aplikace;
  editor vzorů ani verzované účetní profily nepotřebujeme. Před prvním průchodem
  jsou potřeba všechny tři vzory a přístup k testovací firmě.
- Vzor určuje strukturu a výchozí účetní nastavení. Model doplňuje údaje
  z nového dokladu, chybějící hodnoty si nemá vymýšlet. Pokyny uvnitř nahraného
  dokumentu nesmějí měnit zadání ani spouštět akce.
- Z exportovaného příkladu odstraníme identitu původního dokladu, interní číslo,
  vazby a stavy úhrad. Aplikace po vygenerování kontroluje povolenou agendu
  a pole, odstranění cizích identifikátorů a doplní vlastní stabilní externí ID.
  Údaj „zaplaceno kartou“ sám nezakládá úhradu v ABRA.
- Před kontrolou uživatelem ověříme čitelné XML bezpečným parserem bez externích
  entit, očekávanou strukturu a základní shodu částek. Částky zpracujeme přes
  Decimal. Nepovedený výstup zobrazíme jako chybu s možností nového pokusu.
- Platné XML ani úspěšný dry-run nezaručují správné účetní údaje. Proto je
  ruční kontrola povinná. Rozdíly DPH a zaokrouhlení, například u účtenky PENNY,
  ověříme na konkrétním importu. V MVP nezavádíme automatické rozdělování haléřů;
  problémový doklad opravíme ručně nebo zpracujeme mimo aplikaci.
- Dvojklik nesmí založit dva doklady. Přenos používá stabilní externí ID
  a režim pouze vytvoření bez přepsání existujícího dokladu. Po timeoutu
  nejprve ověříme v ABRA, zda doklad vznikl. Dokud není výsledek jasný,
  další zápis blokujeme; žádné slepé opakování.

## Minimální technické řešení

Pro začátek stačí záznam dokladu: UUID, soubor a jeho hash, agenda, stav,
vygenerované a aktuálně upravené XML, přesné odeslané XML, použitý vzor,
cílová firma, externí ID, výsledek přenosu a časová razítka. Samostatný systém
revizí, pokusů a účetních profilů není podmínkou MVP. Po zahájení přenosu
odesílaný obsah uzamkneme; změna mezitím nesmí přepsat schválenou verzi.

Jednoduché stavy: **nahráno → zpracovává se → ke kontrole → odesílá se → odesláno**.
Chyba obsahuje informaci, zda selhalo vytěžení nebo import. Nejasný výsledek
zápisu má viditelný stav **nutno ověřit v ABRA**.

Originál uchováme v privátním trvalém úložišti přístupném pouze administraci,
společně se stávajícím zálohováním. Omezíme formát a velikost uploadu.
Stejný hash upozorní na opakované nahrání; sofistikované hledání duplicit odložíme.
API klíče zůstanou na serveru, obsah dokladů ani klíče nepatří do běžných logů.
Volání OpenAI použije `store=false`; před pilotem ověříme, že odesílání skutečných
účetních dokladů do OpenAI odpovídá firemním podmínkám pro zpracování dat.

Navážeme na existující ABRA klienty a obsluhu chyb. Seznam dokladů bude načítat
potřebná data hromadně, bez dotazů pro každý řádek.

## Postup a ověření

1. Připravit tři vzory a nastavení testovací firmy.
2. Dodat jeden celý průchod: upload → OpenAI XML → kontrola a oprava → ABRA.
3. Ručně vyzkoušet několik skutečných dokladů ve všech třech agendách, včetně PDF,
   fotografie a účtenky se slevou nebo rozdílem v zaokrouhlení. Porovnat výsledek
   přímo v ABRA včetně účtování a DPH; podle zjištění upravit vzor nebo program.
4. Automaticky ověřit zásadní chování: oprava pole mění odesílané XML, vadný
   výstup či odmítnutí ABRA nezaloží úspěšný stav a dvojklik či timeout nevedou
   k duplicitě. HTTP testy přes Req.Test, bez skutečných zápisů do účetnictví.
5. Po ověření přepnout konfiguraci na ostrou firmu a první doklady jednotlivě
   pečlivě kontrolovat. Produkční zápisy nejsou součástí vývoje ani CI.

**MVP je hotové**, když uživatel ve všech třech agendách projde celý tok, opraví údaj
proti originálu a po vědomém odeslání najde odpovídající doklad v testovací ABRA.
Není nutná rozsáhlá referenční sada ani vyřešení všech typů dokladů před pilotem.

## Odloženo

Automatické schvalování, e-mailový příjem, hromadné importy, párování plateb,
zakládání dodavatelů, skladové vazby, napojení na nákladovost kuchyně,
automatické nahrávání originálu jako přílohy do ABRA, univerzální účetní pravidla,
pokročilý audit a řešení všech zvláštních daňových případů. Nepodporované doklady
zatím zpracujeme ručně. Další funkce přidáme podle zkušeností z pilotu.

## Nejbližší krok

Po kontrole GitHub CI nastavit model OpenAI, ověřit cílovou testovací firmu
a projít celý tok se skutečným dokladem ve všech třech agendách. Porovnat částky,
DPH a účtování v ABRA a podle výsledku upravit vzory. Pilot zatím nebyl proveden.

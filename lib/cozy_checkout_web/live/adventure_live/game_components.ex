defmodule CozyCheckoutWeb.AdventureLive.GameComponents do
  use CozyCheckoutWeb, :html

  def shell(assigns) do
    ~H"""
    <div id="adventure-game-layout" class="adventure-stage">{@inner_content}</div>
    """
  end

  attr :name, :string, required: true
  attr :class, :string, default: ""

  def symbol(assigns) do
    ~H"""
    <span aria-hidden="true" class={["adventure-symbol", "adventure-symbol--#{@name}", @class]}></span>
    """
  end

  def open_help, do: JS.dispatch("adventure:open-help", to: "#adventure-help")
  def close_help, do: JS.dispatch("adventure:close-help", to: "#adventure-help")

  def help_overlay(assigns) do
    ~H"""
    <dialog
      id="adventure-help"
      class="adventure-overlay"
      phx-hook="AdventureHelp"
      phx-update="ignore"
      aria-labelledby="adventure-help-title"
    >
      <div id="adventure-help-panel" class="adventure-guide">
        <button
          id="adventure-help-close"
          autofocus
          type="button"
          phx-click={close_help()}
          class="adventure-close"
          aria-label="Zavřít průvodce"
        ><.icon name="hero-x-mark" class="size-5" /></button>
        <div class="adventure-guide-heading">
          <span class="adventure-emblem"><.symbol name="compass" /></span><div>
            <p class="adventure-eyebrow">Do batohu na cestu</p><h2 id="adventure-help-title">
              Průvodce dobrodružstvím
            </h2>
          </div>
        </div>
        <div class="adventure-guide-body">
          <section>
            <h3>Tvoje výpravy</h3><p>
              Chata je náš společný herní svět. Hrdinu vyber u avatara, výpravu na nástěnce. Přijmi až tři osobní questy a po skutečném splnění je potvrď. Společné výpravy mají vlastní místo a jednu odměnu chatě. Poznámka je nepovinná. Opakované questy se řídí dny nastavenými v knize podle Europe/Prague. Rozpracovanou výpravu můžeš dokončit i později; její zadání a odměna zůstávají zachované.
            </p>
          </section>
          <section>
            <h3>Vlastní úkoly</h3><p>
              Výpravy slouží k hraní; přes Spravovat zadání otevřeš knihu pro vytváření a úpravy. Přepínače oddělují jednorázové questy, opakované šablony a historii. Stačí název; termín, popis a poznámka jsou nepovinné. Velikost předvyplní 50, 100 nebo 250 XP. Přiřazení samo nezabírá slot. Přijetí osobní výpravy v táboře ji přiřadí právě vybranému hrdinovi a počítá se do společného limitu tří osobních výprav.
            </p><p>
              Při dokončení zvol skutečného splnitele, který dostane osobní XP. U společného úkolu výslovně vyber přispěvatele; jednu odměnu dostane jen chata. Zadání lze upravit pouze ve stavu Čeká. Archivace otevřenou práci zruší, historii ani již udělená XP nesmaže. Termín není penalizace. Opakované šablony spravuj přes Výpravy → Spravovat zadání. Nová šablona je pozastavená; po spuštění se úkoly obnovují hodinově nebo ručně. Zmeškané termíny se nehromadí: jedna otevřená položka dostane nový termín a uchová historii. Při pozastavení výslovně vyber, co s otevřeným úkolem. Podmínka hostů může být neznámá, pak lze přidat vlastní úkol. Změny šablony platí pro budoucí výskyty.
            </p>
          </section>
          <section>
            <h3>Dílna a projekty</h3><p>
              Dílna sdružuje všechny projekty, není další místností k vylepšování. Projekt patří konkrétní oblasti nebo celé chatě. Kroky projektu jsou běžné questy: od každého přejdeš přímo k přijetí a plnění ve hře. Dokončené kroky projekt automaticky nepřevezmou a převzetí nepřidává další XP.
            </p>
          </section>
          <section>
            <h3>Mapa a služba dne</h3><p>
              Provoz se načte při vstupu do tábora a tlačítkem Obnovit provoz, bez automatické obnovy. Prohlížení ani obnova nevytvářejí questy a neudělují XP. Podnět převedeš na čekající quest výslovným uložením návrhu; jeho zmizení quest nesplní. Provozní podklady upravuj v hlavní aplikaci.
            </p>
          </section>
          <section>
            <h3>XP a úrovně</h3><p>
              Osobní questy odměňují skutečného splnitele zvoleného při potvrzení. Staré kampaně mají automatické milníky pro společnou chatu; nové sezónní kroniky žádné automatické XP nepřidělují. XP nejsou peníze ani provozní ukazatel. Další úroveň začíná při 100 × L × (L + 1) / 2 XP. Opakované potvrzení nevytváří novou odměnu.
            </p>
          </section>
          <section>
            <h3>Kdo právě hraje?</h3><p>
              Výběr profilu je vlastní prohlášení, nikoli ověřená identita. Prohlížeč si ho pamatuje v místním úložišti, se zálohou v roční cookie, i po obnovení stránky nebo návratu do hry. Vymazáním výběru nebo všech dat tohoto webu jej zapomene. Volba platí pro stejnou adresu webu a stejný prohlížeč; IP adresa a doménové jméno mohou mít jiná uložená data. Pokud prohlížeč ukládání blokuje, hra tě upozorní. Všechny stránky a akce dál chrání společný admin PIN. Automatické XP nikdy nepřipadnou člověku jen proto, že stiskl přepočet.
            </p>
          </section>
          <section>
            <h3>Kronika sezóny</h3><p>
              Kronika je účetní list našeho herního světa: pobyty, uskutečněné lůžkonoci, inkaso a vyúčtování. Nové sezóny nepotřebují cíle. Kapacita je volitelná; bez ní není dostupná procentní obsazenost, ostatní metriky zůstávají. Kronika nikdy sama neodměňuje XP. Přepočet spouštíš výslovně tlačítkem nebo uzavřením, prohlížení jen čte uložené výsledky.
            </p><p>
              Sezóna vzniká jako návrh v Nastavení. Potvrď období a aktivuj ji; současně může být aktivní jedna. Minulé období místo aktivace zapiš jako historickou uzavřenou sezónu. Nespustí opakované úkoly ani nepřidá zpětné XP. Po aktivaci či historickém zápisu jsou období a pravidla neměnné. Oprava uzavřené kroniky vyžaduje důvod a vytvoří novou verzi, původní zůstane v auditu. Jiné období znamená novou sezónu.
            </p><p>
              Realizované lůžkonoci zahrnují noci před dneškem ve stavech active/completed, budoucí rezervace noci od dneška ve stavech upcoming/active. Příjezd se počítá, odjezd ne; osoby zahrnují i děti a kojence. Zrušené a smazané pobyty jsou vyloučené. Kapacita je ručně potvrzená konstanta, nikoli historie pokojů.
            </p>
          </section>
          <section>
            <h3>Dva pohledy na peníze</h3><p>
              Inkaso sleduje datum platby a refundace v období. Vyúčtování sleduje pobyty podle společného data odjezdu, celé i při přesahu sezóny; úhrady těchto pobytů jsou aktuální k přepočtu a mohou být mimo sezónu. Listopadová záloha 30 000 a lednový doplatek 70 000 znamenají zimní inkaso 70 000, ale vyúčtování lednového pobytu 100 000 a celkem uhrazeno 100 000. Zálohový a daňový doklad nejsou další platba.
            </p><p>
              Bar a ubytování ukazujeme odděleně a nesčítáme inkaso s vyúčtováním. Barové inkaso obsahuje aktuálně platné platby, servis je zvlášť; platba může zahrnovat spropitné. Nejde o tržbu za zboží, úplný bankovní audit ani zisk. Chybějící konečné faktury a nehotové rozdělení plátců označujeme jako dílčí podklady, ne nulu. Přeplatek jednoho plátce nesmaže dluh jiného. Smazání rezervace nevymaže její vydané doklady a platby z finanční historie.
            </p>
          </section>
          <section>
            <h3>Původní kampaně a kvalita podkladů</h3><p>
              Původní kampaně s pravidly stays_v1 zůstávají beze změny včetně cílů a milníků. Jejich milníky počítají completed pobyty s odjezdem v kampani, před dnešním pražským datem a po dni aktivace. První pobyt znamená 100 společných XP, deset pobytů 250 XP. Stav rezervace sám neověřuje skutečnou účast hostů.
            </p><p>
              Neúplné nebo nekonzistentní podklady označujeme přímo u výsledků. Nedostupná hodnota není nula. Z neúplných podkladů se XP nepřiznávají ani neodebírají. Při opraveném stornu může být milník odvolán s jednorázovou kompenzací. Původní důkaz zůstává v auditu; odvolaný milník se ve stejné kampani znovu neodměňuje.
            </p>
          </section>
          <section>
            <h3>Hra zůstává hrou</h3><p>
              Herní akce zapisují pouze do vlastních tabulek Adventure. Provozní rezervace, platby a doklady se jen čtou při výslovném přepočtu. Hra nemění platby, účetnictví, rezervace ani zásoby a neposílá hostům zprávy. Poznámky nevyplňuj osobními údaji hostů.
            </p><p>
              Srovnání sezón, náklady, zisk a automatické skilly zůstávají další cestou. Z neúplných podkladů nevykazujeme domnělé úspory.
            </p>
          </section>
        </div>
        <button
          type="button"
          phx-click={close_help()}
          class="adventure-button adventure-button--primary"
        >Zpátky do tábora <.symbol name="trees" /></button>
      </div>
    </dialog>
    """
  end

  def quest_symbol("prepare_stay"), do: "house"
  def quest_symbol("review_deposits"), do: "coins"
  def quest_symbol("shopping_plan"), do: "utensils"
  def quest_symbol(_), do: "wrench"

  def level_floor(level), do: div(100 * (level - 1) * level, 2)
  def level_progress(xp, level), do: max(0, xp - level_floor(level))
end

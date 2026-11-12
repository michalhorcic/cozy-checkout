defmodule CozyCheckoutWeb.AdventureLive.GameComponents do
  use CozyCheckoutWeb, :html

  def shell(assigns) do
    ~H"""
    <div id="adventure-game-layout" class="adventure-stage">{@inner_content}</div>
    """
  end

  def world_map(assigns) do
    ~H"""
    <section id="adventure-world-map" class="adventure-panel adventure-world-map">
      <header class="adventure-section-heading">
        <div>
          <p class="adventure-eyebrow">Za branami tábora</p><h2>Mapa chaty</h2>
        </div><.symbol name="compass" />
      </header>
      <p class="adventure-muted">Vydej se do provozu. Tvá rozpracovaná výprava na tebe počká.</p>
      <div class="adventure-map-places">
        <.link href={~p"/admin/bookings/calendar"} class="adventure-place adventure-place--lodge"><span class="adventure-place-token"><.symbol name="house" /></span><strong>Recepce</strong><span>Rezervace a hosté</span><.icon
          name="hero-arrow-up-right"
          class="size-4"
        /></.link>
        <.link href={~p"/admin/meal-planner"} class="adventure-place adventure-place--kitchen"><span class="adventure-place-token"><.symbol name="utensils" /></span><strong>Kuchyně</strong><span>Jídla a nákupy</span><.icon
          name="hero-arrow-up-right"
          class="size-4"
        /></.link>
        <.link href={~p"/admin/bar-stock"} class="adventure-place adventure-place--bar"><span class="adventure-place-token"><.symbol name="backpack" /></span><strong>Bar</strong><span>Zásoby baru</span><.icon
          name="hero-arrow-up-right"
          class="size-4"
        /></.link>
        <.link href={~p"/admin/billing"} class="adventure-place adventure-place--treasury"><span class="adventure-place-token"><.symbol name="coins" /></span><strong>Pokladnice</strong><span>Doklady a platby</span><.icon
          name="hero-arrow-up-right"
          class="size-4"
        /></.link>
      </div>
      <.link href={~p"/admin"} class="adventure-text-link adventure-world-exit">Celá aplikace
      <.icon name="hero-arrow-right" class="size-4" /></.link>
    </section>
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
              Tábor je tvoje herní obrazovka: vyber hrdinu, otevři „Najít další výpravu“, přijmi až tři osobní questy a po splnění je potvrď. Společné výpravy mají vlastní místo a jednu odměnu chatě. Poznámka je nepovinná. Opakované questy se řídí dny nastavenými v knize podle Europe/Prague. Rozpracovanou výpravu můžeš dokončit i později; její zadání a odměna zůstávají zachované.
            </p>
          </section>
          <section>
            <h3>Vlastní úkoly</h3><p>
              Questy jsou kniha zadání: tady práci vytváříš a upravuješ, samotný výběr a plnění patří do tábora. Přepínače oddělují jednorázové questy, opakované šablony a historii. Stačí název; termín, popis a poznámka jsou nepovinné. Velikost předvyplní 50, 100 nebo 250 XP. Přiřazení samo nezabírá slot. Přijetí osobní výpravy v táboře ji přiřadí právě vybranému hrdinovi a počítá se do společného limitu tří osobních výprav.
            </p><p>
              Při dokončení zvol skutečného splnitele, který dostane osobní XP. U společného úkolu výslovně vyber přispěvatele; jednu odměnu dostane jen chata. Zadání lze upravit pouze ve stavu Čeká. Archivace otevřenou práci zruší, historii ani již udělená XP nesmaže. Termín není penalizace. Opakované šablony spravuj v Questech. Nová šablona je pozastavená; po spuštění se úkoly obnovují hodinově nebo ručně. Zmeškané termíny se nehromadí: jedna otevřená položka dostane nový termín a uchová historii. Při pozastavení výslovně vyber, co s otevřeným úkolem. Podmínka hostů může být neznámá, pak lze přidat vlastní úkol. Změny šablony platí pro budoucí výskyty.
            </p>
          </section>
          <section>
            <h3>XP a úrovně</h3><p>
              Osobní questy odměňují vybraný profil. Automatické milníky odměňují pouze společnou chatu. XP nejsou peníze ani provozní ukazatel. Další úroveň začíná při 100 × L × (L + 1) / 2 XP. Opakované potvrzení nevytváří novou odměnu.
            </p>
          </section>
          <section>
            <h3>Kdo právě hraje?</h3><p>
              Výběr profilu je vlastní prohlášení, nikoli ověřená identita. Prohlížeč si ho pamatuje rok v cookie této hry, i po obnovení stránky. Vymazáním výběru nebo cookies jej zapomene. Všechny stránky a akce dál chrání společný admin PIN. Automatické XP nikdy nepřipadnou člověku jen proto, že stiskl přepočet.
            </p>
          </section>
          <section>
            <h3>Co dělá kampaň?</h3><p>
              Kampaň je společná sezónní výprava chaty. Určuje období, za které sledujeme pobyty, lůžkonoci a obsazenost. Cíle ukazují postup; společné XP zatím dávají jen milníky za 1 a 10 pobytů. Přepočet spouštíš ručně tlačítkem nebo uzavřením kampaně, nic neběží na pozadí.
            </p><p>
              Kampaň vzniká jako návrh. V Nastavení potvrď období, cíle a stálou kapacitu, teprve potom ji aktivuj. Současně může být aktivní jedna kampaň. Po aktivaci jsou pravidla uzamčená. Přepočítat lze i uzavřenou kampaň; její hranice realizace už se neposouvá.
            </p><p>
              Realizované lůžkonoci zahrnují noci před dneškem ve stavech active/completed, budoucí rezervace noci od dneška ve stavech upcoming/active. Příjezd se počítá, odjezd ne; osoby zahrnují i děti a kojence. Zrušené a smazané pobyty jsou vyloučené. Kapacita je ručně potvrzená konstanta, nikoli historie pokojů.
            </p>
          </section>
          <section>
            <h3>Milníky a kvalita podkladů</h3><p>
              Milníky počítají completed pobyty s odjezdem v kampani, před dnešním pražským datem a po dni aktivace. První pobyt znamená 100 společných XP, deset pobytů 250 XP. Stav rezervace sám neověřuje skutečnou účast hostů.
            </p><p>
              Neúplné nebo nekonzistentní podklady označujeme přímo u výsledků. Nedostupná hodnota není nula. Z neúplných podkladů se XP nepřiznávají ani neodebírají. Při opraveném stornu může být milník odvolán s jednorázovou kompenzací. Původní důkaz zůstává v auditu; odvolaný milník se ve stejné kampani znovu neodměňuje.
            </p>
          </section>
          <section>
            <h3>Hra zůstává hrou</h3><p>
              Herní akce zapisují pouze do vlastních tabulek Adventure. Provozní rezervace se jen čtou při výslovném přepočtu. Hra nemění platby, účetnictví, rezervace ani zásoby a neposílá hostům zprávy. Poznámky nevyplňuj osobními údaji hostů.
            </p><p>
              Obchod, finance, kuchyně, provoz, hosté a rekonstrukce jsou zatím další cesta, bez automatických skillů a vykazování úspor.
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

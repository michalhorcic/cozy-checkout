defmodule CozyCheckoutWeb.AdventureLive.WorldComponents do
  use CozyCheckoutWeb, :html
  import CozyCheckoutWeb.AdventureLive.GameComponents
  alias CozyCheckoutWeb.AdventureLive.OperationComponents, as: Operation

  def navigation(assigns) do
    ~H"""
    <nav class="adventure-nav adventure-game-nav" aria-label="Adventure">
      <.link
        :for={
          {view, label, icon} <- [
            {"world", "Chata", "house"},
            {"expeditions", "Výpravy", "backpack"},
            {"development", "Rozvoj", "wrench"},
            {"chronicle", "Kronika", "notebook-pen"}
          ]
        }
        patch={@live_action == :index && ~p"/admin/adventure?#{%{view: view}}"}
        navigate={@live_action != :index && ~p"/admin/adventure?#{%{view: view}}"}
        aria-current={@live_action == :index && @game_view == view && "page"}
      >
        <.symbol name={icon} /><span>{label}</span>
      </.link>
    </nav>
    """
  end

  def player(assigns) do
    ~H"""
    <section :if={@data.profiles != []} class="adventure-player adventure-player--compact">
      <details
        id="adventure-hero-switcher"
        class="adventure-hero-switcher"
        open={is_nil(@data.profile)}
      >
        <summary>
          <span class="adventure-avatar">{if @data.profile,
            do: String.first(@data.profile.display_name),
            else: "?"}</span><span><strong>{if @data.profile,
            do: @data.profile.display_name,
            else: "Vyber hrdinu"}</strong><small>{if @data.profile,
            do: "Úroveň #{@data.level} · #{@data.total_xp} XP",
            else: "Kdo dnes hraje?"}</small></span><.icon name="hero-chevron-down" class="size-3" />
        </summary>
        <div class="adventure-hero-choices">
          <.form
            for={@profile_form}
            id="adventure-profile"
            phx-change="profile"
          >
            <.input
              field={@profile_form[:id]}
              type="select"
              label="Herní profil"
              prompt="Vyber profil"
              options={Enum.map(@data.profiles, &{&1.display_name, &1.id})}
            />
          </.form>
        </div>
      </details>
      <div :if={@data.profile} id="adventure-progress" class="adventure-player-progress">
        <span>Hrdina <strong>{@data.total_xp} XP</strong></span>
        <progress
          aria-label="Postup osobního profilu k další úrovni"
          value={level_progress(@data.total_xp, @data.level)}
          max={100 * @data.level}
        ></progress>
      </div>
      <div class="adventure-lodge-progress">
        <span><.symbol name="house" />
        Chata · úroveň {@game.level}<strong>{@game.total_xp} XP</strong></span><progress
          aria-label="Postup společné chaty k další úrovni"
          value={level_progress(@game.total_xp, @game.level)}
          max={100 * @game.level}
        ></progress>
      </div>
    </section>
    """
  end

  def world(assigns) do
    active = Enum.filter(assigns.data.quests, &(&1.status == "active")) |> Enum.take(3)
    shared = Enum.filter(assigns.camp_quests, &(&1.scope == "shared" && &1.status == "active"))
    focus = Enum.find(active ++ shared, &(&1.id == assigns.focus_quest_id)) || List.first(active)
    assigns = assign(assigns, active: active, shared: shared, focus: focus)

    ~H"""
    <section
      id="adventure-world-map"
      class="adventure-world"
      aria-label="Svět naší chaty"
      aria-busy={@operation_state == :loading}
    >
      <header class="adventure-world-heading">
        <div>
          <p class="adventure-eyebrow">Jindřichův dům · náš společný svět</p><h1>
            Vítej doma na horách.
          </h1>
        </div><button
          id="adventure-operation-refresh"
          aria-label="Obnovit provoz"
          type="button"
          phx-click="refresh-operation"
          disabled={@operation_state == :loading}
          class="adventure-button adventure-refresh"
        ><.icon name="hero-arrow-path" class="size-4" /><span>Obnovit provoz</span></button>
      </header>
      <div class="adventure-world-grid">
        <div class="adventure-scene-column">
          <Operation.village
            highlight={@success && @success.kind == :project && @success.area}
            snapshot={@operation}
            area={if @world_panel == "area", do: @operation_area}
            world={@world}
          />
          <div class="adventure-scene-toolbar">
            <button
              type="button"
              phx-click="world-panel"
              phx-value-panel="duty"
              class="adventure-service-shortcut"
            ><.symbol name="flag" /><span>Služba dne</span><strong>{if @operation,
              do: length(@operation.issues),
              else: "?"}</strong><.icon name="hero-chevron-right" class="size-4" /></button>
            <details class="adventure-area-list">
              <summary>Seznam oblastí</summary><div>
                <button
                  :for={{key, label, _} <- Operation.places()}
                  type="button"
                  phx-click="operation-area"
                  phx-value-area={key}
                >{label}</button>
              </div>
            </details>
          </div>
          <div class="adventure-source-status">
            <Operation.operation_status
              snapshot={@operation}
              state={@operation_state}
              checked_at={@operation_checked_at}
            />
          </div>
        </div>
        <aside
          id="adventure-context"
          phx-hook="AdventureContext"
          data-panel={@world_panel}
          data-view={@game_view}
          class={["adventure-context", @world_panel != "continue" && "adventure-context--detail"]}
          aria-label="Vybraná práce nebo oblast"
          tabindex="-1"
        >
          <button
            :if={@world_panel != "continue"}
            type="button"
            phx-click="world-panel"
            phx-value-panel="continue"
            class="adventure-context-back"
          ><.icon name="hero-arrow-left" class="size-4" /> Zpět k chatě</button>
          <div hidden={@world_panel != "continue"}>
            <p class="adventure-eyebrow">Další krok našeho dobrodružství</p>
            <.quest_focus quest={@focus} profile={@data.profile} />
          </div>
          <div hidden={@world_panel != "area"}>
            <Operation.area_detail
              area={@operation_area}
              snapshot={@operation}
              world={@world}
              profiles={@data.profiles}
            />
          </div>
          <div hidden={@world_panel != "duty"}>
            <h2>Služba dne</h2><Operation.operation_status
              id="adventure-duty-status"
              snapshot={@operation}
              state={@operation_state}
              checked_at={@operation_checked_at}
            /><Operation.service_day
              snapshot={@operation}
              duty_links={@duty_links}
              profile={@data.profile}
            />
          </div>
        </aside>
      </div>
      <div class="adventure-quest-dock">
        <section id="adventure-expeditions">
          <header>
            <h2>Tvoje výpravy</h2><span>{length(@active)} / 3</span>
          </header><div class="adventure-dock-items">
            <button
              :for={quest <- @active}
              id={"adventure-quest-#{quest.id}"}
              type="button"
              phx-click="focus-quest"
              phx-value-id={quest.id}
              aria-pressed={to_string(@focus && @focus.id == quest.id)}
            ><.symbol name="backpack" /><span>{quest.definition_snapshot["title"]}</span><strong>+{quest.definition_snapshot[
              "xp"
            ]} XP</strong></button><button
              id="adventure-find-quest"
              type="button"
              phx-click="find-quests"
              disabled={!@data.profile}
              class="adventure-dock-add"
            ><.symbol name="compass" /> Najít další výpravu</button>
          </div>
        </section>
        <section id="adventure-shared-expeditions">
          <header>
            <h2>Společně pro chatu</h2><span>{length(@shared)} na cestě</span>
          </header><.link
            patch={~p"/admin/adventure?view=expeditions"}
            class="adventure-shared-summary"
          ><.symbol name="flag" /><span>{if @shared == [],
            do: "Vyberme další společnou výpravu",
            else: hd(@shared).definition_snapshot["title"]}</span><.icon
            name="hero-arrow-right"
            class="size-4"
          /></.link>
        </section>
      </div>
    </section>
    """
  end

  attr :quest, :any, default: nil
  attr :profile, :any, default: nil

  def quest_focus(assigns) do
    ~H"""
    <div class="adventure-quest-focus">
      <span class="adventure-focus-emblem"><.symbol name={
        if @quest, do: quest_symbol(@quest.code), else: "compass"
      } /></span>
      <h2>{if @quest, do: @quest.definition_snapshot["title"], else: "Kam se vydáme dnes?"}</h2>
      <details :if={@quest && @quest.description not in [nil, ""]} class="adventure-focus-description">
        <summary>Zadání výpravy</summary><p>{@quest.description}</p>
      </details>
      <p :if={@quest && @quest.due_on} class="adventure-muted">
        Termín {Calendar.strftime(@quest.due_on, "%d. %m. %Y")}
      </p>
      <p :if={@quest} class="adventure-reward">
        +{@quest.definition_snapshot["xp"]} XP {if @quest.scope == "shared",
          do: "chatě",
          else: "splniteli"}
      </p>
      <p :if={!@quest} class="adventure-muted">
        Vyber výpravu nebo prozkoumej, co můžeme na chatě zlepšit.
      </p>
      <button
        :if={@quest && @profile}
        type="button"
        phx-click="prepare-completion"
        phx-value-id={@quest.id}
        class="adventure-button adventure-button--primary"
      ><.symbol name="check" /> Potvrdit splnění</button>
      <button
        :if={!@quest}
        type="button"
        phx-click="find-quests"
        disabled={!@profile}
        class="adventure-button adventure-button--primary"
      ><.symbol name="compass" /> Vybrat výpravu</button>
      <span :if={!@profile} class="adventure-muted">Začni výběrem hrdiny nahoře.</span>
    </div>
    """
  end

  def success(assigns) do
    ~H"""
    <section
      :if={@success}
      id="adventure-success"
      class="adventure-success"
      role="status"
      aria-live="polite"
    >
      <.symbol name={if @success.kind == :project, do: "trophy", else: "sparkles"} /><div>
        <strong>{@success.title}</strong><p>{@success.message}</p><p :if={@success.level_up}>
          Nová úroveň! Naše dobrodružství pokračuje.
        </p>
      </div><button type="button" phx-click="dismiss-success" aria-label="Zavřít oznámení"><.icon
        name="hero-x-mark"
        class="size-5"
      /></button>
    </section>
    """
  end
end

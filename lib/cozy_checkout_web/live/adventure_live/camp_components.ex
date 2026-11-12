defmodule CozyCheckoutWeb.AdventureLive.CampComponents do
  use CozyCheckoutWeb, :html
  import CozyCheckoutWeb.AdventureLive.GameComponents
  import CozyCheckoutWeb.AdventureLive.TaskComponents, only: [profile_name: 2]

  attr :quests, :list, required: true
  attr :profile, :any, required: true
  attr :shared, :boolean, default: false

  def expeditions(assigns) do
    assigns = assign(assigns, :active, Enum.filter(assigns.quests, &(&1.status == "active")))

    ~H"""
    <section
      id={if @shared, do: "adventure-shared-expeditions", else: "adventure-expeditions"}
      class={[
        "adventure-panel",
        "adventure-expedition-panel",
        @shared && "adventure-expedition-panel--shared"
      ]}
    >
      <header class="adventure-section-heading">
        <div>
          <p class="adventure-eyebrow">
            {if @shared, do: "Jedna chata · společná odměna", else: "Tvá družina · právě na cestě"}
          </p><h2>{if @shared, do: "Společné výpravy", else: "Tvoje výpravy"}</h2>
        </div>
        <span class="adventure-count">{if @shared,
          do: "#{length(@active)} na cestě",
          else: "#{length(@active)} / 3"}</span>
      </header>
      <div
        :if={!@shared}
        class="adventure-slot-track"
        aria-label={"Obsazené sloty výprav: #{length(@active)} ze 3"}
      >
        <span
          :for={slot <- 1..3}
          class={["adventure-slot-stone", slot <= length(@active) && "is-filled"]}
        ><.symbol name={if slot <= length(@active), do: "backpack", else: "compass"} /></span>
        <p :if={!@profile}>
          Nejdřív si vyber hrdinu.
        </p>
      </div>
      <div class="adventure-active-list">
        <article
          :for={quest <- @active}
          id={"adventure-quest-#{quest.id}"}
          class="adventure-active-quest"
        >
          <span class="adventure-quest-token"><.symbol name={quest_symbol(quest.code)} /></span>
          <div class="adventure-quest-copy">
            <span class="adventure-eyebrow">{if @shared, do: "Pro naši chatu", else: "Rozpracováno"}</span><h3>
              {quest.definition_snapshot["title"]}
            </h3>
            <p :if={quest.due_on} class="adventure-muted">
              Termín {Calendar.strftime(quest.due_on, "%d. %m.")}
            </p>
            <span class="adventure-reward">+{quest.definition_snapshot["xp"]} XP {if @shared,
              do: "chatě"}</span>
          </div>
          <button
            :if={@profile}
            phx-click="prepare-completion"
            phx-value-id={quest.id}
            class="adventure-finish"
            aria-label={"Potvrdit splnění: #{quest.definition_snapshot["title"]}"}
          ><.symbol name="check" /> Hotovo</button>
        </article>
        <div :if={@active == []} class="adventure-empty adventure-empty--expedition">
          <.symbol name={if @shared, do: "flag", else: "backpack"} /><h3>
            {if @shared, do: "Společná cesta je před námi", else: "Batoh je připravený"}
          </h3>
        </div>
      </div>
      <button
        :if={!@shared}
        id="adventure-find-quest"
        phx-click={JS.push_focus(to: "#adventure-find-quest") |> JS.push("find-quests")}
        disabled={!@profile}
        class="adventure-button adventure-button--primary adventure-find-button"
      ><.symbol name="compass" /> Najít další výpravu <.icon name="hero-arrow-right" class="size-4" /></button>
    </section>
    """
  end

  attr :quests, :list, required: true
  attr :profiles, :list, required: true
  attr :profile, :any, required: true
  attr :filter, :string, required: true
  attr :search_form, :any, required: true
  attr :active_count, :integer, required: true

  def quest_picker(assigns) do
    ~H"""
    <div id="adventure-quest-picker" class="adventure-quest-picker">
      <p class="adventure-eyebrow">Nástěnka dobrodružství</p><h2 id="adventure-picker-modal-title">
        Kam vyrazíš dál?
      </h2>
      <p id="adventure-picker-modal-description" class="adventure-picker-intro">
        Osobní výpravu převezme {@profile.display_name}; společná odmění chatu.
      </p>
      <div class="adventure-book-tabs" aria-label="Nabídka výprav">
        <button
          :for={{label, value} <- [{"Pro mě", "mine"}, {"Společné", "shared"}, {"Všechny", "all"}]}
          type="button"
          phx-click="picker-filter"
          phx-value-scope={value}
          aria-pressed={to_string(@filter == value)}
        >{label}</button>
      </div>
      <.form for={@search_form} id="adventure-picker-search" phx-change="picker-search">
        <.input
          field={@search_form[:search]}
          label="Hledat výpravu"
          phx-debounce="200"
          placeholder="Název questu…"
        />
      </.form>
      <p :if={@active_count >= 3} class="adventure-slot-notice">
        Všechny tři osobní sloty jsou obsazené. Dokonči výpravu; společnou můžeš přijmout i teď.
      </p>
      <div class="adventure-picker-grid">
        <article :for={quest <- @quests} id={"pick-quest-#{quest.id}"} class="adventure-scroll-card">
          <div class="adventure-scroll-card-top">
            <span class="adventure-quest-token"><.symbol name={quest_symbol(quest.code)} /></span><span class="adventure-cadence">{if quest.template_id,
              do: "Opakovaná",
              else: "Jednorázová"} · {quest.category}</span>
          </div>
          <h3>{quest.definition_snapshot["title"]}</h3>
          <details :if={quest.description not in [nil, ""]} class="adventure-quest-description">
            <summary>Popis questu</summary><p>{quest.description}</p>
          </details>
          <p class="adventure-muted">
            {if quest.scope == "shared",
              do: "Společná chata",
              else: profile_name(@profiles, quest.assigned_profile_id)}
          </p>
          <p :if={quest.due_on} class="adventure-muted">
            Termín {Calendar.strftime(quest.due_on, "%d. %m. %Y")}
          </p>
          <div class="adventure-scroll-card-footer">
            <span class="adventure-reward">+{quest.definition_snapshot["xp"]} XP {if quest.scope ==
                                                                                       "shared",
                                                                                     do: "chatě"}</span><button
              type="button"
              phx-click="start-task"
              phx-value-id={quest.id}
              disabled={quest.scope != "shared" && @active_count >= 3}
              class="adventure-button adventure-button--primary"
            >{if quest.scope == "shared", do: "Vyrazit společně", else: "Přijmout výpravu"}</button>
          </div>
        </article>
      </div>
      <div :if={@quests == []} class="adventure-empty">
        <.symbol name="notebook-pen" /><h3>Tady zatím žádná výprava nečeká</h3><p>
          Připrav zadání nebo spusť opakovanou šablonu v knize questů.
        </p>
      </div>
      <.link
        navigate={~p"/admin/adventure/quests"}
        class="adventure-text-link adventure-picker-manage"
      ><.symbol name="notebook-pen" /> Otevřít knihu questů · správa zadání</.link>
    </div>
    """
  end
end

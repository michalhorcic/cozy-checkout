defmodule CozyCheckoutWeb.AdventureLive.OperationComponents do
  use CozyCheckoutWeb, :html
  import CozyCheckoutWeb.AdventureLive.GameComponents, only: [symbol: 1]
  alias CozyCheckout.Adventure.Sources.Operation
  alias CozyCheckout.Adventure.{Quest, Tasks}
  import CozyCheckoutWeb.KitchenComponents, only: [searchable_picker: 1]

  import CozyCheckoutWeb.AdventureLive.ProjectComponents,
    only: [format_project_date: 1, audit_datetime: 1]

  import CozyCheckoutWeb.AdventureLive.TaskComponents, only: [profile_name: 2]

  attr :snapshot, :any, required: true
  attr :checked_at, :any, required: true
  attr :state, :atom, required: true
  attr :area, :string, required: true
  attr :world, :map, required: true
  attr :chronicle, :any, required: true
  attr :chronicle_page, :integer, required: true
  attr :profiles, :list, required: true
  attr :duty_links, :map, default: %{}
  attr :profile, :any, default: nil

  def operation_world(assigns) do
    assigns =
      assign(assigns, :places, [
        {"reception", "Recepce", "house"},
        {"rooms", "Pokoje", "mountain-snow"},
        {"kitchen", "Kuchyně", "utensils"},
        {"bar", "Bar", "backpack"},
        {"treasury", "Pokladnice", "coins"},
        {"workshop", "Dílna", "notebook-pen"}
      ])

    ~H"""
    <section
      id="adventure-world-map"
      class="adventure-panel adventure-operation"
      aria-labelledby="operation-title"
      aria-busy={@state == :loading}
    >
      <header class="adventure-section-heading">
        <div>
          <p class="adventure-eyebrow">Jedna chata · dnešní služba</p><h2 id="operation-title">
            Život pod střechou
          </h2>
        </div>
        <button
          id="adventure-operation-refresh"
          type="button"
          phx-click="refresh-operation"
          disabled={@state == :loading}
          class="adventure-button"
        >Obnovit provoz</button>
      </header>
      <.operation_status {assigns} />
      <.service_day {assigns} />
      <div class="adventure-operation-layout">
        <.village {assigns} />
        <.area_detail {assigns} />
      </div>
      <.cabin_chronicle {assigns} />
    </section>
    """
  end

  def operation_status(assigns) do
    assigns = assign(assigns, :places, places())

    ~H"""
    <div id={assigns[:id] || "adventure-operation-status"} role="status" aria-live="polite">
      <p :if={@state == :loading}>Načítám společný provozní přehled…</p>
      <p :if={@state == :error} class="adventure-operation-warning">
        Provoz se nepodařilo načíst. Zkus ruční obnovu.
        <span :if={@snapshot}>Poslední dostupné údaje níže nejsou čerstvé.</span>
      </p>
      <p :if={@snapshot} class="adventure-muted">
        Provoz pro {date(@snapshot.today)} · načteno <time datetime={
          DateTime.to_iso8601(@snapshot.loaded_at)
        }>{Calendar.strftime(@snapshot.loaded_at, "%H:%M UTC")}</time>.
        Bez automatické obnovy.
        <strong :if={Operation.stale?(@snapshot, @checked_at) or @state == :error}>Starší údaje, obnov přehled.</strong>
      </p>
    </div>
    """
  end

  def service_day(assigns) do
    assigns =
      assigns
      |> assign_new(:duty_tab, fn -> "issues" end)
      |> assign_new(:duty_follow_up, fn -> nil end)
      |> assign_new(:duty_follow_up_error, fn -> false end)
      |> assign_new(:profiles, fn -> [] end)
      |> assign_new(:state, fn -> :ready end)
      |> assign_new(:checked_at, fn -> DateTime.utc_now() end)

    ~H"""
    <section
      id="adventure-service-day"
      class="adventure-service-day"
      aria-label="Podněty a otevřená práce"
    >
      <nav class="adventure-duty-tabs" aria-label="Služba dne">
        <button
          type="button"
          phx-click="duty-tab"
          phx-value-tab="issues"
          aria-pressed={to_string(@duty_tab == "issues")}
          class="adventure-button"
        >Podněty</button>
        <button
          type="button"
          id="adventure-duty-work-tab"
          phx-click="duty-tab"
          phx-value-tab="work"
          aria-pressed={to_string(@duty_tab == "work")}
          class="adventure-button"
        >Otevřená práce</button>
      </nav>
      <div hidden={@duty_tab != "issues"}>
        <div :if={@snapshot}>
          <header>
            <h3 id="service-day-title">Služba dne · {date(@snapshot.today)}</h3><p class="adventure-muted">
              Podněty do {date(@snapshot.through)} · uvedené datum je příjezd, ne vznik závady.
            </p>
          </header>
          <p :if={@snapshot.issues == []}>
            Bez hlášených podnětů. Nejde o potvrzení připravenosti chaty.
          </p>
          <ul>
            <li
              :for={{issue, index} <- @snapshot.issues |> Enum.take(4) |> Enum.with_index()}
              id={"adventure-duty-#{index}"}
            >
              <span><strong>{if issue.kind == :details, do: "Podklady stravování", else: "Jídelníček"}</strong>
              · příjezd {date(issue.on)}<br />{issue.reason}</span>
              <.link href={~p"/admin/bookings/#{issue.booking_id}"} class="adventure-text-link">Otevřít pobyt</.link>
              <.duty_actions
                issue={issue}
                link={@duty_links[Tasks.duty_key(issue)]}
                profile={@profile}
              />
            </li>
          </ul>
          <p :if={length(@snapshot.issues) > 4}>
            Dalších podnětů: {length(@snapshot.issues) - 4}.
            <.link href={~p"/admin/meal-planner"} class="adventure-text-link">Zkontrolovat v plánu jídel</.link>
          </p>
        </div>
        <p :if={!@snapshot}>Podněty zatím nejsou dostupné. Otevřenou práci můžeš najít i bez nich.</p>
      </div>
      <div hidden={@duty_tab != "work"}>
        <.duty_work
          follow_up={@duty_follow_up}
          error={@duty_follow_up_error}
          snapshot={@snapshot}
          state={@state}
          checked_at={@checked_at}
          profiles={@profiles}
        />
      </div>
    </section>
    """
  end

  defp duty_work(assigns) do
    ~H"""
    <section id="adventure-duty-work" aria-labelledby="adventure-duty-work-title">
      <header class="adventure-duty-work-heading">
        <div>
          <h3 id="adventure-duty-work-title">Otevřená práce</h3>
          <p class="adventure-muted">
            Čekající a rozpracované questy obou hrdinů i společné chaty. Zůstávají tu i po zmizení podnětu.
          </p>
        </div>
        <button type="button" phx-click="refresh-duty-work" class="adventure-button">Obnovit práci</button>
      </header>
      <p :if={@error} role="status" class="adventure-operation-warning">
        Práci se nepodařilo načíst. Zkus obnovu práce.
        <span :if={@follow_up}>Níže je poslední dostupný seznam; stav práce nemusí být aktuální.</span>
      </p>
      <div :if={@follow_up}>
        <p class="adventure-muted">
          Práce načtena <time datetime={DateTime.to_iso8601(@follow_up.loaded_at)}>{Calendar.strftime(@follow_up.loaded_at, "%H:%M UTC")}</time>. Bez automatické obnovy.
        </p>
        <p :if={@follow_up.quests == []}>
          Na této stránce není žádná otevřená práce ze Služby dne. Nejde o potvrzení připravenosti chaty.
        </p>
        <p :if={@snapshot} class="adventure-muted">
          Výhled podkladu: {date(@snapshot.today)} až {date(@snapshot.through)}.
        </p>
        <details class="adventure-duty-explanation">
          <summary>Jak číst stav podkladu</summary>
          <p>
            Porovnáváme celou poslední provozní projekci, ne pouze čtyři viditelné podněty. Nepřítomný podnět mohl změnit datum, vypadnout z výhledu nebo být odstraněn. Neznamená to vyřešení. Starší údaje ani neúspěšná obnova nepotvrzují aktuální stav. Splnění práce vždy potvrzuje člověk.
          </p>
        </details>
        <ul class="adventure-duty-work-list">
          <li :for={quest <- @follow_up.quests} id={"adventure-duty-work-#{quest.id}"}>
            <h4>{quest.definition_snapshot["title"]}</h4>
            <p>
              <strong>Práce: {duty_status(quest)}</strong>
              · {profile_name(@profiles, quest.assigned_profile_id || quest.profile_id)} · {if quest.scope ==
                                                                                                 "shared",
                                                                                               do:
                                                                                                 "Společná chata",
                                                                                               else:
                                                                                                 "Osobní odměna"}
            </p>
            <.duty_source_status
              quest={quest}
              snapshot={@snapshot}
              state={@state}
              checked_at={@checked_at}
              compact={true}
            />
            <div class="flex flex-wrap gap-3">
              <button
                type="button"
                phx-click="open-duty-quest"
                phx-value-id={quest.id}
                class="adventure-button adventure-button--primary"
              >Otevřít quest</button>
              <button
                type="button"
                phx-click="duty-history"
                phx-value-source={quest.source_ref <> ":" <> quest.source_type}
                class="adventure-text-link"
              >Historie podnětu</button>
            </div>
          </li>
        </ul>
        <nav class="adventure-duty-pagination" aria-label="Stránky otevřené práce">
          <button
            :if={@follow_up.page > 0}
            type="button"
            phx-click="duty-work-page"
            phx-value-direction="previous"
            class="adventure-button"
          >Předchozí práce</button>
          <span>Strana {@follow_up.page + 1}</span>
          <button
            :if={@follow_up.more?}
            type="button"
            phx-click="duty-work-page"
            phx-value-direction="next"
            class="adventure-button"
          >Další práce</button>
        </nav>
      </div>
    </section>
    """
  end

  defp duty_source_status(assigns) do
    assigns = assign_new(assigns, :compact, fn -> false end)

    assigns =
      assign(
        assigns,
        :source_status,
        Operation.duty_source_status(
          assigns.quest,
          assigns.snapshot,
          assigns.state,
          assigns.checked_at
        )
      )

    ~H"""
    <p class="adventure-duty-source-status" data-source-status={@source_status}>
      <strong>Podklad:</strong>
      <span :if={@source_status == :present}>Podnět potvrzený posledním načtením.</span>
      <span :if={@source_status == :changed}>Podnět je v přehledu, jeho údaje se od založení questu změnily.</span>
      <span :if={@source_status == :absent}>{if @compact,
        do: "Nelze ověřit; podnět není v přehledu.",
        else:
          "Nelze ověřit. Podnět není v aktuálním přehledu; mohl se změnit nebo vypadnout z časového výhledu. Neznamená to vyřešení."}</span>
      <span :if={@source_status == :stale}>Nelze ověřit. Provozní údaje jsou starší, obnov přehled.</span>
      <span :if={@source_status == :unavailable}>Nelze ověřit. Provozní přehled se načítá nebo poslední obnova není dostupná.</span>
      <small :if={@snapshot && !@compact}>Poslední načtení {audit_datetime(@snapshot.loaded_at)} · výhled {date(
        @snapshot.today
      )} až {date(@snapshot.through)}.</small>
    </p>
    """
  end

  def village(assigns) do
    assigns = assign(assigns, :places, places())

    ~H"""
    <nav class="adventure-village" aria-label="Oblasti chaty">
      <img
        class="adventure-village-land"
        src={~p"/images/adventure/cabin-world.svg"}
        alt="Jedna horská chata s odkrytým interiérem: pokoje a pracovní koutky v patře, recepce, kuchyně a bar v přízemí"
        width="1200"
        height="800"
        fetchpriority="high"
      />
      <button
        :for={{key, label, icon} <- @places}
        id={"adventure-area-#{key}"}
        type="button"
        phx-click="operation-area"
        phx-value-area={key}
        aria-pressed={to_string(@area == key)}
        aria-controls="adventure-area-detail"
        class={[
          "adventure-village-place",
          "adventure-village-place--#{key}",
          assigns[:highlight] == key && "adventure-village-place--new",
          key != "workshop" && area_count(@world, key, ["accepted"]) > 0 &&
            "adventure-village-place--developed"
        ]}
      >
        <span class="adventure-place-label"><.symbol name={icon} /><strong>{label}</strong></span>
        <span class="adventure-place-summary">{summary(key, @snapshot)}</span>
        <span
          :if={key != "workshop" && area_count(@world, key, ["accepted"]) > 0}
          class="adventure-world-decoration"
          role="img"
          aria-label={"#{area_count(@world, key, ["accepted"])} převzatých zlepšení"}
        >
          <.symbol name="flag" /><.symbol
            :if={area_count(@world, key, ["accepted"]) >= 2}
            name="trophy"
          />
        </span>
      </button>
    </nav>
    """
  end

  def area_detail(assigns) do
    assigns = assign(assigns, :places, places())

    ~H"""
    <section
      id="adventure-area-detail"
      class="adventure-area-detail"
      aria-label="Detail vybrané oblasti"
      aria-live="polite"
    >
      <p class="adventure-eyebrow">
        {Enum.find_value(@places, fn {key, label, _} -> key == @area && label end)}
      </p>
      <div :if={@area in ["reception", "rooms"]}>
        <h3>Kalendář, ne hlášení přítomnosti</h3>
        <dl :if={@snapshot} class="adventure-operation-counts">
          <div>
            <dt>Příjezdy skupin dnes</dt><dd>{@snapshot.arrivals}</dd>
          </div>
          <div>
            <dt>Odjezdy skupin dnes</dt><dd>{@snapshot.departures}</dd>
          </div>
          <div>
            <dt>Osob podle kalendáře</dt><dd>{@snapshot.occupancy} / {@snapshot.capacity}</dd>
          </div>
        </dl>
        <p>
          Obsazenost zahrnuje příjezd, ne odjezd. Neověřuje přítomnost hostů ani připravenost pokojů.
        </p>
        <.link href={~p"/admin/bookings/calendar"} class="adventure-text-link">Otevřít kalendář rezervací</.link>
      </div>
      <div :if={@area == "kitchen"}>
        <h3>Porce podle zadaného stravování</h3>
        <dl :if={@snapshot} class="adventure-operation-counts">
          <div :for={
            {key, label} <- [{"breakfast", "Snídaně"}, {"lunch", "Obědy"}, {"dinner", "Večeře"}]
          }>
            <dt>{label}</dt><dd>
              {if @snapshot.incomplete > 0, do: "nejméně "}{@snapshot.portions[key].total}
            </dd>
          </div>
        </dl>
        <p :if={@snapshot && @snapshot.incomplete > 0} class="adventure-operation-warning">
          Neúplné podklady pro {@snapshot.incomplete} skupin dnes. Počty jsou pouze známé porce, nikoli celková potřeba.
        </p>
        <p>Plánované porce nejsou uvařené jídlo.</p>
        <.link href={~p"/admin/meal-planner"} class="adventure-text-link">Otevřít plán jídel</.link>
      </div>
      <a :if={@area == "bar"} href="/admin/adventure?view=chronicle" class="adventure-text-link">Kronika baru</a>
      <div :if={@area == "treasury"}>
        <h3>Finance patří do kroniky</h3>
        <p>
          Sezónní inkaso a vyúčtování jsou uložené snapshoty, nikoli živý stav. Obnova provozu je nepřepočítává. Inkaso není zisk ani hodnota prodeje.
        </p>
        <a
          href="/admin/adventure?view=chronicle"
          class="adventure-text-link"
        >Přejít na kroniku sezóny a datum přepočtu</a>
        <.link :if={@area == "treasury"} href={~p"/admin/billing"} class="adventure-text-link">Otevřít doklady a platby</.link>
        <p>Tato finanční kronika neověřuje zásoby, otevřené účty ani dostupné peníze.</p>
      </div>
      <div :if={@area == "workshop"}>
        <h3>Dílna projektů</h3>
        <p>Všechny projekty chaty a jejich questy na jednom místě.</p>
        <.link navigate={~p"/admin/adventure/quests?section=projects"} class="adventure-text-link">Otevřít knihu projektů</.link>
      </div>
      <p :if={!@snapshot && @area in ["reception", "rooms", "kitchen"]}>
        Provozní údaje zatím nejsou dostupné. Neznámý stav není nula.
      </p>
      <details :if={@area != "workshop"} class="adventure-world-development">
        <summary>
          Rozvoj oblasti · {area_count(@world, @area, ["accepted"])} milníků · {area_count(
            @world,
            @area,
            ["idea", "ready", "approved", "paused"]
          )} plánů · {area_count(@world, @area, ["active"])} v realizaci
        </summary>
        <p>
          Milníky jsou lidsky převzaté výsledky, ne technická kontrola ani provozní bonus.
        </p>
        <article
          :for={project <- Enum.filter(@world.projects, &(&1.area == @area))}
          class="adventure-world-project"
        >
          <.link
            navigate={
              ~p"/admin/adventure/quests?#{%{section: "projects", project_search: project.title, project_id: project.id}}"
            }
            class="adventure-text-link"
          >{project.title}</.link>
          <span>{project_status(project.status)}{if project.archived_at, do: " · archiv"}</span>
          <.accepted_outcome
            :if={project.status == "accepted"}
            project={project}
            profiles={@profiles}
          />
        </article>
        <p :if={!Enum.any?(@world.projects, &(&1.area == @area))}>
          V posledních 100 změněných projektech zde není žádný záznam.
        </p>
        <.link
          navigate={~p"/admin/adventure/quests?#{%{section: "projects", project_area: @area}}"}
          class="adventure-text-link"
        >Plánovat další zlepšení</.link>
      </details>
    </section>
    """
  end

  def cabin_chronicle(assigns) do
    assigns = assign(assigns, :places, places())

    ~H"""
    <details
      id="adventure-cabin-chronicle"
      class="adventure-cabin-chronicle"
      aria-labelledby="cabin-chronicle-title"
      open={assigns[:expanded] || !is_nil(@chronicle)}
    >
      <summary id="cabin-chronicle-title">Kronika chaty</summary>
      <header class="adventure-section-heading">
        <p class="adventure-eyebrow">Výsledky napříč sezónami</p>
        <button phx-click="refresh-world" class="adventure-button">Obnovit rozvoj</button>
      </header>
      <p>
        Převzatá zlepšení včetně archivu, odděleně od finanční kroniky sezóny.
      </p>
      <p class="adventure-muted">
        Mapa ukazuje posledních 100 změněných projektů, počty milníků celou historii.
      </p>
      <button
        :if={is_nil(@chronicle)}
        phx-click="cabin-chronicle"
        phx-value-direction="first"
        class="adventure-button"
      >Otevřít výsledky napříč sezónami</button>
      <div :if={!is_nil(@chronicle)}>
        <p :if={@chronicle == []}>Zatím žádné další převzaté zlepšení.</p>
        <article
          :for={project <- Enum.take(@chronicle, 20)}
          id={"cabin-outcome-#{project.id}"}
          class="adventure-world-project"
        >
          <h4>
            <.link
              navigate={
                ~p"/admin/adventure/quests?#{%{section: "projects", project_search: project.title, project_id: project.id}}"
              }
              class="adventure-text-link"
            >{project.title}</.link>
          </h4>
          <p>
            {if project.area == "workshop",
              do: "Celá chata",
              else: Enum.find_value(@places, fn {key, label, _} -> key == project.area && label end)}{if project.archived_at,
              do: " · archiv"}
          </p>
          <.accepted_outcome project={project} profiles={@profiles} />
        </article>
        <nav class="flex flex-wrap gap-3" aria-label="Stránky kroniky chaty">
          <button
            :if={@chronicle_page > 0}
            phx-click="cabin-chronicle"
            phx-value-direction="previous"
            class="adventure-button"
          >Novější výsledky</button>
          <span>Strana {@chronicle_page + 1}</span>
          <button
            :if={length(@chronicle) > 20}
            phx-click="cabin-chronicle"
            phx-value-direction="next"
            class="adventure-button"
          >Starší výsledky</button>
          <button phx-click="close-cabin-chronicle" class="adventure-button">Zavřít kroniku chaty</button>
        </nav>
      </div>
    </details>
    """
  end

  def places,
    do: [
      {"treasury", "Pokladnice", "coins"},
      {"rooms", "Pokoje", "mountain-snow"},
      {"workshop", "Dílna", "wrench"},
      {"reception", "Recepce", "house"},
      {"kitchen", "Kuchyně", "utensils"},
      {"bar", "Bar", "backpack"}
    ]

  attr :issue, :map, required: true
  attr :link, :any, required: true
  attr :profile, :any, required: true

  defp duty_actions(assigns) do
    assigns = assign(assigns, :open, assigns.link && duty_open?(assigns.link.quest))

    ~H"""
    <div :if={Tasks.duty_key(@issue)} class="flex flex-wrap items-center gap-3">
      <span :if={@link}>Quest: {duty_status(@link.quest)}</span>
      <button
        :if={@open}
        type="button"
        phx-click="open-duty-quest"
        phx-value-id={@link.quest.id}
        class="adventure-button"
      >Otevřít quest</button>
      <button
        :if={!@open && @profile}
        type="button"
        phx-click="prepare-duty"
        phx-value-source={duty_token(@issue)}
        class="adventure-button"
      >{if @link, do: "Připravit další řešení", else: "Připravit quest"}</button>
      <span :if={!@open && !@profile} class="adventure-muted">Pro přípravu questu vyber hrdinu.</span>
      <button
        :if={@link}
        type="button"
        phx-click="duty-history"
        phx-value-source={duty_token(@issue)}
        class="adventure-text-link"
      >Historie podnětu ({@link.count})</button>
    </div>
    """
  end

  attr :draft, :map, required: true
  attr :form, :any, required: true
  attr :profiles, :list, required: true
  attr :profile_query, :any, required: true
  attr :profile_open, :boolean, required: true
  attr :checked_at, :any, required: true
  attr :state, :atom, required: true

  def duty_draft(assigns) do
    xp = assigns.form[:xp].value

    assigns =
      assign(
        assigns,
        :reward,
        if(xp in [nil, ""],
          do: %{"small" => 50, "medium" => 100, "large" => 250}[assigns.form[:size].value],
          else: xp
        )
      )

    ~H"""
    <div class="space-y-4">
      <h2 id="adventure-duty-modal-title" class="text-xl font-bold pr-8">
        Návrh questu ze služby dne
      </h2>
      <p id="adventure-duty-modal-description">
        Vznikne čekající quest, nikoli zahájená práce. Bez termínu, pokud ho sám nedoplníš. Stav podkladu a stav questu jsou oddělené.
      </p>
      <div id="adventure-duty-source" class="adventure-muted">
        <p>
          {if @draft.issue.kind == :details, do: "Podklady stravování", else: "Jídelníček"} · příjezd {date(
            @draft.issue.on
          )}
        </p>
        <p>{@draft.issue.reason}</p>
        <p>
          Podnět pro období {date(@draft.snapshot.today)} až {date(@draft.snapshot.through)} · načteno {Calendar.strftime(
            @draft.snapshot.loaded_at,
            "%d. %m. %Y %H:%M UTC"
          )}.
        </p>
        <p>Datum příjezdu není termín questu ani den vzniku závady.</p>
        <p
          :if={Operation.stale?(@draft.snapshot, @checked_at) or @state != :ready}
          role="status"
          class="adventure-operation-warning"
        >
          Starší nebo neověřené údaje. {if @state == :error, do: "Poslední obnova selhala. "}Zavři návrh a ručně obnov provoz, pokud potřebuješ čerstvé podklady.
        </p>
        <.link href={~p"/admin/bookings/#{@draft.issue.booking_id}"} class="adventure-text-link">Otevřít původní pobyt</.link>
      </div>
      <div :if={@draft.previous_id} id="adventure-duty-previous" class="adventure-operation-warning">
        <p>
          Předchozí quest: <strong>{@draft.previous_quest.definition_snapshot["title"]}</strong>
          · {duty_status(@draft.previous_quest)} · {@draft.previous_quest.definition_snapshot["xp"]} XP.
        </p>
        <p>
          Pro tento pobyt a typ podnětu už existuje uzavřená práce. Přetrvávající podnět neznamená, že předchozí quest nebyl splněn. Další quest zahájí nové řešení a zachová historii.
        </p>
        <button
          :if={!@draft.confirmed}
          id="adventure-duty-confirm-next"
          type="button"
          phx-click="prepare-next-duty"
          class="adventure-button"
        >Výslovně připravit další quest</button>
      </div>
      <.form
        :if={@draft.confirmed}
        for={@form}
        id="adventure-duty-form"
        phx-change="validate-duty"
        phx-submit="save-duty"
        class="grid gap-4"
      >
        <.input field={@form[:title]} label="Název questu" required maxlength="200" />
        <.searchable_picker
          field={@form[:assigned_profile_id]}
          options={[
            %{id: "", name: "Volný úkol", hint: "Bez přiřazení"}
            | Enum.map(@profiles, &%{id: &1.id, name: &1.display_name, hint: ""})
          ]}
          label="Přiřazení (nepovinné)"
          prompt="Volný úkol"
          required={false}
          index="duty-profile"
          query={@profile_query}
          open={@profile_open}
          search_name="duty_profile_query"
          search_event="duty-profile-search"
          open_event="duty-profile-open"
          close_event="duty-profile-close"
          select_event="duty-profile-select"
        />
        <.input
          field={@form[:size]}
          type="select"
          label="Velikost"
          options={[
            {"Malý · 50 XP", "small"},
            {"Střední · 100 XP", "medium"},
            {"Velký · 250 XP", "large"}
          ]}
        />
        <p id="adventure-duty-reward" class="adventure-muted">
          Po uložení: Čeká · {@reward} XP pro {if @form[:scope].value == "shared",
            do: "společnou chatu",
            else: "skutečného splnitele"}. Bez automatického zahájení nebo udělení XP.
        </p>
        <details>
          <summary>Další podrobnosti (nepovinné)</summary>
          <div class="grid gap-3 mt-3">
            <.input field={@form[:description]} type="textarea" label="Popis" maxlength="5000" />
            <.input
              field={@form[:scope]}
              type="select"
              label="Odměna pro"
              options={[{"Splnitele", "personal"}, {"Společnou chatu", "shared"}]}
            />
            <.input field={@form[:xp]} type="number" label="Vlastní XP" min="1" max="10000" />
            <.input field={@form[:due_on]} type="date" label="Termín" />
            <.input
              field={@form[:priority]}
              type="select"
              label="Priorita"
              options={[{"Nízká", "low"}, {"Běžná", "normal"}, {"Vysoká", "high"}]}
            />
            <.input
              field={@form[:category]}
              type="select"
              label="Kategorie"
              options={Quest.categories()}
            />
          </div>
        </details>
        <button
          type="submit"
          class="adventure-button adventure-button--primary"
          phx-disable-with="Ukládám…"
        >Uložit čekající quest</button>
      </.form>
      <button type="button" phx-click="cancel-duty" class="adventure-button">Zpět bez uložení</button>
    </div>
    """
  end

  attr :quest, :any, required: true
  attr :profiles, :list, required: true
  attr :profile, :any, required: true

  attr :snapshot, :any, default: nil
  attr :state, :atom, default: :loading
  attr :checked_at, :any, default: nil

  def duty_detail(assigns) do
    assigns = assign(assigns, :checked_at, assigns.checked_at || DateTime.utc_now())

    ~H"""
    <article id={"adventure-duty-quest-#{@quest.id}"} class="space-y-4 break-words">
      <h2 id="adventure-duty-detail-modal-title" class="text-xl font-bold pr-8">
        {@quest.definition_snapshot["title"]}
      </h2>
      <p id="adventure-duty-detail-modal-description">
        {if @quest.source_namespace == "operation_v1",
          do: "Quest ze služby dne",
          else: "Quest projektu"} · {duty_status(@quest)}.
        <span :if={@quest.source_namespace == "operation_v1"}>Změna provozního podkladu tento quest automaticky nedokončí.</span>
      </p>
      <p>
        {profile_name(@profiles, @quest.assigned_profile_id || @quest.profile_id)} · {@quest.definition_snapshot[
          "xp"
        ]} XP · {if @quest.scope == "shared", do: "Společná chata", else: "Osobní odměna"}
      </p>
      <p :if={@quest.due_on}>Termín: {date(@quest.due_on)}</p>
      <p :if={@quest.description not in [nil, ""]} class="whitespace-pre-wrap">
        {@quest.description}
      </p>
      <div :if={@quest.source_namespace == "operation_v1"} class="adventure-muted">
        <.duty_source_status
          quest={@quest}
          snapshot={@snapshot}
          state={@state}
          checked_at={@checked_at}
        />
        <p>Původní podnět: {@quest.source_context["reason"]}</p>
        <p>Příjezd {format_project_date(@quest.source_context["on"])} · nejde o termín questu.</p>
        <details>
          <summary>Původ podnětu</summary><p>
            Načteno {audit_datetime(@quest.source_context["loaded_at"])} · historický podklad, nikoli živé ověření.
          </p>
        </details>
        <.link href={~p"/admin/bookings/#{@quest.source_ref}"} class="adventure-text-link">Otevřít původní pobyt</.link>
      </div>
      <p :if={@quest.evidence["note"] not in [nil, ""]} class="whitespace-pre-wrap">
        {@quest.evidence["note"]}
      </p>
      <div :if={@profile && duty_open?(@quest)} class="flex flex-wrap gap-3">
        <button
          :if={@quest.status == "waiting"}
          type="button"
          phx-click="start-task"
          phx-value-id={@quest.id}
          class="adventure-button adventure-button--primary"
        >Přijmout a zahájit</button>
        <button
          :if={@quest.status == "active"}
          type="button"
          phx-click="prepare-completion"
          phx-value-id={@quest.id}
          class="adventure-button adventure-button--primary"
        >Dokončit quest</button>
        <button
          type="button"
          phx-click="archive-task"
          phx-value-id={@quest.id}
          data-confirm="Archivovat úkol? Otevřený úkol se zruší, historie zůstane."
          class="adventure-button"
        >Archivovat</button>
      </div>
      <button type="button" phx-click="close-duty-detail" class="adventure-button">Zavřít quest</button>
    </article>
    """
  end

  attr :history, :map, required: true

  def duty_history(assigns) do
    ~H"""
    <section class="space-y-4">
      <h2 id="adventure-duty-history-modal-title" class="text-xl font-bold pr-8">Historie podnětu</h2>
      <p id="adventure-duty-history-modal-description">
        {if @history.issue.kind == :details, do: "Podklady stravování", else: "Jídelníček"} · příjezd {date(
          @history.issue.on
        )}. Nejvýše 20 questů na stránce, včetně uzavřené a archivované práce.
      </p>
      <p :if={@history.quests == []}>Pro tento podnět zatím není žádný quest.</p>
      <article
        :for={quest <- @history.quests}
        id={"adventure-duty-history-#{quest.id}"}
        class="border-t py-3"
      >
        <h3>{quest.definition_snapshot["title"]}</h3>
        <p>{duty_status(quest)}</p>
        <button
          type="button"
          phx-click="open-duty-quest"
          phx-value-id={quest.id}
          class="adventure-text-link"
        >Otevřít quest</button>
      </article>
      <nav class="flex flex-wrap gap-3" aria-label="Stránky historie podnětu">
        <button
          :if={@history.page > 0}
          type="button"
          phx-click="duty-history-page"
          phx-value-direction="previous"
          class="adventure-button"
        >Novější práce</button>
        <span>Strana {@history.page + 1}</span>
        <button
          :if={@history.more?}
          type="button"
          phx-click="duty-history-page"
          phx-value-direction="next"
          class="adventure-button"
        >Starší práce</button>
      </nav>
      <button type="button" phx-click="close-duty-history" class="adventure-button">Zavřít historii</button>
    </section>
    """
  end

  defp duty_open?(quest), do: quest.status in ["waiting", "active"] && is_nil(quest.archived_at)

  defp duty_token(issue) do
    case Tasks.duty_key(issue) do
      {id, type} -> id <> ":" <> type
      _ -> nil
    end
  end

  defp duty_status(quest) do
    label =
      %{
        "waiting" => "Čeká",
        "active" => "Rozpracováno",
        "completed" => "Hotovo",
        "cancelled" => "Zrušeno"
      }[quest.status]

    if quest.archived_at, do: "#{label} · archiv", else: label
  end

  attr :project, :any, required: true
  attr :profiles, :list, required: true

  defp accepted_outcome(assigns) do
    ~H"""
    <div class="adventure-accepted-outcome">
      <p>
        Převzato {format_project_date(@project.acceptance["confirmed_at"])} · potvrdil {profile_name(
          @profiles,
          @project.acceptance["actor_id"]
        )} · vlastní prohlášení
      </p>
      <p>
        Přispěvatelé: {Enum.map_join(
          @project.acceptance["contributors"] || [],
          ", ",
          &profile_name(@profiles, &1)
        )}
      </p>
      <p :if={@project.acceptance["result"] not in [nil, ""]}>
        {@project.acceptance["result"]}
      </p>
      <details>
        <summary>Převzaté výstupy etap</summary><p :for={stage <- @project.acceptance["stages"] || []}>
          {stage["output"]}
        </p>
      </details>
    </div>
    """
  end

  def area_count(world, area, statuses),
    do:
      Enum.reduce(world.counts, 0, fn {key, status, count}, total ->
        if key == area and status in statuses, do: total + count, else: total
      end)

  defp project_status(status),
    do:
      %{
        "idea" => "Návrh",
        "ready" => "Ke schválení",
        "approved" => "Schválený plán",
        "active" => "Realizace",
        "paused" => "Pozastaveno",
        "accepted" => "Převzato",
        "cancelled" => "Zrušeno"
      }[status]

  defp date(nil), do: "neznámý"
  defp date(date), do: Calendar.strftime(date, "%d. %m. %Y")
  defp summary("reception", nil), do: "Provoz zatím neznámý"
  defp summary("reception", data), do: "#{data.arrivals} příjezdů · #{data.departures} odjezdů"
  defp summary("rooms", nil), do: "Kalendář zatím neznámý"
  defp summary("rooms", data), do: "#{data.occupancy} / #{data.capacity} osob v kalendáři"
  defp summary("kitchen", nil), do: "Porce zatím neznámé"
  defp summary("kitchen", %{incomplete: count}) when count > 0, do: "Neúplné počty porcí"

  defp summary("kitchen", data),
    do:
      "#{data.portions["breakfast"].total} · #{data.portions["lunch"].total} · #{data.portions["dinner"].total} porcí S/O/V"

  defp summary("bar", _), do: "Sklad baru · otevřít detail"
  defp summary("treasury", _), do: "Sezónní kronika · ne živě"
  defp summary("workshop", _), do: "Projekty celé chaty"
end

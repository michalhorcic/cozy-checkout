defmodule CozyCheckoutWeb.AdventureLive.OperationComponents do
  use CozyCheckoutWeb, :html
  import CozyCheckoutWeb.AdventureLive.GameComponents, only: [symbol: 1]
  alias CozyCheckout.Adventure.Sources.Operation
  import CozyCheckoutWeb.AdventureLive.ProjectComponents, only: [format_project_date: 1]
  import CozyCheckoutWeb.AdventureLive.TaskComponents, only: [profile_name: 2]

  attr :snapshot, :any, required: true
  attr :checked_at, :any, required: true
  attr :state, :atom, required: true
  attr :area, :string, required: true
  attr :world, :map, required: true
  attr :chronicle, :any, required: true
  attr :chronicle_page, :integer, required: true
  attr :profiles, :list, required: true

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
      <div id="adventure-operation-status" role="status" aria-live="polite">
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
      <div class="adventure-operation-layout">
        <nav class="adventure-village" aria-label="Oblasti chaty">
          <div class="adventure-village-land" aria-hidden="true"><span>Jindřichův dům</span></div>
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
              area_count(@world, key, ["accepted"]) > 0 && "adventure-village-place--developed"
            ]}
          >
            <.symbol name={icon} /><strong>{label}</strong><span>{summary(key, @snapshot)}</span>
            <span class="adventure-world-milestone">{area_count(@world, key, ["accepted"])} převzatých zlepšení</span>
            <span class="adventure-world-plans">{area_count(@world, key, [
              "idea",
              "ready",
              "approved",
              "paused"
            ])} plánů · {area_count(@world, key, ["active"])} v realizaci</span>
          </button>
        </nav>
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
              Příjezd je zahrnut, odjezd vyloučen z obsazenosti. Rezervace nedokazuje fyzickou přítomnost, čistotu ani připravenost pokoje.
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
            <p>Plánované porce nejsou uvařené jídlo. Menu a podklady kontroluj ve službě dne.</p>
            <.link href={~p"/admin/meal-planner"} class="adventure-text-link">Otevřít plán jídel</.link>
          </div>
          <div :if={@area in ["bar", "treasury"]}>
            <h3>Finance patří do kroniky</h3>
            <p>
              Sezónní inkaso a vyúčtování jsou uložené snapshoty, nikoli živý stav. Obnova provozu je nepřepočítává. Inkaso není zisk ani hodnota prodeje.
            </p>
            <a href="#adventure-shared" class="adventure-text-link">Přejít na kroniku sezóny a datum přepočtu</a>
            <.link :if={@area == "bar"} href={~p"/admin/bar-stock"} class="adventure-text-link">Otevřít sklad baru</.link>
            <.link :if={@area == "treasury"} href={~p"/admin/billing"} class="adventure-text-link">Otevřít doklady a platby</.link>
            <p>Mapa zde neověřuje zásoby, otevřené účty ani dostupné peníze.</p>
          </div>
          <div :if={@area == "workshop"}>
            <h3>Místo pro příští zlepšení</h3>
            <p>
              Vlastní projekty propojují plánované zlepšení s existujícími questy. Rozpočet je jen plán; převzetí výsledku vždy výslovně potvrdí člověk, bez dalších XP.
            </p>
            <.link navigate={~p"/admin/adventure/quests?section=projects"} class="adventure-text-link">Otevřít knihu projektů</.link>
          </div>
          <p :if={!@snapshot && @area in ["reception", "rooms", "kitchen"]}>
            Provozní údaje zatím nejsou dostupné. Neznámý stav není nula.
          </p>
          <section class="adventure-world-development" aria-label="Rozvoj oblasti">
            <h3>Rozvoj oblasti · {area_count(@world, @area, ["accepted"])} trvalých milníků</h3>
            <p>
              Milník vzniká až lidským převzetím. Archivace ho neodstraní. Nejde o technickou kontrolu ani provozní bonus.
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
            <.link navigate={~p"/admin/adventure/quests?section=projects"} class="adventure-text-link">Plánovat další zlepšení</.link>
          </section>
        </section>
      </div>
      <section
        id="adventure-cabin-chronicle"
        class="adventure-cabin-chronicle"
        aria-labelledby="cabin-chronicle-title"
      >
        <header class="adventure-section-heading">
          <div>
            <p class="adventure-eyebrow">Trvalý rozvoj napříč sezónami</p><h3 id="cabin-chronicle-title">
              Kronika chaty
            </h3>
          </div>
          <button phx-click="refresh-world" class="adventure-button">Obnovit rozvoj</button>
        </header>
        <p>
          Výsledky výslovně převzatých projektů včetně archivu. Samostatná historie zlepšení, nikoli finanční Kronika sezóny. Bez dalších XP.
        </p>
        <p class="adventure-muted">
          Mapa a detail zobrazují nejvýše 100 naposledy změněných projektů; počty milníků zahrnují celou historii. Starší výsledky otevři výslovně níže.
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
              {Enum.find_value(@places, fn {key, label, _} -> key == project.area && label end)}{if project.archived_at,
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
      </section>
      <section
        :if={@snapshot}
        id="adventure-service-day"
        class="adventure-service-day"
        aria-labelledby="service-day-title"
      >
        <header>
          <h3 id="service-day-title">Služba dne · {date(@snapshot.today)}</h3><p class="adventure-muted">
            Podněty z Přehledu do {date(@snapshot.through)}. Datum u podnětu je příjezd skupiny, nikoli den vzniku závady.
          </p>
        </header>
        <p :if={@snapshot.issues == []}>
          Zdroj v tomto období nehlásí chybějící podklady ani problém menu. Není to potvrzení připravenosti chaty.
        </p>
        <ul>
          <li :for={issue <- Enum.take(@snapshot.issues, 4)}>
            <span><strong>{if issue.kind == :details, do: "Podklady stravování", else: "Jídelníček"}</strong>
            · příjezd {date(issue.on)}<br />{issue.reason}</span>
            <.link href={~p"/admin/bookings/#{issue.booking_id}"} class="adventure-text-link">Otevřít pobyt</.link>
          </li>
        </ul>
        <p :if={length(@snapshot.issues) > 4}>
          Dalších podnětů: {length(@snapshot.issues) - 4}.
          <.link href={~p"/admin/meal-planner"} class="adventure-text-link">Zkontrolovat v plánu jídel</.link>
        </p>
      </section>
      <p class="adventure-muted">
        Pouze čtení. Prohlížení ani obnova nezakládají questy a neudělují XP.
        <.link href={~p"/admin"} class="adventure-text-link">Celá aplikace</.link>
      </p>
    </section>
    """
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

  defp area_count(world, area, statuses),
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

  defp summary("bar", _), do: "Sezónní kronika · ne živě"
  defp summary("treasury", _), do: "Sezónní kronika · ne živě"
  defp summary("workshop", _), do: "Vlastní plány a etapy"
end

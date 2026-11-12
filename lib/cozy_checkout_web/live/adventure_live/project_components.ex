defmodule CozyCheckoutWeb.AdventureLive.ProjectComponents do
  use CozyCheckoutWeb, :html
  alias CozyCheckout.Adventure.{Project, Quest}
  alias CozyCheckoutWeb.CurrencyHelper
  import CozyCheckoutWeb.AdventureLive.GameComponents, only: [symbol: 1]

  attr :projects, :list, required: true
  attr :selected_id, :any, required: true
  attr :history, :list, required: true
  attr :profiles, :list, required: true
  attr :form, :any, required: true
  attr :quest_results, :list, required: true
  attr :editing_id, :any, required: true
  attr :editor_open, :boolean, required: true
  attr :search, :string, required: true
  attr :stage_editor, :any, required: true
  attr :stage_form, :any, required: true
  attr :acceptance_open, :boolean, required: true

  def projects(assigns) do
    assigns =
      assign(
        assigns,
        :selected,
        Enum.find(assigns.projects, &(&1.project.id == assigns.selected_id))
      )

    ~H"""
    <section id="adventure-projects" class="adventure-panel adventure-projects">
      <header class="adventure-section-heading flex-wrap">
        <div>
          <p class="adventure-eyebrow">Dílna · zlepšení, která zůstávají</p><h2>Kniha projektů</h2>
        </div>
        <div class="adventure-project-tools">
          <button type="button" phx-click="refresh-projects" class="adventure-button">Obnovit</button>
          <button
            type="button"
            phx-click="new-project"
            class="adventure-button adventure-button--primary"
          ><.symbol name="notebook-pen" />Nový projekt</button>
        </div>
      </header>
      <details id="project-help" class="adventure-project-disclosure">
        <summary>Jak projekty fungují</summary>
        <div>
          <p>
            Návrh → Realizace → Převzato. Schválení a zahájení uzamkne plán i kroky, ale nespustí jejich questy. Každý krok propojuje očekávaný výsledek s jedním skutečným questem.
          </p>
          <p>
            Questy přijmi a dokonči v táboře. XP patří pouze questům; projekt nepřidává druhou odměnu. Převzetí vždy výslovně potvrdí člověk s výběrem přispěvatelů.
          </p>
          <p>
            Rozpočet je pouze odhad, ne hotovost, skutečné náklady ani rezervace peněz. Schválení není objednávka. Převzetí je vlastní prohlášení, ne technická nebo účetní kontrola; nemění provozní čísla.
          </p>
          <p>
            Projekty a historie zůstávají napříč sezónami. Odpojení kroku ani zrušení projektu nemění jeho quest. Reference je pouze text; neuváděj osobní údaje hostů.
          </p>
        </div>
      </details>

      <section
        :if={@editor_open}
        id="adventure-project-editor"
        class="adventure-project-editor"
        aria-labelledby="project-editor-title"
      >
        <header class="adventure-section-heading">
          <h3 id="project-editor-title">
            {if @editing_id, do: "Upravit návrh", else: "Nové zlepšení chaty"}
          </h3>
          <button type="button" phx-click="close-project-editor" class="adventure-button">Zavřít</button>
        </header>
        <.form for={@form} id="project-form" phx-submit="save-project" class="adventure-project-form">
          <input type="hidden" name="project[request_key]" value={@form[:request_key].value} />
          <div class="adventure-project-fields">
            <.input field={@form[:title]} label="Název projektu" required maxlength="200" />
            <.input field={@form[:area]} type="select" label="Oblast chaty" options={areas()} />
          </div>
          <details
            id="project-optional-fields"
            class="adventure-project-disclosure"
            open={@form.errors != []}
          >
            <summary>Další podrobnosti <span>nepovinné</span></summary>
            <div class="adventure-project-fields">
              <.input
                field={@form[:purpose]}
                type="textarea"
                label="Co chceme zlepšit"
                maxlength="5000"
              />
              <.input
                field={@form[:owner_id]}
                type="select"
                label="Odpovědný hrdina"
                prompt="Zatím neurčeno"
                options={Enum.map(@profiles, &{&1.display_name, &1.id})}
              />
              <.input field={@form[:due_on]} type="date" label="Plánovaný termín (nepovinný)" />
              <.input
                field={@form[:budget]}
                type="number"
                label="Odhad rozpočtu (nepovinný)"
                min="0"
                step="0.01"
              />
              <.input field={@form[:currency]} label="Měna odhadu (ISO)" maxlength="3" />
              <.input
                field={@form[:price_basis]}
                type="select"
                label="Základ ceny"
                options={[
                  {"Včetně DPH", "including_vat"},
                  {"Bez DPH", "excluding_vat"},
                  {"Neurčeno", "unknown"}
                ]}
              />
              <.input field={@form[:reference]} label="Reference na podklady" maxlength="1000" />
            </div>
          </details>
          <button class="adventure-button adventure-button--primary" phx-disable-with="Ukládám…">Uložit plán</button>
        </.form>
      </section>

      <.form
        for={%{}}
        as={:projects}
        id="project-filter"
        phx-submit="filter-projects"
        class="adventure-project-search"
      >
        <.input
          name="projects[query]"
          value={@search}
          label="Hledat projekt i v archivu"
          maxlength="200"
        />
        <button class="adventure-button">Hledat</button>
      </.form>
      <div :if={@projects == []} class="adventure-empty">
        <.symbol name="wrench" /><h3>
          {if @search == "", do: "Místo pro další zlepšení", else: "Žádný odpovídající projekt"}
        </h3>
        <p>
          {if @search == "",
            do: "Začni názvem a oblastí chaty. Kroky přidáš potom.",
            else: "Zkus jiný název nebo zruš hledání."}
        </p>
      </div>
      <div class="adventure-project-list" aria-label="Projekty">
        <button
          :for={row <- @projects}
          id={"project-#{row.project.id}"}
          type="button"
          phx-click="select-project"
          phx-value-id={row.project.id}
          aria-pressed={@selected_id == row.project.id}
          aria-controls="project-detail"
          class="adventure-project-card"
        >
          <span class="adventure-project-card-top"><span>{area(row.project.area)}{if row.project.archived_at,
            do: " · Archiv"}</span><span class={"adventure-project-status adventure-project-status--#{row.project.status}"}>{status(
            row.project.status
          )}</span></span>
          <strong>{row.project.title}</strong>
          <span class="adventure-project-card-bottom"><span>{progress(row.stages)}</span><span :if={
            row.project.due_on
          }>Do {format_project_date(row.project.due_on)}</span></span>
        </button>
      </div>
      <p class="adventure-muted adventure-project-limit">
        Nejvýše 100 nejnovějších shod. Starší projekt vyhledej názvem.
      </p>

      <section
        :if={@selected}
        id="project-detail"
        class="adventure-project-detail"
        aria-labelledby="project-detail-title"
      >
        <header class="adventure-project-detail-heading">
          <div>
            <p class="adventure-eyebrow">
              {area(@selected.project.area)}{if @selected.project.archived_at, do: " · Archiv"}
            </p><h3 id="project-detail-title">{@selected.project.title}</h3>
          </div>
          <span class={"adventure-project-status adventure-project-status--#{@selected.project.status}"}>{status(
            @selected.project.status
          )}</span>
        </header>
        <ol class="adventure-project-path" aria-label="Postup projektu">
          <li aria-current={if @selected.project.status in ["idea", "ready"], do: "step"}>
            1. Návrh
          </li>
          <li aria-current={
            if @selected.project.status in ["approved", "active", "paused"], do: "step"
          }>
            2. Realizace
          </li>
          <li aria-current={if @selected.project.status == "accepted", do: "step"}>3. Převzato</li>
        </ol>
        <p :if={present?(@selected.project.purpose)} class="adventure-project-copy">
          {@selected.project.purpose}
        </p>
        <dl class="adventure-project-meta">
          <div :if={@selected.project.owner_id}>
            <dt>Odpovědnost</dt><dd>{profile(@profiles, @selected.project.owner_id)}</dd>
          </div>
          <div :if={@selected.project.due_on}>
            <dt>Plánovaný termín</dt><dd>{format_project_date(@selected.project.due_on)}</dd>
          </div>
          <div :if={@selected.project.budget}>
            <dt>Odhad, ne skutečné náklady</dt><dd>
              {CurrencyHelper.format_number(@selected.project.budget)} {@selected.project.currency} · {basis(
                @selected.project.price_basis
              )}
            </dd>
          </div>
          <div :if={present?(@selected.project.reference)}>
            <dt>Podklady</dt><dd>{@selected.project.reference}</dd>
          </div>
        </dl>
        <div :if={!@selected.project.archived_at} class="adventure-project-next">
          <div class="adventure-project-tools">
            <button
              :for={{target, label} <- actions(@selected.project.status)}
              type="button"
              phx-click="project-status"
              phx-value-id={@selected.project.id}
              phx-value-status={target}
              class={[
                "adventure-button",
                target == "active" && "adventure-button--primary",
                target == "cancelled" && "adventure-project-danger"
              ]}
              data-confirm={
                if target == "cancelled", do: "Zrušit projekt? Připojené questy zůstanou beze změny."
              }
            >{label}</button>
            <button
              :if={editable?(@selected.project)}
              type="button"
              phx-click="edit-project"
              phx-value-id={@selected.project.id}
              class="adventure-button"
            >Upravit plán</button>
            <button
              :if={@selected.project.status in ["accepted", "cancelled"]}
              type="button"
              phx-click="archive-project"
              phx-value-id={@selected.project.id}
              class="adventure-button"
            >Archivovat s historií</button>
          </div>
          <p :if={editable?(@selected.project)} class="adventure-muted">
            Schválením uzamkneš plán i kroky. Questy tím ještě nezahájíš.
          </p>
        </div>

        <section class="adventure-project-steps" aria-labelledby="project-steps-title">
          <header class="adventure-section-heading">
            <div>
              <h4 id="project-steps-title">
                Kroky projektu <span class="adventure-count">{progress(@selected.stages)}</span>
              </h4><p class="adventure-muted">
                Každý krok je quest. Práci přijmi a dokonči v táboře.
              </p>
            </div>
          </header>
          <p :if={@selected.stages == []} class="adventure-muted">
            {if editable?(@selected.project),
              do: "Přidej první konkrétní práci, která vede k výsledku.",
              else: "Projekt nemá žádné připojené kroky."}
          </p>
          <ol class="adventure-project-stage-list">
            <li
              :for={{{stage, quest}, index} <- Enum.with_index(@selected.stages, 1)}
              id={"project-stage-#{stage.id}"}
              class="adventure-project-stage"
            >
              <div class="adventure-project-stage-heading">
                <span class={[
                  "adventure-project-step-number",
                  quest.status == "completed" && "adventure-project-step-number--done"
                ]}>{index}</span><div>
                  <strong>{stage.output}</strong><p
                    :if={stage.output != quest.definition_snapshot["title"]}
                    class="adventure-muted"
                  >
                    Quest: {quest.definition_snapshot["title"]}
                  </p>
                </div><span class="adventure-project-status">{quest_status(quest.status)}{if quest.archived_at,
                  do: " · Archiv"}</span>
              </div>
              <p
                :if={stage.quest_snapshot["title"] != quest.definition_snapshot["title"]}
                class="adventure-muted"
              >
                Původní quest: {stage.quest_snapshot["title"]}
              </p>
              <p :if={quest.due_on} class="adventure-muted">
                Termín questu: {format_project_date(quest.due_on)}
              </p>
              <button
                :if={editable?(@selected.project) && @stage_editor != stage.id}
                type="button"
                phx-click="project-stage-editor"
                phx-value-mode={stage.id}
                class="adventure-button"
              >Upravit krok</button>
              <.form
                :if={editable?(@selected.project) && @stage_editor == stage.id}
                for={%{}}
                as={:stage}
                id={"project-stage-edit-#{stage.id}"}
                phx-submit="edit-project-stage"
                class="adventure-project-form"
              >
                <input type="hidden" name="stage[id]" value={stage.id} />
                <.input
                  name="stage[output]"
                  value={stage.output}
                  label="Očekávaný výsledek kroku"
                  required
                  maxlength="2000"
                />
                <div class="adventure-project-tools">
                  <button class="adventure-button adventure-button--primary">Uložit výsledek</button><button
                    type="button"
                    phx-click="project-stage-editor"
                    phx-value-mode="close"
                    class="adventure-button"
                  >Zpět</button><button
                    type="button"
                    phx-click="remove-project-stage"
                    phx-value-id={stage.id}
                    class="adventure-button adventure-project-danger"
                  >Odpojit krok</button>
                </div>
              </.form>
            </li>
          </ol>
          <div :if={editable?(@selected.project)} class="adventure-project-add">
            <div class="adventure-project-tools">
              <button
                type="button"
                phx-click="project-stage-editor"
                phx-value-mode="new"
                aria-expanded={@stage_editor == "new"}
                aria-controls="project-new-stage"
                class="adventure-button adventure-project-add-button"
              ><.symbol name="notebook-pen" />Nový krok</button>
              <button
                type="button"
                phx-click="project-stage-editor"
                phx-value-mode="link"
                aria-expanded={@stage_editor == "link"}
                aria-controls="project-link-stage"
                class="adventure-button"
              >Připojit existující quest</button>
            </div>
            <section
              :if={@stage_editor == "new"}
              id="project-new-stage"
              class="adventure-project-editor"
              aria-label="Nový krok"
            >
              <.form
                for={@stage_form}
                id="project-new-stage-form"
                phx-submit="create-project-stage"
                class="adventure-project-form"
              >
                <.input field={@stage_form[:title]} label="Název kroku" required maxlength="200" />
                <details class="adventure-project-disclosure" open={@stage_form.errors != []}>
                  <summary>Upřesnění a nastavení questu <span>nepovinné</span></summary>
                  <div class="adventure-project-fields">
                    <.input
                      name="step[output]"
                      value={@stage_form.params["output"] || ""}
                      label="Očekávaný výsledek (jinak název kroku)"
                      maxlength="2000"
                    />
                    <.input
                      field={@stage_form[:description]}
                      type="textarea"
                      label="Popis práce"
                      maxlength="5000"
                    />
                    <.input
                      field={@stage_form[:due_on]}
                      type="date"
                      label="Termín questu (nepovinný)"
                    />
                    <.input
                      field={@stage_form[:scope]}
                      type="select"
                      label="Odměna"
                      options={[{"Osobní quest", "personal"}, {"Společný quest chaty", "shared"}]}
                    />
                    <.input
                      field={@stage_form[:assigned_profile_id]}
                      type="select"
                      label="Přiřazení osobního questu"
                      prompt="Volný quest"
                      options={Enum.map(@profiles, &{&1.display_name, &1.id})}
                    />
                    <.input
                      field={@stage_form[:category]}
                      type="select"
                      label="Kategorie"
                      options={Quest.categories()}
                    />
                    <.input
                      field={@stage_form[:priority]}
                      type="select"
                      label="Priorita"
                      options={[{"Běžná", "normal"}, {"Nízká", "low"}, {"Vysoká", "high"}]}
                    />
                    <.input
                      field={@stage_form[:size]}
                      type="select"
                      label="Velikost / výchozí XP"
                      options={[
                        {"Malý · 50 XP", "small"},
                        {"Střední · 100 XP", "medium"},
                        {"Velký · 250 XP", "large"}
                      ]}
                    />
                    <.input
                      field={@stage_form[:xp]}
                      type="number"
                      label="Vlastní XP (jinak podle velikosti)"
                      min="1"
                      max="10000"
                    />
                  </div>
                </details>
                <p class="adventure-muted">
                  Vznikne čekající quest, bez zahájení a bez odměny navíc.
                </p>
                <div class="adventure-project-tools">
                  <button
                    class="adventure-button adventure-button--primary"
                    phx-disable-with="Přidávám…"
                  >Přidat krok</button><button
                    type="button"
                    phx-click="project-stage-editor"
                    phx-value-mode="close"
                    class="adventure-button"
                  >Zpět</button>
                </div>
              </.form>
            </section>
            <section
              :if={@stage_editor == "link"}
              id="project-link-stage"
              class="adventure-project-editor"
              aria-label="Připojit quest"
            >
              <.form
                for={%{}}
                as={:search}
                id="project-quest-search"
                phx-submit="search-project-quests"
                class="adventure-project-search"
              >
                <.input
                  name="search[query]"
                  value=""
                  label="Hledat quest podle názvu"
                  maxlength="200"
                />
                <button class="adventure-button">Vyhledat</button>
              </.form>
              <p class="adventure-muted">
                Nejvýše 30 shod. Lze připojit i konkrétní existující výskyt opakování.
              </p>
              <.form
                for={%{}}
                as={:stage}
                id="project-stage-form"
                phx-submit="add-project-stage"
                class="adventure-project-form"
              >
                <fieldset :if={@quest_results != []}>
                  <legend>Vyber quest</legend><label
                    :for={quest <- @quest_results}
                    class="adventure-project-choice"
                  ><input type="radio" name="stage[quest_id]" value={quest.id} required /><span>{quest.definition_snapshot[
                    "title"
                  ]} · {quest_status(quest.status)}</span></label>
                </fieldset>
                <details :if={@quest_results != []} class="adventure-project-disclosure">
                  <summary>Upřesnit očekávaný výsledek</summary><.input
                    name="stage[output]"
                    value=""
                    label="Očekávaný výsledek (jinak název questu)"
                    maxlength="2000"
                  />
                </details>
                <div class="adventure-project-tools">
                  <button
                    disabled={@quest_results == []}
                    class="adventure-button adventure-button--primary"
                    phx-disable-with="Připojuji…"
                  >Připojit krok</button><button
                    type="button"
                    phx-click="project-stage-editor"
                    phx-value-mode="close"
                    class="adventure-button"
                  >Zpět</button>
                </div>
              </.form>
            </section>
          </div>
          <.link
            :if={@selected.stages != []}
            navigate={~p"/admin/adventure"}
            class="adventure-button adventure-project-camp"
          ><.symbol name="compass" />Pokračovat s questy v táboře</.link>
        </section>

        <section :if={ready_to_accept?(@selected)} class="adventure-project-acceptance">
          <div :if={!@acceptance_open} class="adventure-project-ready">
            <div>
              <h4>Všechny kroky jsou hotové</h4><p class="adventure-muted">
                Zkontroluj skutečný výsledek a potvrď převzetí.
              </p>
            </div><button
              type="button"
              phx-click="project-acceptance-editor"
              phx-value-open="true"
              class="adventure-button adventure-button--primary"
            >Převzít výsledek</button>
          </div>
          <.form
            :if={@acceptance_open}
            for={%{}}
            as={:acceptance}
            id="project-acceptance"
            phx-submit="accept-project"
            class="adventure-project-form"
          >
            <h4>Převzetí výsledku</h4>
            <fieldset>
              <legend>Skuteční přispěvatelé (vyber výslovně)</legend><label
                :for={hero <- @profiles}
                class="adventure-project-choice"
              ><input type="checkbox" name="acceptance[contributors][]" value={hero.id} /><span>{hero.display_name}</span></label>
            </fieldset>
            <.input
              name="acceptance[result]"
              value=""
              type="textarea"
              label="Výsledek / reference (nepovinné)"
              maxlength="5000"
            />
            <label class="adventure-project-choice"><input
              type="checkbox"
              name="acceptance[confirmed]"
              value="true"
              required
            /><span>Jako vybraný hrdina výslovně potvrzuji převzetí skutečného výsledku. Jde o vlastní prohlášení, ne technickou nebo účetní kontrolu.</span></label>
            <div class="adventure-project-tools">
              <button
                class="adventure-button adventure-button--primary"
                phx-disable-with="Přebírám…"
              >Převzít bez dalších XP</button><button
                type="button"
                phx-click="project-acceptance-editor"
                phx-value-open="false"
                class="adventure-button"
              >Zpět</button>
            </div>
          </.form>
        </section>
        <section
          :if={@selected.project.status == "accepted"}
          id="project-accepted"
          class="adventure-project-accepted"
        >
          <h4><.symbol name="check" />Převzato do provozu</h4>
          <p>
            {format_project_date(@selected.project.acceptance["confirmed_at"])} · {profile(
              @profiles,
              @selected.project.acceptance["actor_id"]
            )} · vlastní prohlášení
          </p>
          <p>
            Přispěvatelé: {Enum.map_join(
              @selected.project.acceptance["contributors"] || [],
              ", ",
              &profile(@profiles, &1)
            )}
          </p>
          <p :if={present?(@selected.project.acceptance["result"])} class="adventure-project-copy">
            {@selected.project.acceptance["result"]}
          </p>
        </section>
        <details id="project-audit" class="adventure-project-disclosure">
          <summary>Historie projektu <span>posledních 50 událostí</span></summary>
          <ol class="adventure-project-audit-list">
            <li :for={event <- @history}>
              <strong>{event_label(event.action)}</strong><p class="adventure-muted">
                v{event.version} · {audit_datetime(event.inserted_at)} · {profile(
                  @profiles,
                  event.actor_id
                )}
              </p>
              <p>{event.snapshot["title"]} · {status(event.snapshot["status"])}</p>
              <p :if={event.snapshot["output"]}>Krok: {event.snapshot["output"]}</p>
              <details class="adventure-project-disclosure">
                <summary>Dobové zadání</summary><div>
                  <p :if={present?(event.snapshot["purpose"])} class="adventure-project-copy">
                    {event.snapshot["purpose"]}
                  </p>
                  <p :if={event.snapshot["due_on"]}>
                    Termín: {format_project_date(event.snapshot["due_on"])}
                  </p>
                  <p :if={event.snapshot["budget"]}>
                    Plánovaný odhad: {event.snapshot["budget"]} {event.snapshot["currency"]} · {basis(
                      event.snapshot["price_basis"]
                    )}
                  </p>
                  <p :if={present?(event.snapshot["reference"])}>
                    Podklady: {event.snapshot["reference"]}
                  </p>
                  <p :if={event.snapshot["acceptance"]["confirmed_at"]}>
                    Převzetí: {audit_datetime(event.snapshot["acceptance"]["confirmed_at"])}
                  </p>
                </div>
              </details>
            </li>
          </ol>
        </details>
      </section>
    </section>
    """
  end

  def defaults,
    do: %{
      "title" => "",
      "purpose" => "",
      "area" => "workshop",
      "owner_id" => "",
      "due_on" => "",
      "budget" => "",
      "currency" => "CZK",
      "price_basis" => "including_vat",
      "reference" => ""
    }

  def areas, do: Enum.map(Project.areas(), &{area(&1), &1})

  # Pure presentation: never consult the database or the server's local timezone.
  def format_project_date(%Date{} = date), do: Calendar.strftime(date, "%-d. %-m. %Y")
  def format_project_date(%DateTime{} = date), do: format_project_date(DateTime.to_date(date))

  def format_project_date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _} ->
        format_project_date(date)

      _ ->
        case Date.from_iso8601(value) do
          {:ok, date} -> format_project_date(date)
          _ -> "Datum neznámé"
        end
    end
  end

  def format_project_date(_), do: "Datum neznámé"

  def audit_datetime(%DateTime{} = value),
    do: Calendar.strftime(value, "%-d. %-m. %Y %H:%M:%S UTC")

  def audit_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _} -> audit_datetime(date)
      _ -> "Čas neznámý"
    end
  end

  def audit_datetime(_), do: "Čas neznámý"

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp editable?(project), do: project.status in ["idea", "ready"] and is_nil(project.archived_at)
  defp completed(stages), do: Enum.count(stages, fn {_, q} -> q.status == "completed" end)
  defp progress([]), do: "Zatím bez kroků"
  defp progress(stages), do: "#{completed(stages)} z #{length(stages)} kroků hotovo"

  defp ready_to_accept?(row),
    do:
      row.project.status == "active" and is_nil(row.project.archived_at) and row.stages != [] and
        completed(row.stages) == length(row.stages)

  defp area(key),
    do:
      %{
        "reception" => "Recepce",
        "rooms" => "Pokoje",
        "kitchen" => "Kuchyně",
        "bar" => "Bar",
        "treasury" => "Pokladnice",
        "workshop" => "Dílna"
      }[key]

  defp status(key),
    do:
      %{
        "idea" => "Návrh",
        "ready" => "Připraveno ke schválení",
        "approved" => "Schváleno",
        "active" => "Realizace",
        "accepted" => "Převzato",
        "paused" => "Pozastaveno",
        "cancelled" => "Zrušeno"
      }[key] || key

  defp quest_status(key),
    do:
      %{
        "waiting" => "Čeká",
        "active" => "Rozpracováno",
        "completed" => "Hotovo",
        "cancelled" => "Zrušeno"
      }[key] || key

  defp basis(key),
    do:
      %{
        "including_vat" => "včetně DPH",
        "excluding_vat" => "bez DPH",
        "unknown" => "základ ceny neurčen"
      }[key]

  defp profile(profiles, id),
    do: Enum.find_value(profiles, "Historický profil", fn p -> p.id == id && p.display_name end)

  defp actions(status) when status in ["idea", "ready"],
    do: [{"active", "Schválit a zahájit"}, {"cancelled", "Zrušit projekt"}]

  defp actions("approved"),
    do: [
      {"active", "Zahájit realizaci"},
      {"paused", "Pozastavit"},
      {"cancelled", "Zrušit projekt"}
    ]

  defp actions("active"), do: [{"paused", "Pozastavit"}, {"cancelled", "Zrušit projekt"}]
  defp actions("paused"), do: [{"active", "Obnovit realizaci"}, {"cancelled", "Zrušit projekt"}]
  defp actions(_), do: []

  defp event_label(key),
    do:
      %{
        "created" => "Projekt založen",
        "edited" => "Plán upraven",
        "stage_added" => "Krok připojen",
        "stage_restored" => "Krok znovu připojen",
        "stage_removed" => "Krok odpojen",
        "stage_edited" => "Výsledek kroku upraven",
        "status_changed" => "Stav změněn",
        "accepted" => "Výsledek převzat",
        "archived" => "Projekt archivován"
      }[key] || key
end

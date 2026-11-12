defmodule CozyCheckoutWeb.AdventureLive.ProjectComponents do
  use CozyCheckoutWeb, :html
  alias CozyCheckout.Adventure.Project
  alias CozyCheckoutWeb.CurrencyHelper

  attr :projects, :list, required: true
  attr :selected_id, :any, required: true
  attr :history, :list, required: true
  attr :profiles, :list, required: true
  attr :form, :any, required: true
  attr :quest_results, :list, required: true
  attr :editing_id, :any, required: true
  attr :editor_open, :boolean, required: true
  attr :search, :string, required: true

  def projects(assigns) do
    assigns =
      assign(
        assigns,
        :selected,
        Enum.find(assigns.projects, &(&1.project.id == assigns.selected_id))
      )

    ~H"""
    <section id="adventure-projects" class="adventure-panel">
      <header class="adventure-section-heading flex-wrap">
        <div>
          <p class="adventure-eyebrow">Dílna · trvalé plány chaty</p><h2>Kniha projektů</h2>
        </div>
        <button type="button" phx-click="new-project" class="adventure-button">Nový nápad</button>
        <button type="button" phx-click="refresh-projects" class="adventure-button">Obnovit projekty</button>
      </header>
      <p>Projekt přetrvává mezi sezónami. Rozpočet je pouze plán, ne hotovost, náklady ani účetnictví.
        XP získáš jen za questy v táboře. Převzetí výsledku je samostatné lidské potvrzení bez XP.</p>
      <details id="adventure-project-editor" open={@editor_open}>
        <summary>{if @editing_id, do: "Upravit návrh projektu", else: "Zapsat nový projekt"}</summary>
        <.form
          for={@form}
          id="project-form"
          phx-submit="save-project"
          class="grid gap-3 sm:grid-cols-2"
        >
          <input type="hidden" name="project[request_key]" value={@form[:request_key].value} />
          <.input field={@form[:title]} label="Název" required maxlength="200" />
          <.input field={@form[:area]} type="select" label="Oblast" options={areas()} />
          <.input
            field={@form[:purpose]}
            type="textarea"
            label="Problém a zamýšlený přínos"
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
            label="Plánovaný rozpočet (nepovinný)"
            min="0"
            step="0.01"
          />
          <.input field={@form[:currency]} label="Měna plánu (ISO, např. CZK)" maxlength="3" />
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
          <.input
            field={@form[:reference]}
            label="Reference na podklady (text, nepovinné)"
            maxlength="1000"
          />
          <button class="adventure-button adventure-button--primary" phx-disable-with="Ukládám…">Uložit plán</button>
        </.form>
      </details>
      <p :if={@projects == []}>
        Zatím žádný projekt. Zapiš vlastní nápad; žádná investice se nezakládá automaticky.
      </p>
      <.form for={%{}} as={:projects} id="project-filter" phx-submit="filter-projects">
        <.input
          name="projects[query]"
          value={@search}
          label="Hledat projekt včetně starší historie a archivu"
          maxlength="200"
        />
        <button class="adventure-button">Hledat projekty</button>
      </.form>
      <p class="adventure-muted">
        Nejvýše 100 nejnovějších projektů včetně archivu. Počet hotových etap není procento dokončení stavby.
      </p>
      <div class="grid gap-3 sm:grid-cols-2">
        <button
          :for={row <- @projects}
          id={"project-#{row.project.id}"}
          type="button"
          phx-click="select-project"
          phx-value-id={row.project.id}
          aria-pressed={@selected_id == row.project.id}
          class="adventure-button text-left min-w-0 break-words"
        >
          {row.project.title} · {status(row.project.status)}{if row.project.archived_at,
            do: " · Archiv"} · {completed(row.stages)} z {length(row.stages)} etap
        </button>
      </div>
      <section :if={@selected} id="project-detail" class="mt-6 space-y-4" aria-label="Detail projektu">
        <h3>{@selected.project.title} · {status(@selected.project.status)}</h3>
        <p class="whitespace-pre-wrap break-words">{@selected.project.purpose}</p>
        <p>
          Oblast: {area(@selected.project.area)} · Odpovědnost: {profile(
            @profiles,
            @selected.project.owner_id
          )} · Termín: {@selected.project.due_on || "Neurčen"}
        </p>
        <p :if={@selected.project.budget}>
          Plánovaný odhad: {CurrencyHelper.format_number(@selected.project.budget)} {@selected.project.currency} · {basis(
            @selected.project.price_basis
          )}. Nejde o skutečné náklady nebo dostupné peníze.
        </p>
        <p :if={!@selected.project.budget}>
          Plánovaný rozpočet nezadán. Skutečné náklady se zde nesčítají.
        </p>
        <p class="break-words">Reference: {@selected.project.reference}</p>
        <div :if={!@selected.project.archived_at} class="flex flex-wrap gap-2">
          <button
            :if={@selected.project.status in ["idea", "ready"]}
            type="button"
            phx-click="edit-project"
            phx-value-id={@selected.project.id}
            class="adventure-button"
          >Upravit návrh</button>
          <button
            :for={{target, label} <- actions(@selected.project.status)}
            type="button"
            phx-click="project-status"
            phx-value-id={@selected.project.id}
            phx-value-status={target}
            class="adventure-button"
          >{label}</button>
          <button
            :if={@selected.project.status in ["accepted", "cancelled"]}
            type="button"
            phx-click="archive-project"
            phx-value-id={@selected.project.id}
            class="adventure-button"
          >Archivovat s historií</button>
        </div>
        <p>
          Schválení je rozhodnutí o herním plánu, nikoli objednávka nebo rezervace peněz. Po schválení je zadání a seznam etap uzamčen.
        </p>
        <ol class="space-y-3">
          <li
            :for={{stage, quest} <- @selected.stages}
            id={"project-stage-#{stage.id}"}
            class="break-words"
          >
            <strong>{stage.position}. {stage.output}</strong><br />Quest: {quest.definition_snapshot[
              "title"
            ]} · {quest.status}
            <span :if={quest.archived_at}> · Quest archivován, historie zachována</span>
            <p :if={stage.quest_snapshot["title"] != quest.definition_snapshot["title"]}>
              Původně připojeno jako: {stage.quest_snapshot["title"]}
            </p>
            <.form
              :if={@selected.project.status in ["idea", "ready"] && !@selected.project.archived_at}
              for={%{}}
              as={:stage}
              id={"project-stage-edit-#{stage.id}"}
              phx-submit="edit-project-stage"
            >
              <input type="hidden" name="stage[id]" value={stage.id} />
              <.input
                name="stage[output]"
                value={stage.output}
                label="Upravit očekávaný výstup"
                required
                maxlength="2000"
              />
              <button class="adventure-button">Uložit výstup etapy</button>
            </.form>
            <button
              :if={@selected.project.status in ["idea", "ready"] && !@selected.project.archived_at}
              type="button"
              phx-click="remove-project-stage"
              phx-value-id={stage.id}
              class="adventure-button"
            >Odpojit etapu s historií</button>
          </li>
        </ol>
        <div :if={@selected.project.status in ["idea", "ready"] && !@selected.project.archived_at}>
          <h4>Připojit existující quest jako etapu</h4>
          <p>
            Quest nejprve připrav v Jednorázových questech; zde se nevytváří druhý úkol ani odměna.
          </p>
          <.form for={%{}} as={:search} id="project-quest-search" phx-submit="search-project-quests">
            <.input name="search[query]" value="" label="Hledat quest podle názvu" />
            <button class="adventure-button">Vyhledat (nejvýše 30 výsledků)</button>
          </.form>
          <.form for={%{}} as={:stage} id="project-stage-form" phx-submit="add-project-stage">
            <label :for={quest <- @quest_results} class="block break-words">
              <input type="radio" name="stage[quest_id]" value={quest.id} required /> {quest.definition_snapshot[
                "title"
              ]} · {quest.status}
            </label>
            <.input
              name="stage[output]"
              value=""
              label="Očekávaný výstup etapy"
              required
              maxlength="2000"
            />
            <button disabled={@quest_results == []} class="adventure-button">Připojit etapu</button>
          </.form>
        </div>
        <.link navigate={~p"/admin/adventure"} class="adventure-text-link">Questy přijmi a splň v táboře</.link>
        <.form
          :if={@selected.project.status == "active" && !@selected.project.archived_at}
          for={%{}}
          as={:acceptance}
          id="project-acceptance"
          phx-submit="accept-project"
        >
          <h4>Výslovně převzít výsledek</h4>
          <p>Všechny etapy musí mít splněný quest. Ani jejich splnění samo projekt nepřevezme.</p>
          <fieldset>
            <legend>Skuteční přispěvatelé (vyber výslovně)</legend>
            <label :for={hero <- @profiles} class="block"><input
              type="checkbox"
              name="acceptance[contributors][]"
              value={hero.id}
            /> {hero.display_name}</label>
          </fieldset>
          <.input
            name="acceptance[result]"
            value=""
            type="textarea"
            label="Výsledek / reference (nepovinné)"
            maxlength="5000"
          />
          <label class="block"><input
            type="checkbox"
            name="acceptance[confirmed]"
            value="true"
            required
          />
          Jako vybraný hrdina výslovně potvrzuji převzetí skutečného výsledku. Jde o vlastní prohlášení, ne technickou nebo účetní kontrolu.</label>
          <button class="adventure-button adventure-button--primary" phx-disable-with="Přebírám…">Převzít bez dalších XP</button>
        </.form>
        <div :if={@selected.project.status == "accepted"} id="project-accepted">
          <h4>Převzato do provozu (vlastní prohlášení)</h4>
          <p>
            {@selected.project.acceptance["confirmed_at"]} · {profile(
              @profiles,
              @selected.project.acceptance["actor_id"]
            )}
          </p>
          <p>
            Přispěvatelé: {Enum.map_join(
              @selected.project.acceptance["contributors"] || [],
              ", ",
              &profile(@profiles, &1)
            )}
          </p>
          <p class="whitespace-pre-wrap break-words">{@selected.project.acceptance["result"]}</p>
          <p>
            Bez dalších XP, změny kapacity, účetnictví nebo provozních čísel. Převzetí zůstává neměnné.
          </p>
        </div>
        <details id="project-audit">
          <summary>Audit projektu (posledních 50 událostí)</summary>
          <ol>
            <li :for={event <- @history} class="break-words">
              v{event.version} · {event.inserted_at} · {profile(@profiles, event.actor_id)} · {event.action}
              <p>{event.snapshot["title"]} · {status(event.snapshot["status"])}</p>
              <p :if={event.snapshot["output"]}>Etapa: {event.snapshot["output"]}</p>
              <details>
                <summary>Dobové zadání plánu</summary>
                <p class="whitespace-pre-wrap">{event.snapshot["purpose"]}</p>
                <p>
                  Plánovaný odhad: {event.snapshot["budget"] || "Nezadán"} {event.snapshot["currency"]} · {basis(
                    event.snapshot["price_basis"]
                  )}
                </p>
                <p>Reference: {event.snapshot["reference"]}</p>
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
  defp completed(stages), do: Enum.count(stages, fn {_, q} -> q.status == "completed" end)

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
        "idea" => "Nápad",
        "ready" => "Připraveno ke schválení",
        "approved" => "Schváleno",
        "active" => "Realizace",
        "accepted" => "Převzato",
        "paused" => "Pozastaveno",
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
    do:
      Enum.find_value(profiles, "Neurčen / historický profil", fn p ->
        p.id == id && p.display_name
      end)

  defp actions("idea"), do: [{"ready", "Připravit ke schválení"}, {"cancelled", "Zrušit plán"}]

  defp actions("ready"),
    do: [
      {"idea", "Vrátit k návrhu"},
      {"approved", "Schválit herní plán"},
      {"cancelled", "Zrušit plán"}
    ]

  defp actions("approved"),
    do: [{"active", "Zahájit realizaci"}, {"paused", "Pozastavit"}, {"cancelled", "Zrušit plán"}]

  defp actions("active"), do: [{"paused", "Pozastavit"}, {"cancelled", "Zrušit plán"}]

  defp actions("paused"),
    do: [{"approved", "Obnovit schválený plán"}, {"cancelled", "Zrušit plán"}]

  defp actions(_), do: []
end

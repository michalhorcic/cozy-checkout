defmodule CozyCheckoutWeb.AdventureLive.TemplateComponents do
  use CozyCheckoutWeb, :html
  import CozyCheckoutWeb.KitchenComponents, only: [searchable_picker: 1]
  import CozyCheckoutWeb.AdventureLive.TaskComponents, only: [profile_name: 2]
  alias CozyCheckout.Adventure.Quest

  attr :templates, :list, required: true
  attr :history, :list, required: true
  attr :profiles, :list, required: true
  attr :profile, :any, required: true
  attr :form, :any, required: true
  attr :editing_id, :any, required: true
  attr :campaign_options, :list, required: true
  attr :campaign_query, :any, default: nil
  attr :campaign_open, :boolean, default: false
  attr :editor_open, :boolean, default: false
  attr :view, :string, required: true
  attr :page, :integer, required: true
  attr :more, :boolean, required: true
  attr :occurrences, :map, required: true
  attr :confirmation, :any, required: true

  def templates(assigns) do
    ~H"""
    <section id="adventure-templates" class="adventure-panel adventure-ledger-panel p-4 sm:p-6 mb-6">
      <header class="adventure-section-heading">
        <div>
          <p class="adventure-eyebrow">Dobrodružství, která se vracejí</p><h2>Opakované questy</h2>
        </div>
      </header>
      <p class="adventure-muted my-3">
        Tady upravuješ šablony budoucích výprav. Každá nabídne jeden otevřený úkol; v táboře si ho vybereš. Nová šablona začíná pozastavená.
      </p>
      <nav class="flex flex-wrap gap-3 my-3" aria-label="Zobrazení šablon">
        <button
          :if={@view == "archive"}
          phx-click="template-view"
          phx-value-view="current"
          class="adventure-text-link"
        >Aktivní a pozastavené</button>
        <button
          :if={@view == "current"}
          phx-click="template-view"
          phx-value-view="archive"
          class="adventure-text-link"
        >Otevřít archiv šablon</button>
        <strong :if={@view == "archive"}>Archiv šablon · nevratné</strong>
      </nav>
      <div :if={@profile} class="flex flex-wrap gap-3 mb-4">
        <button phx-click="generate-tasks" class="adventure-button adventure-button--primary">Obnovit opakované úkoly</button>
        <button phx-click="example-templates" class="adventure-button">Přidat 7 doporučených šablon</button>
      </div>
      <details
        :if={@profile}
        id="adventure-template-editor"
        open={@editor_open}
        class="my-4"
      >
        <summary phx-click="toggle-template-editor">
          {if @editing_id, do: "Upravit šablonu", else: "Nová opakovaná šablona"}
        </summary>
        <.form
          for={@form}
          id="adventure-template-form"
          phx-change="template-change"
          phx-submit="save-template"
          class="grid gap-3 sm:grid-cols-2 mt-4"
        >
          <.input field={@form[:title]} label="Název šablony" required maxlength="200" />
          <.input
            field={@form[:cadence]}
            type="select"
            label="Opakování"
            options={[
              {"Denně", "daily"},
              {"Týdně", "weekly"},
              {"Měsíčně", "monthly"},
              {"Půlročně", "semiannual"},
              {"Ročně", "yearly"},
              {"Jednou (původní katalog)", "once"}
            ]}
          />
          <fieldset :if={@form[:cadence].value == "weekly"} class="sm:col-span-2">
            <legend>Dny v týdnu</legend>
            <input type="hidden" name="template[weekdays][]" value="" />
            <label
              :for={{label, day} <- Enum.with_index(["Po", "Út", "St", "Čt", "Pá", "So", "Ne"], 1)}
              class="inline-flex items-center gap-1 mr-3 my-2"
            >
              <input
                type="checkbox"
                name="template[weekdays][]"
                value={day}
                checked={to_string(day) in Enum.map(@form[:weekdays].value || [], &to_string/1)}
                class="checkbox checkbox-sm"
              />{label}
            </label>
            <p :for={error <- @form[:weekdays].errors} class="text-error">{translate_error(error)}</p>
          </fieldset>
          <.input
            field={@form[:starts_on]}
            type="date"
            label={
              if @form[:cadence].value in ["monthly", "semiannual", "yearly"],
                do: "První termín",
                else: "Platí od"
            }
            required
          />
          <.input
            field={@form[:applicability]}
            type="select"
            label="Působnost"
            options={[
              {"Vždy", "always"},
              {"Během vybrané kampaně", "campaign"},
              {"Jen když jsou hosté", "guests"}
            ]}
          />
          <.searchable_picker
            :if={@form[:applicability].value == "campaign"}
            field={@form[:campaign_id]}
            options={@campaign_options}
            label="Kampaň"
            index="campaign"
            query={@campaign_query}
            open={@campaign_open}
            search_name="template_campaign_query"
            search_event="template-campaign-search"
            open_event="template-campaign-open"
            close_event="template-campaign-close"
            select_event="template-campaign-select"
          />
          <.input
            field={@form[:scope]}
            type="select"
            label="Odměna pro"
            options={[{"Splnitele", "personal"}, {"Společnou chatu", "shared"}]}
          />
          <.input
            field={@form[:assigned_profile_id]}
            type="select"
            label="Výchozí přiřazení osobního úkolu"
            prompt="Volný úkol"
            options={Enum.map(@profiles, &{&1.display_name, &1.id})}
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
          <.input field={@form[:xp]} type="number" label="XP" min="1" max="10000" />
          <.input
            field={@form[:category]}
            type="select"
            label="Kategorie"
            options={Quest.categories()}
          />
          <.input
            field={@form[:priority]}
            type="select"
            label="Priorita"
            options={[{"Nízká", "low"}, {"Běžná", "normal"}, {"Vysoká", "high"}]}
          />
          <div class="sm:col-span-2">
            <.input field={@form[:description]} type="textarea" label="Popis" maxlength="5000" />
          </div>
          <div class="flex flex-wrap gap-3">
            <button type="submit" class="adventure-button adventure-button--primary">Uložit šablonu</button><button
              :if={@editing_id}
              type="button"
              phx-click="new-template"
              class="adventure-button"
            >Nová šablona</button>
          </div>
        </.form>
      </details>
      <article
        :for={template <- @templates}
        id={"template-#{template.id}"}
        class={[
          "adventure-blueprint",
          "border-t border-base-300 py-4 space-y-2 break-words",
          template.status == "active" && "adventure-blueprint--active"
        ]}
      >
        <h3 class="font-bold">{template.title}</h3>
        <p class="text-sm">
          {status_label(template.status)} · {cadence_label(template.cadence)} · {if template.scope ==
                                                                                      "shared",
                                                                                    do:
                                                                                      "Společná chata",
                                                                                    else:
                                                                                      profile_name(
                                                                                        @profiles,
                                                                                        template.assigned_profile_id
                                                                                      )} · {template.xp} XP · verze {template.version}
        </p>
        <details class="adventure-template-details">
          <summary>
            Podrobnosti · {length(Map.get(@occurrences, template.id, []))} otevřených úkolů
          </summary>
          <p class="text-sm">
            {applicability_label(template.applicability)} · od {Calendar.strftime(
              template.starts_on,
              "%d. %m. %Y"
            )}
          </p>
          <p :if={template.description != ""} class="text-sm">{template.description}</p>
          <p :for={quest <- Map.get(@occurrences, template.id, [])} class="text-sm">
            {quest.definition_snapshot["title"]} · termín {if quest.due_on,
              do: Calendar.strftime(quest.due_on, "%d. %m. %Y"),
              else: "neurčen"}
          </p>
          <p :if={template.cadence == "weekly"} class="text-sm">
            Dny: {Enum.map_join(
              template.weekdays,
              ", ",
              &Enum.at(["Po", "Út", "St", "Čt", "Pá", "So", "Ne"], &1 - 1)
            )}
          </p>
          <p :if={template.last_check["state"]} class="text-sm">
            Kontrola {template.last_check["day"]}: {check_label(template.last_check["state"])}
          </p>
          <p :if={template.last_check["result"]} class="text-sm">
            {result_label(template.last_check["result"])}
          </p>
        </details>
        <p :if={template.next_due_on && template.status == "active"} class="text-sm">
          Další plánovaný termín: {Calendar.strftime(template.next_due_on, "%d. %m. %Y")}
        </p>
        <p :if={template.last_check["state"] == "unknown"} class="text-sm">
          Podmínku nelze ověřit. Potřebnou práci můžeš přidat jako vlastní jednorázový úkol.
        </p>
        <button
          :if={@profile && template.status != "archived"}
          phx-click="edit-template"
          phx-value-id={template.id}
          class="adventure-button"
        ><.icon name="hero-pencil-square" class="size-4" /> Upravit</button>
        <button
          :if={@profile && template.status == "paused"}
          type="button"
          phx-click="resume-template"
          phx-value-id={template.id}
          class="adventure-button adventure-button--primary"
        ><.icon name="hero-play" class="size-4" /> Spustit / obnovit</button>
        <button
          :if={@profile && template.status == "active"}
          phx-click="confirm-template-status"
          phx-value-id={template.id}
          phx-value-status="paused"
          class="adventure-button"
        ><.icon name="hero-pause" class="size-4" /> Pozastavit</button>
        <button
          :if={@profile && template.status != "archived"}
          phx-click="confirm-template-status"
          phx-value-id={template.id}
          phx-value-status="archived"
          class="adventure-button"
        ><.icon name="hero-archive-box" class="size-4" /> Archivovat</button>
        <section
          :if={@confirmation && @confirmation.id == template.id}
          id={"template-confirm-#{template.id}"}
          class="adventure-template-confirm"
          aria-label="Potvrzení změny šablony"
        >
          <h4>
            {if @confirmation.status == "paused",
              do: "Pozastavit šablonu",
              else: "Nevratně archivovat šablonu"}?
          </h4>
          <p>
            Budoucí generování se zastaví. Výslovně rozhodni o otevřené práci. {if @confirmation.status ==
                                                                                     "archived",
                                                                                   do:
                                                                                     "Archivovanou šablonu nelze obnovit."}
          </p>
          <button phx-click="apply-template-status" phx-value-choice="keep" class="adventure-button">Potvrdit · ponechat otevřený úkol</button>
          <button phx-click="apply-template-status" phx-value-choice="cancel" class="adventure-button">Potvrdit · zrušit a archivovat otevřený úkol</button>
          <button phx-click="cancel-template-status" class="adventure-button">Zpět</button>
        </section>
      </article>
      <p :if={@templates == []}>V tomto zobrazení nejsou další šablony.</p>
      <nav class="flex flex-wrap gap-3 my-3" aria-label="Stránky šablon">
        <button
          :if={@page > 0}
          phx-click="template-page"
          phx-value-direction="previous"
          class="adventure-button"
        >Předchozí</button>
        <span>Strana {@page + 1} · nejvýše 30 šablon</span>
        <button
          :if={@more}
          phx-click="template-page"
          phx-value-direction="next"
          class="adventure-button"
        >Další</button>
      </nav>
      <button phx-click="template-history" class="adventure-text-link">Načíst historii změn šablon</button>
      <details :if={@history != []} class="mt-4">
        <summary>Historie změn šablon (posledních 50)</summary>
        <p :for={version <- @history} class="text-sm py-2 border-t border-base-300">
          {version.definition["title"]} · verze {version.version} · {if version.actor_id,
            do: profile_name(@profiles, version.actor_id),
            else: "Systém"} · {Calendar.strftime(
            version.inserted_at,
            "%d. %m. %Y %H:%M"
          )} UTC
        </p>
      </details>
    </section>
    """
  end

  defp result_label(value),
    do:
      %{
        "created" => "Nový úkol připraven.",
        "rolled" => "Otevřený úkol zachován, termín zkontrolován.",
        "already_recorded" => "Původní termín už je uzavřený.",
        "already_closed" =>
          "Práce už byla tento den uzavřena; další výskyt až v příštím termínu.",
        "already_generated" => "Tento termín už má evidovaný výskyt.",
        "skipped" => "V tomto termínu nevznikl nový úkol."
      }[value] || value

  defp status_label(status),
    do: %{"paused" => "Pozastaveno", "active" => "Spuštěno", "archived" => "Archivováno"}[status]

  defp cadence_label(cadence),
    do:
      %{
        "daily" => "Denně",
        "weekly" => "Týdně",
        "monthly" => "Měsíčně",
        "semiannual" => "Půlročně",
        "yearly" => "Ročně",
        "once" => "Jednou"
      }[cadence]

  defp applicability_label(value),
    do:
      %{
        "always" => "Vždy",
        "campaign" => "V období vybrané aktivní kampaně",
        "guests" => "Jen když jsou hosté"
      }[value]

  defp check_label(value),
    do:
      %{
        "eligible" => "Podmínka splněna",
        "present" => "Hosté přítomni",
        "empty" => "Bez hostů",
        "unknown" => "Přítomnost hostů neznámá",
        "outside_campaign" => "Mimo vybranou aktivní kampaň"
      }[value] || value
end

defmodule CozyCheckoutWeb.AdventureLive.TaskComponents do
  use CozyCheckoutWeb, :html
  alias CozyCheckout.Adventure.Quest

  attr :tasks, :list, required: true
  attr :profiles, :list, required: true
  attr :profile, :any, required: true
  attr :task_form, :any, required: true
  attr :filter_form, :any, required: true
  attr :editing_id, :any, required: true

  def task_board(assigns) do
    ~H"""
    <section id="adventure-task-board" class="adventure-panel p-4 sm:p-6 mb-6">
      <header class="adventure-section-heading">
        <div>
          <p class="adventure-eyebrow">Práce pro naši chatu</p><h2>Společný úkolovník</h2>
        </div>
      </header>
      <details :if={@profile} id="adventure-task-editor" open={@editing_id != nil} class="mb-6">
        <summary>{if @editing_id, do: "Upravit úkol", else: "Přidat vlastní úkol"}</summary>
        <.form
          for={@task_form}
          id="adventure-task-form"
          phx-submit="save-task"
          class="grid gap-3 mt-4 sm:grid-cols-2"
        >
          <.input field={@task_form[:title]} label="Název" required maxlength="200" />
          <.input
            field={@task_form[:scope]}
            type="select"
            label="Odměna pro"
            options={[{"Splnitele", "personal"}, {"Společnou chatu", "shared"}]}
          />
          <.input
            field={@task_form[:assigned_profile_id]}
            type="select"
            label="Přiřazení (osobní úkol)"
            prompt="Volný úkol"
            options={Enum.map(@profiles, &{&1.display_name, &1.id})}
          />
          <.input
            field={@task_form[:size]}
            type="select"
            label="Velikost"
            options={[
              {"Malý · 50 XP", "small"},
              {"Střední · 100 XP", "medium"},
              {"Velký · 250 XP", "large"}
            ]}
          />
          <.input
            field={@task_form[:xp]}
            type="number"
            label="Vlastní XP (nepovinné)"
            min="1"
            max="10000"
          />
          <.input field={@task_form[:due_on]} type="date" label="Termín (nepovinný)" />
          <.input
            field={@task_form[:priority]}
            type="select"
            label="Priorita"
            options={[{"Nízká", "low"}, {"Běžná", "normal"}, {"Vysoká", "high"}]}
          />
          <.input
            field={@task_form[:category]}
            type="select"
            label="Kategorie"
            options={Quest.categories()}
          />
          <div class="sm:col-span-2">
            <.input
              field={@task_form[:description]}
              type="textarea"
              label="Popis (nepovinný)"
              maxlength="5000"
            />
          </div>
          <div class="flex gap-3">
            <button class="adventure-button adventure-button--primary" type="submit">Uložit úkol</button><button
              :if={@editing_id}
              type="button"
              phx-click="new-task"
              class="adventure-button"
            >Zrušit úpravu</button>
          </div>
        </.form>
      </details>
      <.form
        for={@filter_form}
        id="adventure-task-filters"
        phx-change="filter-tasks"
        class="grid gap-3 sm:grid-cols-3 mb-4"
      >
        <.input field={@filter_form[:search]} label="Hledat úkol" phx-debounce="300" />
        <.input
          field={@filter_form[:scope]}
          type="select"
          label="Přiřazení"
          options={[{"Všechny", "all"}, {"Moje", "mine"}, {"Volné", "free"}, {"Společné", "shared"}]}
        />
        <.input
          field={@filter_form[:status]}
          type="select"
          label="Stav"
          options={[
            {"Otevřené", "open"},
            {"Čeká", "waiting"},
            {"Rozpracováno", "active"},
            {"Hotovo", "completed"},
            {"Zrušeno", "cancelled"},
            {"Archiv", "archived"},
            {"Celá historie", "all"}
          ]}
        />
        <.input
          field={@filter_form[:category]}
          type="select"
          label="Kategorie"
          prompt="Všechny"
          options={Quest.categories()}
        />
        <.input
          field={@filter_form[:due]}
          type="select"
          label="Termín"
          options={[{"Všechny", "all"}, {"Po termínu", "overdue"}, {"Bez termínu", "none"}]}
        />
      </.form>
      <p :if={@tasks == []} class="adventure-muted">Tomuto výběru zatím neodpovídá žádný úkol.</p>
      <article
        :for={task <- @tasks}
        id={"task-#{task.id}"}
        class="border-t border-base-300 py-4 space-y-2 break-words"
      >
        <h3 class="font-bold">{task.definition_snapshot["title"]}</h3>
        <p class="text-sm">
          {status_label(task.status)} · {task.category} · {priority_label(task.priority)} · {if task.scope ==
                                                                                                  "shared",
                                                                                                do:
                                                                                                  "Společná chata",
                                                                                                else:
                                                                                                  profile_name(
                                                                                                    @profiles,
                                                                                                    task.assigned_profile_id
                                                                                                  )} · {task.definition_snapshot[
            "xp"
          ]} XP
        </p>
        <p :if={task.due_on} class="text-sm">
          Termín: {Calendar.strftime(task.due_on, "%d. %m. %Y")}
        </p>
        <p :if={task.description != ""} class="whitespace-pre-wrap">{task.description}</p>
        <p :if={task.status == "completed"} class="text-sm">
          Splnil/a {profile_name(@profiles, task.evidence["actor_profile_id"])} · {Calendar.strftime(
            task.completed_at,
            "%d. %m. %Y %H:%M"
          )} UTC
        </p>
        <p :if={task.scope == "shared" and task.status == "completed"} class="text-sm">
          Přispěli: {Enum.map_join(
            task.evidence["contributor_profile_ids"] || [],
            ", ",
            &profile_name(@profiles, &1)
          )}
        </p>
        <p :if={task.evidence["note"] not in [nil, ""]} class="whitespace-pre-wrap">
          {task.evidence["note"]}
        </p>
        <div :if={@profile && !task.archived_at} class="flex flex-wrap gap-3">
          <button
            :if={task.status == "waiting"}
            phx-click="start-task"
            phx-value-id={task.id}
            class="adventure-button"
          >{if task.scope == "shared", do: "Rozpracovat", else: "Převzít a rozpracovat"}</button>
          <button
            :if={task.status == "waiting"}
            phx-click="edit-task"
            phx-value-id={task.id}
            class="adventure-button"
          >Upravit</button>
          <button
            :if={task.status == "active"}
            phx-click="prepare-task-completion"
            phx-value-id={task.id}
            class="adventure-button adventure-button--primary"
          >Hotovo</button>
          <button
            phx-click="archive-task"
            phx-value-id={task.id}
            data-confirm="Archivovat úkol? Otevřený úkol se zruší, historie zůstane."
            class="adventure-button"
          >Archivovat</button>
        </div>
      </article>
      <p :if={length(@tasks) == 100} class="adventure-muted">
        Zobrazeno prvních 100 úkolů. Upřesni filtry nebo hledání.
      </p>
    </section>
    """
  end

  def profile_name(_profiles, nil), do: "Volný úkol"

  def profile_name(profiles, id) do
    case Enum.find(profiles, &(&1.id == id)) do
      nil -> "Neaktivní hrdina"
      profile -> profile.display_name
    end
  end

  defp status_label(status),
    do:
      %{
        "waiting" => "Čeká",
        "active" => "Rozpracováno",
        "completed" => "Hotovo",
        "cancelled" => "Zrušeno"
      }[status]

  defp priority_label(priority),
    do:
      %{"low" => "Nízká priorita", "normal" => "Běžná priorita", "high" => "Vysoká priorita"}[
        priority
      ]
end

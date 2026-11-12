defmodule CozyCheckoutWeb.AdventureLive.Index do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Adventure
  alias CozyCheckout.Adventure.{Campaign, Campaigns, Quest, Tasks, TaskTemplate, Templates}
  import CozyCheckoutWeb.AdventureLive.CampComponents
  import CozyCheckoutWeb.AdventureLive.CampaignComponents
  import CozyCheckoutWeb.AdventureLive.TemplateComponents
  import CozyCheckoutWeb.AdventureLive.TaskComponents
  import CozyCheckoutWeb.AdventureLive.GameComponents
  import CozyCheckoutWeb.AdventureLive.OperationComponents
  import CozyCheckoutWeb.AdventureLive.ProjectComponents, only: [projects: 1]
  alias CozyCheckoutWeb.AdventureLive.WorldComponents, as: World
  alias CozyCheckout.Adventure.Projects
  alias CozyCheckoutWeb.AdventureLive.ProjectComponents

  @impl true
  def mount(params, _, socket) do
    section =
      if params["section"] in ["tasks", "templates", "history", "projects"],
        do: params["section"],
        else: "tasks"

    if Adventure.enabled?() do
      {:ok,
       socket
       |> assign(
         page_title: "Cozy Adventure",
         game_view: game_view(params["view"]),
         world_panel: "continue",
         focus_quest_id: nil,
         chronicle_tab: "improvements",
         history_tasks: [],
         history_loaded: false,
         projects_loaded: false,
         projects: [],
         success: nil,
         selected_profile_id: nil,
         completing: nil,
         profile_storage_available: nil,
         operation: nil,
         operation_checked_at: DateTime.utc_now(),
         operation_state: :loading,
         operation_area: "reception",
         duty_links: %{},
         duty_tab: "issues",
         duty_follow_up: nil,
         duty_follow_up_error: false,
         duty_draft: nil,
         duty_form: nil,
         duty_detail: nil,
         camp_quest_id: params["quest_id"],
         duty_history: nil,
         duty_profile_query: nil,
         duty_profile_open: false
       )
       |> assign(
         finding: false,
         picker_filter: "mine",
         picker_search: "",
         quest_section: section,
         project_area:
           if(params["project_area"] in CozyCheckout.Adventure.Project.areas(),
             do: params["project_area"],
             else: "workshop"
           ),
         task_editor_open: false,
         template_editor_open: false,
         template_view: "current",
         template_page: 0,
         template_history: [],
         template_confirmation: nil,
         world: %{counts: [], projects: []},
         cabin_chronicle: nil,
         cabin_page: 0,
         selected_campaign_id: nil,
         campaign_search: "",
         task_filters: if(section == "history", do: %{"status" => "completed"}, else: %{}),
         editing_task_id: nil,
         task_form: to_form(Tasks.change(%Quest{}), as: :task)
       )
       |> new_project()
       |> assign(
         selected_project_id: params["project_id"],
         project_focus_id: params["project_id"],
         project_history: [],
         project_quest_results: [],
         project_stage_editor: nil,
         project_stage_form: to_form(Tasks.change(%Quest{}), as: :step),
         project_acceptance_open: false,
         project_editor_open: false,
         project_search: String.slice(params["project_search"] || "", 0, 200)
       )
       |> new_template()
       |> new_campaign()
       |> load()
       |> schedule_operation(), layout: {CozyCheckoutWeb.AdventureLive.GameComponents, :shell}}
    else
      {:ok, redirect(socket, to: ~p"/admin")}
    end
  end

  defp game_view(view) when view in ~w(world expeditions development chronicle), do: view
  defp game_view(_), do: "world"

  @impl true
  def handle_params(params, _uri, socket) do
    if Adventure.enabled?() do
      socket =
        assign(socket,
          game_view: game_view(params["view"]),
          world_panel: "continue",
          finding: false,
          operation_checked_at: DateTime.utc_now()
        )

      socket =
        if socket.assigns.game_view == "chronicle" && params["tab"] == "seasons",
          do: assign(socket, chronicle_tab: "seasons"),
          else: socket

      socket =
        if socket.assigns.live_action == :index && socket.assigns.game_view == "development" &&
             !socket.assigns.projects_loaded, do: load_projects(socket), else: socket

      {:noreply, socket}
    else
      {:noreply, redirect(socket, to: ~p"/admin")}
    end
  end

  defp schedule_operation(socket) do
    if connected?(socket) and socket.assigns.live_action == :index,
      do: send(self(), :load_operation)

    socket
  end

  @impl true
  def handle_info(:load_operation, socket) do
    socket = assign(socket, operation_checked_at: DateTime.utc_now())

    if Adventure.enabled?() do
      case CozyCheckout.Adventure.Sources.Operation.load() do
        {:ok, snapshot} ->
          {:noreply,
           socket
           |> assign(
             operation: snapshot,
             operation_state: :ready,
             duty_draft: nil,
             duty_history: nil
           )
           |> refresh_duty_links()
           |> refresh_duty_follow_up()}

        {:error, _} ->
          {:noreply, socket |> assign(operation_state: :error) |> refresh_duty_follow_up()}
      end
    else
      {:noreply, redirect(socket, to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    socket = assign(socket, operation_checked_at: DateTime.utc_now())

    if Adventure.enabled?() do
      handle_game_event(event, params, socket)
    else
      {:noreply, redirect(socket, to: ~p"/admin")}
    end
  end

  defp handle_game_event("world-panel", %{"panel" => panel}, socket)
       when panel in ~w(continue duty),
       do: {:noreply, assign(socket, world_panel: panel)}

  defp handle_game_event("duty-tab", %{"tab" => tab}, socket)
       when tab in ~w(issues work) do
    socket = assign(socket, duty_tab: tab)

    socket =
      if tab == "work" && is_nil(socket.assigns.duty_follow_up),
        do: load_duty_follow_up(socket, 0),
        else: socket

    {:noreply, socket}
  end

  defp handle_game_event("duty-work-page", %{"direction" => direction}, socket) do
    case socket.assigns.duty_follow_up do
      %{page: page, more?: more?} ->
        next =
          cond do
            direction == "next" && more? -> page + 1
            direction == "previous" && page > 0 -> page - 1
            true -> page
          end

        {:noreply, if(next != page, do: load_duty_follow_up(socket, next), else: socket)}

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_game_event("refresh-duty-work", _, socket),
    do: {:noreply, load_duty_follow_up(socket, 0)}

  defp handle_game_event("focus-quest", %{"id" => id}, socket) do
    if Enum.any?(
         socket.assigns.data.quests ++ socket.assigns.camp_quests,
         &(&1.id == id && &1.status == "active")
       ),
       do: {:noreply, assign(socket, focus_quest_id: id, world_panel: "continue")},
       else: {:noreply, socket}
  end

  defp handle_game_event("dismiss-success", _, socket),
    do: {:noreply, assign(socket, success: nil)}

  defp handle_game_event("chronicle-tab", %{"tab" => tab}, socket)
       when tab in ~w(improvements quests seasons) do
    socket = assign(socket, chronicle_tab: tab)

    socket =
      if tab == "quests" && !socket.assigns.history_loaded,
        do:
          assign(socket,
            history_tasks:
              Tasks.list(socket.assigns.selected_profile_id, %{
                "kind" => "history",
                "status" => "completed"
              }),
            history_loaded: true
          ),
        else: socket

    {:noreply, socket}
  end

  defp handle_game_event("refresh-operation", _, socket) do
    if socket.assigns.operation_state == :loading do
      {:noreply, socket}
    else
      send(self(), :load_operation)
      {:noreply, assign(socket, operation_state: :loading)}
    end
  end

  defp handle_game_event("operation-area", %{"area" => area}, socket)
       when area in ["reception", "rooms", "kitchen", "bar", "treasury", "workshop"],
       do: {:noreply, assign(socket, operation_area: area, world_panel: "area")}

  defp handle_game_event("prepare-duty", params, socket) do
    with issue when not is_nil(issue) <- duty_issue(socket, params["source"]),
         key when not is_nil(key) <- Tasks.duty_key(issue),
         %{id: _} <- socket.assigns.data.profile do
      link = socket.assigns.duty_links[key]

      if link && duty_open?(link.quest) do
        {:noreply, assign(socket, duty_detail: link.quest, duty_draft: nil)}
      else
        draft = %{
          key: key,
          issue: issue,
          snapshot: socket.assigns.operation,
          request_key: Ecto.UUID.generate(),
          previous_id: link && link.quest.id,
          previous_quest: link && link.quest,
          confirmed: is_nil(link)
        }

        {:noreply,
         assign(socket,
           duty_draft: draft,
           duty_detail: nil,
           duty_history: nil,
           duty_profile_query: nil,
           duty_profile_open: false,
           duty_form:
             to_form(
               Tasks.change(%Quest{}, %{
                 "title" => issue.reason,
                 "category" => "Kuchyně",
                 "scope" => "personal",
                 "size" => "small"
               }),
               as: :duty
             )
         )}
      end
    else
      _ -> result(socket, {:error, :invalid_duty_source})
    end
  end

  defp handle_game_event("prepare-next-duty", _, socket) do
    case socket.assigns.duty_draft do
      %{previous_id: id} = draft when not is_nil(id) ->
        {:noreply, assign(socket, duty_draft: %{draft | confirmed: true})}

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_game_event("cancel-duty", _, socket),
    do: {:noreply, assign(socket, duty_draft: nil, duty_profile_open: false)}

  defp handle_game_event("validate-duty", %{"duty" => attrs}, socket) do
    if socket.assigns.duty_draft do
      {:noreply,
       assign(socket,
         duty_form: to_form(Tasks.change(%Quest{}, attrs), as: :duty, action: :validate)
       )}
    else
      {:noreply, socket}
    end
  end

  defp handle_game_event("save-duty", %{"duty" => attrs}, socket) do
    case socket.assigns.duty_draft do
      %{confirmed: true} = draft ->
        case Tasks.create_from_duty(
               socket.assigns.selected_profile_id,
               draft.snapshot,
               draft.key,
               attrs,
               draft.request_key,
               draft.previous_id
             ) do
          {:ok, quest} ->
            {:noreply,
             socket
             |> assign(duty_draft: nil, duty_detail: quest, camp_quests: Tasks.camp_quests())
             |> refresh_duty_links()
             |> refresh_duty_follow_up()
             |> clear_flash(:error)
             |> put_flash(:info, "Quest je uložen. Provozní podklad se nezměnil.")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, duty_form: to_form(changeset, as: :duty))}

          error ->
            result(socket, error)
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_game_event(
         "duty-profile-search",
         %{"duty_profile_query" => %{"duty-profile" => query}},
         socket
       ),
       do: {:noreply, assign(socket, duty_profile_query: query, duty_profile_open: true)}

  defp handle_game_event("duty-profile-open", _, socket),
    do: {:noreply, assign(socket, duty_profile_open: true)}

  defp handle_game_event("duty-profile-close", _, socket),
    do: {:noreply, assign(socket, duty_profile_open: false)}

  defp handle_game_event("duty-profile-select", %{"id" => id}, socket) do
    if socket.assigns.duty_draft &&
         (id == "" or Enum.any?(socket.assigns.data.profiles, &(&1.id == id))) do
      attrs = Map.put(socket.assigns.duty_form.params, "assigned_profile_id", id)

      {:noreply,
       assign(socket,
         duty_form: to_form(Tasks.change(%Quest{}, attrs), as: :duty),
         duty_profile_query: nil,
         duty_profile_open: false
       )}
    else
      {:noreply, socket}
    end
  end

  defp handle_game_event("open-duty-quest", %{"id" => id}, socket) do
    known =
      Enum.any?(socket.assigns.duty_links, fn {_, link} -> link.quest.id == id end) or
        Enum.any?(duty_follow_up_quests(socket), &(&1.id == id))

    history = socket.assigns.duty_history

    if known or (history && Enum.any?(history.quests, &(&1.id == id))) do
      {:noreply,
       assign(socket, duty_detail: Tasks.get_managed(id), duty_history: nil, duty_draft: nil)}
    else
      {:noreply, socket}
    end
  end

  defp handle_game_event("close-duty-detail", _, socket),
    do: {:noreply, assign(socket, duty_detail: nil)}

  defp handle_game_event("duty-history", params, socket) do
    case duty_history_issue(socket, params["source"]) do
      nil ->
        {:noreply, socket}

      issue ->
        case Tasks.duty_key(issue) do
          nil ->
            {:noreply, socket}

          key ->
            history = Tasks.duty_history(key)

            {:noreply,
             assign(socket,
               duty_history: Map.merge(history, %{key: key, issue: issue, page: 0}),
               duty_detail: nil,
               duty_draft: nil
             )}
        end
    end
  end

  defp handle_game_event("duty-history-page", %{"direction" => direction}, socket) do
    case socket.assigns.duty_history do
      %{page: page} = history ->
        next =
          cond do
            direction == "next" && history.more? -> page + 1
            direction == "previous" -> max(page - 1, 0)
            true -> page
          end

        if next == page do
          {:noreply, socket}
        else
          {:noreply,
           assign(socket,
             duty_history:
               Map.merge(history, Map.put(Tasks.duty_history(history.key, next), :page, next))
           )}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_game_event("close-duty-history", _, socket),
    do: {:noreply, assign(socket, duty_history: nil)}

  defp handle_game_event("refresh-world", _, socket),
    do: {:noreply, assign(socket, world: Projects.world(), cabin_chronicle: nil, cabin_page: 0)}

  defp handle_game_event("cabin-chronicle", %{"direction" => direction}, socket) do
    page =
      case direction do
        "next" -> socket.assigns.cabin_page + 1
        "previous" -> max(socket.assigns.cabin_page - 1, 0)
        _ -> 0
      end

    {:noreply, assign(socket, cabin_chronicle: Projects.chronicle(page), cabin_page: page)}
  end

  defp handle_game_event("close-cabin-chronicle", _, socket),
    do: {:noreply, assign(socket, cabin_chronicle: nil, cabin_page: 0)}

  defp handle_game_event("template-view", %{"view" => view}, socket)
       when view in ["current", "archive"],
       do:
         {:noreply,
          socket
          |> new_template()
          |> assign(template_view: view, template_page: 0, template_confirmation: nil)
          |> load_templates()}

  defp handle_game_event("template-page", %{"direction" => direction}, socket) do
    page = max(socket.assigns.template_page + if(direction == "next", do: 1, else: -1), 0)

    {:noreply,
     socket |> assign(template_page: page, template_confirmation: nil) |> load_templates()}
  end

  defp handle_game_event("template-history", _, socket),
    do: {:noreply, assign(socket, template_history: Templates.history())}

  defp handle_game_event("confirm-template-status", %{"id" => id, "status" => status}, socket)
       when status in ["paused", "archived"] do
    if Enum.any?(socket.assigns.templates, &(&1.id == id and &1.status != "archived")) do
      {:noreply, assign(socket, template_confirmation: %{id: id, status: status})}
    else
      {:noreply, socket}
    end
  end

  defp handle_game_event("cancel-template-status", _, socket),
    do: {:noreply, assign(socket, template_confirmation: nil)}

  defp handle_game_event("apply-template-status", %{"choice" => choice}, socket) do
    case socket.assigns.template_confirmation do
      %{id: id, status: status} ->
        outcome = Templates.set_status(socket.assigns.selected_profile_id, id, status, choice)

        case outcome do
          {:ok, _} ->
            result(socket |> new_template() |> assign(template_confirmation: nil), outcome)

          error ->
            result(socket, error)
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_game_event("manage-section", %{"section" => section}, socket)
       when section in ["tasks", "templates", "history", "projects"] do
    filters = if section == "history", do: %{"status" => "completed"}, else: %{}
    {:noreply, socket |> assign(quest_section: section, task_filters: filters) |> load()}
  end

  defp handle_game_event("new-project", _, socket), do: {:noreply, new_project(socket)}

  defp handle_game_event("close-project-editor", _, socket),
    do: {:noreply, assign(socket, project_editor_open: false)}

  defp handle_game_event("close-project-detail", _, socket),
    do:
      {:noreply,
       assign(socket,
         selected_project_id: nil,
         project_history: [],
         project_stage_editor: nil,
         project_acceptance_open: false,
         project_editor_open: false
       )}

  defp handle_game_event("project-stage-editor", %{"mode" => mode}, socket) do
    {:noreply,
     assign(socket,
       project_stage_editor: if(mode == "close", do: nil, else: mode),
       project_stage_form: to_form(Tasks.change(%Quest{}), as: :step),
       project_quest_results: []
     )}
  end

  defp handle_game_event("project-acceptance-editor", %{"open" => open}, socket),
    do: {:noreply, assign(socket, project_acceptance_open: open == "true")}

  defp handle_game_event("refresh-projects", _, socket), do: {:noreply, load_projects(socket)}

  defp handle_game_event("filter-projects", %{"projects" => %{"query" => query}}, socket),
    do:
      {:noreply,
       socket
       |> assign(project_search: String.slice(query, 0, 200), project_focus_id: nil)
       |> load_projects()}

  defp handle_game_event("select-project", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.projects, &(&1.project.id == id)) do
      {:noreply,
       assign(socket,
         selected_project_id: id,
         project_history: Projects.history(id),
         project_quest_results: [],
         project_editor_open: false,
         project_stage_editor: nil,
         project_acceptance_open: false
       )}
    else
      {:noreply, socket}
    end
  end

  defp handle_game_event("edit-project", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.projects, &(&1.project.id == id)) do
      %{project: project}
      when project.status in ["idea", "ready"] and is_nil(project.archived_at) ->
        attrs =
          Map.new(Map.keys(ProjectComponents.defaults()), fn key ->
            {key, Map.get(project, String.to_existing_atom(key))}
          end)

        {:noreply,
         assign(socket,
           editing_project_id: id,
           project_editor_open: true,
           project_form: to_form(attrs, as: :project)
         )}

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_game_event("save-project", %{"project" => attrs}, socket) do
    outcome =
      if socket.assigns.editing_project_id,
        do:
          Projects.update(
            socket.assigns.selected_profile_id,
            socket.assigns.editing_project_id,
            attrs
          ),
        else: Projects.create(socket.assigns.selected_profile_id, attrs, attrs["request_key"])

    case outcome do
      {:ok, project} ->
        project_result(
          socket
          |> assign(
            selected_project_id: project.id,
            project_focus_id:
              if(socket.assigns.project_focus_id || socket.assigns.project_search != "",
                do: project.id
              ),
            project_editor_open: false,
            editing_project_id: nil
          ),
          outcome
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, project_form: to_form(%{changeset | action: :validate}, as: :project))}

      error ->
        project_result(socket, error)
    end
  end

  defp handle_game_event("search-project-quests", %{"search" => %{"query" => query}}, socket),
    do: {:noreply, assign(socket, project_quest_results: Projects.search_quests(query))}

  defp handle_game_event("create-project-stage", %{"step" => attrs}, socket) do
    case Projects.create_stage(
           socket.assigns.selected_profile_id,
           socket.assigns.selected_project_id,
           attrs
         ) do
      {:error, %Ecto.Changeset{data: %Quest{}} = changeset} ->
        {:noreply,
         assign(socket, project_stage_form: to_form(%{changeset | action: :validate}, as: :step))}

      outcome ->
        project_result(socket, outcome)
    end
  end

  defp handle_game_event("add-project-stage", %{"stage" => attrs}, socket),
    do:
      project_result(
        socket,
        Projects.add_stage(
          socket.assigns.selected_profile_id,
          socket.assigns.selected_project_id,
          attrs["quest_id"],
          attrs["output"]
        )
      )

  defp handle_game_event("remove-project-stage", %{"id" => id}, socket),
    do:
      project_result(
        socket,
        Projects.remove_stage(
          socket.assigns.selected_profile_id,
          socket.assigns.selected_project_id,
          id
        )
      )

  defp handle_game_event("edit-project-stage", %{"stage" => attrs}, socket),
    do:
      project_result(
        socket,
        Projects.update_stage(
          socket.assigns.selected_profile_id,
          socket.assigns.selected_project_id,
          attrs["id"],
          attrs["output"]
        )
      )

  defp handle_game_event("project-status", %{"id" => id, "status" => status}, socket),
    do:
      project_result(socket, Projects.transition(socket.assigns.selected_profile_id, id, status))

  defp handle_game_event("accept-project", %{"acceptance" => attrs}, socket) do
    outcome =
      Projects.accept(
        socket.assigns.selected_profile_id,
        socket.assigns.selected_project_id,
        attrs
      )

    case project_result(socket, outcome) do
      {:noreply, updated} ->
        case outcome do
          {:ok, %{newly_accepted: true} = project} ->
            world = socket.assigns.world

            counts =
              Enum.reduce(world.counts, %{}, fn {area, status, count}, acc ->
                Map.put(acc, {area, status}, count)
              end)
              |> Map.update({project.area, "accepted"}, 1, &(&1 + 1))
              |> Map.update({project.area, "active"}, 0, &max(&1 - 1, 0))

            world = %{
              world
              | counts: Enum.map(counts, fn {{area, status}, count} -> {area, status, count} end),
                projects:
                  [project | Enum.reject(world.projects, &(&1.id == project.id))]
                  |> Enum.take(100)
            }

            {:noreply,
             updated
             |> assign(
               world: world,
               cabin_chronicle: nil,
               success: %{
                 kind: :project,
                 area: project.area,
                 title: project.title,
                 message:
                   "Převzato pro naši chatu · #{Enum.map_join(project.acceptance["contributors"], ", ", &profile_name(socket.assigns.data.profiles, &1))}",
                 level_up: false
               }
             )
             |> clear_flash(:info)}

          _ ->
            {:noreply, updated}
        end
    end
  end

  defp handle_game_event("archive-project", %{"id" => id}, socket),
    do: project_result(socket, Projects.archive(socket.assigns.selected_profile_id, id))

  defp handle_game_event("toggle-task-editor", _, socket),
    do: {:noreply, assign(socket, task_editor_open: !socket.assigns.task_editor_open)}

  defp handle_game_event("find-quests", _, socket) do
    case Templates.refresh(socket.assigns.selected_profile_id) do
      {:ok, _} -> {:noreply, socket |> load() |> assign(finding: true)}
      error -> result(socket, error)
    end
  end

  defp handle_game_event("close-picker", _, socket),
    do: {:noreply, assign(socket, finding: false)}

  defp handle_game_event("picker-filter", %{"scope" => scope}, socket)
       when scope in ["mine", "shared", "all"],
       do: {:noreply, assign(socket, picker_filter: scope)}

  defp handle_game_event("picker-search", %{"offer" => %{"search" => search}}, socket),
    do: {:noreply, assign(socket, picker_search: String.slice(search, 0, 200))}

  defp handle_game_event("toggle-template-editor", _, socket),
    do: {:noreply, assign(socket, template_editor_open: !socket.assigns.template_editor_open)}

  defp handle_game_event("template-change", %{"template" => attrs} = params, socket) do
    attrs =
      if params["_target"] == ["template", "size"],
        do:
          Map.put(attrs, "xp", %{"small" => 50, "medium" => 100, "large" => 250}[attrs["size"]]),
        else: attrs

    {:noreply,
     assign(socket,
       template_form:
         to_form(Templates.change(socket.assigns.template_draft, attrs), as: :template)
     )}
  end

  defp handle_game_event("save-template", %{"template" => attrs}, socket) do
    outcome =
      if socket.assigns.editing_template_id,
        do:
          Templates.update(
            socket.assigns.selected_profile_id,
            socket.assigns.editing_template_id,
            attrs
          ),
        else: Templates.create(socket.assigns.selected_profile_id, attrs)

    case outcome do
      {:ok, _} ->
        result(new_template(socket), outcome)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, template_form: to_form(changeset, as: :template))}

      error ->
        result(socket, error)
    end
  end

  defp handle_game_event("edit-template", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.templates, &(&1.id == id and &1.status != "archived")) do
      nil ->
        result(socket, {:error, :not_found})

      template ->
        {:noreply,
         assign(socket,
           editing_template_id: id,
           template_editor_open: true,
           template_draft: template,
           template_form: to_form(Templates.change(template), as: :template),
           template_campaign_query: nil,
           template_campaign_open: false
         )}
    end
  end

  defp handle_game_event("new-template", _, socket),
    do: {:noreply, new_template(socket) |> assign(template_editor_open: true)}

  defp handle_game_event("example-templates", _, socket),
    do: result(socket, Templates.add_examples(socket.assigns.selected_profile_id))

  defp handle_game_event("generate-tasks", _, socket),
    do: result(socket, Templates.refresh(socket.assigns.selected_profile_id))

  defp handle_game_event("resume-template", %{"id" => id}, socket),
    do:
      result(
        socket,
        Templates.set_status(socket.assigns.selected_profile_id, id, "active", "keep")
      )

  defp handle_game_event("template-status", %{"template_id" => id, "state" => state}, socket),
    do:
      result(
        new_template(socket),
        Templates.set_status(
          socket.assigns.selected_profile_id,
          id,
          state["status"],
          state["open_choice"]
        )
      )

  defp handle_game_event(
         "template-campaign-search",
         %{"template_campaign_query" => %{"campaign" => query}},
         socket
       ),
       do:
         {:noreply, assign(socket, template_campaign_query: query, template_campaign_open: true)}

  defp handle_game_event("template-campaign-open", _, socket),
    do: {:noreply, assign(socket, template_campaign_open: true)}

  defp handle_game_event("template-campaign-close", _, socket),
    do: {:noreply, assign(socket, template_campaign_open: false)}

  defp handle_game_event("template-campaign-select", %{"id" => id}, socket) do
    attrs = Map.put(socket.assigns.template_form.params, "campaign_id", id)

    {:noreply,
     assign(socket,
       template_form:
         to_form(Templates.change(socket.assigns.template_draft, attrs), as: :template),
       template_campaign_query: nil,
       template_campaign_open: false
     )}
  end

  defp handle_game_event("save-task", %{"task" => attrs}, socket) do
    outcome =
      if socket.assigns.editing_task_id,
        do:
          Tasks.update(socket.assigns.selected_profile_id, socket.assigns.editing_task_id, attrs),
        else: Tasks.create(socket.assigns.selected_profile_id, attrs)

    case outcome do
      {:ok, _} ->
        result(reset_task(socket), outcome)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, task_form: to_form(changeset, as: :task))}

      error ->
        result(socket, error)
    end
  end

  defp handle_game_event("new-task", _, socket), do: {:noreply, reset_task(socket)}

  defp handle_game_event("filter-tasks", %{"filters" => filters}, socket),
    do: {:noreply, socket |> assign(task_filters: filters) |> load()}

  defp handle_game_event("edit-task", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.tasks, &(&1.id == id and &1.status == "waiting")) do
      nil ->
        result(socket, {:error, :not_found})

      task ->
        {:noreply,
         assign(socket,
           editing_task_id: id,
           task_editor_open: true,
           task_form: to_form(Tasks.change(task), as: :task)
         )}
    end
  end

  defp handle_game_event("start-task", %{"id" => id}, socket),
    do: task_result(socket, Tasks.start(socket.assigns.selected_profile_id, id))

  defp handle_game_event("archive-task", %{"id" => id}, socket),
    do: task_result(socket, Tasks.archive(socket.assigns.selected_profile_id, id))

  defp handle_game_event("initialize", _, socket) do
    result(socket, Adventure.initialize())
  end

  defp handle_game_event("save-campaign", %{"campaign" => attrs}, socket) do
    outcome =
      if id = socket.assigns.editing_campaign_id,
        do: Campaigns.update(id, attrs),
        else: Campaigns.create(attrs)

    case outcome do
      {:ok, _} ->
        result(new_campaign(socket), outcome)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, campaign_form: to_form(changeset, as: :campaign))}

      error ->
        result(socket, error)
    end
  end

  defp handle_game_event("edit-campaign", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.game.campaigns, &(&1.id == id and &1.status == "draft")) do
      nil ->
        result(socket, {:error, :not_found})

      campaign ->
        {:noreply,
         assign(socket,
           editing_campaign_id: campaign.id,
           campaign_form: to_form(Campaign.changeset(campaign, %{}), as: :campaign)
         )}
    end
  end

  defp handle_game_event("new-campaign", _, socket), do: {:noreply, new_campaign(socket)}

  defp handle_game_event("select-campaign", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.game.campaigns, &(&1.id == id and &1.status != "draft")),
      do: {:noreply, assign(socket, selected_campaign_id: id)},
      else: result(socket, {:error, :not_found})
  end

  defp handle_game_event("search-campaigns", %{"season" => %{"search" => search}}, socket),
    do: {:noreply, assign(socket, campaign_search: String.slice(search, 0, 100))}

  defp handle_game_event("activate-campaign", %{"campaign_id" => id} = params, socket) do
    confirmed = get_in(params, ["activation", "confirmed"]) == "true"
    result(socket, Campaigns.activate(id, socket.assigns.selected_profile_id, confirmed))
  end

  defp handle_game_event("evaluate-campaign", %{"id" => id}, socket) do
    result(socket, Campaigns.evaluate(id, socket.assigns.selected_profile_id))
  end

  defp handle_game_event(
         "correct-campaign",
         %{"campaign_id" => id, "correction" => attrs},
         socket
       ) do
    result(
      socket,
      Campaigns.evaluate(id, socket.assigns.selected_profile_id,
        correction_reason: attrs["reason"]
      )
    )
  end

  defp handle_game_event("archive-historical", %{"campaign_id" => id} = params, socket) do
    confirmed = get_in(params, ["activation", "confirmed"]) == "true"

    result(
      socket,
      Campaigns.archive_historical(id, socket.assigns.selected_profile_id, confirmed)
    )
  end

  defp handle_game_event("close-campaign", %{"id" => id}, socket) do
    result(socket, Campaigns.close(id, socket.assigns.selected_profile_id))
  end

  defp handle_game_event("profile", %{"profile" => %{"id" => id}}, socket) do
    {:noreply, select_profile(socket, id)}
  end

  defp handle_game_event("restore-profile", %{"id" => id}, socket) do
    {:noreply, select_profile(socket, id)}
  end

  defp handle_game_event("profile-storage-status", %{"persistent" => persistent}, socket)
       when is_boolean(persistent),
       do: {:noreply, assign(socket, :profile_storage_available, persistent)}

  defp handle_game_event("prepare-completion", %{"id" => id}, socket) do
    quests =
      socket.assigns.data.quests ++
        socket.assigns.camp_quests ++ List.wrap(socket.assigns.duty_detail)

    quest =
      if socket.assigns.data.profile,
        do: Enum.find(quests, &(&1.id == id and &1.status == "active")),
        else: nil

    {:noreply, assign(socket, completing: quest)}
  end

  defp handle_game_event("cancel-completion", _, socket),
    do: {:noreply, assign(socket, completing: nil)}

  defp handle_game_event("complete", params, socket) do
    note = get_in(params, ["completion", "note"]) || ""

    if quest = socket.assigns.completing do
      actor_id = get_in(params, ["completion", "actor_id"]) || socket.assigns.selected_profile_id

      outcome =
        if quest.managed,
          do: Tasks.complete(actor_id, quest.id, params["completion"] || %{}),
          else:
            Adventure.complete_manual_quest(socket.assigns.selected_profile_id, quest.id, note)

      {:noreply, updated} = task_result(socket, outcome)

      case outcome do
        {:ok, %{newly_completed: true} = completed} ->
          shared = completed.scope == "shared"
          recipient_id = completed.evidence["actor_profile_id"] || completed.profile_id

          recipient =
            if shared,
              do: "Společná chata",
              else: profile_name(socket.assigns.data.profiles, recipient_id)

          level_up =
            if shared,
              do: updated.assigns.game.level > socket.assigns.game.level,
              else:
                recipient_id == updated.assigns.selected_profile_id &&
                  updated.assigns.data.level > socket.assigns.data.level

          {:noreply,
           updated
           |> assign(
             success: %{
               kind: :quest,
               title: completed.definition_snapshot["title"],
               message: "+#{completed.definition_snapshot["xp"]} XP · #{recipient}",
               level_up: level_up
             },
             duty_detail: nil,
             history_loaded: false
           )
           |> clear_flash(:info)}

        _ ->
          {:noreply, updated}
      end
    else
      {:noreply, socket}
    end
  end

  defp handle_game_event(_, _, socket), do: {:noreply, socket}

  defp select_profile(socket, id) do
    socket =
      socket
      |> assign(
        selected_profile_id: id,
        success: nil,
        focus_quest_id: nil,
        history_tasks: [],
        history_loaded: false,
        completing: nil,
        finding: false,
        template_confirmation: nil,
        duty_draft: nil,
        duty_detail: nil,
        duty_history: nil
      )
      |> load()

    selected_id = socket.assigns.data.profile && socket.assigns.data.profile.id

    socket
    |> assign(:selected_profile_id, selected_id)
    |> open_linked_quest()
    |> push_event("adventure:hero-selected", %{id: selected_id || "", requested_id: id})
  end

  defp open_linked_quest(socket) do
    if socket.assigns.live_action == :index && socket.assigns.data.profile &&
         socket.assigns.camp_quest_id do
      assign(socket,
        duty_detail: Tasks.get_managed(socket.assigns.camp_quest_id),
        camp_quest_id: nil
      )
    else
      socket
    end
  end

  defp result(socket, {:ok, _}) do
    {:noreply,
     socket
     |> assign(completing: nil, finding: false)
     |> load()
     |> clear_flash(:error)
     |> put_flash(:info, "Herní postup uložen.")}
  end

  defp result(socket, {:error, reason}) do
    message =
      case reason do
        :invalid_duty_source ->
          "Podnět není v načteném přehledu. Obnov provoz a vyber podnět znovu."

        :history_confirmation_required ->
          "Předchozí práce se změnila. Zavři návrh, obnov provoz a výslovně připrav další quest."

        :invalid_request ->
          "Návrh už není platný. Zavři ho a připrav nový z podnětu."

        :immutable_template ->
          "Archivovanou šablonu nelze upravit."

        :open_choice_required ->
          "Výslovně vyber, zda otevřený úkol ponechat, nebo zrušit. Při obnovení ho ponech."

        :immutable_task ->
          "Upravovat lze jen čekající úkol. Splnění vyžaduje rozpracovaný úkol."

        :contributors_required ->
          "U společného úkolu vyber alespoň jednoho přispěvatele."

        :active_limit ->
          "Můžeš mít nejvýše 3 aktivní osobní questy."

        :invalid_note ->
          "Poznámka může mít nejvýše 1000 znaků."

        :invalid_profile ->
          "Nejprve vyber herní profil."

        :confirmation_required ->
          "Potvrď období a pravidla sezóny."

        :correction_reason_required ->
          "Oprava uzavřené kroniky vyžaduje důvod a vytvoří novou verzi."

        :correction_reason_too_long ->
          "Důvod opravy může mít nejvýše 1000 znaků."

        :not_past_campaign ->
          "Historickou kroniku lze zapsat až po skončení období."

        :past_campaign ->
          "Nelze aktivovat již skončené období."

        :immutable_campaign ->
          "Po aktivaci nelze období a pravidla měnit."

        :inactive_campaign ->
          "Nejprve aktivuj kampaň."

        %Ecto.Changeset{} ->
          "Zkontroluj zadané údaje a aktuální stav úkolu nebo kampaně."

        _ ->
          "Akci nelze dokončit. Obnov stránku a zkontroluj výběr profilu."
      end

    {:noreply, socket |> clear_flash(:info) |> put_flash(:error, message)}
  end

  defp duty_issue(socket, source) when is_binary(source) do
    if snapshot = socket.assigns.operation do
      Enum.find(snapshot.issues, fn issue ->
        case Tasks.duty_key(issue) do
          {id, type} -> source == id <> ":" <> type
          _ -> false
        end
      end)
    end
  end

  defp duty_issue(_, _), do: nil

  defp duty_follow_up_quests(socket),
    do: if(socket.assigns.duty_follow_up, do: socket.assigns.duty_follow_up.quests, else: [])

  defp duty_history_issue(socket, source) do
    duty_issue(socket, source) ||
      case Enum.find(
             duty_follow_up_quests(socket),
             &(source == &1.source_ref <> ":" <> &1.source_type)
           ) do
        nil ->
          nil

        quest ->
          on =
            case Date.from_iso8601(quest.source_context["on"] || "") do
              {:ok, date} -> date
              _ -> nil
            end

          %{
            booking_id: quest.source_ref,
            kind: if(quest.source_type == "details", do: :details, else: :menu),
            on: on,
            reason: quest.source_context["reason"]
          }
      end
  end

  defp load_duty_follow_up(socket, page) do
    assign(socket,
      duty_follow_up:
        Map.merge(Tasks.duty_follow_up(page), %{page: page, loaded_at: DateTime.utc_now()}),
      duty_follow_up_error: false
    )
  rescue
    _error in [Postgrex.Error, DBConnection.ConnectionError] ->
      assign(socket, duty_follow_up_error: true)
  end

  defp refresh_duty_follow_up(socket) do
    if socket.assigns.duty_follow_up || socket.assigns.duty_follow_up_error,
      do: load_duty_follow_up(socket, 0),
      else: socket
  end

  defp duty_open?(quest), do: quest.status in ["waiting", "active"] && is_nil(quest.archived_at)

  defp refresh_duty_links(socket) do
    issues = if socket.assigns.operation, do: socket.assigns.operation.issues, else: []
    assign(socket, duty_links: Tasks.duty_links(issues))
  end

  defp task_result(socket, {:ok, quest} = outcome) do
    socket = socket |> refresh_duty_links() |> refresh_duty_follow_up()

    socket =
      if socket.assigns.duty_detail && socket.assigns.duty_detail.id == quest.id,
        do: assign(socket, duty_detail: quest),
        else: socket

    result(socket, outcome)
  end

  defp task_result(socket, error), do: result(socket, error)

  defp load(socket) do
    {:ok, data} = Adventure.dashboard(socket.assigns.selected_profile_id)
    {:ok, game} = Campaigns.overview()

    socket = socket |> load_projects() |> load_templates()

    socket =
      if socket.assigns.live_action == :index,
        do: assign(socket, world: Projects.world()),
        else: socket

    assign(socket,
      data: data,
      tasks:
        Tasks.list(
          data.profile && data.profile.id,
          if(socket.assigns.quest_section == "history",
            do: Map.put(socket.assigns.task_filters, "kind", "history"),
            else: Map.put(socket.assigns.task_filters, "kind", "one_off")
          )
        ),
      camp_quests: Tasks.camp_quests(),
      template_campaign_options:
        Enum.map(game.campaigns, &%{id: &1.id, name: &1.name, hint: &1.status}),
      filter_form: to_form(socket.assigns.task_filters, as: :filters),
      game: game,
      profile_form: to_form(%{"id" => data.profile && data.profile.id}, as: :profile),
      completion_form:
        to_form(%{"note" => "", "actor_id" => data.profile && data.profile.id}, as: :completion)
    )
  end

  defp load_templates(socket) do
    page =
      if socket.assigns.live_action == :quests and socket.assigns.quest_section == "templates",
        do: Templates.page(socket.assigns.template_view, socket.assigns.template_page),
        else: %{templates: [], open: %{}, more?: false}

    assign(socket,
      templates: page.templates,
      template_occurrences: page.open,
      template_more: page.more?
    )
  end

  defp new_project(socket),
    do:
      assign(socket,
        editing_project_id: nil,
        project_focus_id: nil,
        project_editor_open: true,
        project_form:
          to_form(
            ProjectComponents.defaults()
            |> Map.put("area", socket.assigns.project_area)
            |> Map.put("request_key", Ecto.UUID.generate()),
            as: :project
          )
      )

  defp load_projects(socket) do
    if (socket.assigns.live_action == :quests and socket.assigns.quest_section == "projects") or
         (socket.assigns.live_action == :index and socket.assigns.game_view == "development") do
      rows = Projects.list(socket.assigns.project_search, socket.assigns.project_focus_id)

      history =
        if Enum.any?(rows, &(&1.project.id == socket.assigns.selected_project_id)),
          do: Projects.history(socket.assigns.selected_project_id),
          else: []

      assign(socket, projects: rows, project_history: history, projects_loaded: true)
    else
      socket
    end
  end

  defp project_result(socket, {:ok, _}),
    do:
      {:noreply,
       socket
       |> assign(
         project_editor_open: false,
         project_stage_editor: nil,
         project_acceptance_open: false,
         project_quest_results: []
       )
       |> load_projects()
       |> put_flash(:info, "Projekt uložen.")}

  defp project_result(socket, {:error, reason}) do
    message =
      case reason do
        :unfinished_stages ->
          "Nejprve dokonči všechny připojené questy v táboře. Projekt potřebuje alespoň jednu etapu."

        :contributors_required ->
          "Výslovně vyber platné přispěvatele."

        :confirmation_required ->
          "Převzetí musíš výslovně potvrdit."

        :invalid_profile ->
          "Vyber aktivního hrdinu."

        :immutable_project ->
          "Schválený nebo archivovaný projekt již nelze upravovat."

        _ ->
          "Projekt se nepodařilo uložit. Zkontroluj vstupy a povolený stav projektu."
      end

    {:noreply, put_flash(socket, :error, message)}
  end

  defp visible_offers(quests, profile_id, scope, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(quests, fn quest ->
      quest.status == "waiting" and
        (scope == "all" or (scope == "shared" and quest.scope == "shared") or
           (scope == "mine" and quest.scope == "personal" and
              quest.assigned_profile_id in [nil, profile_id])) and
        String.contains?(String.downcase(quest.definition_snapshot["title"]), search)
    end)
  end

  defp new_template(socket) do
    draft = %TaskTemplate{starts_on: CozyCheckout.Adventure.Sources.Operation.today()}

    assign(socket,
      editing_template_id: nil,
      template_editor_open: false,
      template_draft: draft,
      template_form: to_form(Templates.change(draft), as: :template),
      template_campaign_query: nil,
      template_campaign_open: false
    )
  end

  defp reset_task(socket) do
    assign(socket,
      editing_task_id: nil,
      task_editor_open: false,
      task_form: to_form(Tasks.change(%Quest{}), as: :task)
    )
  end

  defp new_campaign(socket) do
    today = CozyCheckout.Adventure.Sources.Stays.today()

    campaign = %Campaign{
      name: "Nová sezóna",
      rules_version: "season_v1",
      starts_on: today,
      ends_on: Date.add(today, 90)
    }

    assign(socket,
      editing_campaign_id: nil,
      campaign_form: to_form(Campaign.changeset(campaign, %{}), as: :campaign)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      content_class="adventure-frame"
      main_class="adventure-main"
    >
      <div class="adventure">
        <div id="adventure-shell" class="adventure-shell" phx-hook="AdventureHero">
          <header class="adventure-masthead">
            <.link navigate={~p"/admin/adventure"} class="adventure-wordmark"><span class="adventure-mark"><.symbol name="mountain-snow" /></span><span>Cozy
            <strong>Adventure</strong></span></.link>
            <World.navigation live_action={@live_action} game_view={@game_view} />
            <.link
              navigate={~p"/admin/adventure/settings"}
              class="adventure-settings-link"
              aria-label="Nastavení"
            ><.icon name="hero-cog-6-tooth" class="size-5" /></.link>
            <button
              id="adventure-help-open"
              aria-label="Průvodce dobrodružstvím"
              type="button"
              class="adventure-help-button"
              phx-click={open_help()}
              aria-controls="adventure-help"
              aria-expanded="false"
            ><.symbol name="compass" /> <span>Průvodce</span></button>
            <.link href={~p"/admin"} class="adventure-exit" aria-label="Přejít do administrace"><.icon
              name="hero-arrow-top-right-on-square"
              class="size-4"
            /><span>Do aplikace</span></.link>
          </header>
          <header :if={@live_action != :index} class="adventure-book-title">
            <h1>
              {if @live_action == :quests, do: "Správa zadání", else: "Nastavení dobrodružství"}
            </h1><.link navigate={~p"/admin/adventure"}>Zpět ke hře</.link>
          </header>
          <section :if={@data.profiles == []} class="adventure-welcome">
            <span class="adventure-emblem"><.symbol name="backpack" /></span><div>
              <h2>Připravit batohy?</h2><p>Michal, Lucka a jedna společná chata.</p>
            </div><button
              id="adventure-initialize"
              phx-click="initialize"
              class="adventure-button adventure-button--primary"
            >Začít dobrodružství <.icon name="hero-arrow-right" class="size-4" /></button>
          </section>
          <World.player data={@data} game={@game} profile_form={@profile_form} />
          <World.success success={@success} />
          <p
            :if={@profile_storage_available == false}
            id="adventure-profile-storage-warning"
            class="adventure-muted"
            role="status"
          >
            Prohlížeč blokuje zapamatování profilu. Výběr platí jen na této stránce; povol ukládání dat tohoto webu.
          </p>
          <nav
            :if={@live_action == :quests}
            id="adventure-management-tabs"
            class="adventure-book-tabs"
            aria-label="Správa questů"
          >
            <button
              :for={
                {label, section, symbol} <- [
                  {"Questy", "tasks", "notebook-pen"},
                  {"Opakování", "templates", "compass"},
                  {"Projekty", "projects", "house"},
                  {"Historie", "history", "trophy"}
                ]
              }
              phx-click="manage-section"
              phx-value-section={section}
              aria-pressed={to_string(@quest_section == section)}
            ><.symbol name={symbol} />{label}</button>
          </nav>
          <.task_board
            :if={@live_action == :quests && @quest_section in ["tasks", "history"]}
            tasks={@tasks}
            profiles={@data.profiles}
            profile={@data.profile}
            task_form={@task_form}
            filter_form={@filter_form}
            editing_id={@editing_task_id}
            editor_open={@task_editor_open}
            history={@quest_section == "history"}
          />
          <.projects
            :if={
              (@live_action == :quests && @quest_section == "projects") ||
                (@live_action == :index && @game_view == "development")
            }
            projects={@projects}
            selected_id={@selected_project_id}
            history={@project_history}
            profiles={@data.profiles}
            form={@project_form}
            quest_results={@project_quest_results}
            editing_id={@editing_project_id}
            editor_open={@project_editor_open}
            stage_editor={@project_stage_editor}
            stage_form={@project_stage_form}
            acceptance_open={@project_acceptance_open}
            search={@project_search}
          />
          <.templates
            :if={@live_action == :quests && @quest_section == "templates"}
            templates={@templates}
            history={@template_history}
            profiles={@data.profiles}
            profile={@data.profile}
            form={@template_form}
            editing_id={@editing_template_id}
            campaign_options={@template_campaign_options}
            campaign_query={@template_campaign_query}
            campaign_open={@template_campaign_open}
            editor_open={@template_editor_open}
            view={@template_view}
            page={@template_page}
            more={@template_more}
            occurrences={@template_occurrences}
            confirmation={@template_confirmation}
          />
          <div :if={@live_action == :index} hidden={@game_view != "world"}>
            <World.world {assigns} />
          </div>
          <section
            :if={@live_action == :index}
            id="adventure-expeditions-view"
            hidden={@game_view != "expeditions"}
          >
            <header class="adventure-view-heading">
              <div>
                <p class="adventure-eyebrow">Malé kroky, společné výsledky</p><h1>Naše výpravy</h1>
              </div><.link navigate={~p"/admin/adventure/quests"} class="adventure-button">Spravovat zadání</.link>
            </header>
            <div class="adventure-book-tabs" aria-label="Výpravy">
              <button type="button" phx-click="close-picker" aria-pressed={to_string(!@finding)}>Rozpracované</button><button
                type="button"
                phx-click="find-quests"
                disabled={!@data.profile}
                aria-pressed={to_string(@finding)}
              >Nabídka</button>
            </div>
            <div class="adventure-expeditions-grid" hidden={@finding}>
              <.expeditions
                quests={@data.quests}
                profile={@data.profile}
                id="adventure-personal-list"
              /><.expeditions
                quests={Enum.filter(@camp_quests, &(&1.scope == "shared"))}
                profile={@data.profile}
                shared
                id="adventure-shared-list"
              />
            </div>
            <.quest_picker
              :if={@finding && @data.profile && @game_view == "expeditions"}
              quests={visible_offers(@camp_quests, @data.profile.id, @picker_filter, @picker_search)}
              profiles={@data.profiles}
              profile={@data.profile}
              filter={@picker_filter}
              search_form={to_form(%{"search" => @picker_search}, as: :offer)}
              active_count={Enum.count(@data.quests, &(&1.status == "active"))}
            />
          </section>
          <section
            :if={@live_action == :index}
            id="adventure-chronicle-view"
            hidden={@game_view != "chronicle"}
          >
            <header class="adventure-view-heading">
              <div>
                <p class="adventure-eyebrow">Co už jsme společně dokázali</p><h1>Naše kronika</h1>
              </div>
            </header>
            <div class="adventure-book-tabs" aria-label="Části kroniky">
              <button
                :for={
                  {tab, label} <- [
                    {"improvements", "Zlepšení chaty"},
                    {"quests", "Splněné výpravy"},
                    {"seasons", "Sezóny"}
                  ]
                }
                type="button"
                phx-click="chronicle-tab"
                phx-value-tab={tab}
                aria-pressed={to_string(@chronicle_tab == tab)}
              >{label}</button>
            </div>
            <div hidden={@chronicle_tab != "improvements"}>
              <.cabin_chronicle
                expanded={@game_view == "chronicle"}
                chronicle={@cabin_chronicle}
                world={@world}
                chronicle_page={@cabin_page}
                profiles={@data.profiles}
              />
            </div>
            <div hidden={@chronicle_tab != "quests"}>
              <p :if={@history_tasks == []}>Zatím tu není žádná splněná výprava.</p><article
                :for={quest <- @history_tasks}
                class="adventure-history-item"
              >
                <.symbol name="check" /><div>
                  <h2>{quest.definition_snapshot["title"]}</h2><p>
                    {quest.definition_snapshot["xp"]} XP · {if quest.scope == "shared",
                      do: "Společná chata",
                      else:
                        CozyCheckoutWeb.AdventureLive.TaskComponents.profile_name(
                          @data.profiles,
                          quest.evidence["actor_profile_id"] || quest.profile_id
                        )}
                  </p>
                </div>
              </article>
            </div>
          </section>
          <div
            :if={@live_action == :index}
            hidden={@game_view != "chronicle" || @chronicle_tab != "seasons"}
          >
            <details
              :if={@live_action == :index}
              id="adventure-season-disclosure"
              class="adventure-journal"
              open={@game_view == "chronicle" && @chronicle_tab == "seasons"}
            >
              <summary>
                <span><.symbol name="coins" />Kronika sezóny</span><.icon
                  name="hero-chevron-down"
                  class="size-4"
                />
              </summary>
              <div class="adventure-season-content">
                <.campaigns
                  game={@game}
                  definitions={Campaigns.achievements()}
                  profile_selected={!is_nil(@data.profile)}
                  settings={false}
                  campaign_form={@campaign_form}
                  editing_id={@editing_campaign_id}
                  selected_id={@selected_campaign_id}
                  search={@campaign_search}
                />
              </div>
            </details>
          </div>
          <div :if={@live_action == :settings} class="adventure-content adventure-content--settings">
            <.campaigns
              game={@game}
              definitions={Campaigns.achievements()}
              profile_selected={!is_nil(@data.profile)}
              settings
              campaign_form={@campaign_form}
              editing_id={@editing_campaign_id}
            />
          </div>
          <details :if={@live_action == :settings} class="adventure-journal">
            <summary>
              <span><.symbol name="notebook-pen" /> Osobní XP · audit</span><.icon
                name="hero-chevron-down"
                class="size-4"
              />
            </summary><p class="adventure-muted px-5">
              Profil je vlastní výběr, nikoli ověřená identita. Modul: ADVENTURE_ENABLED=true.
            </p><ul id="adventure-ledger" class="adventure-audit-list">
              <li :for={entry <- @data.ledger}>
                <strong>{entry.amount} XP</strong><span>{entry.reason}</span><small>{entry.inserted_at} UTC · {entry.attribution}</small>
              </li>
            </ul>
          </details>
          <footer class="adventure-footer">
            <.symbol name="mountain-snow" /><span>Dobrodružství po našem.</span><button
              type="button"
              phx-click={open_help()}
            >Pravidla a nápověda</button>
          </footer>
        </div>
        <.help_overlay />
        <.modal :if={@duty_draft} id="adventure-duty-modal" show on_cancel={JS.push("cancel-duty")}>
          <.duty_draft
            draft={@duty_draft}
            form={@duty_form}
            profiles={@data.profiles}
            profile_query={@duty_profile_query}
            profile_open={@duty_profile_open}
            checked_at={@operation_checked_at}
            state={@operation_state}
          />
        </.modal>
        <.modal
          :if={@duty_detail && !@completing}
          id="adventure-duty-detail-modal"
          show
          on_cancel={JS.push("close-duty-detail")}
        >
          <.duty_detail
            quest={@duty_detail}
            profiles={@data.profiles}
            profile={@data.profile}
            snapshot={@operation}
            state={@operation_state}
            checked_at={@operation_checked_at}
          />
        </.modal>
        <.modal
          :if={@duty_history}
          id="adventure-duty-history-modal"
          show
          on_cancel={JS.push("close-duty-history")}
        >
          <.duty_history history={@duty_history} />
        </.modal>
        <.modal
          :if={@finding && @data.profile && @game_view != "expeditions"}
          id="adventure-picker-modal"
          show
          on_cancel={JS.push("close-picker")}
        >
          <.quest_picker
            quests={visible_offers(@camp_quests, @data.profile.id, @picker_filter, @picker_search)}
            profiles={@data.profiles}
            profile={@data.profile}
            filter={@picker_filter}
            search_form={to_form(%{"search" => @picker_search}, as: :offer)}
            active_count={Enum.count(@data.quests, &(&1.status == "active"))}
          />
        </.modal>
        <.modal
          :if={@completing}
          id="adventure-completion-modal"
          show
          on_cancel={JS.push("cancel-completion")}
        >
          <div class="adventure-completion-heading">
            <span class="adventure-emblem"><.symbol name={quest_symbol(@completing.code)} /></span><p class="adventure-eyebrow">
              Další krok za tebou
            </p><h2 id="adventure-completion-modal-title">
              {@completing.definition_snapshot["title"]}
            </h2><p id="adventure-completion-modal-description">
              {if @completing.managed && @completing.scope == "shared",
                do: "Společná odměna chatě. Vyber splnitele a přispěvatele.",
                else: "Dokončit jako #{@data.profile.display_name}?"}
            </p><strong class="adventure-big-reward">+{@completing.definition_snapshot["xp"]} XP</strong>
          </div>
          <.form
            for={@completion_form}
            id="adventure-completion"
            phx-submit="complete"
            class="adventure-completion-form"
          >
            <.input
              :if={@completing.managed}
              field={@completion_form[:actor_id]}
              type="select"
              label="Skutečný splnitel"
              options={Enum.map(@data.profiles, &{&1.display_name, &1.id})}
            />
            <fieldset :if={@completing.managed && @completing.scope == "shared"}>
              <legend>Přispěvatelé · odměnu získá jednou společná chata</legend>
              <label :for={profile <- @data.profiles} class="flex items-center gap-2 my-2">
                <input
                  type="checkbox"
                  name="completion[contributors][]"
                  value={profile.id}
                  class="checkbox"
                />
                {profile.display_name}
              </label>
            </fieldset>
            <details>
              <summary>Přidat poznámku <span class="adventure-muted">nepovinné</span></summary><.input
                field={@completion_form[:note]}
                type="textarea"
                label="Poznámka ke splnění"
                maxlength="1000"
              />
            </details><button class="adventure-button adventure-button--primary" type="submit"><.symbol name="check" />
            Potvrdit splnění</button>
          </.form>
        </.modal>
      </div>
    </Layouts.app>
    """
  end
end

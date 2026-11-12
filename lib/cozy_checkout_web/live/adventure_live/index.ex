defmodule CozyCheckoutWeb.AdventureLive.Index do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Adventure
  alias CozyCheckout.Adventure.{Campaign, Campaigns, Quest, Tasks, TaskTemplate, Templates}
  import CozyCheckoutWeb.AdventureLive.CampComponents
  import CozyCheckoutWeb.AdventureLive.CampaignComponents
  import CozyCheckoutWeb.AdventureLive.TemplateComponents
  import CozyCheckoutWeb.AdventureLive.TaskComponents
  import CozyCheckoutWeb.AdventureLive.GameComponents

  @impl true
  def mount(params, _, socket) do
    section =
      if params["section"] in ["tasks", "templates", "history"],
        do: params["section"],
        else: "tasks"

    if Adventure.enabled?() do
      {:ok,
       socket
       |> assign(
         page_title: "Cozy Adventure",
         selected_profile_id: nil,
         completing: nil,
         profile_storage_available: nil
       )
       |> assign(
         finding: false,
         picker_filter: "mine",
         picker_search: "",
         quest_section: section,
         task_editor_open: false,
         template_editor_open: false,
         selected_campaign_id: nil,
         campaign_search: "",
         task_filters: if(section == "history", do: %{"status" => "completed"}, else: %{}),
         editing_task_id: nil,
         task_form: to_form(Tasks.change(%Quest{}), as: :task)
       )
       |> new_template()
       |> new_campaign()
       |> load(), layout: {CozyCheckoutWeb.AdventureLive.GameComponents, :shell}}
    else
      {:ok, redirect(socket, to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    if Adventure.enabled?() do
      handle_game_event(event, params, socket)
    else
      {:noreply, redirect(socket, to: ~p"/admin")}
    end
  end

  defp handle_game_event("manage-section", %{"section" => section}, socket)
       when section in ["tasks", "templates", "history"] do
    filters = if section == "history", do: %{"status" => "completed"}, else: %{}
    {:noreply, socket |> assign(quest_section: section, task_filters: filters) |> load()}
  end

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
    do: result(socket, Tasks.start(socket.assigns.selected_profile_id, id))

  defp handle_game_event("archive-task", %{"id" => id}, socket),
    do: result(socket, Tasks.archive(socket.assigns.selected_profile_id, id))

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
    quests = socket.assigns.data.quests ++ socket.assigns.camp_quests

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
      result(
        socket,
        if quest.managed do
          Tasks.complete(
            get_in(params, ["completion", "actor_id"]) || socket.assigns.selected_profile_id,
            quest.id,
            params["completion"] || %{}
          )
        else
          Adventure.complete_manual_quest(socket.assigns.selected_profile_id, quest.id, note)
        end
      )
    else
      {:noreply, socket}
    end
  end

  defp handle_game_event(_, _, socket), do: {:noreply, socket}

  defp select_profile(socket, id) do
    socket = socket |> assign(selected_profile_id: id, completing: nil, finding: false) |> load()
    selected_id = socket.assigns.data.profile && socket.assigns.data.profile.id

    socket
    |> assign(:selected_profile_id, selected_id)
    |> push_event("adventure:hero-selected", %{id: selected_id || "", requested_id: id})
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

  defp load(socket) do
    {:ok, data} = Adventure.dashboard(socket.assigns.selected_profile_id)
    {:ok, game} = Campaigns.overview()

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
      templates: Templates.list(),
      template_history: Templates.history(),
      template_campaign_options:
        Enum.map(game.campaigns, &%{id: &1.id, name: &1.name, hint: &1.status}),
      filter_form: to_form(socket.assigns.task_filters, as: :filters),
      game: game,
      profile_form: to_form(%{"id" => data.profile && data.profile.id}, as: :profile),
      completion_form:
        to_form(%{"note" => "", "actor_id" => data.profile && data.profile.id}, as: :completion)
    )
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
    draft = %TaskTemplate{starts_on: CozyCheckout.Adventure.Sources.Stays.today()}

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
            <nav aria-label="Adventure" class="adventure-nav">
              <.link navigate={~p"/admin/adventure"} aria-current={@live_action == :index && "page"}><.symbol name="trees" />
              Tábor</.link>
              <.link
                navigate={~p"/admin/adventure/quests"}
                aria-current={@live_action == :quests && "page"}
              ><.symbol name="backpack" /> Questy</.link>
              <.link
                navigate={~p"/admin/adventure/settings"}
                aria-current={@live_action == :settings && "page"}
              ><.icon name="hero-adjustments-horizontal" class="size-4" /> Nastavení</.link>
            </nav>
            <button
              id="adventure-help-open"
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
          <section
            :if={@live_action == :index}
            class="adventure-hero"
            aria-labelledby="adventure-title"
          >
            <img
              class="adventure-hero-art"
              src={~p"/images/adventure/mountain-lodge.png"}
              alt="Ilustrovaná horská chata mezi smrky a zelenými kopci"
              width="1983"
              height="793"
              fetchpriority="high"
            />
            <div class="adventure-hero-shade"></div>
            <div class="adventure-hero-copy">
              <p class="adventure-eyebrow">Jindřichův dům · naše společná výprava</p><h1 id="adventure-title">
                Vítej v táboře.<br />Chata čeká na hrdiny.
              </h1><p>Vyber výpravu. Udělej další krok. Rozvíjej naši chatu.</p>
            </div>
            <div class="adventure-lodge-level">
              <span class="adventure-level-coin"><.symbol name="house" /></span><div>
                <span class="adventure-eyebrow">Společná chata</span><strong>Úroveň {@game.level}</strong><span>{@game.total_xp} XP</span>
              </div><progress
                aria-label="Postup společné chaty k další úrovni"
                value={level_progress(@game.total_xp, @game.level)}
                max={100 * @game.level}
              ></progress>
            </div>
            <span class="adventure-hero-caption"><.symbol name="trees" /> Doma na horách</span>
          </section>
          <section :if={@live_action != :index} class="adventure-book-heading">
            <span class="adventure-emblem"><.symbol name={
              if @live_action == :quests, do: "notebook-pen", else: "compass"
            } /></span>
            <div>
              <p class="adventure-eyebrow">
                {if @live_action == :quests, do: "Kniha zadání", else: "Pravidla našeho světa"}
              </p>
              <h1>
                {if @live_action == :quests,
                  do: "Každá výprava má svůj příběh",
                  else: "Nastavení dobrodružství"}
              </h1>
              <p>
                {if @live_action == :quests,
                  do: "Tady questy vytváříš a upravuješ. V táboře je vybíráš a plníš.",
                  else: "Sezóny, pravidla a audit společného postupu."}
              </p>
            </div><.link
              navigate={~p"/admin/adventure"}
              class="adventure-button adventure-button--subtle"
            ><.symbol name="trees" /> Zpět do tábora</.link>
          </section>
          <section :if={@data.profiles == []} class="adventure-welcome">
            <span class="adventure-emblem"><.symbol name="backpack" /></span><div>
              <h2>Připravit batohy?</h2><p>Michal, Lucka a jedna společná chata.</p>
            </div><button
              id="adventure-initialize"
              phx-click="initialize"
              class="adventure-button adventure-button--primary"
            >Začít dobrodružství <.icon name="hero-arrow-right" class="size-4" /></button>
          </section>
          <section :if={@data.profiles != []} class="adventure-player">
            <span class="adventure-avatar">{if @data.profile,
              do: String.first(@data.profile.display_name),
              else: "?"}</span>
            <.form for={@profile_form} id="adventure-profile" phx-change="profile">
              <.input
                field={@profile_form[:id]}
                type="select"
                label={
                  if @live_action == :index, do: "Kdo dnes vyráží?", else: "Kdo zapisuje do knihy?"
                }
                prompt="Vyber profil"
                options={Enum.map(@data.profiles, &{&1.display_name, &1.id})}
              />
            </.form>
            <div :if={@data.profile} id="adventure-progress" class="adventure-player-progress">
              <h2>{@data.profile.display_name} · úroveň {@data.level}</h2><div class="adventure-xp-line">
                <span>{@data.total_xp} XP</span><span>další úroveň {level_floor(@data.level + 1)} XP</span>
              </div><progress
                aria-label="Postup osobního profilu k další úrovni"
                value={level_progress(@data.total_xp, @data.level)}
                max={100 * @data.level}
              ></progress>
            </div>
            <span :if={!@data.profile} class="adventure-muted">{if @live_action == :index,
              do: "Vyber hrdinu a vyraz.",
              else: "Vyber hrdinu pro správu zadání."}</span>
          </section>
          <p
            :if={@profile_storage_available == false}
            id="adventure-profile-storage-warning"
            class="adventure-muted"
            role="status"
          >
            Prohlížeč blokuje zapamatování profilu. Výběr platí jen na této stránce; povol ukládání dat tohoto webu.
          </p>
          <nav :if={@live_action == :quests} class="adventure-book-tabs" aria-label="Správa questů">
            <button
              :for={
                {label, section, symbol} <- [
                  {"Jednorázové questy", "tasks", "notebook-pen"},
                  {"Opakované questy", "templates", "compass"},
                  {"Historie", "history", "trophy"}
                ]
              }
              phx-click="manage-section"
              phx-value-section={section}
              aria-pressed={@quest_section == section}
            ><.symbol name={symbol} />{label}</button>
          </nav>
          <.task_board
            :if={@live_action == :quests && @quest_section != "templates"}
            tasks={@tasks}
            profiles={@data.profiles}
            profile={@data.profile}
            task_form={@task_form}
            filter_form={@filter_form}
            editing_id={@editing_task_id}
            editor_open={@task_editor_open}
            history={@quest_section == "history"}
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
          />
          <div :if={@live_action == :index} class="adventure-camp-grid">
            <div class="adventure-quests-column">
              <.expeditions quests={@data.quests} profile={@data.profile} />
              <.expeditions
                quests={Enum.filter(@camp_quests, &(&1.scope == "shared"))}
                profile={@data.profile}
                shared
              />
              <.link
                :if={@data.profile}
                navigate={~p"/admin/adventure/quests?section=history"}
                id="adventure-history"
                class="adventure-journal-link"
              ><.symbol name="notebook-pen" /><span>Otevřít deník splněných questů</span><.icon
                name="hero-arrow-right"
                class="size-4"
              /></.link>
            </div>
            <aside class="adventure-camp-aside">
              <.world_map />
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
            </aside>
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
        <.modal
          :if={@finding && @data.profile}
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

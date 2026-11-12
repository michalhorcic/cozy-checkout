defmodule CozyCheckoutWeb.AdventureLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckout.{Adventure, Repo}
  alias CozyCheckout.Adventure.{Profile, Quest, Tasks, XpTransaction}
  alias CozyCheckoutWeb.AdminAuth

  setup %{conn: conn} do
    Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ", [],
      sandbox_subtransaction: false
    )

    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    pin = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :adventure_enabled, previous)

      if pin,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, pin),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    conn = init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})
    {:ok, conn: conn}
  end

  test "all game routes require the existing admin PIN" do
    for path <- ["/admin/adventure", "/admin/adventure/quests", "/admin/adventure/settings"] do
      assert build_conn() |> get(path) |> redirected_to() =~ "/admin/login"
    end
  end

  test "disabled routes redirect and navigation hides the game", %{conn: conn} do
    Application.put_env(:cozy_checkout, :adventure_enabled, false)

    refute Enum.any?(CozyCheckoutWeb.AdminNavigation.groups(), fn {_, links} ->
             Enum.any?(links, fn {_, path} -> path == "/admin/adventure" end)
           end)

    for path <- ["/admin/adventure", "/admin/adventure/quests", "/admin/adventure/settings"] do
      assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, path)
    end

    assert Repo.aggregate(Profile, :count) == 0
  end

  test "explicit setup, profile selection and confirmed quest completion", %{conn: conn} do
    {:ok, view, html} = live(conn, "/admin/adventure")
    assert html =~ "nikoli ověřená identita"
    assert Repo.aggregate(Profile, :count) == 0
    view |> element("#adventure-initialize") |> render_click()
    profile = Repo.get_by!(Profile, slug: "michal")
    view |> form("#adventure-profile", profile: %{id: profile.id}) |> render_change()
    assert has_element?(view, "#adventure-progress", "Michal · úroveň 1")

    {:ok, quest} =
      Tasks.create(profile.id, %{"title" => "Zavést jedno provozní zlepšení", "xp" => 250})

    view |> element("#adventure-find-quest") |> render_click()
    view |> element("#pick-quest-#{quest.id} button") |> render_click()
    view |> element("#adventure-quest-#{quest.id} button") |> render_click()
    assert Repo.aggregate(XpTransaction, :count) == 0

    view
    |> form("#adventure-completion", completion: %{note: "Nový postup je zavedený."})
    |> render_submit()

    assert has_element?(view, "#adventure-progress", "250 XP")
    refute has_element?(view, "#adventure-quest-#{quest.id}")
    {:ok, journal, _} = live(conn, "/admin/adventure/quests?section=history")
    assert render(journal) =~ "Nový postup je zavedený."
    assert Repo.aggregate(XpTransaction, :count) == 1
    # Browser restoration is a separate hook event and cannot create another reward.
    {:ok, refreshed, _} = live(conn, "/admin/adventure")
    refute has_element?(refreshed, "#adventure-progress")
    assert Repo.aggregate(XpTransaction, :count) == 1
  end

  test "remembered hero is validated, restored and cleared without awarding XP", %{conn: conn} do
    {:ok, _} = Adventure.initialize()
    p = Repo.get_by!(Profile, slug: "michal")
    {:ok, view, _} = live(conn, "/admin/adventure")
    render_click(view, "restore-profile", %{"id" => p.id})
    assert has_element?(view, "#adventure-progress", "Michal · úroveň 1")
    profile_id = p.id

    assert_push_event(view, "adventure:hero-selected", %{
      id: ^profile_id,
      requested_id: ^profile_id
    })

    render_click(view, "restore-profile", %{"id" => "invalid-cookie"})
    refute has_element?(view, "#adventure-progress")
    assert_push_event(view, "adventure:hero-selected", %{id: "", requested_id: "invalid-cookie"})

    p |> Ecto.Changeset.change(active: false) |> Repo.update!()
    render_click(view, "restore-profile", %{"id" => p.id})
    refute has_element?(view, "#adventure-progress")
    assert_push_event(view, "adventure:hero-selected", %{id: "", requested_id: ^profile_id})
    assert Repo.aggregate(XpTransaction, :count) == 0
    assert Repo.aggregate(Quest, :count) == 0
  end

  test "blocked browser storage is visible without changing the selected hero", %{conn: conn} do
    {:ok, _} = Adventure.initialize()
    p = Repo.get_by!(Profile, slug: "michal")
    {:ok, view, _} = live(conn, "/admin/adventure")
    render_click(view, "restore-profile", %{"id" => p.id})
    refute has_element?(view, "#adventure-profile-storage-warning")

    render_click(view, "profile-storage-status", %{"persistent" => false})
    assert has_element?(view, "#adventure-profile-storage-warning", "Prohlížeč blokuje")
    assert has_element?(view, "#adventure-progress", "Michal")

    render_click(view, "profile-storage-status", %{"persistent" => true})
    refute has_element?(view, "#adventure-profile-storage-warning")
    assert has_element?(view, "#adventure-progress", "Michal")
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "help is an optional overlay and completion does not require a note", %{conn: conn} do
    {:ok, _} = Adventure.initialize()
    p = Repo.get_by!(Profile, slug: "michal")
    {:ok, quest} = Adventure.activate_quest(p.id, "prepare_stay")
    {:ok, view, _} = live(conn, "/admin/adventure")

    assert has_element?(
             view,
             "dialog#adventure-help:not([open])[aria-labelledby=adventure-help-title]"
           )

    assert has_element?(view, "#adventure-help-open[aria-controls=adventure-help]")
    refute has_element?(view, "#adventure-shell", "nikoli ověřená identita")
    view |> form("#adventure-profile", profile: %{id: p.id}) |> render_change()
    view |> element("#adventure-quest-#{quest.id} button") |> render_click()
    refute has_element?(view, "#completion_note[required]")
    refute has_element?(view, "#completion_note[minlength]")
    view |> form("#adventure-completion", completion: %{note: ""}) |> render_submit()
    assert Repo.get!(Quest, quest.id).status == "completed"
    assert Repo.get!(Quest, quest.id).evidence["note"] == ""
    assert has_element?(view, "#adventure-progress", "50 XP")
  end

  test "switching profiles clears a pending completion and cannot reward another player", %{
    conn: conn
  } do
    {:ok, _} = Adventure.initialize()
    michal = Repo.get_by!(Profile, slug: "michal")
    lucka = Repo.get_by!(Profile, slug: "lucka")
    {:ok, quest} = Adventure.activate_quest(michal.id, "improvement")
    {:ok, view, _} = live(conn, "/admin/adventure")
    view |> form("#adventure-profile", profile: %{id: michal.id}) |> render_change()
    view |> element("#adventure-quest-#{quest.id} button") |> render_click()
    view |> form("#adventure-profile", profile: %{id: lucka.id}) |> render_change()
    refute has_element?(view, "#adventure-completion")

    render_click(view, "complete", %{
      "completion" => %{"note" => "Zpožděný požadavek na splnění."}
    })

    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "disabling an already opened game blocks pending mutations", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/adventure")
    Application.put_env(:cozy_checkout, :adventure_enabled, false)
    render_click(view, "initialize", %{})
    assert_redirect(view, "/admin")
    assert Repo.aggregate(Profile, :count) == 0
  end

  test "quest book authors work and camp chooses and rewards its actual completer", %{
    conn: conn
  } do
    alias CozyCheckout.Adventure.Tasks
    {:ok, _} = Adventure.initialize()
    michal = Repo.get_by!(Profile, slug: "michal")
    lucka = Repo.get_by!(Profile, slug: "lucka")
    {:ok, view, _} = live(conn, "/admin/adventure/quests")
    refute has_element?(view, "#adventure-task-form")
    view |> form("#adventure-profile", profile: %{id: michal.id}) |> render_change()

    view
    |> form("#adventure-task-form",
      task: %{title: "Vyčistit kamna", assigned_profile_id: michal.id}
    )
    |> render_submit()

    [task] = Tasks.list(michal.id)
    assert task.status == "waiting"
    refute has_element?(view, "button[phx-click=start-task]")
    refute has_element?(view, "#adventure-expeditions")
    refute has_element?(view, ".adventure-hero")
    {:ok, camp, _} = live(conn, "/admin/adventure")
    camp |> form("#adventure-profile", profile: %{id: michal.id}) |> render_change()
    refute has_element?(camp, "#adventure-task-form")
    refute has_element?(camp, "#adventure-templates")
    camp |> element("#adventure-find-quest") |> render_click()
    assert has_element?(camp, "#pick-quest-#{task.id}", "Vyčistit kamna")
    camp |> element("#pick-quest-#{task.id} button") |> render_click()
    camp |> element("#adventure-quest-#{task.id} button") |> render_click()
    view = camp
    assert has_element?(view, "#completion_actor_id")

    view
    |> form("#adventure-completion", completion: %{actor_id: lucka.id, note: ""})
    |> render_submit()

    assert Repo.one!(XpTransaction).profile_id == lucka.id
    {:ok, view, _} = live(conn, "/admin/adventure/quests")
    view |> form("#adventure-profile", profile: %{id: michal.id}) |> render_change()
    render_click(view, "manage-section", %{"section" => "history"})
    view |> form("#adventure-task-filters", filters: %{status: "completed"}) |> render_change()
    assert has_element?(view, "#task-#{task.id}", "Lucka")
    assert has_element?(view, "#adventure-progress", "0 XP")
  end

  test "shared task completion requires contributors and archive keeps history", %{conn: conn} do
    alias CozyCheckout.Adventure.Tasks
    {:ok, _} = Adventure.initialize()
    p = Repo.get_by!(Profile, slug: "michal")
    {:ok, task} = Tasks.create(p.id, %{"title" => "Opravit plot", "scope" => "shared"})
    {:ok, _} = Tasks.start(p.id, task.id)
    {:ok, view, _} = live(conn, "/admin/adventure")
    # An event without a selected hero cannot open a completion modal.
    render_click(view, "prepare-completion", %{"id" => task.id})
    refute has_element?(view, "#adventure-completion")
    view |> form("#adventure-profile", profile: %{id: p.id}) |> render_change()
    view |> element("#adventure-quest-#{task.id} button", "Hotovo") |> render_click()
    view |> form("#adventure-completion", completion: %{actor_id: p.id}) |> render_submit()
    assert render(view) =~ "vyber alespoň jednoho přispěvatele"

    view
    |> form("#adventure-completion", completion: %{actor_id: p.id, contributors: [p.id]})
    |> render_submit()

    assert Repo.one!(XpTransaction).recipient_type == "shared"
    {:ok, view, _} = live(conn, "/admin/adventure/quests")
    view |> form("#adventure-profile", profile: %{id: p.id}) |> render_change()
    render_click(view, "manage-section", %{"section" => "history"})
    view |> form("#adventure-task-filters", filters: %{status: "completed"}) |> render_change()
    view |> element("#task-#{task.id} button", "Archivovat") |> render_click()
    view |> form("#adventure-task-filters", filters: %{status: "archived"}) |> render_change()
    assert has_element?(view, "#task-#{task.id}", "Přispěli: Michal")
    assert Repo.aggregate(XpTransaction, :count) == 1
  end

  test "recurring templates are managed from quests and pause explicitly retains the task", %{
    conn: conn
  } do
    alias CozyCheckout.Adventure.TaskTemplate
    {:ok, _} = Adventure.initialize()
    p = Repo.get_by!(Profile, slug: "michal")
    {:ok, view, _} = live(conn, "/admin/adventure/quests")
    view |> form("#adventure-profile", profile: %{id: p.id}) |> render_change()
    render_click(view, "manage-section", %{"section" => "templates"})
    today = CozyCheckout.Adventure.Sources.Stays.today()

    view
    |> form("#adventure-template-form",
      template: %{title: "Každodenní úklid", starts_on: Date.to_iso8601(today), cadence: "daily"}
    )
    |> render_submit()

    template = Repo.get_by!(TaskTemplate, title: "Každodenní úklid")
    assert template.status == "paused"
    assert Repo.aggregate(Quest, :count) == 0

    view
    |> form("#template-status-#{template.id}", %{state: %{status: "active", open_choice: "keep"}})
    |> render_submit()

    view |> element("button[phx-click=generate-tasks]") |> render_click()
    task = Repo.one!(Quest)
    refute has_element?(view, "#adventure-task-board")
    refute has_element?(view, "button[phx-click=start-task]")

    view
    |> form("#template-status-#{template.id}", %{state: %{status: "paused", open_choice: "keep"}})
    |> render_submit()

    assert Repo.get!(Quest, task.id).status == "waiting"
    assert has_element?(view, "#template-#{template.id}", "Pozastaveno")
    view |> element("button[phx-click=generate-tasks]") |> render_click()
    assert Repo.aggregate(Quest, :count) == 1
    assert Repo.aggregate(XpTransaction, :count) == 0
    {:ok, camp, _} = live(conn, "/admin/adventure")
    camp |> form("#adventure-profile", profile: %{id: p.id}) |> render_change()
    camp |> element("#adventure-find-quest") |> render_click()
    assert has_element?(camp, "#pick-quest-#{task.id}", "Každodenní úklid")
    camp |> element("#pick-quest-#{task.id} button") |> render_click()
    assert has_element?(camp, "#adventure-quest-#{task.id}")
  end

  test "camp uses a game shell and links to operational areas without creating rewards", %{
    conn: conn
  } do
    {:ok, _} = Adventure.initialize()
    {:ok, camp, _} = live(conn, "/admin/adventure")
    assert has_element?(camp, "#adventure-game-layout")
    refute has_element?(camp, "#admin-sidebar")
    assert has_element?(camp, "#adventure-world-map a[href='/admin/bookings/calendar']")
    assert has_element?(camp, "#adventure-world-map a[href='/admin/meal-planner']")
    assert has_element?(camp, "#adventure-world-map a[href='/admin/bar-stock']")
    assert has_element?(camp, "#adventure-world-map a[href='/admin/billing']")
    assert has_element?(camp, "#adventure-shared-expeditions")
    refute has_element?(camp, "#activate-improvement")
    assert Repo.aggregate(Quest, :count) == 0
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "quest picker separates mine and shared work and cannot exceed personal slots", %{
    conn: conn
  } do
    {:ok, _} = Adventure.initialize()
    p = Repo.get_by!(Profile, slug: "michal")
    other = Repo.get_by!(Profile, slug: "lucka")
    {:ok, mine} = Tasks.create(p.id, %{"title" => "Moje práce"})

    {:ok, theirs} =
      Tasks.create(p.id, %{"title" => "Práce Lucky", "assigned_profile_id" => other.id})

    {:ok, shared} = Tasks.create(p.id, %{"title" => "Společná práce", "scope" => "shared"})
    {:ok, camp, _} = live(conn, "/admin/adventure")
    camp |> form("#adventure-profile", profile: %{id: p.id}) |> render_change()
    camp |> element("#adventure-find-quest") |> render_click()
    assert has_element?(camp, "#pick-quest-#{mine.id}")
    refute has_element?(camp, "#pick-quest-#{theirs.id}")
    refute has_element?(camp, "#pick-quest-#{shared.id}")
    render_click(camp, "picker-filter", %{"scope" => "shared"})
    assert has_element?(camp, "#pick-quest-#{shared.id}")
    camp |> element("#pick-quest-#{shared.id} button") |> render_click()
    assert has_element?(camp, "#adventure-shared-expeditions #adventure-quest-#{shared.id}")
    assert {:ok, %{quests: []}} = Adventure.dashboard(p.id)

    for code <- ["prepare_stay", "review_deposits", "shopping_plan"],
        do: Adventure.activate_quest(p.id, code)

    camp |> element("#adventure-find-quest") |> render_click()
    render_click(camp, "picker-filter", %{"scope" => "all"})
    assert has_element?(camp, "#pick-quest-#{mine.id} button[disabled]")
    render_click(camp, "start-task", %{"id" => mine.id})
    assert Repo.get!(Quest, mine.id).status == "waiting"
    assert render(camp) =~ "nejvýše 3"
  end

  test "season draft requires confirmation and profile; recalculation is explicit", %{
    conn: conn
  } do
    alias CozyCheckout.Adventure.{Campaign, Evaluation}
    {:ok, _} = Adventure.initialize()
    p = Repo.get_by!(Profile, slug: "michal")
    {:ok, view, _} = live(conn, "/admin/adventure/settings")
    today = CozyCheckout.Adventure.Sources.Stays.today()

    view
    |> form("#adventure-campaign-form",
      campaign: %{
        name: "Nová kampaň",
        starts_on: Date.to_iso8601(today),
        ends_on: Date.to_iso8601(Date.add(today, 30)),
        capacity: "45",
        completed_goal: "10",
        reserved_goal: "100",
        occupancy_goal: "50"
      }
    )
    |> render_submit()

    c = Repo.one!(Campaign)
    assert c.status == "draft"

    render_click(view, "activate-campaign", %{
      "campaign_id" => c.id,
      "activation" => %{"confirmed" => "true"}
    })

    assert Repo.get!(Campaign, c.id).status == "draft"
    view |> form("#adventure-profile", profile: %{id: p.id}) |> render_change()

    view
    |> form("#activate-campaign-#{c.id}", activation: %{confirmed: "false"})
    |> render_submit()

    assert Repo.get!(Campaign, c.id).status == "draft"

    view
    |> form("#activate-campaign-#{c.id}", activation: %{confirmed: "true"})
    |> render_submit()

    assert Repo.get!(Campaign, c.id).status == "active"
    assert Repo.aggregate(Evaluation, :count) == 0
    assert has_element?(view, "#campaign-#{c.id}", "Zatím nepřepočítáno")
    view |> element("#evaluate-campaign-#{c.id}") |> render_click()
    assert Repo.aggregate(Evaluation, :count) == 1
    assert has_element?(view, "#campaign-#{c.id}", "Kvalita dat:")
    assert Repo.aggregate(XpTransaction, :count) == 0
    Application.put_env(:cozy_checkout, :adventure_enabled, false)
    render_click(view, "evaluate-campaign", %{"id" => c.id})
    assert_redirect(view, "/admin")
    assert Repo.aggregate(Evaluation, :count) == 1
  end

  test "historical chronicle needs no goals and corrections preserve prior versions", %{
    conn: conn
  } do
    alias CozyCheckout.Adventure.{Campaign, Evaluation}
    {:ok, _} = Adventure.initialize()
    p = Repo.get_by!(Profile, slug: "michal")
    today = CozyCheckout.Adventure.Sources.Stays.today()
    {:ok, view, _} = live(conn, "/admin/adventure/settings")
    refute has_element?(view, "#campaign_capacity[required]")
    refute has_element?(view, "#campaign_completed_goal[required]")
    view |> form("#adventure-profile", profile: %{id: p.id}) |> render_change()

    view
    |> form("#adventure-campaign-form",
      campaign: %{
        name: "Minulá horská sezóna",
        starts_on: Date.to_iso8601(Date.add(today, -60)),
        ends_on: Date.to_iso8601(Date.add(today, -30))
      }
    )
    |> render_submit()

    c = Repo.one!(Campaign)
    assert c.rules_version == "season_v1"
    assert is_nil(c.capacity)
    assert is_nil(c.completed_goal)
    assert has_element?(view, "#activate-campaign-#{c.id}", "Zapsat historickou sezónu")

    view
    |> form("#activate-campaign-#{c.id}", activation: %{confirmed: "true"})
    |> render_submit()

    assert Repo.get!(Campaign, c.id).status == "closed"
    original = Repo.one!(Evaluation)
    assert original.version == 1
    assert has_element?(view, "#campaign-#{c.id} [data-metric=occupancy_percent]", "Nedostupné")
    refute has_element?(view, "#evaluate-campaign-#{c.id}")
    refute has_element?(view, "#campaign-#{c.id} .adventure-medals")

    view |> form("#correct-campaign-#{c.id}", correction: %{reason: ""}) |> render_submit()
    assert Repo.aggregate(Evaluation, :count) == 1

    view
    |> form("#correct-campaign-#{c.id}", correction: %{reason: "Doplněné konečné doklady"})
    |> render_submit()

    assert Repo.aggregate(Evaluation, :count) == 2
    assert Repo.get!(Evaluation, original.id).snapshot == original.snapshot
    assert render(view) =~ "Doplněné konečné doklady"
    assert has_element?(view, "#evaluation-#{original.id}", "verze 1")

    {:ok, camp, _} = live(conn, "/admin/adventure")
    assert has_element?(camp, "#campaign-#{c.id}", "Minulá horská sezóna")
    assert has_element?(camp, "[data-season-finances]", "Inkaso v období")
    refute has_element?(camp, "#correct-campaign-#{c.id}")
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "camp can search and read a historical season without recalculating it", %{conn: conn} do
    alias CozyCheckout.Adventure.{Campaigns, Evaluation}
    {:ok, _} = Adventure.initialize()
    p = Repo.get_by!(Profile, slug: "michal")
    today = CozyCheckout.Adventure.Sources.Stays.today()

    attrs = %{
      name: "Zimní kronika",
      starts_on: Date.add(today, -60),
      ends_on: Date.add(today, -30)
    }

    {:ok, winter} = Campaigns.create_historical(attrs, p.id)
    {:ok, summer} = Campaigns.create_historical(%{attrs | name: "Letní kronika"}, p.id)
    {:ok, camp, _} = live(conn, "/admin/adventure")

    camp |> form("#adventure-season-search", season: %{search: "Zimní"}) |> render_change()
    assert has_element?(camp, "#adventure-season-picker button", "Zimní kronika")
    refute has_element?(camp, "#adventure-season-picker button", "Letní kronika")

    camp
    |> element("#adventure-season-picker button[phx-value-id='#{winter.id}']")
    |> render_click()

    assert has_element?(camp, "#campaign-#{winter.id}")
    refute has_element?(camp, "#campaign-#{summer.id}")
    assert Repo.aggregate(Evaluation, :count) == 2
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "historical draft controls do not read the Prague date once per season", %{conn: conn} do
    alias CozyCheckout.Adventure.{Campaigns, Sources.Stays}
    {:ok, _} = Adventure.initialize()
    today = Stays.today()

    attrs = %{
      rules_version: "season_v1",
      starts_on: Date.add(today, -60),
      ends_on: Date.add(today, -30)
    }

    {:ok, _} = Campaigns.create(Map.put(attrs, :name, "První návrh"))

    {_, single_queries} =
      CozyCheckout.QueryRecorder.record(fn -> live(conn, "/admin/adventure/settings") end)

    for n <- 1..31, do: Campaigns.create(Map.put(attrs, :name, "Historický návrh #{n}"))

    {_, many_queries} =
      CozyCheckout.QueryRecorder.record(fn -> live(conn, "/admin/adventure/settings") end)

    date_queries = fn queries ->
      Enum.count(queries, &String.contains?(&1, "SELECT timezone('Europe/Prague'"))
    end

    assert date_queries.(many_queries) == date_queries.(single_queries)
  end
end

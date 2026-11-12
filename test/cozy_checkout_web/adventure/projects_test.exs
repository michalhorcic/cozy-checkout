defmodule CozyCheckoutWeb.AdventureProjectsLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckout.{Adventure, Repo}

  alias CozyCheckout.Adventure.{
    Profile,
    Project,
    ProjectStage,
    Projects,
    Quest,
    Tasks,
    XpTransaction
  }

  alias CozyCheckoutWeb.AdventureLive.ProjectComponents
  alias CozyCheckoutWeb.AdminAuth

  setup %{conn: conn} do
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

    {:ok, :ok} = Adventure.initialize()
    actor = Repo.get_by!(Profile, slug: "michal")
    conn = init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})
    %{conn: conn, actor: actor}
  end

  test "book creates a plan, links existing work and accepts only an explicit human result", %{
    conn: conn,
    actor: actor
  } do
    {:ok, quest} = Tasks.create(actor.id, %{"title" => "Skutečná práce"})
    {:ok, view, _} = live(conn, "/admin/adventure/quests?section=projects")
    render_click(view, "restore-profile", %{"id" => actor.id})
    assert has_element?(view, "#adventure-projects", "Projekty")
    refute has_element?(view, "#adventure-world-map")
    refute has_element?(view, "#project-form")
    render_click(view, "new-project")
    assert has_element?(view, "#project-optional-fields:not([open])")
    view |> form("#project-form", project: %{title: "Vlastní projekt"}) |> render_submit()
    project = Repo.one!(Project)
    assert has_element?(view, "#project-detail", "Vlastní projekt")
    refute has_element?(view, "#project-form")
    refute has_element?(view, "#project-quest-search")
    render_click(view, "project-stage-editor", %{"mode" => "link"})
    view |> form("#project-quest-search", search: %{query: "Skutečná"}) |> render_submit()
    assert has_element?(view, "#project-stage-form input[value='#{quest.id}']")

    view
    |> form("#project-stage-form", stage: %{quest_id: quest.id, output: "Funkční výsledek"})
    |> render_submit()

    assert has_element?(view, "#project-#{project.id}", "0 z 1 kroků hotovo")
    refute has_element?(view, "#project-stage-form")

    assert has_element?(
             view,
             "#project-detail button.adventure-button--primary",
             "Schválit a zahájit"
           )

    render_click(view, "project-status", %{"id" => project.id, "status" => "active"})

    refute has_element?(view, "#project-stage-form")
    refute has_element?(view, "#project-acceptance")
    refute has_element?(view, "button[phx-click=project-acceptance-editor]", "Převzít výsledek")

    render_submit(view, "accept-project", %{
      "acceptance" => %{"confirmed" => "true", "contributors" => [actor.id]}
    })

    refute has_element?(view, "#project-accepted")
    {:ok, _} = Tasks.start(actor.id, quest.id)
    {:ok, _} = Tasks.complete(actor.id, quest.id)
    render_click(view, "refresh-projects")
    assert has_element?(view, "#project-#{project.id}", "1 z 1 kroků hotovo")
    refute has_element?(view, "#project-accepted")
    refute has_element?(view, "#project-acceptance")

    {_, acceptance_queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "project-acceptance-editor", %{"open" => "true"})
          render_click(view, "project-acceptance-editor", %{"open" => "false"})
          render_click(view, "project-acceptance-editor", %{"open" => "true"})
        end,
        view.pid
      )

    assert acceptance_queries == []
    assert has_element?(view, "#project-acceptance")
    refute has_element?(view, "#project-acceptance input[checked]")

    view |> form("#project-acceptance", acceptance: %{confirmed: "true"}) |> render_submit()
    assert has_element?(view, "#project-acceptance")
    refute has_element?(view, "#project-accepted")

    render_submit(view, "accept-project", %{
      "acceptance" => %{
        "confirmed" => "true",
        "contributors" => [actor.id],
        "result" => "Převzato člověkem"
      }
    })

    assert has_element?(view, "#project-accepted", "Převzato člověkem")
    assert has_element?(view, "#project-audit:not([open])", "Výsledek převzat")
    assert Repo.aggregate(XpTransaction, :count) == 1
    assert {:ok, reopened, _} = live(conn, "/admin/adventure/quests?section=projects")
    render_click(reopened, "select-project", %{"id" => project.id})
    assert has_element?(reopened, "#project-accepted", "Převzato člověkem")
    assert Repo.aggregate(XpTransaction, :count) == 1
  end

  test "workshop is a project hub, while general projects retain their stored area", %{
    conn: conn,
    actor: actor
  } do
    {:ok, project} =
      Projects.create(actor.id, %{"title" => "Společný plán"}, Ecto.UUID.generate())

    assert project.area == "workshop"
    {:ok, camp, _} = live(conn, "/admin/adventure")
    render_click(camp, "operation-area", %{"area" => "workshop"})
    assert has_element?(camp, "#adventure-area-detail", "Dílna projektů")
    refute has_element?(camp, "#adventure-area-detail .adventure-world-development")
    refute has_element?(camp, "#adventure-area-workshop .adventure-world-milestone")
    refute has_element?(camp, "#adventure-area-workshop .adventure-world-plans")
    render_click(camp, "operation-area", %{"area" => "rooms"})
    projects_path = ~p"/admin/adventure/quests?#{%{section: "projects", project_area: "rooms"}}"

    assert has_element?(
             camp,
             "#adventure-area-detail a[href='#{projects_path}']"
           )

    {:ok, book, _} = live(conn, projects_path)
    render_click(book, "restore-profile", %{"id" => actor.id})
    assert has_element?(book, "#project-#{project.id}", "Celá chata")
    render_click(book, "new-project")

    assert has_element?(
             book,
             "#project-form select[name='project[area]'] option[value=rooms][selected]"
           )

    book
    |> form("#project-form", project: %{title: "Pokoje mají vlastní plán"})
    |> render_submit()

    assert Repo.get_by!(Project, title: "Pokoje mají vlastní plán").area == "rooms"
    assert Repo.get!(Project, project.id).area == "workshop"
  end

  test "project selection collapses the chooser and keeps completed work in a separate group", %{
    conn: conn,
    actor: actor
  } do
    {:ok, current} = Projects.create(actor.id, %{"title" => "Dnešní práce"}, Ecto.UUID.generate())
    {:ok, closed} = Projects.create(actor.id, %{"title" => "Starý plán"}, Ecto.UUID.generate())
    {:ok, _} = Projects.transition(actor.id, closed.id, "cancelled")
    {:ok, _} = Projects.archive(actor.id, closed.id)
    {:ok, view, _} = live(conn, "/admin/adventure/quests?section=projects")
    assert has_element?(view, "#project-chooser[open]")
    assert has_element?(view, "details.adventure-project-group[open] #project-#{current.id}")
    assert has_element?(view, "details.adventure-project-group:not([open]) #project-#{closed.id}")
    render_click(view, "select-project", %{"id" => current.id})
    assert has_element?(view, "#project-chooser:not([open])")
    assert has_element?(view, "#project-detail-title[tabindex='-1']", "Dnešní práce")

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn -> render_click(view, "close-project-detail") end,
        view.pid
      )

    assert queries == []
    assert has_element?(view, "#project-chooser[open]")
    refute has_element?(view, "#project-detail")
  end

  test "project step leads to that exact quest in camp without starting it", %{
    conn: conn,
    actor: actor
  } do
    {:ok, project} = Projects.create(actor.id, %{"title" => "Oprava"}, Ecto.UUID.generate())
    {:ok, quest} = Tasks.create(actor.id, %{"title" => "Konkrétní krok"})
    {:ok, _} = Projects.add_stage(actor.id, project.id, quest.id, "Opraveno")

    {:ok, view, _} =
      live(conn, "/admin/adventure/quests?section=projects&project_id=#{project.id}")

    assert has_element?(
             view,
             "#project-detail a[href='/admin/adventure?quest_id=#{quest.id}']",
             "Přijmout v táboře"
           )

    {:ok, camp, _} = live(conn, "/admin/adventure?quest_id=#{quest.id}")
    refute has_element?(camp, "#adventure-duty-detail-modal")
    render_click(camp, "restore-profile", %{"id" => actor.id})
    assert has_element?(camp, "#adventure-duty-detail-modal", "Konkrétní krok")
    assert has_element?(camp, "#adventure-duty-detail-modal button[phx-click=start-task]")
    refute has_element?(camp, "#adventure-duty-detail-modal", "Změna provozního podkladu")
    assert Repo.get!(Quest, quest.id).status == "waiting"
    assert Repo.aggregate(XpTransaction, :count) == 0
    render_click(camp, "start-task", %{"id" => quest.id})
    assert Repo.get!(Quest, quest.id).status == "active"
    refute has_element?(camp, "#adventure-duty-detail-modal")
    assert has_element?(camp, "#adventure-context[data-panel=continue]", "Konkrétní krok")

    camp
    |> element(
      "#adventure-context .adventure-quest-focus button[phx-click=prepare-completion][phx-value-id='#{quest.id}']"
    )
    |> render_click()

    assert has_element?(camp, "#adventure-completion")
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "PIN, feature flag and explicit hero protect project actions", %{conn: conn, actor: actor} do
    assert build_conn() |> get("/admin/adventure/quests?section=projects") |> redirected_to() =~
             "/admin/login"

    {:ok, view, _} = live(conn, "/admin/adventure/quests?section=projects")
    render_click(view, "new-project")
    view |> form("#project-form", project: %{title: "Bez hrdiny"}) |> render_submit()
    assert Repo.aggregate(Project, :count) == 0
    render_click(view, "restore-profile", %{"id" => actor.id})
    view |> form("#project-form", project: %{title: "S hrdinou"}) |> render_submit()
    assert Repo.aggregate(Project, :count) == 1
    Application.put_env(:cozy_checkout, :adventure_enabled, false)
    render_click(view, "refresh-projects")
    assert_redirect(view, "/admin")
    assert Repo.aggregate(Project, :count) == 1
  end

  test "inline step has one required name, closes after save and is read first", %{
    conn: conn,
    actor: actor
  } do
    {:ok, p} =
      Projects.create(
        actor.id,
        %{"title" => "Kompaktní plán", "due_on" => "2026-11-12"},
        Ecto.UUID.generate()
      )

    {:ok, view, _} = live(conn, "/admin/adventure/quests?section=projects&project_id=#{p.id}")
    render_click(view, "restore-profile", %{"id" => actor.id})
    assert has_element?(view, "#project-detail", "12. 11. 2026")
    refute has_element?(view, "#project-new-stage-form")
    refute has_element?(view, "#project-detail", "Plánovaný rozpočet nezadán")

    {_, opening_queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "project-stage-editor", %{"mode" => "new"})
          render(view)
        end,
        view.pid
      )

    assert opening_queries == []
    assert has_element?(view, "#project-new-stage-form input[name='step[title]'][required]")
    refute has_element?(view, "#project-new-stage-form input[name='step[output]'][required]")
    refute has_element?(view, "#project-new-stage-form input[type=date][required]")

    view |> form("#project-new-stage-form", step: %{title: "Opravit dveře"}) |> render_submit()
    q = Repo.one!(Quest)
    stage = Repo.one!(ProjectStage)
    assert q.status == "waiting"
    assert q.due_on == nil
    assert stage.output == "Opravit dveře"
    assert stage.quest_id == q.id
    assert has_element?(view, "#project-stage-#{stage.id}", "Čeká")
    refute has_element?(view, "#project-new-stage-form")
    refute has_element?(view, "#project-stage-edit-#{stage.id}")
    assert Repo.aggregate(XpTransaction, :count) == 0

    {_, edit_queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "project-stage-editor", %{"mode" => stage.id})
          render(view)
        end,
        view.pid
      )

    assert edit_queries == []

    view
    |> form("#project-stage-edit-#{stage.id}", stage: %{output: "Dveře těsní"})
    |> render_submit()

    refute has_element?(view, "#project-stage-edit-#{stage.id}")
    assert has_element?(view, "#project-stage-#{stage.id}", "Dveře těsní")
    assert has_element?(view, "#project-stage-#{stage.id}", "Quest: Opravit dveře")

    render_click(view, "edit-project", %{"id" => p.id})

    view
    |> form("#project-form", project: %{title: "Upravený plán", due_on: ""})
    |> render_submit()

    refute has_element?(view, "#project-form")
    assert Repo.get!(Project, p.id).due_on == nil
    assert has_element?(view, "#project-detail", "Upravený plán")
    render_click(view, "edit-project", %{"id" => p.id})
    assert has_element?(view, "#project-form")
    render_click(view, "project-status", %{"id" => p.id, "status" => "active"})
    refute has_element?(view, "#project-form")
    render_click(view, "project-status", %{"id" => p.id, "status" => "paused"})

    assert has_element?(
             view,
             "#project-detail button.adventure-button--primary",
             "Obnovit realizaci"
           )

    render_click(view, "project-status", %{"id" => p.id, "status" => "active"})
    refute has_element?(view, "#project-detail button[phx-click=edit-project]")
    refute has_element?(view, "#project-detail button[phx-value-mode=new]")
    assert Repo.get!(Quest, q.id).status == "waiting"
  end

  test "invalid inline quest keeps the editor without orphaned work", %{conn: conn, actor: actor} do
    {:ok, p} = Projects.create(actor.id, %{"title" => "Plán"}, Ecto.UUID.generate())
    {:ok, view, _} = live(conn, "/admin/adventure/quests?section=projects&project_id=#{p.id}")
    render_click(view, "restore-profile", %{"id" => actor.id})
    render_click(view, "project-stage-editor", %{"mode" => "new"})
    view |> form("#project-new-stage-form", step: %{title: "", xp: "0"}) |> render_submit()
    assert has_element?(view, "#project-new-stage-form")
    assert has_element?(view, "#project-new-stage-form details[open]")
    assert Repo.aggregate(Quest, :count) == 0
    assert Repo.aggregate(ProjectStage, :count) == 0
    render_click(view, "project-stage-editor", %{"mode" => "close"})
    refute has_element?(view, "#project-new-stage-form")
  end

  test "Czech project dates and explicit UTC audit times are pure presentation" do
    {_, queries} =
      CozyCheckout.QueryRecorder.record(fn ->
        assert ProjectComponents.format_project_date(~D[2026-11-12]) == "12. 11. 2026"
        assert ProjectComponents.format_project_date("2026-11-12T17:24:16Z") == "12. 11. 2026"
        assert ProjectComponents.format_project_date("2026-01-02") == "2. 1. 2026"

        assert ProjectComponents.audit_datetime(~U[2026-11-12 17:24:16Z]) ==
                 "12. 11. 2026 17:24:16 UTC"

        assert ProjectComponents.audit_datetime("2026-11-12T18:24:16+01:00") ==
                 "12. 11. 2026 17:24:16 UTC"

        assert ProjectComponents.format_project_date(nil) == "Datum neznámé"
        assert ProjectComponents.format_project_date("invalid") == "Datum neznámé"
      end)

    assert queries == []
  end

  test "project UI selection and render never load operational sources or per-stage queries", %{
    conn: conn,
    actor: actor
  } do
    {:ok, p} = Projects.create(actor.id, %{"title" => "Plán"}, Ecto.UUID.generate())
    {:ok, view, _} = live(conn, "/admin/adventure/quests?section=projects")

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "select-project", %{"id" => p.id})
          render(view)
        end,
        view.pid
      )

    assert length(queries) == 1
    assert hd(queries) =~ "adventure_project_events"
  end

  test "map milestones and permanent chronicle show historical archived acceptance without query on area switches",
       %{conn: conn, actor: actor} do
    {:ok, p} =
      Projects.create(
        actor.id,
        %{"title" => "Trvalé zlepšení", "area" => "rooms"},
        Ecto.UUID.generate()
      )

    {:ok, q} = Tasks.create(actor.id, %{"title" => "Skutečně provést"})
    {:ok, _} = Projects.add_stage(actor.id, p.id, q.id, "Funkční výstup")
    for status <- ~w(ready approved active), do: Projects.transition(actor.id, p.id, status)
    {:ok, _} = Tasks.start(actor.id, q.id)
    {:ok, _} = Tasks.complete(actor.id, q.id)

    {:ok, accepted} =
      Projects.accept(actor.id, p.id, %{
        "confirmed" => "true",
        "contributors" => [actor.id],
        "result" => "Nový výsledek pro hosty"
      })

    accepted
    |> Ecto.Changeset.change(
      acceptance: Map.put(accepted.acceptance, "confirmed_at", "2026-11-12T17:24:16Z")
    )
    |> Repo.update!()

    {:ok, _} = Projects.archive(actor.id, p.id)
    {:ok, view, _} = live(conn, "/admin/adventure")
    render(view)

    assert has_element?(
             view,
             "#adventure-area-rooms.adventure-village-place--developed .adventure-world-decoration[aria-label='1 převzatých zlepšení']"
           )

    refute has_element?(view, "#cabin-outcome-#{p.id}")

    {_, switches} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          for area <- ~w(rooms kitchen bar treasury workshop reception rooms),
              do: render_click(view, "operation-area", %{"area" => area})

          render(view)
        end,
        view.pid
      )

    assert switches == []
    assert has_element?(view, "#adventure-area-detail", "Nový výsledek pro hosty")
    assert has_element?(view, "#adventure-area-detail", "Převzato 12. 11. 2026")
    refute has_element?(view, "#adventure-area-detail", "2026-11-12T17:24:16Z")
    assert has_element?(view, "#adventure-area-detail", "archiv")

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn -> render_click(view, "cabin-chronicle", %{"direction" => "first"}) end,
        view.pid
      )

    assert length(queries) == 1
    assert hd(queries) =~ "adventure_projects"
    assert has_element?(view, "#cabin-outcome-#{p.id}", "Nový výsledek pro hosty")
    assert has_element?(view, "#cabin-outcome-#{p.id}", actor.display_name)
    assert has_element?(view, "#cabin-outcome-#{p.id}", "Převzato 12. 11. 2026")
    assert has_element?(view, "#cabin-outcome-#{p.id}", "Funkční výstup")

    {_, refresh} =
      CozyCheckout.QueryRecorder.record(fn -> render_click(view, "refresh-world") end, view.pid)

    assert length(refresh) == 2
    assert Enum.all?(refresh, &String.contains?(&1, "adventure_projects"))
    assert Repo.aggregate(XpTransaction, :count) == 1

    for i <- 1..101 do
      {:ok, _} =
        Projects.create(actor.id, %{"title" => "Novější návrh #{i}"}, Ecto.UUID.generate())
    end

    assert {:ok, detail, _} =
             live(conn, "/admin/adventure/quests?section=projects&project_id=#{p.id}")

    assert has_element?(detail, "#project-accepted", "Nový výsledek pro hosty")
  end

  test "compact recurring controls explicitly keep or cancel work and load archive and history only on demand",
       %{conn: conn, actor: actor} do
    alias CozyCheckout.Adventure.{Templates, TaskTemplate, Quest}
    today = CozyCheckout.Adventure.Sources.Stays.today()

    {:ok, t} =
      Templates.create(actor.id, %{
        "title" => "A Opakovaná práce",
        "starts_on" => Date.to_iso8601(today)
      })

    {:ok, _} = Templates.set_status(actor.id, t.id, "active", "keep")
    {:ok, _} = Templates.generate()
    q = Repo.get_by!(Quest, template_id: t.id)
    t = Repo.get!(TaskTemplate, t.id)

    t
    |> Ecto.Changeset.change(last_check: %{"state" => "unknown", "day" => Date.to_iso8601(today)})
    |> Repo.update!()

    {:ok, view, _} = live(conn, "/admin/adventure/quests?section=templates")
    render_click(view, "restore-profile", %{"id" => actor.id})
    assert has_element?(view, "#template-#{t.id} .adventure-template-details:not([open])")
    assert has_element?(view, "#template-#{t.id} > p", "Podmínku nelze ověřit")
    refute has_element?(view, "#template-#{t.id} select")

    {_, confirm_queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "confirm-template-status", %{"id" => t.id, "status" => "paused"})
          render_click(view, "cancel-template-status")
        end,
        view.pid
      )

    assert confirm_queries == []
    assert Repo.get!(TaskTemplate, t.id).status == "active"
    render_click(view, "confirm-template-status", %{"id" => t.id, "status" => "paused"})
    render_click(view, "apply-template-status", %{"choice" => "keep"})
    assert Repo.get!(Quest, q.id).status == "waiting"
    assert Repo.get!(TaskTemplate, t.id).status == "paused"
    render_click(view, "confirm-template-status", %{"id" => t.id, "status" => "archived"})
    render_click(view, "apply-template-status", %{"choice" => "invalid"})
    assert has_element?(view, "#template-confirm-#{t.id}")
    assert Repo.get!(TaskTemplate, t.id).status == "paused"
    render_click(view, "apply-template-status", %{"choice" => "cancel"})
    assert Repo.get!(Quest, q.id).status == "cancelled"
    assert Repo.get!(Quest, q.id).archived_at
    refute has_element?(view, "#template-#{t.id}")

    {_, archive_queries} =
      CozyCheckout.QueryRecorder.record(
        fn -> render_click(view, "template-view", %{"view" => "archive"}) end,
        view.pid
      )

    assert length(archive_queries) == 2

    assert Enum.all?(
             archive_queries,
             &(String.contains?(&1, "adventure_task_templates") or
                 String.contains?(&1, "adventure_quests"))
           )

    assert has_element?(view, "#template-#{t.id}", "Archivováno")
    refute has_element?(view, "#template-#{t.id} button[phx-click=resume-template]")

    {_, current_queries} =
      CozyCheckout.QueryRecorder.record(
        fn -> render_click(view, "template-view", %{"view" => "current"}) end,
        view.pid
      )

    assert length(current_queries) == 2
    assert Enum.all?(current_queries, &String.starts_with?(&1, "SELECT"))
    refute has_element?(view, "#template-#{t.id}")

    {_, history_queries} =
      CozyCheckout.QueryRecorder.record(
        fn -> render_click(view, "template-history") end,
        view.pid
      )

    assert length(history_queries) == 1
    assert hd(history_queries) =~ "adventure_template_versions"
    assert Repo.aggregate(XpTransaction, :count) == 0
  end
end

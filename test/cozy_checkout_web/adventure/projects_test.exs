defmodule CozyCheckoutWeb.AdventureProjectsLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckout.{Adventure, Repo}
  alias CozyCheckout.Adventure.{Profile, Project, Projects, Tasks, XpTransaction}
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
    assert has_element?(view, "#adventure-projects", "Kniha projektů")
    refute has_element?(view, "#adventure-world-map")
    view |> form("#project-form", project: %{title: "Vlastní projekt"}) |> render_submit()
    project = Repo.one!(Project)
    assert has_element?(view, "#project-detail", "Vlastní projekt")
    view |> form("#project-quest-search", search: %{query: "Skutečná"}) |> render_submit()
    assert has_element?(view, "#project-stage-form input[value='#{quest.id}']")

    view
    |> form("#project-stage-form", stage: %{quest_id: quest.id, output: "Funkční výsledek"})
    |> render_submit()

    assert has_element?(view, "#project-#{project.id}", "0 z 1 etap")

    for status <- ~w(ready approved active),
        do: render_click(view, "project-status", %{"id" => project.id, "status" => status})

    refute has_element?(view, "#project-stage-form")
    assert has_element?(view, "#project-acceptance")

    render_submit(view, "accept-project", %{
      "acceptance" => %{"confirmed" => "true", "contributors" => [actor.id]}
    })

    refute has_element?(view, "#project-accepted")
    {:ok, _} = Tasks.start(actor.id, quest.id)
    {:ok, _} = Tasks.complete(actor.id, quest.id)
    render_click(view, "refresh-projects")
    assert has_element?(view, "#project-#{project.id}", "1 z 1 etap")
    refute has_element?(view, "#project-accepted")

    render_submit(view, "accept-project", %{
      "acceptance" => %{
        "confirmed" => "true",
        "contributors" => [actor.id],
        "result" => "Převzato člověkem"
      }
    })

    assert has_element?(view, "#project-accepted", "Převzato člověkem")
    assert has_element?(view, "#project-audit", "accepted")
    assert Repo.aggregate(XpTransaction, :count) == 1
    assert {:ok, reopened, _} = live(conn, "/admin/adventure/quests?section=projects")
    render_click(reopened, "select-project", %{"id" => project.id})
    assert has_element?(reopened, "#project-accepted", "Převzato člověkem")
    assert Repo.aggregate(XpTransaction, :count) == 1
  end

  test "PIN, feature flag and explicit hero protect project actions", %{conn: conn, actor: actor} do
    assert build_conn() |> get("/admin/adventure/quests?section=projects") |> redirected_to() =~
             "/admin/login"

    {:ok, view, _} = live(conn, "/admin/adventure/quests?section=projects")
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
end

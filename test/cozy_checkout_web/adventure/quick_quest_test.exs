defmodule CozyCheckoutWeb.AdventureQuickQuestTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckout.{Adventure, QueryRecorder, Repo}
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

    {:ok, _} = Adventure.initialize()
    conn = init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    %{
      conn: conn,
      actor: Repo.get_by!(Profile, slug: "michal"),
      other: Repo.get_by!(Profile, slug: "lucka")
    }
  end

  test "both game entries require a selected hero; editing and cancellation use no queries", %{
    conn: conn,
    actor: actor
  } do
    {:ok, view, _} = live(conn, "/admin/adventure")
    assert has_element?(view, "#adventure-quick-new-world[disabled]")
    assert has_element?(view, "#adventure-quick-new-expeditions[disabled]")
    render_click(view, "new-quick-task")
    refute has_element?(view, "#adventure-quick-task-modal")
    render_click(view, "restore-profile", %{"id" => actor.id})

    {_, queries} =
      QueryRecorder.record(
        fn ->
          view |> element("#adventure-quick-new-world") |> render_click()

          view
          |> form("#adventure-quick-task-form",
            quick: %{title: "Připravit dřevo", category: "Údržba"}
          )
          |> render_change()

          for category <- Quest.categories(),
              do: assert(has_element?(view, "#quick_category option", category))

          render_click(view, "cancel-quick-task")
        end,
        view.pid
      )

    assert queries == []
    assert Repo.aggregate(Quest, :count) == 0
  end

  test "creation from expeditions retains category and returns to the active quest without a detail card",
       %{conn: conn, actor: actor} do
    {:ok, view, _} = live(conn, "/admin/adventure?view=expeditions")
    render_click(view, "restore-profile", %{"id" => actor.id})
    snapshot = :sys.get_state(view.pid).socket.assigns.operation
    view |> element("#adventure-quick-new-expeditions") |> render_click()
    request = :sys.get_state(view.pid).socket.assigns.quick_task.id
    assert has_element?(view, "input[name='quick[disposition]'][value=mine][checked]")

    view
    |> form("#adventure-quick-task-form",
      quick: %{title: "Nachystat bar", category: "Bar", size: "large"}
    )
    |> render_submit()

    assert_patch(view, "/admin/adventure?view=world")
    refute has_element?(view, "#adventure-quick-task-modal")
    refute has_element?(view, "#adventure-duty-detail-modal")
    assert has_element?(view, "#adventure-context[data-panel=continue]", "Nachystat bar")
    task = Repo.get!(Quest, request)
    assert task.status == "active"
    assert task.assigned_profile_id == actor.id
    assert task.category == "Bar"
    assert task.definition_snapshot["xp"] == 250
    assert :sys.get_state(view.pid).socket.assigns.operation == snapshot
    render_submit(view, "save-quick-task", %{"quick" => %{"title" => "Dvojklik"}})
    assert Repo.aggregate(Quest, :count) == 1
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "a free quest is unassigned and validation preserves the selected recipient", %{
    conn: conn,
    actor: actor,
    other: other
  } do
    {:ok, view, _} = live(conn, "/admin/adventure")
    render_click(view, "restore-profile", %{"id" => actor.id})
    render_click(view, "new-quick-task")

    view
    |> form("#adventure-quick-task-form", quick: %{title: "", disposition: "free"})
    |> render_submit()

    assert has_element?(view, "#adventure-quick-task-modal input[value=free][checked]")
    assert Repo.aggregate(Quest, :count) == 0

    view
    |> form("#adventure-quick-task-form", quick: %{title: "Vybrat recepty", category: "Kuchyně"})
    |> render_submit()

    task = Repo.one!(Quest)
    assert task.status == "waiting"
    assert task.assigned_profile_id == nil
    assert task.category == "Kuchyně"
    assert {:ok, _} = Tasks.start(other.id, task.id)
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "a race for the last slot preserves the draft and allows explicit save for later", %{
    conn: conn,
    actor: actor
  } do
    {:ok, view, _} = live(conn, "/admin/adventure")
    render_click(view, "restore-profile", %{"id" => actor.id})
    render_click(view, "new-quick-task")
    request = :sys.get_state(view.pid).socket.assigns.quick_task.id

    for code <- ~w(prepare_stay review_deposits shopping_plan),
        do: Adventure.activate_quest(actor.id, code)

    view
    |> form("#adventure-quick-task-form", quick: %{title: "Pozdější údržba", category: "Údržba"})
    |> render_submit()

    assert has_element?(view, "#adventure-quick-task-form button", "Uložit na později")
    refute Repo.get(Quest, request)
    view |> form("#adventure-quick-task-form") |> render_submit()
    task = Repo.get!(Quest, request)
    assert task.status == "waiting"
    assert task.assigned_profile_id == actor.id
    assert task.category == "Údržba"
    refute has_element?(view, "#adventure-quick-task-modal")
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "changing heroes discards the previous hero draft", %{
    conn: conn,
    actor: actor,
    other: other
  } do
    {:ok, view, _} = live(conn, "/admin/adventure")
    render_click(view, "restore-profile", %{"id" => actor.id})
    render_click(view, "new-quick-task")
    render_click(view, "restore-profile", %{"id" => other.id})
    refute has_element?(view, "#adventure-quick-task-modal")
    render_submit(view, "save-quick-task", %{"quick" => %{"title" => "Starý návrh"}})
    assert Repo.aggregate(Quest, :count) == 0
  end
end

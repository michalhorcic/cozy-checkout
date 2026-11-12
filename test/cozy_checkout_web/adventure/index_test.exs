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

  test "operational map shares one mount snapshot and refreshes only explicitly", %{conn: conn} do
    {:ok, _} = Adventure.initialize()
    table = :ets.new(:operation_source_queries, [:public, :ordered_set])
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:cozy_checkout, :repo, :query],
        &__MODULE__.operation_query/4,
        table
      )

    try do
      assert get(conn, "/admin/adventure").status == 200
      assert :ets.info(table, :size) == 0
      {:ok, view, _} = live(conn, "/admin/adventure")
      assert has_element?(view, "#adventure-operation-status", "Bez automatické obnovy")
      initial = :ets.info(table, :size)
      assert initial > 0
      assert initial <= 15

      areas = ["rooms", "kitchen", "bar", "treasury", "workshop", "reception"]
      assert has_element?(view, "#adventure-area-reception[aria-pressed=false]")
      assert has_element?(view, "#adventure-area-rooms[aria-pressed=false]")

      for area <- areas do
        view |> element("#adventure-area-#{area}") |> render_click()
        assert has_element?(view, "#adventure-area-#{area}[aria-pressed=true]")

        for other <- areas -- [area] do
          assert has_element?(view, "#adventure-area-#{other}[aria-pressed=false]")
        end
      end

      assert render(view) =~ "Dnes na chatě"
      render_click(view, "restore-profile", %{"id" => Repo.get_by!(Profile, slug: "michal").id})
      render_click(view, "picker-filter", %{"scope" => "all"})
      assert :ets.info(table, :size) == initial
      assert has_element?(view, "#adventure-area-detail a[href='/admin/bookings/calendar']")

      view |> element("#adventure-operation-refresh") |> render_click()
      assert has_element?(view, "#adventure-operation-status", "Bez automatické obnovy")
      assert :ets.info(table, :size) == 2 * initial
      assert Repo.aggregate(XpTransaction, :count) == 0

      before_disable = :ets.info(table, :size)
      Application.put_env(:cozy_checkout, :adventure_enabled, false)
      render_click(view, "refresh-operation")
      assert_redirect(view, "/admin")
      assert :ets.info(table, :size) == before_disable
    after
      :telemetry.detach(handler)
      :ets.delete(table)
    end
  end

  test "map details link to real tools and finance stays explicitly seasonal", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/adventure")

    for {area, panel, href} <- [
          {"kitchen", "#adventure-area-detail", "/admin/meal-planner"},
          {"bar", "#adventure-bar-stock", "/admin/bar-stock"},
          {"treasury", "#adventure-area-detail", "/admin/billing"},
          {"workshop", "#adventure-area-detail", "/admin/adventure/quests?section=projects"}
        ] do
      render_click(view, "operation-area", %{"area" => area})
      assert has_element?(view, "#{panel} a[href='#{href}']")
    end

    for area <- ~w(reception rooms) do
      render_click(view, "operation-area", %{"area" => area})
      refute has_element?(view, "#adventure-area-detail", "Neověřuje přítomnost")
      refute has_element?(view, "#adventure-area-detail", "Obsazenost zahrnuje")
    end

    render_click(view, "operation-area", %{"area" => "kitchen"})
    refute has_element?(view, "#adventure-area-detail", "Plánované porce nejsou uvařené jídlo")

    render_click(view, "operation-area", %{"area" => "bar"})

    assert has_element?(
             view,
             "#adventure-area-detail a[href='/admin/adventure?view=chronicle&tab=seasons']",
             "Kronika baru"
           )

    render_click(view, "operation-area", %{"area" => "treasury"})

    assert has_element?(
             view,
             "#adventure-treasury-help:not([open])",
             "Obnova provozu je nepřepočítává"
           )

    assert has_element?(
             view,
             "#adventure-area-detail a[href='/admin/adventure?view=chronicle&tab=seasons']"
           )

    {:ok, book, _} = live(conn, "/admin/adventure/quests")
    refute has_element?(book, "#adventure-world-map")
  end

  def operation_query(_, _, metadata, table) do
    if Regex.match?(
         ~r/\b(?:FROM|JOIN)\s+"(?:bookings|guests|rooms|booking_rooms|booking_menus|booking_menu_items|recipes|booking_menu_supplements)"/,
         metadata.query
       ) do
      :ets.insert(table, {System.unique_integer([:monotonic]), metadata.query})
    end
  end

  test "mine returns to the lodge focused on the newly active expedition", %{conn: conn} do
    {view, actor, _booking} = duty_view(conn)
    render_click(view, "world-panel", %{"panel" => "duty"})
    render_click(view, "prepare-duty", %{"source" => duty_source(view)})
    assert has_element?(view, ".adventure-duty-choice input[value=free][checked]")

    view
    |> form("#adventure-duty-form", duty: %{disposition: "mine", title: "Moje nová výprava"})
    |> render_change()

    assert has_element?(view, "#adventure-duty-form button", "Vytvořit a vyrazit")
    view |> form("#adventure-duty-form") |> render_submit()
    refute has_element?(view, "#adventure-duty-modal")
    refute has_element?(view, "#adventure-duty-detail-modal")
    quest = Repo.get_by!(Quest, assigned_profile_id: actor.id)
    assert quest.status == "active"
    assert has_element?(view, "#adventure-context[data-panel=continue]", "Moje nová výprava")
    assert :sys.get_state(view.pid).socket.assigns.focus_quest_id == quest.id
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "full slots keep the illustrated draft and create no extra quest", %{conn: conn} do
    {view, actor, _booking} = duty_view(conn)

    for code <- ~w(prepare_stay review_deposits shopping_plan),
        do: Adventure.activate_quest(actor.id, code)

    render_click(view, "prepare-duty", %{"source" => duty_source(view)})
    request = :sys.get_state(view.pid).socket.assigns.duty_draft.request_key
    render_submit(view, "save-duty", %{"duty" => %{"title" => "Další", "disposition" => "mine"}})
    assert has_element?(view, "#adventure-duty-modal")
    assert has_element?(view, ".adventure-duty-choice input[value=mine][checked]")
    refute Repo.get_by(Quest, source_request_key: request)
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "duty drafts validate snapshot membership and cancel without any SELECT", %{conn: conn} do
    {view, _profile, booking} = duty_view(conn)

    with_duty_queries(fn queries ->
      render_click(view, "prepare-duty", %{"source" => "999", "booking_id" => booking.id})
      refute has_element?(view, "#adventure-duty-modal")
      render_click(view, "prepare-duty", %{"source" => "-1"})
      render_click(view, "prepare-duty", %{"source" => "0junk"})
      refute has_element?(view, "#adventure-duty-modal")
      view |> element("#adventure-duty-0 button", "Připravit quest") |> render_click()
      assert has_element?(view, "#adventure-duty-modal [role=dialog][aria-modal=true]")
      assert has_element?(view, "#adventure-duty-modal-title", "Nová výprava")
      assert has_element?(view, "#adventure-duty-source", "Příjezd")
      refute has_element?(view, "#adventure-duty-source", "UTC")
      assert has_element?(view, "#duty_size option[value=small][selected]")
      assert has_element?(view, "input[name='duty[scope]'][value=personal]")
      refute has_element?(view, "#duty_due_on[value]:not([value=''])")
      assert has_element?(view, "#adventure-duty-form details summary", "nepovinné")
      view |> form("#adventure-duty-form", duty: %{title: ""}) |> render_change()
      assert has_element?(view, "#adventure-duty-form")
      view |> element("#adventure-duty-modal button", "Zpět") |> render_click()
      refute has_element?(view, "#adventure-duty-modal")
      assert :ets.info(queries, :size) == 0
    end)

    assert Repo.aggregate(Quest, :count) == 0
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "an old card token resolves its own source after reordering and rejects removed sources",
       %{conn: conn} do
    {view, _profile, booking} = duty_view(conn)
    source = duty_source(view)
    snapshot = :sys.get_state(view.pid).socket.assigns.operation
    other = %{hd(snapshot.issues) | booking_id: Ecto.UUID.generate(), reason: "Jiný podnět"}

    :sys.replace_state(view.pid, fn state ->
      socket =
        Phoenix.Component.assign(state.socket,
          operation: %{snapshot | issues: [other | snapshot.issues]}
        )

      %{state | socket: socket}
    end)

    with_duty_queries(fn queries ->
      render_click(view, "prepare-duty", %{"source" => source, "booking_id" => other.booking_id})
      assert :sys.get_state(view.pid).socket.assigns.duty_draft.issue.booking_id == booking.id
      render_click(view, "cancel-duty")
      assert :ets.info(queries, :size) == 0
    end)

    :sys.replace_state(view.pid, fn state ->
      socket = Phoenix.Component.assign(state.socket, operation: %{snapshot | issues: [other]})
      %{state | socket: socket}
    end)

    with_duty_queries(fn queries ->
      render_click(view, "prepare-duty", %{"source" => source})
      refute has_element?(view, "#adventure-duty-modal")
      assert :ets.info(queries, :size) == 0
    end)
  end

  test "duty creation uses server source and request with only the two UI refresh SELECTs", %{
    conn: conn
  } do
    {view, _profile, booking} = duty_view(conn)
    render_click(view, "prepare-duty", %{"source" => duty_source(view)})
    draft = :sys.get_state(view.pid).socket.assigns.duty_draft
    forged = Ecto.UUID.generate()

    with_duty_queries(fn queries ->
      render_submit(view, "save-duty", %{
        "duty" => %{
          "title" => "Ověřit porce před příjezdem",
          "source_ref" => forged,
          "source_type" => "menu",
          "source_request_key" => forged,
          "source_previous_id" => forged,
          "status" => "active"
        },
        "source" => "999",
        "booking_id" => forged,
        "request_key" => forged,
        "previous_id" => forged
      })

      # Context: profile lock, source lock, request replay, latest work. UI: camp + links.
      assert :ets.info(queries, :size) == 6
      statements = Enum.map(:ets.tab2list(queries), &elem(&1, 1))
      refute Enum.any?(statements, &String.contains?(&1, "adventure_xp_transactions"))
      refute Enum.any?(statements, &String.contains?(&1, "adventure_campaigns"))
      refute Enum.any?(statements, &Regex.match?(~r/\b(?:FROM|JOIN)\s+"bookings"/, &1))
      assert has_element?(view, "#adventure-duty-0", "Quest: Čeká")
      refute has_element?(view, "#adventure-duty-0 button", "Připravit quest")
      assert has_element?(view, "#adventure-duty-detail-modal", "Ověřit porce před příjezdem")
      assert has_element?(view, "#adventure-duty-detail-modal", "50 XP")

      :ets.delete_all_objects(queries)
      render_submit(view, "save-duty", %{"duty" => %{"title" => "Duplicitní kliknutí"}})
      assert :ets.info(queries, :size) == 0
    end)

    quest = Repo.get_by!(Quest, source_request_key: draft.request_key)
    assert quest.source_ref == booking.id
    assert quest.source_type == elem(draft.key, 1)
    assert quest.source_previous_id == nil
    assert quest.status == "waiting"
    assert quest.scope == "personal"
    assert quest.assigned_profile_id == nil
    assert quest.due_on == nil
    assert quest.definition_snapshot["size"] == "small"
    assert quest.definition_snapshot["xp"] == 50
    assert Repo.aggregate(Quest, :count) == 1
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "normal quest mutations refresh duty links and further work needs explicit confirmation",
       %{
         conn: conn
       } do
    {view, profile, _booking} = duty_view(conn)
    render_click(view, "prepare-duty", %{"source" => duty_source(view)})
    view |> form("#adventure-duty-form", duty: %{title: "Doplnit podklady"}) |> render_submit()
    quest = :sys.get_state(view.pid).socket.assigns.duty_detail
    assert_duty_refresh(fn -> render_click(view, "start-task", %{"id" => quest.id}) end)
    assert has_element?(view, "#adventure-duty-0", "Quest: Rozpracováno")
    refute has_element?(view, "#adventure-duty-0 button", "Připravit quest")
    render_click(view, "prepare-completion", %{"id" => quest.id})

    assert_duty_refresh(fn ->
      view
      |> form("#adventure-completion", completion: %{actor_id: profile.id})
      |> render_submit()
    end)

    assert has_element?(view, "#adventure-duty-0", "Quest: Hotovo")
    render_click(view, "close-duty-detail")

    with_duty_queries(fn queries ->
      view |> element("#adventure-duty-0 button", "Připravit další řešení") |> render_click()
      assert has_element?(view, "#adventure-duty-previous", "Hotovo")
      assert has_element?(view, "#adventure-duty-confirm-next", "Připravit další quest")
      assert has_element?(view, "#adventure-duty-previous", "Doplnit podklady")
      refute has_element?(view, "#adventure-duty-form")

      render_submit(view, "save-duty", %{
        "duty" => %{"title" => "Bez potvrzení"},
        "previous_id" => quest.id
      })

      refute has_element?(view, "#adventure-duty-form")
      render_click(view, "cancel-duty")
      assert :ets.info(queries, :size) == 0
      render_click(view, "prepare-duty", %{"source" => duty_source(view)})
      view |> element("#adventure-duty-confirm-next") |> render_click()
      assert has_element?(view, "#adventure-duty-form")
      assert :ets.info(queries, :size) == 0
    end)

    render_submit(view, "save-duty", %{
      "duty" => %{"title" => "Nové ověření po změně", "previous_id" => Ecto.UUID.generate()},
      "previous_id" => Ecto.UUID.generate()
    })

    next = :sys.get_state(view.pid).socket.assigns.duty_detail
    assert next.id != quest.id
    assert next.source_previous_id == quest.id
    assert has_element?(view, "#adventure-duty-0", "Quest: Čeká")
    assert_duty_refresh(fn -> render_click(view, "archive-task", %{"id" => next.id}) end)
    assert has_element?(view, "#adventure-duty-0", "Zrušeno · archiv")
    assert Repo.aggregate(Quest, :count) == 2
    assert Repo.aggregate(XpTransaction, :count) == 1
  end

  test "duty detail and explicit source history each use one bounded SELECT", %{conn: conn} do
    {:ok, _} = Adventure.initialize()
    profile = Repo.get_by!(Profile, slug: "michal")
    today = CozyCheckout.Adventure.Sources.Operation.today()

    CozyCheckout.AdventureFixtures.adventure_booking(%{
      status: "upcoming",
      check_in_date: today,
      check_out_date: Date.add(today, 2),
      meal_plan: nil
    })

    {:ok, snapshot} = CozyCheckout.Adventure.Sources.Operation.load()
    key = Tasks.duty_key(hd(snapshot.issues))

    latest =
      Enum.reduce(1..21, nil, fn attempt, previous ->
        {:ok, quest} =
          Tasks.create_from_duty(
            profile.id,
            snapshot,
            key,
            %{"title" => "Pokus #{attempt}"},
            Ecto.UUID.generate(),
            previous && previous.id
          )

        {:ok, archived} = Tasks.archive(profile.id, quest.id)
        archived
      end)

    {:ok, view, _} = live(conn, "/admin/adventure")
    first = hd(Tasks.duty_history(key, 1).quests)
    assert has_element?(view, "#adventure-duty-0", "Historie podnětu (21)")

    with_duty_queries(fn queries ->
      render_click(view, "open-duty-quest", %{"id" => Ecto.UUID.generate()})
      assert :ets.info(queries, :size) == 0
      render_click(view, "open-duty-quest", %{"id" => latest.id})
      assert :ets.info(queries, :size) == 1
      assert has_element?(view, "#adventure-duty-detail-modal", "Pokus 21")
      render_click(view, "close-duty-detail")
      assert :ets.info(queries, :size) == 1
      :ets.delete_all_objects(queries)

      view |> element("#adventure-duty-0 button", "Historie podnětu") |> render_click()
      assert :ets.info(queries, :size) == 1
      assert length(:sys.get_state(view.pid).socket.assigns.duty_history.quests) == 20
      assert has_element?(view, "#adventure-duty-history-modal", "Pokus 21")
      refute has_element?(view, "#adventure-duty-history-#{first.id}")
      :ets.delete_all_objects(queries)
      view |> element("#adventure-duty-history-modal button", "Starší práce") |> render_click()
      assert :ets.info(queries, :size) == 1
      assert has_element?(view, "#adventure-duty-history-modal h3", "Pokus 1")
      refute has_element?(view, "#adventure-duty-history-modal button", "Starší práce")
      :ets.delete_all_objects(queries)
      view |> element("#adventure-duty-history-modal button", "Novější práce") |> render_click()
      assert :ets.info(queries, :size) == 1
      :ets.delete_all_objects(queries)
      render_click(view, "close-duty-history")
      assert :ets.info(queries, :size) == 0
    end)
  end

  test "draft retains Czech arrival and failed stale snapshot context with optional task details",
       %{
         conn: conn
       } do
    {view, _profile, _booking} = duty_view(conn)

    :sys.replace_state(view.pid, fn state ->
      snapshot = %{
        state.socket.assigns.operation
        | loaded_at: DateTime.add(DateTime.utc_now(), -901)
      }

      socket =
        Phoenix.Component.assign(state.socket, operation: snapshot, operation_state: :error)

      %{state | socket: socket}
    end)

    snapshot = :sys.get_state(view.pid).socket.assigns.operation
    render_click(view, "prepare-duty", %{"source" => duty_source(view)})

    assert has_element?(
             view,
             "#adventure-duty-source [role=status]",
             "Starší nebo neověřený podklad"
           )

    refute has_element?(view, "#adventure-duty-source", "UTC")

    assert has_element?(
             view,
             "#adventure-duty-source",
             Calendar.strftime(CozyCheckout.Adventure.Sources.Operation.today(), "%-d. %-m.")
           )

    draft = :sys.get_state(view.pid).socket.assigns.duty_draft
    assert draft.snapshot == snapshot

    view
    |> form("#adventure-duty-form", duty: %{size: "medium", xp: 175})
    |> render_change()

    assert has_element?(view, "#adventure-duty-reward", "175 XP")

    view
    |> form("#adventure-duty-form",
      duty: %{
        title: "Vlastní krátký název",
        description: "Ověřit s kuchyní.",
        size: "medium",
        due_on: "2030-06-12",
        priority: "high",
        xp: 175
      }
    )
    |> render_submit()

    quest = :sys.get_state(view.pid).socket.assigns.duty_detail
    assert quest.assigned_profile_id == nil
    assert quest.description == "Ověřit s kuchyní."
    assert quest.definition_snapshot["xp"] == 175
    assert quest.definition_snapshot["size"] == "medium"
    assert quest.priority == "high"
    assert quest.due_on == ~D[2030-06-12]
    assert quest.status == "waiting"
    assert has_element?(view, "#adventure-operation-status", "Poslední dostupné údaje")
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "open duty work loads lazily once and remains accessible without its source", %{conn: conn} do
    {view, profile, _booking} = duty_view(conn)
    snapshot = :sys.get_state(view.pid).socket.assigns.operation
    issue = hd(snapshot.issues)

    {:ok, quest} =
      Tasks.create_from_duty(
        profile.id,
        snapshot,
        Tasks.duty_key(issue),
        %{"title" => "Stále otevřená práce"},
        Ecto.UUID.generate()
      )

    assert is_nil(:sys.get_state(view.pid).socket.assigns.duty_follow_up)

    :sys.replace_state(view.pid, fn state ->
      %{
        state
        | socket:
            Phoenix.Component.assign(state.socket,
              operation: %{snapshot | issues: []},
              duty_links: %{}
            )
      }
    end)

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "world-panel", %{"panel" => "duty"})
          render_click(view, "duty-tab", %{"tab" => "work"})
        end,
        view.pid
      )

    assert length(queries) == 1
    assert hd(queries) =~ ~s(FROM "adventure_quests")
    assert has_element?(view, "#adventure-duty-work-#{quest.id}", "Stále otevřená práce")

    assert has_element?(
             view,
             "#adventure-duty-work-#{quest.id} [data-source-status=absent]",
             "Podnět už není v přehledu"
           )

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          for tab <- ~w(issues work issues work),
              do: render_click(view, "duty-tab", %{"tab" => tab})

          render_click(view, "world-panel", %{"panel" => "continue"})
          render_click(view, "world-panel", %{"panel" => "duty"})
          render(view)
        end,
        view.pid
      )

    assert queries == []

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "open-duty-quest", %{"id" => quest.id})
        end,
        view.pid
      )

    assert length(queries) == 1
    assert has_element?(view, "#adventure-duty-detail-modal [data-source-status=absent]")
    render_click(view, "close-duty-detail")

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          view
          |> element("#adventure-duty-work-#{quest.id} button", "Historie podnětu")
          |> render_click()
        end,
        view.pid
      )

    assert length(queries) == 1
    assert has_element?(view, "#adventure-duty-history-modal", "Stále otevřená práce")
    render_click(view, "close-duty-history")
    render_click(view, "open-duty-quest", %{"id" => quest.id})
    render_click(view, "start-task", %{"id" => quest.id})
    assert has_element?(view, "#adventure-duty-work-#{quest.id}", "Práce: Rozpracováno")
    render_click(view, "prepare-completion", %{"id" => quest.id})

    render_submit(view, "complete", %{
      "completion" => %{"actor_id" => profile.id, "note" => "Hotovo ručně"}
    })

    refute has_element?(view, "#adventure-duty-work-#{quest.id}")
    assert Repo.get!(Quest, quest.id).status == "completed"
    assert Repo.aggregate(XpTransaction, :count) == 1
  end

  test "open duty pagination is bounded and refresh reads only one Adventure batch", %{conn: conn} do
    {view, profile, _booking} = duty_view(conn)
    snapshot = :sys.get_state(view.pid).socket.assigns.operation
    issue = hd(snapshot.issues)

    for n <- 1..21 do
      issue = %{issue | booking_id: Ecto.UUID.generate()}

      {:ok, _} =
        Tasks.create_from_duty(
          profile.id,
          %{snapshot | issues: [issue]},
          Tasks.duty_key(issue),
          %{"title" => "Práce #{n}"},
          Ecto.UUID.generate()
        )
    end

    render_click(view, "duty-tab", %{"tab" => "work"})
    assert length(:sys.get_state(view.pid).socket.assigns.duty_follow_up.quests) == 20

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "duty-work-page", %{"direction" => "next"})
        end,
        view.pid
      )

    assert length(queries) == 1
    assert length(:sys.get_state(view.pid).socket.assigns.duty_follow_up.quests) == 1
    assert has_element?(view, "#adventure-duty-work", "Strana 2")

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "duty-work-page", %{"direction" => "next"})
          render_click(view, "duty-work-page", %{"direction" => "junk"})
          render_click(view, "open-duty-quest", %{"id" => Ecto.UUID.generate()})
          render_click(view, "duty-history", %{"source" => Ecto.UUID.generate() <> ":details"})
        end,
        view.pid
      )

    assert queries == []

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn -> render_click(view, "refresh-duty-work") end,
        view.pid
      )

    assert length(queries) == 1
    assert hd(queries) =~ ~s(FROM "adventure_quests")
    assert :sys.get_state(view.pid).socket.assigns.duty_follow_up.page == 0
    render_click(view, "duty-work-page", %{"direction" => "next"})
    render_click(view, "duty-work-page", %{"direction" => "previous"})
    assert :sys.get_state(view.pid).socket.assigns.duty_follow_up.page == 0
  end

  test "open duty source status follows snapshot freshness without SQL or changing work", %{
    conn: conn
  } do
    {view, profile, _booking} = duty_view(conn)
    snapshot = :sys.get_state(view.pid).socket.assigns.operation
    issue = hd(snapshot.issues)

    {:ok, quest} =
      Tasks.create_from_duty(
        profile.id,
        snapshot,
        Tasks.duty_key(issue),
        %{"title" => "Ověřit podklad"},
        Ecto.UUID.generate()
      )

    render_click(view, "duty-tab", %{"tab" => "work"})

    for {status, issues, loaded_at, expected} <- [
          {:ready, List.duplicate(%{issue | booking_id: Ecto.UUID.generate()}, 4) ++ [issue],
           snapshot.loaded_at, "present"},
          {:ready, [%{issue | reason: "Změněný podklad"}], snapshot.loaded_at, "changed"},
          {:ready, [], snapshot.loaded_at, "absent"},
          {:ready, [issue], DateTime.add(snapshot.loaded_at, -901), "stale"},
          {:error, [issue], snapshot.loaded_at, "unavailable"}
        ] do
      :sys.replace_state(view.pid, fn state ->
        %{
          state
          | socket:
              Phoenix.Component.assign(state.socket,
                operation_state: status,
                operation: %{snapshot | issues: issues, loaded_at: loaded_at}
              )
        }
      end)

      {_, queries} =
        CozyCheckout.QueryRecorder.record(
          fn -> render_click(view, "duty-tab", %{"tab" => "work"}) end,
          view.pid
        )

      assert queries == []

      assert has_element?(
               view,
               "#adventure-duty-work-#{quest.id} [data-source-status=#{expected}]"
             )

      assert Repo.get!(Quest, quest.id).status == "waiting"
    end

    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "manual operation refresh refreshes the loaded work once and cached hero switches keep it",
       %{conn: conn} do
    {view, profile, _booking} = duty_view(conn)

    {_, [work_query]} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "duty-tab", %{"tab" => "work"})
        end,
        view.pid
      )

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "refresh-operation")
          render(view)
        end,
        view.pid
      )

    assert Enum.count(queries, &(&1 == work_query)) == 1
    cached = :sys.get_state(view.pid).socket.assigns.duty_follow_up
    render_click(view, "restore-profile", %{"id" => profile.id})
    assert :sys.get_state(view.pid).socket.assigns.duty_follow_up == cached
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "cached work survives unavailable sources and shows a failed list refresh explicitly", %{
    conn: conn
  } do
    {view, profile, _booking} = duty_view(conn)
    snapshot = :sys.get_state(view.pid).socket.assigns.operation
    issue = hd(snapshot.issues)

    {:ok, quest} =
      Tasks.create_from_duty(
        profile.id,
        snapshot,
        Tasks.duty_key(issue),
        %{"title" => "Práce bez zdroje"},
        Ecto.UUID.generate()
      )

    render_click(view, "duty-tab", %{"tab" => "work"})

    :sys.replace_state(view.pid, fn state ->
      %{
        state
        | socket:
            Phoenix.Component.assign(state.socket,
              operation: nil,
              operation_state: :error,
              duty_follow_up_error: true
            )
      }
    end)

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "world-panel", %{"panel" => "duty"})
          render_click(view, "duty-tab", %{"tab" => "work"})
        end,
        view.pid
      )

    assert queries == []
    assert has_element?(view, "#adventure-duty-work", "stav práce nemusí být aktuální")
    assert has_element?(view, "#adventure-duty-work-#{quest.id} [data-source-status=unavailable]")
    assert has_element?(view, "#adventure-duty-work button", "Obnovit práci")
    render_click(view, "refresh-duty-work")
    refute :sys.get_state(view.pid).socket.assigns.duty_follow_up_error
    assert Repo.get!(Quest, quest.id).status == "waiting"
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  defp duty_view(conn) do
    {:ok, _} = Adventure.initialize()
    profile = Repo.get_by!(Profile, slug: "michal")
    today = CozyCheckout.Adventure.Sources.Operation.today()

    booking =
      CozyCheckout.AdventureFixtures.adventure_booking(%{
        status: "upcoming",
        check_in_date: today,
        check_out_date: Date.add(today, 2),
        meal_plan: nil
      })

    {:ok, view, _} = live(conn, "/admin/adventure")
    assert has_element?(view, "#adventure-duty-0")
    render_click(view, "restore-profile", %{"id" => profile.id})
    {view, profile, booking}
  end

  defp duty_source(view) do
    issue = hd(:sys.get_state(view.pid).socket.assigns.operation.issues)
    {id, type} = Tasks.duty_key(issue)
    id <> ":" <> type
  end

  defp assert_duty_refresh(fun) do
    with_duty_queries(fn queries ->
      fun.()
      statements = Enum.map(:ets.tab2list(queries), &elem(&1, 1))
      assert Enum.count(statements, &String.contains?(&1, "PARTITION BY")) == 1

      refute Enum.any?(
               statements,
               &Regex.match?(
                 ~r/\b(?:FROM|JOIN)\s+"(?:bookings|booking_menus|booking_menu_items|booking_menu_supplements)"/,
                 &1
               )
             )
    end)
  end

  defp with_duty_queries(fun) do
    table = :ets.new(:duty_ui_selects, [:public, :ordered_set])
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(handler, [:cozy_checkout, :repo, :query], &__MODULE__.duty_query/4, table)

    try do
      fun.(table)
    after
      :telemetry.detach(handler)
      :ets.delete(table)
    end
  end

  def duty_query(_, _, metadata, table) do
    if Regex.match?(~r/^\s*SELECT\b/i, metadata.query) do
      :ets.insert(table, {System.unique_integer([:monotonic]), metadata.query})
    end
  end

  test "manual refresh replaces the retained operation without making quests or rewards", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/admin/adventure")
    assert has_element?(view, "#adventure-area-reception", "0 příjezdů")
    today = CozyCheckout.Adventure.Sources.Operation.today()

    booking =
      CozyCheckout.AdventureFixtures.adventure_booking(%{
        status: "upcoming",
        check_in_date: today,
        check_out_date: Date.add(today, 2),
        meal_plan: nil
      })

    render_click(view, "operation-area", %{"area" => "kitchen"})
    assert has_element?(view, "#adventure-area-reception", "0 příjezdů")
    view |> element("#adventure-operation-refresh") |> render_click()
    assert has_element?(view, "#adventure-area-reception", "1 příjezdů")
    assert has_element?(view, "#adventure-area-detail", "Neúplné podklady")
    assert has_element?(view, "#adventure-service-day a[href='/admin/bookings/#{booking.id}']")
    refute render(view) =~ "Soukromé jméno hosta"
    assert Repo.aggregate(Quest, :count) == 0
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "operation exposes loading, unavailable and stale states without false zero claims" do
    component = &CozyCheckoutWeb.AdventureLive.OperationComponents.operation_world/1
    checked_at = DateTime.utc_now()

    loading =
      render_component(component,
        snapshot: nil,
        checked_at: checked_at,
        state: :loading,
        area: "kitchen",
        world: %{counts: [], projects: []},
        chronicle: nil,
        chronicle_page: 0,
        profiles: []
      )

    assert loading =~ "Načítám společný provozní přehled"
    assert loading =~ "Neznámý stav není nula"

    failed =
      render_component(component,
        snapshot: nil,
        checked_at: checked_at,
        state: :error,
        area: "reception",
        world: %{counts: [], projects: []},
        chronicle: nil,
        chronicle_page: 0,
        profiles: []
      )

    assert failed =~ "Provoz se nepodařilo načíst"
    refute failed =~ "0 /"
    {:ok, snapshot} = CozyCheckout.Adventure.Sources.Operation.load()
    snapshot = %{snapshot | loaded_at: DateTime.add(checked_at, -901)}

    stale =
      render_component(component,
        snapshot: snapshot,
        checked_at: checked_at,
        state: :ready,
        area: "kitchen",
        world: %{counts: [], projects: []},
        chronicle: nil,
        chronicle_page: 0,
        profiles: []
      )

    assert stale =~ "Starší údaje, obnov přehled"

    retained =
      render_component(component,
        snapshot: snapshot,
        checked_at: checked_at,
        state: :error,
        area: "reception",
        world: %{counts: [], projects: []},
        chronicle: nil,
        chronicle_page: 0,
        profiles: []
      )

    assert retained =~ "Poslední dostupné údaje níže nejsou čerstvé"
  end

  test "unrelated event updates freshness even when the operation inputs otherwise stay unchanged",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/adventure")
    assert has_element?(view, "#adventure-operation-status", "Bez automatické obnovy")
    refute has_element?(view, "#adventure-operation-status strong", "Starší údaje")

    # Simulate time passing without marking the operation assign as changed.
    :sys.replace_state(view.pid, fn state ->
      snapshot = %{
        state.socket.assigns.operation
        | loaded_at: DateTime.add(DateTime.utc_now(), -901)
      }

      socket = %{state.socket | assigns: %{state.socket.assigns | operation: snapshot}}
      %{state | socket: socket}
    end)

    aged_snapshot = :sys.get_state(view.pid).socket.assigns.operation
    previous_check = :sys.get_state(view.pid).socket.assigns.operation_checked_at
    render_click(view, "close-picker")
    assert has_element?(view, "#adventure-operation-status strong", "Starší údaje, obnov přehled")
    assigns = :sys.get_state(view.pid).socket.assigns
    assert assigns.operation == aged_snapshot
    assert DateTime.compare(assigns.operation_checked_at, previous_check) == :gt
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
    assert has_element?(view, "#adventure-hero-switcher summary", "Michal")
    assert has_element?(view, "#adventure-hero-switcher summary", "Úroveň 1")

    {:ok, quest} =
      Tasks.create(profile.id, %{"title" => "Zavést jedno provozní zlepšení", "xp" => 250})

    view |> element("#adventure-find-quest") |> render_click()
    view |> element("#pick-quest-#{quest.id} button") |> render_click()
    view |> element("#expedition-quest-#{quest.id} button") |> render_click()
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
    assert has_element?(view, "#adventure-hero-switcher summary", "Michal")
    assert has_element?(view, "#adventure-hero-switcher summary", "Úroveň 1")
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
    assert has_element?(view, "#adventure-hero-switcher summary", "Michal")
    assert has_element?(view, "#adventure-progress", "0 XP")

    render_click(view, "profile-storage-status", %{"persistent" => true})
    refute has_element?(view, "#adventure-profile-storage-warning")
    assert has_element?(view, "#adventure-hero-switcher summary", "Michal")
    assert has_element?(view, "#adventure-progress", "0 XP")
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
    view |> element("#expedition-quest-#{quest.id} button") |> render_click()
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
    view |> element("#expedition-quest-#{quest.id} button") |> render_click()
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
    camp |> element("#expedition-quest-#{task.id} button") |> render_click()
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

  test "management and picker controls expose exactly one active section", %{conn: conn} do
    {:ok, _} = Adventure.initialize()
    profile = Repo.get_by!(Profile, slug: "michal")
    {:ok, view, _} = live(conn, "/admin/adventure/quests")

    for section <- ~w(tasks templates projects history tasks) do
      render_click(view, "manage-section", %{"section" => section})

      assert has_element?(
               view,
               "#adventure-management-tabs button[phx-value-section='#{section}'][aria-pressed=true]"
             )

      for other <- ~w(tasks templates projects history) -- [section] do
        assert has_element?(
                 view,
                 "#adventure-management-tabs button[phx-value-section='#{other}'][aria-pressed=false]"
               )
      end
    end

    {:ok, camp, _} = live(conn, "/admin/adventure")
    render_click(camp, "restore-profile", %{"id" => profile.id})
    render_click(camp, "find-quests")

    for scope <- ~w(mine shared all) do
      render_click(camp, "picker-filter", %{"scope" => scope})

      assert has_element?(
               camp,
               "#adventure-quest-picker button[phx-value-scope='#{scope}'][aria-pressed=true]"
             )
    end
  end

  test "camp leads with the world and keeps secondary work in contextual views", %{conn: conn} do
    {camp, profile, _booking} = duty_view(conn)
    html = render(camp)
    assert {scene, _} = :binary.match(html, "class=\"adventure-village\"")
    assert {work, _} = :binary.match(html, "class=\"adventure-quest-dock\"")
    assert scene < work
    refute has_element?(camp, ".adventure-hero")
    assert has_element?(camp, "#adventure-context[data-panel=continue]")
    assert has_element?(camp, "#adventure-expeditions-view[hidden]")
    assert has_element?(camp, "#adventure-chronicle-view[hidden]")
    assert has_element?(camp, "#adventure-season-disclosure:not([open])")
    render_click(camp, "world-panel", %{"panel" => "duty"})
    assert has_element?(camp, "#adventure-context[data-panel=duty]")
    render_click(camp, "world-panel", %{"panel" => "continue"})
    assert has_element?(camp, "#adventure-context[data-panel=continue]")

    {:ok, book, _} = live(conn, "/admin/adventure/quests")
    render_click(book, "restore-profile", %{"id" => profile.id})
    assert has_element?(book, "#adventure-task-optional-fields:not([open])")
    render_click(book, "toggle-task-editor")
    book |> form("#adventure-task-form", task: %{title: "Chybné XP", xp: "0"}) |> render_submit()
    assert has_element?(book, "#adventure-task-optional-fields[open]")
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
    view |> element("#expedition-quest-#{task.id} button", "Hotovo") |> render_click()
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
    |> element("#template-#{template.id} button[phx-click=resume-template]")
    |> render_click()

    view |> element("button[phx-click=generate-tasks]") |> render_click()
    task = Repo.one!(Quest)
    refute has_element?(view, "#adventure-task-board")
    refute has_element?(view, "button[phx-click=start-task]")

    view
    |> element("#template-#{template.id} button[phx-value-status=paused]")
    |> render_click()

    assert Repo.get!(TaskTemplate, template.id).status == "active"
    refute has_element?(view, "#template-confirm-#{template.id} select")

    view
    |> element("#template-confirm-#{template.id} button[phx-value-choice=keep]")
    |> render_click()

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

    for {area, path} <- [
          {"kitchen", "/admin/meal-planner"},
          {"bar", "/admin/bar-stock"},
          {"treasury", "/admin/billing"}
        ] do
      render_click(camp, "operation-area", %{"area" => area})
      assert has_element?(camp, "#adventure-world-map a[href='#{path}']")
    end

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
    assert has_element?(camp, "#adventure-shared-list #expedition-quest-#{shared.id}")
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

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn -> render_click(camp, "operation-area", %{"area" => "treasury"}) end,
        camp.pid
      )

    assert queries == []
    assert has_element?(camp, "#adventure-treasury-summary", "Zimní kronika")
    assert has_element?(camp, "#adventure-treasury-summary [data-metric='period_net_amount']")
    assert has_element?(camp, "#adventure-treasury-summary [data-metric='received_amount']")

    camp |> element("#adventure-area-detail a[data-phx-link='patch']") |> render_click()
    assert_patch(camp, "/admin/adventure?view=chronicle&tab=seasons")
    assert has_element?(camp, "button[phx-value-tab='seasons'][aria-pressed='true']")
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

  test "game navigation preserves the operational snapshot and cached views add no SELECTs", %{
    conn: conn
  } do
    {:ok, _} = Adventure.initialize()
    {:ok, view, _} = live(conn, "/admin/adventure")
    render(view)
    snapshot = :sys.get_state(view.pid).socket.assigns.operation

    render_patch(view, "/admin/adventure?view=development")
    assert has_element?(view, "#adventure-projects")
    assert :sys.get_state(view.pid).socket.assigns.projects_loaded

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          for page <- ~w(expeditions chronicle world development world) do
            render_patch(view, "/admin/adventure?view=#{page}")

            assert has_element?(
                     view,
                     ".adventure-game-nav a[aria-current=page][href='/admin/adventure?view=#{page}']"
                   )
          end

          render_click(view, "operation-area", %{"area" => "kitchen"})
          render_click(view, "world-panel", %{"panel" => "duty"})
          render_click(view, "world-panel", %{"panel" => "continue"})
        end,
        view.pid
      )

    assert queries == []
    assert :sys.get_state(view.pid).socket.assigns.operation == snapshot
    assert Repo.aggregate(XpTransaction, :count) == 0
  end

  test "invalid view defaults to the world and direct development links retain authoring", %{
    conn: conn
  } do
    {:ok, _} = Adventure.initialize()
    {:ok, view, _} = live(conn, "/admin/adventure?view=unknown")
    assert has_element?(view, ".adventure-game-nav a[aria-current=page]", "Chata")
    render_patch(view, "/admin/adventure?view=development")
    assert has_element?(view, "#adventure-projects")
    assert has_element?(view, "#adventure-world-map")

    assert has_element?(
             view,
             "#adventure-world-map .adventure-village-land[src$='cabin-world.svg']"
           )
  end

  test "completion celebrates the actual recipient once and never on reconnect or replay", %{
    conn: conn
  } do
    alias CozyCheckout.Adventure.Tasks
    {:ok, _} = Adventure.initialize()
    michal = Repo.get_by!(Profile, slug: "michal")
    lucka = Repo.get_by!(Profile, slug: "lucka")
    {:ok, quest} = Tasks.create(michal.id, %{"title" => "Nový výsledek", "size" => "medium"})
    {:ok, _} = Tasks.start(michal.id, quest.id)
    {:ok, view, _} = live(conn, "/admin/adventure")
    render_click(view, "restore-profile", %{"id" => michal.id})
    render_click(view, "prepare-completion", %{"id" => quest.id})
    view |> form("#adventure-completion", completion: %{actor_id: lucka.id}) |> render_submit()
    assert has_element?(view, "#adventure-success", "+100 XP · Lucka")
    assert has_element?(view, "#adventure-success", "Nový výsledek")
    render_click(view, "dismiss-success")
    render_submit(view, "complete", %{"completion" => %{"actor_id" => lucka.id}})
    refute has_element?(view, "#adventure-success")
    {:ok, reconnected, _} = live(conn, "/admin/adventure")
    render_click(reconnected, "restore-profile", %{"id" => michal.id})
    refute has_element?(reconnected, "#adventure-success")
    assert Repo.aggregate(XpTransaction, :count) == 1
  end

  test "treasury shows the selected season income and preserves missing and partial data" do
    summary = &CozyCheckoutWeb.AdventureLive.CampaignComponents.treasury_summary/1

    active = %{
      id: "active",
      name: "Aktuální sezóna",
      status: "active",
      starts_on: ~D[2026-10-01],
      ends_on: ~D[2026-12-31],
      last_evaluation: nil
    }

    snapshot = %{
      "as_of" => "2026-11-12T10:00:00Z",
      "sources" => %{
        "billing" => %{
          "metrics" => %{"period_net_amount" => "12345.50"},
          "metric_metadata" => %{"period_net_amount" => %{"completeness" => "partial"}}
        },
        "bar" => %{
          "metrics" => %{"received_amount" => "0.00"},
          "quality" => %{"completeness" => "complete"}
        }
      }
    }

    historical = %{
      active
      | id: "historical",
        name: "Minulá sezóna",
        status: "closed",
        last_evaluation: %{snapshot: snapshot}
    }

    game = %{campaigns: [active, historical]}

    pending = render_component(summary, game: game)
    assert pending =~ "Aktuální sezóna"
    assert pending =~ "Zatím nepřepočítáno"
    refute pending =~ "data-metric"

    html = render_component(summary, game: game, selected_id: historical.id)
    assert html =~ "Minulá sezóna"
    assert html =~ "12. 11. 2026 · 10:00 UTC"
    assert html =~ "01. 10. 2026 — 31. 12. 2026"
    refute html =~ "2026-11-12T10:00:00Z"
    assert html =~ CozyCheckoutWeb.CurrencyHelper.format_currency(Decimal.new("12345.50"))
    assert html =~ CozyCheckoutWeb.CurrencyHelper.format_currency(Decimal.new("0.00"))
    assert html =~ "Dílčí podklady"
    assert html =~ "Inkaso baru bez servisu"
    assert html =~ "Inkaso ubytování po vratkách"
    document = Floki.parse_document!(html)
    assert [_] = Floki.find(document, "details:not([open])")
    assert Floki.find(document, ".adventure-metric small") |> Floki.text() == "Dílčí"

    missing = %{historical | last_evaluation: %{snapshot: %{snapshot | "sources" => %{}}}}
    assert render_component(summary, game: %{campaigns: [missing]}) =~ "Nedostupné"
    assert render_component(summary, game: %{campaigns: []}) =~ "Zatím není vybraná žádná sezóna"
  end

  test "financial area links open the season chronicle on direct navigation and patch", %{
    conn: conn
  } do
    {:ok, _} = Adventure.initialize()
    {:ok, camp, _} = live(conn, "/admin/adventure")
    path = "/admin/adventure?view=chronicle&tab=seasons"

    for area <- ~w(bar treasury) do
      render_click(camp, "operation-area", %{"area" => area})
      assert has_element?(camp, "#adventure-area-detail a[href='#{path}']")
    end

    {:ok, chronicle, _} = live(conn, path)
    assert has_element?(chronicle, "button[phx-value-tab='seasons'][aria-pressed='true']")
    assert has_element?(chronicle, "#adventure-season-disclosure[open]")

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn -> render_patch(camp, path) end,
        camp.pid
      )

    assert queries == []
    assert has_element?(camp, "button[phx-value-tab='seasons'][aria-pressed='true']")
    assert has_element?(camp, "#adventure-season-disclosure[open]")
  end

  test "chronicle history is explicit and cached without refreshing operational sources", %{
    conn: conn
  } do
    {:ok, _} = Adventure.initialize()
    {:ok, view, _} = live(conn, "/admin/adventure?view=chronicle")
    render(view)

    {_, queries} =
      CozyCheckout.QueryRecorder.record(
        fn ->
          render_click(view, "chronicle-tab", %{"tab" => "quests"})
          render_click(view, "chronicle-tab", %{"tab" => "seasons"})
          render_click(view, "chronicle-tab", %{"tab" => "quests"})
        end,
        view.pid
      )

    assert length(queries) == 1
    assert hd(queries) =~ "adventure_quests"
  end

  test "world decoration has zero, one and two-result stages and never develops the workshop" do
    village = &CozyCheckoutWeb.AdventureLive.OperationComponents.village/1
    base = %{snapshot: nil, area: nil, world: %{counts: [], projects: []}}
    plain = render_component(village, base)
    refute plain =~ "adventure-world-decoration"

    first = render_component(village, put_in(base, [:world, :counts], [{"rooms", "accepted", 1}]))
    assert first =~ "adventure-symbol--flag"
    refute first =~ "adventure-symbol--trophy"

    developed =
      render_component(
        village,
        put_in(base, [:world, :counts], [{"rooms", "accepted", 3}, {"workshop", "accepted", 8}])
      )

    assert developed =~ "adventure-symbol--trophy"
    assert developed =~ "3 převzatých zlepšení"
    refute developed =~ "8 převzatých zlepšení"
  end

  test "quest offers render once as a camp modal or inline in expeditions", %{conn: conn} do
    {:ok, _} = Adventure.initialize()
    profile = Repo.get_by!(Profile, slug: "michal")
    {:ok, quest} = Tasks.create(profile.id, %{"title" => "Jedna nabídka"})
    {:ok, view, _} = live(conn, "/admin/adventure")
    render_click(view, "restore-profile", %{"id" => profile.id})
    render_click(view, "find-quests")
    assert has_element?(view, "#adventure-picker-modal #pick-quest-#{quest.id}")
    refute has_element?(view, "#adventure-expeditions-view #adventure-quest-picker")

    render_click(view, "close-picker")
    refute has_element?(view, "#adventure-quest-picker")
    render_patch(view, "/admin/adventure?view=expeditions")
    render_click(view, "find-quests")
    assert has_element?(view, "#adventure-expeditions-view #pick-quest-#{quest.id}")
    refute has_element?(view, "#adventure-picker-modal")
    render_patch(view, "/admin/adventure?view=world")
    refute has_element?(view, "#adventure-quest-picker")
    render_click(view, "find-quests")
    assert has_element?(view, "#adventure-picker-modal #pick-quest-#{quest.id}")
    refute has_element?(view, "#adventure-expeditions-view #adventure-quest-picker")
  end
end

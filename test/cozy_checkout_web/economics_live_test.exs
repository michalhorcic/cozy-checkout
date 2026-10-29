defmodule CozyCheckoutWeb.EconomicsLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.EconomicsFixtures
  use Oban.Testing, repo: CozyCheckout.Repo
  alias CozyCheckout.{Economics, Repo}
  alias CozyCheckout.Economics.{Reports, Source, ImportRun, Snapshot, SyncWorker}
  alias CozyCheckoutWeb.AdminAuth
  alias CozyCheckoutWeb.CurrencyHelper

  setup %{conn: conn} do
    previous = Application.get_env(:cozy_checkout, :economics)
    pin = Application.get_env(:cozy_checkout, :admin_pin_hash)

    Application.put_env(:cozy_checkout, :economics,
      enabled: true,
      base_url: "https://accounting.test",
      company_id: "reporting",
      username: "reader",
      password: "never-render-this-secret"
    )

    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cozy_checkout, :economics, previous),
        else: Application.delete_env(:cozy_checkout, :economics)

      if pin,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, pin),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    source = Repo.insert!(%Source{base_url: "https://accounting.test", company_id: "reporting"})
    at = DateTime.utc_now() |> DateTime.truncate(:second)

    run =
      Repo.insert!(%ImportRun{
        source_id: source.id,
        period_code: "FY-TEST",
        state: "succeeded",
        generation: 0,
        started_at: at,
        completed_at: at
      })

    {:ok, month} =
      Reports.month(period(), ~D[2026-07-01], ~D[2026-07-31], catalog(), posted(), [], trial(), [
        open_item()
      ])

    payload = %{
      "period" => period(),
      "months" => [month],
      "posting_state" => "posted",
      "mapping_version" => 1
    }

    Repo.insert!(%Snapshot{
      source_id: source.id,
      import_run_id: run.id,
      period_code: "FY-TEST",
      payload: payload,
      fingerprint: Reports.fingerprint(payload),
      started_at: at,
      checked_at: at
    })

    {:ok,
     conn:
       Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})}
  end

  test "overview reads a local snapshot and manual import enqueues a job", %{conn: conn} do
    {:ok, view, html} = live(conn, "/admin/economics")
    assert html =~ "Ekonomika firmy"
    assert html =~ "Účetní výsledek"
    assert html =~ "Neověřený stav hotovosti"
    refute html =~ "never-render-this-secret"
    assert has_element?(view, "#economics-report")
    assert has_element?(view, "#economics-accounts")
    assert has_element?(view, "#economics-monthly-chart")
    assert has_element?(view, "#economics-cost-chart details summary", "Potraviny")
    assert has_element?(view, "#economics-cost-chart a[href*='/accounts/501100']")
    assert has_element?(view, "#economics-bank-accounts a[href*='/accounts/221001']")
    assert has_element?(view, "[data-document-identity]", "Ukázková firma s.r.o.")

    assert has_element?(
             view,
             "#admin-desktop > a[href='/admin/economics'][aria-current='page']",
             "Ekonomika firmy"
           )

    refute has_element?(view, "#admin-desktop-more a[href='/admin/economics']")
    refute has_element?(view, "#admin-desktop-more[open]")
    assert has_element?(view, "#admin-mobile-navigation a[href='/admin/economics']")
    view |> element("#economics-import") |> render_click()
    assert_enqueued(worker: SyncWorker, args: %{period: "current"})
    assert has_element?(view, "#economics-report")
  end

  test "filters reject unavailable dates and account detail preserves reference and exact amount",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/economics")

    view
    |> form("#economics-range", range: %{period: "FY-TEST", from: "2025-07", to: "2026-07"})
    |> render_submit()

    assert render(view) =~ "Vyberte měsíce dostupné"

    {:ok, detail, html} =
      live(conn, "/admin/economics/accounts/602001?period=FY-TEST&from=2026-07&to=2026-07")

    assert html =~ "602001"
    assert has_element?(detail, "#economics-movements")

    assert has_element?(
             detail,
             "#economics-movements [data-document-identity]",
             "Ukázkový odběratel s.r.o."
           )

    assert has_element?(detail, "#economics-movements", "Prodej čaje a limonády")
    assert has_element?(detail, "#economics-movements", "FV-2026-1")

    assert has_element?(
             detail,
             "#admin-desktop > a[href='/admin/economics'][aria-current='page']"
           )

    expected_amount = CurrencyHelper.format_currency(Decimal.new("120"))
    assert has_element?(detail, "#economics-movements tbody tr td:nth-child(5)", expected_amount)
  end

  test "confirmation uses a local snapshot fingerprint and never displays credentials", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, "/admin/economics/settings")
    refute html =~ "never-render-this-secret"
    assert html =~ "Neověřeno"

    view
    |> form("#economics-confirm-form",
      confirmation: %{month: "2026-07-01", evidence: "Kontrola s účetní podle předvahy."}
    )
    |> render_submit()

    assert render(view) =~ "Potvrzeno"
    assert {:ok, %{report: %{confirmations: [%{confirmed: true}]}}} = Economics.overview()
  end

  test "home cards and alerts use the daily saldo and link to the matching documents", %{
    conn: conn
  } do
    snapshot = Repo.one!(Snapshot)
    today = Date.utc_today()
    date = to_string(today)

    {:ok, items} =
      Reports.saldo(
        [
          open_item(%{
            "idDokl" => "daily-receivable",
            "datSplat" => to_string(Date.add(today, -1))
          }),
          open_item(%{
            "idDokl" => "daily-payable",
            "modul" => "FAP",
            "datSplat" => to_string(Date.add(today, 14))
          })
        ],
        today
      )

    payload = Map.put(snapshot.payload, "current_saldo", %{"date" => date, "items" => items})
    snapshot |> Ecto.Changeset.change(payload: payload) |> Repo.update!()

    assert {:ok, _} =
             Economics.confirm_month(snapshot.id, "2026-07-01", "Potvrzeno po kontrole s účetní.")

    {:ok, home, html} = live(conn, "/admin")
    assert has_element?(home, "#dashboard-economics")
    assert has_element?(home, "[data-economics-issue='overdue_receivables']")
    assert has_element?(home, "[data-economics-issue='upcoming_payables']")
    assert html =~ "2026-07"
    refute html =~ "never-render-this-secret"
    assert {:ok, summary} = Economics.home_summary(today)
    assert summary.saldo.payables.count == 1
    assert summary.result.month == "2026-07-01"
    {:ok, economics, _} = live(conn, "/admin/economics?saldo=payables-upcoming")
    assert has_element?(economics, "#economics-daily-items", "daily-payable")
    assert has_element?(economics, "#economics-daily-items", "Ukázková firma s.r.o.")
    assert has_element?(economics, "#economics-daily-items", "Dodávka občerstvení")
    refute has_element?(economics, "#economics-daily-items", "daily-receivable")
  end

  test "disabled reporting leaves the operational home without financial queries or cards", %{
    conn: conn
  } do
    Application.put_env(:cozy_checkout, :economics, enabled: false)
    {:ok, home, _} = live(conn, "/admin")
    refute has_element?(home, "#dashboard-economics")
    refute has_element?(home, "[data-economics-issue]")
  end

  test "cost mapping requires explicit preview and publication and preserves accounting totals",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/admin/economics/costs?tab=mapping")
    assert html =~ "Nákladovost"
    refute html =~ "never-render-this-secret"
    assert has_element?(view, "#cost-editor")
    assert has_element?(view, "#cost-history")
    view |> element("#cost-suggestions") |> render_click()
    assert has_element?(view, "#cost-draft-rules", "501100")
    assert {:ok, %{version: nil}} = Economics.costs()
    refute has_element?(view, "#cost-publish")

    view
    |> form("#cost-preview-form", publication: %{note: "Potvrzený návrh potravin."})
    |> render_submit()

    assert has_element?(view, "#cost-preview", "1 změněných podkladů")
    view |> element("#cost-publish") |> render_click()
    assert render(view) =~ "Nová verze mapování byla publikována"
    assert {:ok, data} = Economics.costs()
    assert Decimal.equal?(data.totals.variable, "45.50")
    assert Decimal.equal?(data.totals.total, data.report.totals["expense"])
    assert data.version.number == 1
    {:ok, overview, _} = live(conn, "/admin/economics/costs")
    assert has_element?(overview, "#cost-totals")
    assert has_element?(overview, "#cost-months")
    assert has_element?(overview, "#cost-categories", "Potraviny")
    assert has_element?(overview, "#cost-documents", "Variabilní")
  end

  test "cost editor stores a scoped exception, previews it and never changes source postings", %{
    conn: conn
  } do
    snapshot = Repo.one!(Snapshot)
    {:ok, view, _} = live(conn, "/admin/economics/costs")
    view |> element("button[phx-click='from-item'][phx-value-kind='override']") |> render_click()
    assert has_element?(view, "#cost-editor")

    view
    |> form("#cost-editor",
      editor: %{
        behavior: "mixed",
        fixed_percent: "50",
        extraordinary: "true",
        reason: "Ruční odhad poloviny podle smlouvy."
      }
    )
    |> render_submit()

    assert has_element?(view, "#cost-draft-overrides", "Ruční odhad poloviny")

    view
    |> form("#cost-preview-form", publication: %{note: "Výjimka pro jediný podklad."})
    |> render_submit()

    view |> element("#cost-publish") |> render_click()
    assert {:ok, %{items: [item]}} = Economics.costs()
    assert item.estimated and item.extraordinary and item.via == :override
    assert Decimal.equal?(item.fixed, "22.75")
    assert Repo.get!(Snapshot, snapshot.id).payload == snapshot.payload
  end

  test "cost rules use searchable accounts and draft survives tab switching", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/economics/costs?tab=mapping")
    view |> element("#editor_account-search") |> render_focus()
    assert has_element?(view, "#editor_account-option-501100")
    view |> element("#editor_account-option-501100") |> render_click()

    view
    |> form("#cost-editor",
      editor: %{behavior: "fixed", reason: "Syntetický potvrzený paušál.", valid_from: "2026-07"}
    )
    |> render_submit()

    assert has_element?(view, "#cost-draft-rules", "Syntetický potvrzený paušál")
    view |> element("a", "Přehled nákladů") |> render_click()
    view |> element("a", "Mapování") |> render_click()
    assert has_element?(view, "#cost-draft-rules", "Syntetický potvrzený paušál")
    assert {:ok, %{version: nil}} = Economics.costs()
  end

  test "stale cost preview requires reload and disabled reporting rejects a pending mutation", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/admin/economics/costs?tab=mapping")
    view |> element("#cost-suggestions") |> render_click()
    view |> form("#cost-preview-form", publication: %{note: "První kontrola."}) |> render_submit()
    snapshot = Repo.one!(Snapshot)
    snapshot |> Ecto.Changeset.change(fingerprint: "changed-import") |> Repo.update!()
    view |> element("#cost-publish") |> render_click()
    assert render(view) =~ "Podklady nebo aktivní mapování se změnily"
    refute has_element?(view, "#cost-publish")
    assert Repo.aggregate(CozyCheckout.Economics.CostMappingVersion, :count) == 0
    Application.put_env(:cozy_checkout, :economics, enabled: false)
    render_click(view, "suggestions", %{})
    assert Repo.aggregate(CozyCheckout.Economics.CostMappingVersion, :count) == 0
  end

  test "cost historical snapshots and versions expose no mutation controls", %{conn: conn} do
    snapshot = Repo.one!(Snapshot)
    snapshot |> Ecto.Changeset.change(active: false) |> Repo.update!()
    {:ok, view, _} = live(conn, "/admin/economics/costs?snapshot=#{snapshot.id}&tab=mapping")
    refute has_element?(view, "#cost-editor")
    refute has_element?(view, "#cost-preview-form")
    render_click(view, "publish", %{})
    assert Repo.aggregate(CozyCheckout.Economics.CostMappingVersion, :count) == 0
  end

  test "all reporting URLs require the existing admin PIN" do
    for path <- [
          "/admin/economics",
          "/admin/economics/settings",
          "/admin/economics/costs",
          "/admin/economics/accounts/602001"
        ] do
      conn = build_conn() |> get(path)
      assert redirected_to(conn) =~ "/admin/login"
    end
  end

  test "disabled module hides navigation and rejects direct LiveView access", %{conn: conn} do
    Application.put_env(:cozy_checkout, :economics, enabled: false)

    refute Enum.any?(CozyCheckoutWeb.AdminNavigation.primary(), fn {_, path, _} ->
             path == "/admin/economics"
           end)

    refute Enum.any?(CozyCheckoutWeb.AdminNavigation.groups(), fn {_, links} ->
             Enum.any?(links, fn {_, path} -> path == "/admin/economics" end)
           end)

    for path <- [
          "/admin/economics",
          "/admin/economics/settings",
          "/admin/economics/costs",
          "/admin/economics/accounts/602001"
        ] do
      assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, path)
    end
  end
end

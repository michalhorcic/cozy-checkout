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

  test "all reporting URLs require the existing admin PIN" do
    for path <- [
          "/admin/economics",
          "/admin/economics/settings",
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
          "/admin/economics/accounts/602001"
        ] do
      assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, path)
    end
  end
end

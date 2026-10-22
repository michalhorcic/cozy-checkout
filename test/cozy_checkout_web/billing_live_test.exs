defmodule CozyCheckoutWeb.BillingLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Repo}
  alias CozyCheckoutWeb.AdminAuth

  setup %{conn: conn} do
    old = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      if old,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, old),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    Map.put(
      billing_fixture(),
      :conn,
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})
    )
  end

  test "booking flow previews and issues a real document without changing occupancy", %{
    conn: conn,
    booking: booking
  } do
    {:ok, view, html} = live(conn, "/admin/bookings/#{booking.id}/billing")
    assert html =~ "Kalkulace a počty hostů"

    view
    |> form("#billing-issue", issue: %{kind: "advance", percent: "50", amount: ""})
    |> render_submit()

    assert has_element?(view, "#document-preview")
    view |> element("button[phx-click=issue]") |> render_click()
    assert length(Billing.list_documents(%{"booking_id" => booking.id})) == 1
    assert CozyCheckout.Bookings.get_occupancy_for_date(booking.check_in_date) == 2
    assert render(view) =~ "Detail, PDF, odeslání a oprava"
  end

  test "seasons calendar exposes missing dates and supports explicit reprice", %{
    conn: conn,
    booking: booking,
    season: season
  } do
    {:ok, view, _} = live(conn, "/admin/accommodation-prices")
    assert has_element?(view, "#season-calendar")
    Billing.delete_season(season.id)
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    assert render(view) =~ "chybí sezonní ceník"
    assert render_click(element(view, "button[phx-click=pricing]")) =~ "Náhled přecenění"
  end

  test "settings, document detail and filters render", %{conn: conn, booking: booking} do
    final = issue!(booking, "final")
    {:ok, view, _} = live(conn, "/admin/billing/settings")
    assert has_element?(view, "#billing-profile")
    {:ok, view, _} = live(conn, "/admin/billing/documents/#{final.id}")
    assert has_element?(view, "#billing-email")
    assert has_element?(view, "#billing-correction")
    {:ok, view, _} = live(conn, "/admin/billing")
    assert render(view) =~ final.number
    view |> form("#billing-filter", filter: %{number: "NO-MATCH"}) |> render_submit()
    refute render(view) =~ final.number
    assert Repo.get!(CozyCheckout.Billing.Document, final.id).pdf == nil
  end

  test "PDF and billing administration require authentication", %{booking: booking} do
    final = issue!(booking, "final")
    conn = build_conn() |> get("/admin/billing/documents/#{final.id}/pdf")
    assert redirected_to(conn) == "/admin/login"
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(build_conn(), "/admin/billing")
  end

  test "authenticated PDF download generates a real advance PDF", %{conn: conn, booking: booking} do
    doc = issue!(booking, "advance")
    conn = get(conn, "/admin/billing/documents/#{doc.id}/pdf")
    assert response(conn, 200) =~ "%PDF-"
    assert get_resp_header(conn, "content-type") == ["application/pdf; charset=utf-8"]
    assert Billing.get_document!(doc.id).pdf == conn.resp_body
  end
end

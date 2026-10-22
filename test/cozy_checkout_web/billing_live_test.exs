defmodule CozyCheckoutWeb.BillingLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CozyCheckout.BillingFixtures
  import Swoosh.TestAssertions

  setup :set_swoosh_global
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

    assert has_element?(view, "#document-preview", "Záloha na pobyt a objednané služby")
    assert has_element?(view, "#document-preview", "2 850,00 CZK")
    refute has_element?(view, "#document-preview", "Přijatá záloha")
    refute has_element?(view, "#document-preview", "1 × 1")
    view |> element("button[phx-click=issue]") |> render_click()
    assert length(Billing.list_documents(%{"booking_id" => booking.id})) == 1
    assert CozyCheckout.Bookings.get_occupancy_for_date(booking.check_in_date) == 2
    [document] = Billing.list_documents(%{"booking_id" => booking.id})

    assert has_element?(
             view,
             "#billing-document-pdf-#{document.id}[href='/admin/billing/documents/#{document.id}/pdf']"
           )

    assert has_element?(view, "#billing-document-email-#{document.id}")
    refute has_element?(view, "#billing-items .badge", "Osoby")
  end

  test "document email can be checked and sent from the calculation without navigating away", %{
    conn: conn,
    booking: booking
  } do
    document = issue!(booking, "advance")
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    view |> element("#billing-document-email-#{document.id}") |> render_click()
    assert has_element?(view, "#billing-email-modal")
    assert has_element?(view, "#billing-email-modal-description", document.number)

    assert has_element?(
             view,
             "#billing-booking-email input[name='email[recipient]'][value='school@example.com']"
           )

    attrs = %{
      recipient: "test@example.com",
      subject: "Záloha na pobyt",
      body: "Dobrý den, zasíláme výzvu."
    }

    view |> form("#billing-booking-email", email: attrs) |> render_submit()
    assert has_element?(view, "#billing-booking-email-error", "souhlas")
    assert Billing.list_deliveries(document.id) == []

    assert has_element?(
             view,
             "#billing-booking-email input[name='email[recipient]'][value='test@example.com']"
           )

    view
    |> form("#billing-booking-email", email: Map.put(attrs, :consent, true))
    |> render_submit()

    refute has_element?(view, "#billing-email-modal")
    assert has_element?(view, "#billing-documents")
    assert has_element?(view, "#flash-info", "E-mail zařazen k odeslání")
    [delivery] = Billing.list_deliveries(document.id)
    assert delivery.recipient == "test@example.com"
    assert delivery.subject == attrs.subject
    assert delivery.body == attrs.body
    assert delivery.consented_at
    assert delivery.state == "queued"

    assert Repo.get_by!(Oban.Job, worker: "CozyCheckout.Workers.BillingEmailWorker").args == %{
             "delivery_id" => delivery.id
           }

    # A repeated click from the now-closed composer cannot enqueue another delivery.
    render_submit(view, "email", %{"email" => %{"consent" => "true"}})
    assert length(Billing.list_deliveries(document.id)) == 1
    job = %Oban.Job{args: %{"delivery_id" => delivery.id}, attempt: 1, max_attempts: 5}
    assert :ok = CozyCheckout.Workers.BillingEmailWorker.perform(job)
    stored = Billing.get_document!(document.id)

    assert_email_sent(fn email ->
      email.to == [{"", "test@example.com"}] and hd(email.attachments).data == stored.pdf
    end)
  end

  test "email composer validates recipients, cancels cleanly and only opens this booking's documents",
       %{conn: conn, booking: booking} do
    document = issue!(booking, "advance")
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    render_click(view, "compose-email", %{"id" => Ecto.UUID.generate()})
    refute has_element?(view, "#billing-email-modal")
    view |> element("#billing-document-email-#{document.id}") |> render_click()

    view
    |> form("#billing-booking-email", email: %{recipient: "invalid", consent: true})
    |> render_submit()

    assert has_element?(view, "#billing-booking-email-error")
    assert Billing.list_deliveries(document.id) == []
    render_click(view, "close-email")
    refute has_element?(view, "#billing-email-modal")
    assert has_element?(view, "#billing-items")
    assert CozyCheckout.Bookings.get_occupancy_for_date(booking.check_in_date) == 2
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

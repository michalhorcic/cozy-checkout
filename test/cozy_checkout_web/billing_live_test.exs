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

  test "customer form requires only a name and keeps optional fields in collapsed details", %{
    conn: conn,
    booking: booking
  } do
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    assert has_element?(view, "#billing-customer input[name='buyer[name]'][required]")
    assert has_element?(view, "#billing-customer-details summary", "Další údaje")
    refute has_element?(view, "#billing-customer-details[open]")
    refute has_element?(view, "#billing-customer-details [required]")

    attrs =
      Map.new(~w(street city postcode country company_id vat_id email), &{&1, ""})
      |> Map.put("name", "Jana Nováková")

    view |> form("#billing-customer", buyer: attrs) |> render_submit()
    assert Billing.customer(booking.id).data["street"] == ""
    view |> form("#billing-issue", issue: %{kind: "final"}) |> render_submit()
    assert has_element?(view, "#document-preview", "Jana Nováková")
    view |> element("button[phx-click=issue]") |> render_click()
    [document] = Billing.list_documents(%{"booking_id" => booking.id})
    assert document.snapshot["customer"]["name"] == "Jana Nováková"
    assert document.snapshot["customer"]["country"] == ""
  end

  test "customer name validation keeps the entered optional details on error", %{
    conn: conn,
    booking: booking
  } do
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    render_submit(view, "customer", %{"buyer" => %{"name" => "  ", "city" => "Liberec"}})
    assert has_element?(view, "#flash-error", "název/jméno")
    assert has_element?(view, "#billing-customer input[name='buyer[city]'][value='Liberec']")
    assert Billing.customer(booking.id).data["name"] == "Základní škola"
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

    assert has_element?(view, "#advance-preview-breakdown", "Rozpis pobytu a objednaných služeb")

    assert has_element?(
             view,
             "#advance-preview-breakdown",
             "50,00 % z 5 700,00 CZK = 2 850,00 CZK"
           )

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

  test "inline edits preview totals, block issuance, survive refresh and save together", %{
    conn: conn,
    booking: booking
  } do
    invoice = Billing.calculation(booking.id)
    adult = Enum.find(invoice.items, &(&1.name == "Dospělí"))
    child = Enum.find(invoice.items, &(&1.name == "Děti do 12 let"))
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    refute has_element?(view, "#billing-item")

    view |> form("#billing-issue", issue: %{kind: "advance", percent: "50"}) |> render_submit()
    assert has_element?(view, "#document-preview")

    attrs = %{
      adult.id => %{quantity: "3", nights: "2", price_per_night: "1000"},
      child.id => %{quantity: "1"}
    }

    view |> form("#billing-items-form", items: attrs) |> render_change()
    assert has_element?(view, "#billing-items-status", "Máte neuložené změny")
    assert has_element?(view, "#billing-item-#{adult.id}", "6 000,00")
    refute has_element?(view, "#document-preview")
    assert Billing.calculation(booking.id).total_price == invoice.total_price
    render_submit(view, "preview", %{"issue" => %{"kind" => "final"}})
    render_click(view, "issue")
    assert Billing.list_documents(%{"booking_id" => booking.id}) == []
    render_click(view, "refresh")
    assert has_element?(view, "#item-#{adult.id}_quantity[value='3']")
    view |> form("#billing-items-form", items: attrs) |> render_submit()
    saved = Billing.calculation(booking.id)
    assert Enum.find(saved.items, &(&1.id == adult.id)).quantity == 3
    assert Enum.find(saved.items, &(&1.id == child.id)).quantity == 1
    assert Decimal.equal?(saved.total_price, "8640")
    assert has_element?(view, "#billing-items-status", "Všechny změny jsou uloženy")
    assert has_element?(view, "#billing-save-items[disabled]")
    assert CozyCheckout.Bookings.get_occupancy_for_date(booking.check_in_date) == 4
  end

  test "invalid rows remain editable and discard restores persisted values", %{
    conn: conn,
    booking: booking
  } do
    invoice = Billing.calculation(booking.id)
    adult = Enum.find(invoice.items, &(&1.name == "Dospělí"))
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    render_submit(view, "save-items", %{"items" => %{adult.id => %{"quantity" => "-1"}}})
    assert has_element?(view, "#billing-item-#{adult.id} .text-error")
    assert Billing.calculation(booking.id).total_price == invoice.total_price
    assert has_element?(view, "#item-#{adult.id}_quantity[value='-1']")
    view |> element("#billing-discard-items") |> render_click()
    assert has_element?(view, "#item-#{adult.id}_quantity[value='2']")
    assert has_element?(view, "#billing-save-items[disabled]")
  end

  test "invalid numeric input blocks issuance even when casting produces no changes", %{
    conn: conn,
    booking: booking
  } do
    adult = Enum.find(Billing.calculation(booking.id).items, &(&1.name == "Dospělí"))
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    render_change(view, "change-items", %{"items" => %{adult.id => %{"quantity" => "1.5"}}})
    assert has_element?(view, "#billing-items-status", "Máte neuložené změny")
    render_submit(view, "preview", %{"issue" => %{"kind" => "final"}})
    refute has_element?(view, "#document-preview")
    assert has_element?(view, "#flash-error", "Nejprve uložte")
  end

  test "explicit repricing refreshes inline prices and missing prices remain blank", %{
    conn: conn,
    booking: booking
  } do
    adult = Enum.find(Billing.calculation(booking.id).items, &(&1.name == "Dospělí"))
    {:ok, _} = Billing.save_item(booking.id, %{"price_per_night" => ""}, adult.id)
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    assert has_element?(view, "#item-#{adult.id}_price_per_night[placeholder='Chybí cena']")
    assert has_element?(view, "#billing-items-form", "Doplňte ceny")
    render_click(view, "pricing")
    render_click(view, "apply-pricing")
    assert has_element?(view, "#item-#{adult.id}_price_per_night[value='950.00']")
    assert has_element?(view, "#billing-save-items[disabled]")
  end

  test "new items and removals are drafts until the common save", %{conn: conn, booking: booking} do
    invoice = Billing.calculation(booking.id)
    adult = Enum.find(invoice.items, &(&1.name == "Dospělí"))
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    render_click(view, "remove-item", %{"id" => adult.id})
    assert has_element?(view, "#billing-item-#{adult.id}", "Bude odstraněno")
    assert length(Billing.calculation(booking.id).items) == 3
    render_click(view, "restore-item", %{"id" => adult.id})
    assert has_element?(view, "#billing-save-items[disabled]")
    view |> element("#billing-add-item") |> render_click()
    html = render(view)
    [_, key] = Regex.run(~r/id="item-([a-f0-9-]+)_name"[^>]*value=""/, html)

    attrs = %{
      key => %{
        name: "Poplatek z pobytu",
        quantity: "2",
        nights: "3",
        price_per_night: "50",
        tax_mode: "outside"
      }
    }

    view |> form("#billing-items-form", items: attrs) |> render_change()
    assert length(Billing.calculation(booking.id).items) == 3
    view |> form("#billing-items-form", items: attrs) |> render_submit()
    fee = Enum.find(Billing.calculation(booking.id).items, &(&1.name == "Poplatek z pobytu"))
    assert fee.item_type == "extra"
    assert fee.tax_mode == "outside"
    assert Decimal.equal?(fee.total, "300")
    assert CozyCheckout.Bookings.get_occupancy_for_date(booking.check_in_date) == 2
    render_click(view, "remove-item", %{"id" => fee.id})
    view |> form("#billing-items-form") |> render_submit()
    assert length(Billing.calculation(booking.id).items) == 3
  end

  test "concurrent edits are rejected without losing draft input", %{conn: conn, booking: booking} do
    adult = Enum.find(Billing.calculation(booking.id).items, &(&1.name == "Dospělí"))
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    attrs = %{adult.id => %{quantity: "4"}}
    view |> form("#billing-items-form", items: attrs) |> render_change()
    {:ok, _} = Billing.save_item(booking.id, %{"quantity" => "3"}, adult.id)
    view |> form("#billing-items-form", items: attrs) |> render_submit()
    assert has_element?(view, "#flash-error", "mezitím změnila")
    assert has_element?(view, "#item-#{adult.id}_quantity[value='4']")
    assert Enum.find(Billing.calculation(booking.id).items, &(&1.id == adult.id)).quantity == 3
  end

  test "calculation notices clear from the whole notice and stay cleared after refresh", %{
    conn: conn,
    booking: booking
  } do
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")

    for _attempt <- 1..2 do
      view
      |> form("#billing-customer", buyer: %{name: "Test Customer", country: "CZ"})
      |> render_submit()

      assert has_element?(view, "#flash-info", "Uloženo")
      view |> element("#flash-info") |> render_click()
      refute has_element?(view, "#flash-info")

      render_click(view, "refresh")
      refute has_element?(view, "#flash-info")
    end
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

  test "manual accommodation export is available on an authenticated advance detail", %{
    conn: conn,
    booking: booking
  } do
    alias CozyCheckout.Abra.Accommodation
    previous = Application.get_env(:cozy_checkout, :abra_accommodation)

    Application.put_env(:cozy_checkout, :abra_accommodation,
      enabled: true,
      enabled_from: ~U[2020-01-01 00:00:00Z],
      base_url: "https://accounting.test",
      company_id: "test",
      username: "test",
      password: "test",
      advance_type_code: "ZÁLOHA",
      advance_series_code: "COZY-ZALOHA",
      bank_account_code: "BANKOVNÍ ÚČET"
    )

    on_exit(fn -> Application.put_env(:cozy_checkout, :abra_accommodation, previous) end)
    doc = issue!(booking, "advance")
    {:ok, view, _} = live(conn, "/admin/billing/documents/#{doc.id}")
    assert has_element?(view, "#accommodation-abra-export", "Exportovat do ABRA")
    view |> element("#accommodation-abra-export") |> render_click()
    assert has_element?(view, "#accommodation-abra", "Čeká na export")
    refute has_element?(view, "#accommodation-abra-export")
    assert Accommodation.get_export(doc.id).state == "queued"

    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(build_conn(), "/admin/billing/documents/#{doc.id}")
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

  test "reservation list links to actual billing and filters on the recorded payment", %{
    conn: conn,
    booking: booking
  } do
    {:ok, _} = CozyCheckout.Bookings.update_invoice_state(Billing.calculation(booking.id), "paid")
    {:ok, view, _} = live(conn, "/admin/bookings?show_all=true")
    assert has_element?(view, "#booking-billing-#{booking.id}", "Bez dokladu")
    refute has_element?(view, "button[phx-value-state]")
    refute has_element?(view, "#booking-payment-#{booking.id}")

    final = issue!(booking, "final", %{"due_on" => to_string(Date.add(Billing.today(), -1))})
    {:ok, view, _} = live(conn, "/admin/bookings?invoice_state=unpaid&show_all=true")
    assert has_element?(view, "#booking-billing-#{booking.id}", final.number)

    assert has_element?(
             view,
             "#booking-billing-details-#{booking.id}[popover='auto']",
             final.number
           )

    assert has_element?(
             view,
             "#booking-billing-trigger-#{booking.id}[aria-haspopup='dialog']",
             "Neuhrazeno"
           )

    refute has_element?(view, "#booking-billing-trigger-#{booking.id}", final.number)
    refute has_element?(view, "#booking-billing-trigger-#{booking.id}", "5 700")
    assert has_element?(view, "#booking-payment-#{booking.id}", "Neuhrazeno")
    assert has_element?(view, "#booking-overdue-#{booking.id}", "Po splatnosti")
    assert has_element?(view, "#booking-balance-#{booking.id}", "5 700")
    assert has_element?(view, "#bookings-filter option[value='unpaid'][selected]")

    view |> form("#bookings-filter", invoice_state: "paid") |> render_change()
    refute has_element?(view, "#booking-row-#{booking.id}")
    receipt!(booking, "5700", %{"paid_on" => to_string(Billing.today())})
    {:ok, view, _} = live(conn, "/admin/bookings?invoice_state=paid&show_all=true")
    assert has_element?(view, "#booking-payment-#{booking.id}", "Uhrazeno")
    refute has_element?(view, "#booking-overdue-#{booking.id}")
    refute has_element?(view, "#booking-balance-#{booking.id}")

    assert has_element?(
             view,
             "#booking-billing-link-#{booking.id}[href='/admin/bookings/#{booking.id}/billing']"
           )
  end

  test "private stays show no financial balance or payment forms and can return to normal billing",
       %{conn: conn, booking: booking} do
    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")
    view |> element("button[phx-click=personal]") |> render_click()
    assert has_element?(view, "#billing-personal", "Soukromý pobyt")
    refute has_element?(view, "#billing-payment")
    refute has_element?(view, "#billing-issue")
    assert Billing.list_payments(booking.id) == []
    assert Billing.list_documents(%{"booking_id" => booking.id}) == []

    {:ok, list, _} = live(conn, "/admin/bookings?invoice_state=personal&show_all=true")
    assert has_element?(list, "#booking-billing-#{booking.id}", "Soukromý pobyt")
    refute has_element?(list, "#booking-payment-#{booking.id}")
    refute has_element?(list, "#booking-balance-#{booking.id}")
    {:ok, detail, _} = live(conn, "/admin/bookings/#{booking.id}")
    assert has_element?(detail, "#booking-personal", "bez finanční evidence")

    view |> element("button[phx-click=personal]") |> render_click()
    refute has_element?(view, "#billing-personal")
    assert has_element?(view, "#billing-payment")
    assert has_element?(view, "#billing-issue")
  end

  test "advance preview and issued detail show child categories and the chosen amount", %{
    conn: conn,
    booking: booking
  } do
    for item <- Billing.calculation(booking.id).items, item.name != "Dospělí" do
      assert {:ok, _} = Billing.save_item(booking.id, %{"quantity" => "1"}, item.id)
    end

    {:ok, view, _} = live(conn, "/admin/bookings/#{booking.id}/billing")

    view
    |> form("#billing-issue", issue: %{kind: "advance", percent: "50", amount: "2000"})
    |> render_submit()

    assert has_element?(view, "#advance-preview-breakdown td", "Děti do 2 let")
    assert has_element?(view, "#advance-preview-breakdown td", "Děti do 12 let")
    assert has_element?(view, "#advance-preview-breakdown th", "Jedn. cena s DPH")
    assert has_element?(view, "#advance-preview-breakdown td", "950,00 CZK")
    assert has_element?(view, "#advance-preview-breakdown", "Záloha zadaná částkou: 2 000,00 CZK")
    refute has_element?(view, "#advance-preview-breakdown", "50,00 %")
    view |> element("button[phx-click=issue]") |> render_click()
    [document] = Billing.list_documents(%{"booking_id" => booking.id})
    {:ok, detail, _} = live(conn, "/admin/billing/documents/#{document.id}")
    assert has_element?(detail, "#advance-document-breakdown td", "Děti do 2 let")
    assert has_element?(detail, "#advance-document-breakdown td", "Děti do 12 let")

    assert has_element?(
             detail,
             "#advance-document-breakdown",
             "Záloha zadaná částkou: 2 000,00 CZK"
           )
  end
end

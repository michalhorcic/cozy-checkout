defmodule CozyCheckoutWeb.AbraPaymentStatusLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  use Oban.Testing, repo: CozyCheckout.Repo
  import Phoenix.LiveViewTest
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.Repo
  alias CozyCheckout.Abra.AccommodationExport
  alias CozyCheckoutWeb.AdminAuth

  setup %{conn: conn} do
    previous = Application.get_env(:cozy_checkout, :abra_accommodation)
    pin = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    Application.put_env(:cozy_checkout, :abra_accommodation,
      enabled: true,
      base_url: "https://accounting.test",
      company_id: "balances",
      username: "user",
      password: "password"
    )

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :abra_accommodation, previous)

      if pin,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, pin),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    fixture = billing_fixture()
    doc = issue_without_abra!(fixture.booking, "advance", %{"amount" => "1000"})

    export =
      Repo.insert!(%AccommodationExport{
        document_id: doc.id,
        base_url: "https://accounting.test",
        company_id: "balances",
        external_id: "ext:cozy-checkout:accommodation:#{doc.id}",
        remote_id: "101",
        payload: %{},
        state: "synced",
        payment_total: Decimal.new(1000),
        payment_remaining: Decimal.new(0),
        payment_checked_at: DateTime.utc_now(),
        payment_attempted_at: DateTime.utc_now()
      })

    Map.merge(fixture, %{
      document: doc,
      export: export,
      public_conn: conn,
      conn:
        Plug.Test.init_test_session(conn, %{
          AdminAuth.session_key() => System.system_time(:second)
        })
    })
  end

  test "paid advance and remaining stay balance are shown separately, including after a background refresh",
       %{conn: conn, booking: b, document: doc, export: export, invoice: calc} do
    {:ok, view, _} = live(conn, "/admin/bookings/#{b.id}/billing")
    expected = CozyCheckout.Billing.Presentation.amount(Decimal.sub(calc.total_price, 1000))
    assert has_element?(view, "#payer-financial-summary", "Částečně uhrazeno")
    assert has_element?(view, "#payer-financial-summary", expected)
    assert has_element?(view, "#booking-total-outstanding", expected)
    assert has_element?(view, "#abra-payment-#{doc.id}", "Uhrazeno")

    assert has_element?(
             view,
             "#abra-payment-#{doc.id}",
             CozyCheckout.Billing.Presentation.balance_amount(Decimal.new(0))
           )

    view |> element("#check-abra-payments") |> render_click()

    assert_enqueued(
      worker: CozyCheckout.Workers.AbraPaymentStatusWorker,
      args: %{booking_id: b.id}
    )

    assert Repo.aggregate(CozyCheckout.Billing.Payment, :count) == 0
    assert Repo.aggregate(CozyCheckout.Billing.Document, :count) == 1

    export |> Ecto.Changeset.change(payment_remaining: Decimal.new(1000)) |> Repo.update!()
    send(view.pid, :abra_tick)
    assert has_element?(view, "#payer-financial-summary", "Neuhrazeno")

    assert has_element?(
             view,
             "#payer-financial-summary",
             CozyCheckout.Billing.Presentation.amount(calc.total_price)
           )
  end

  test "document list, detail and booking list show the same status and freshness warning",
       %{conn: conn, booking: b, document: doc, export: export} do
    export |> Ecto.Changeset.change(payment_error: "ABRA není dostupná") |> Repo.update!()
    {:ok, booking, _} = live(conn, "/admin/bookings/#{b.id}/billing")
    assert has_element?(booking, "#abra-payment-#{doc.id}", "Údaje mohou být neaktuální")
    {:ok, list, _} = live(conn, "/admin/billing")
    assert has_element?(list, "#abra-payment-#{doc.id}", "Uhrazeno")
    {:ok, detail, _} = live(conn, "/admin/billing/documents/#{doc.id}")
    assert has_element?(detail, "#abra-payment-#{doc.id}", "Údaje mohou být neaktuální")
    {:ok, booking_detail, _} = live(conn, "/admin/bookings/#{b.id}")
    assert has_element?(booking_detail, "#booking-billing-summary", "Údaje mohou být neaktuální")
    {:ok, bookings, _} = live(conn, "/admin/bookings?show_all=true")
    assert has_element?(bookings, "#booking-row-#{b.id}")
    assert has_element?(bookings, "#booking-payment-#{b.id}", "Částečně uhrazeno")
    assert has_element?(bookings, ~s([id="booking-row-#{b.id}"][class~="bg-warning/5"]))
    assert has_element?(bookings, "#booking-document-status-#{b.id}", "Záloha přijata")

    assert has_element?(
             bookings,
             "#booking-billing-details-#{b.id}",
             "Údaje mohou být neaktuální"
           )
  end

  test "billing balances and refresh actions remain behind the admin PIN", %{
    public_conn: conn,
    booking: b
  } do
    assert {:error, {:redirect, %{to: to}}} = live(conn, "/admin/bookings/#{b.id}/billing")
    assert to =~ "/admin/login"
  end
end

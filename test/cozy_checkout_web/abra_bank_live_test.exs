defmodule CozyCheckoutWeb.AbraBankLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckoutWeb.AdminAuth

  setup do
    old = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      if old,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, old),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    :ok
  end

  test "bank data requires admin PIN and the view provides no payment confirmation", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, "/admin/billing/bank")
    assert to =~ "/admin/login"

    conn =
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    {:ok, view, _} = live(conn, "/admin/billing/bank")
    assert has_element?(view, "#bank-status")
    refute has_element?(view, "[phx-click=payment]")
    refute has_element?(view, "[phx-click=confirm]")
  end

  for status <- [200, 403] do
    test "bank download button reports HTTP #{status}", %{conn: conn} do
      previous = Application.get_env(:cozy_checkout, :abra_accommodation)
      options = Req.default_options()
      client = CozyCheckout.Abra.Client

      Application.put_env(:cozy_checkout, :abra_accommodation,
        enabled: true,
        base_url: "https://accounting.test",
        company_id: "download-test",
        username: "test-user",
        password: "test-password",
        bank_account_code: "TEST"
      )

      Req.default_options(plug: {Req.Test, client})

      on_exit(fn ->
        Application.put_env(:cozy_checkout, :abra_accommodation, previous)
        Req.default_options(options)
      end)

      Req.Test.verify_on_exit!()

      Req.Test.expect(client, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/c/download-test/banka/nacteni-vypisu-online"
        Plug.Conn.send_resp(conn, unquote(status), "")
      end)

      conn =
        Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

      {:ok, view, _} = live(conn, "/admin/billing/bank")
      Req.Test.allow(client, self(), view.pid)
      html = view |> element("#bank-download-statements") |> render_click()

      if unquote(status) == 200 do
        assert html =~ "ABRA přijala požadavek"
      else
        assert html =~ "ABRA HTTP 403"
      end
    end
  end

  test "booking list opens bank suggestions in a dialog without marking an invoice paid", %{
    conn: conn
  } do
    previous = Application.get_env(:cozy_checkout, :abra_accommodation)

    Application.put_env(:cozy_checkout, :abra_accommodation,
      enabled: true,
      enabled_from: ~U[2020-01-01 00:00:00Z],
      base_url: "https://accounting.test",
      company_id: "list-test",
      bank_account_code: "TEST"
    )

    on_exit(fn -> Application.put_env(:cozy_checkout, :abra_accommodation, previous) end)

    %{booking: booking} = CozyCheckout.BillingFixtures.billing_fixture()
    doc = CozyCheckout.BillingFixtures.issue_without_abra!(booking, "final")

    movement =
      %CozyCheckout.Abra.BankMovement{}
      |> Ecto.Changeset.change(
        base_url: "https://accounting.test",
        company_id: "list-test",
        remote_id: "1",
        account: "code:TEST",
        amount: doc.total,
        currency: "code:CZK",
        direction: "typPohybu.prijem",
        paid_on: CozyCheckout.Billing.today(),
        variable_symbol: doc.variable_symbol,
        pairing: "unverified",
        scan_id: Ecto.UUID.generate(),
        raw: %{}
      )
      |> CozyCheckout.Repo.insert!()

    conn =
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    {:ok, view, _} = live(conn, "/admin/bookings?show_all=true")

    assert has_element?(
             view,
             "#booking-bank-pending-#{booking.id}[phx-click='open-bank-payment']",
             "Platba z banky k ověření"
           )

    assert has_element?(view, "#booking-payment-#{booking.id}", "Neuhrazeno")
    assert CozyCheckout.Billing.list_payments(booking.id) == []

    second_movement =
      %CozyCheckout.Abra.BankMovement{}
      |> Ecto.Changeset.change(
        Map.take(
          movement,
          ~w(base_url company_id account amount currency direction paid_on variable_symbol pairing scan_id raw)a
        )
        |> Map.put(:remote_id, "2")
      )
      |> CozyCheckout.Repo.insert!()

    view |> element("#booking-bank-pending-#{booking.id}") |> render_click()
    assert has_element?(view, "#booking-bank-payment-modal", "Spárovat platbu z banky")
    assert has_element?(view, "#booking-bank-movement-#{movement.id}", doc.number)
    assert has_element?(view, "#booking-bank-movement-#{second_movement.id}", doc.number)
    refute has_element?(view, "#booking-bank-confirm-payment")
    assert CozyCheckout.Billing.list_payments(booking.id) == []
    assert has_element?(view, "#booking-payment-#{booking.id}", "Neuhrazeno")

    # A stale proposal must disappear on refresh, without leaving the list.
    second_movement
    |> Ecto.Changeset.change(missing_at: DateTime.utc_now(:second))
    |> CozyCheckout.Repo.update!()

    view |> element("#booking-bank-payment-modal button", "Obnovit návrhy") |> render_click()
    refute has_element?(view, "#booking-bank-movement-#{second_movement.id}")
    assert has_element?(view, "#booking-bank-movement-#{movement.id}")

    view |> element("#booking-bank-payment-modal button", "Zavřít") |> render_click()
    refute has_element?(view, "#booking-bank-payment-modal")
    assert has_element?(view, "#booking-bank-pending-#{booking.id}")

    movement
    |> Ecto.Changeset.change(missing_at: DateTime.utc_now(:second))
    |> CozyCheckout.Repo.update!()

    {:ok, refreshed, _} = live(conn, "/admin/bookings?show_all=true")
    refute has_element?(refreshed, "#booking-bank-pending-#{booking.id}")
    assert has_element?(refreshed, "#booking-payment-#{booking.id}", "Neuhrazeno")
  end
end

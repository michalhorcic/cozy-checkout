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

  test "booking list links pending bank suggestions without marking an invoice paid", %{
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
        raw: %{}
      )
      |> CozyCheckout.Repo.insert!()

    conn =
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

    {:ok, view, _} = live(conn, "/admin/bookings?show_all=true")

    assert has_element?(
             view,
             "#booking-bank-pending-#{booking.id}[href='/admin/bookings/#{booking.id}/billing#booking-bank-suggestions']",
             "Platba z banky k ověření"
           )

    assert has_element?(view, "#booking-payment-#{booking.id}", "Neuhrazeno")
    assert CozyCheckout.Billing.list_payments(booking.id) == []

    movement
    |> Ecto.Changeset.change(missing_at: DateTime.utc_now(:second))
    |> CozyCheckout.Repo.update!()

    {:ok, refreshed, _} = live(conn, "/admin/bookings?show_all=true")
    refute has_element?(refreshed, "#booking-bank-pending-#{booking.id}")
    assert has_element?(refreshed, "#booking-payment-#{booking.id}", "Neuhrazeno")
  end
end

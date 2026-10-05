defmodule CozyCheckoutWeb.PosPaymentsTest do
  use CozyCheckoutWeb.ConnCase, async: false
  @moduletag :financial
  import Phoenix.LiveViewTest
  import CozyCheckout.SalesFixtures
  alias CozyCheckout.{Repo, Sales}
  alias CozyCheckoutWeb.{AdminAuth, AdminAuthRateLimiter}
  alias CozyCheckoutWeb.PosLive.OrderManagement

  setup do
    previous = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))
    AdminAuthRateLimiter.reset(:pos_payment)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, previous),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)

      AdminAuthRateLimiter.reset(:pos_payment)
    end)

    order = order_fixture()
    item_fixture(order, "300")
    %{order: order}
  end

  test "POS payment screen can mount through the real route", %{conn: conn, order: order} do
    {:ok, view, _} = live(conn, "/pos/orders/#{order.id}")
    assert has_element?(view, "#pos-keep-alive")
  end

  # The initial disconnected render currently crashes on @order == nil. Exercise
  # the public connected mount and event callbacks independently so that one UI
  # defect does not mask all of the financial regressions below.
  test "cash payment records the adjusted total", %{order: order} do
    socket = order |> mounted() |> authorize() |> adjust("30", "20") |> cash()
    [payment] = Sales.list_payments_for_order(order.id)
    assert_amount(payment.amount, "290")
    assert_amount(Sales.get_order!(order.id).total_amount, "290")
    assert Sales.get_order!(order.id).status == "paid"
    assert socket.assigns.payment_method == "cash_success"
    assert socket.assigns.payment_invoice_number == payment.invoice_number
  end

  test "cash settlement collects only the outstanding balance", %{order: order} do
    {:ok, _} = Sales.create_payment(payment_attrs(order, "100"))
    order |> mounted() |> authorize() |> cash()
    assert_paid_amount(order, "300")
  end

  test "QR settlement collects only the outstanding balance", %{order: order} do
    {:ok, _} = Sales.create_payment(payment_attrs(order, "100"))
    socket = order |> mounted() |> authorize() |> qr()
    event(socket, "confirm_qr_payment")
    assert_paid_amount(order, "300")
  end

  @tag :known_bug
  test "QR preview is not a payment and cancelling does not persist adjustments", %{order: order} do
    socket = order |> mounted() |> authorize() |> adjust("30", "20") |> qr()
    assert Sales.list_payments_for_order(order.id) == []
    assert socket.assigns.payment_qr_svg != nil
    event(socket, "close_payment_modal")
    updated = Sales.get_order!(order.id)
    assert_amount(updated.total_amount, "300")
    assert_amount(updated.discount_amount, "0")
    assert_amount(updated.tips_amount, "0")
  end

  @tag :known_bug
  test "QR confirmation rejects an amount changed after the customer saw the QR", %{order: order} do
    socket = order |> mounted() |> authorize() |> qr()
    item_fixture(order, "50")
    event(socket, "confirm_qr_payment")
    assert Sales.list_payments_for_order(order.id) == []
    assert Sales.get_order!(order.id).status == "open"
  end

  test "direct payment events without a PIN never record payments", %{order: order} do
    socket = mounted(order)
    socket |> cash() |> qr() |> event("confirm_qr_payment")
    assert Sales.list_payments_for_order(order.id) == []
  end

  test "wrong PIN cannot authorize payment and five failures block it", %{order: order} do
    socket = order |> mounted() |> event("open_payment_modal")

    socket =
      Enum.reduce(1..5, socket, fn _, current ->
        next = event(current, "authorize_payment", %{"payment_pin" => "482732"})
        refute next.assigns.payment_pin_authorized
        next
      end)

    socket = event(socket, "authorize_payment", %{"payment_pin" => "482731"})
    refute socket.assigns.payment_pin_authorized
    refute socket.assigns.show_payment_modal
    assert Sales.list_payments_for_order(order.id) == []
  end

  test "closing the modal revokes payment authorization", %{order: order} do
    order |> mounted() |> authorize() |> event("close_payment_modal") |> cash()
    assert Sales.list_payments_for_order(order.id) == []
  end

  test "repeating a successful cash event does not create a second payment", %{order: order} do
    order |> mounted() |> authorize() |> cash() |> cash()
    assert length(Sales.list_payments_for_order(order.id)) == 1
    assert_paid_amount(order, "300")
  end

  test "repeating a successful QR confirmation does not create a second payment", %{order: order} do
    order
    |> mounted()
    |> authorize()
    |> qr()
    |> event("confirm_qr_payment")
    |> event("confirm_qr_payment")

    assert length(Sales.list_payments_for_order(order.id)) == 1
    assert_paid_amount(order, "300")
  end

  @tag :known_bug
  test "failed payment leaves the original total, discount and tips unchanged", %{order: order} do
    socket = order |> mounted() |> authorize() |> adjust("30", "20")
    other = order_fixture()
    item_fixture(other, "1")

    reserved =
      Repo.insert!(
        Sales.Payment.changeset(
          %Sales.Payment{},
          Map.put(payment_attrs(other, "1"), "invoice_number", "PLACEHOLDER")
        )
      )

    number = Sales.generate_invoice_number()
    reserved |> Ecto.Changeset.change(invoice_number: number) |> Repo.update!()
    cash(socket)
    updated = Sales.get_order!(order.id)
    assert_amount(updated.total_amount, "300")
    assert_amount(updated.discount_amount, "0")
    assert_amount(updated.tips_amount, "0")
    assert Sales.list_payments_for_order(order.id) == []
  end

  @tag :known_bug
  test "manual recalculation preserves discount and tips", %{order: order} do
    {:ok, _} =
      Sales.update_order(Sales.get_order!(order.id), %{
        "discount_amount" => "30",
        "tips_amount" => "20",
        "total_amount" => "290"
      })

    order |> mounted() |> event("open_recalculate_modal") |> event("apply_recalculation")
    assert_amount(Sales.get_order!(order.id).total_amount, "290")
  end

  defp mounted(order) do
    socket = %Phoenix.LiveView.Socket{
      endpoint: CozyCheckoutWeb.Endpoint,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{live_temp: %{}}
    }

    {:ok, socket} = OrderManagement.mount(%{"id" => order.id}, %{}, socket)
    socket
  end

  defp event(socket, name, params \\ %{}) do
    {:noreply, socket} = OrderManagement.handle_event(name, params, socket)
    socket
  end

  defp authorize(socket) do
    socket =
      socket
      |> event("open_payment_modal")
      |> event("authorize_payment", %{"payment_pin" => "482731"})

    assert socket.assigns.payment_pin_authorized
    socket
  end

  defp adjust(socket, discount, tips),
    do:
      event(socket, "update_payment_fields", %{
        "discount_amount" => discount,
        "tips_amount" => tips,
        "discount_reason" => "Test discount"
      })

  defp cash(socket), do: event(socket, "select_payment_method", %{"method" => "cash"})
  defp qr(socket), do: event(socket, "select_payment_method", %{"method" => "qr_code"})

  defp assert_paid_amount(order, expected) do
    assert_amount(
      Enum.reduce(
        Sales.list_payments_for_order(order.id),
        Decimal.new(0),
        &Decimal.add(&2, &1.amount)
      ),
      expected
    )
  end
end

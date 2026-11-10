defmodule CozyCheckout.BookingSummaryTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Bookings}
  alias CozyCheckout.Billing.BookingSummary

  setup do: billing_fixture()

  defp summary(booking), do: Map.fetch!(BookingSummary.for_bookings([booking.id]), booking.id)

  defp assert_filter(booking, state) do
    assert {:ok, {bookings, meta}} = Bookings.list_bookings_with_flop(%{"invoice_state" => state})
    assert Enum.map(bookings, & &1.id) == [booking.id]
    assert meta.total_count == 1
  end

  test "advance coverage counts reservations once across pages and respects every filter", %{
    booking: booking
  } do
    issue!(booking, "advance")
    issue!(booking, "advance")

    {:ok, other} =
      Bookings.create_booking(%{
        guest_id: booking.guest_id,
        check_in_date: Billing.today(),
        status: "active"
      })

    assert %{total: 2, issued: 1, percent: percent} =
             Bookings.advance_coverage(%{"page_size" => "1", "page" => "2"})

    assert Decimal.equal?(percent, 50)

    assert %{total: 1, issued: 1} =
             Bookings.advance_coverage(%{"invoice_state" => "advance_issued"})

    assert %{total: 1, issued: 0} =
             Bookings.advance_coverage(%{
               "filters" => [%{"field" => "status", "op" => "==", "value" => "active"}]
             })

    assert %{total: 1, issued: 0} =
             Bookings.advance_coverage(%{"show_current_and_future" => "true"})

    assert %{total: 0, issued: 0, percent: nil} =
             Bookings.advance_coverage(%{"guest_search" => "no-such-guest"})

    {:ok, _} = Bookings.delete_booking(other)
    assert %{total: 1, issued: 1} = Bookings.advance_coverage(%{})
  end

  test "advance coverage excludes personal stays", %{booking: booking} do
    issue!(booking, "advance")

    {:ok, personal} =
      Bookings.create_booking(%{
        guest_id: booking.guest_id,
        check_in_date: booking.check_in_date,
        check_out_date: booking.check_out_date
      })

    assert {:ok, _} = Billing.create_calculation(personal.id)
    assert {:ok, _} = Billing.set_personal(personal.id)

    assert %{total: 1, issued: 1, percent: percent} = Bookings.advance_coverage(%{})
    assert Decimal.equal?(percent, 100)

    assert %{total: 0, issued: 0, percent: nil} =
             Bookings.advance_coverage(%{"invoice_state" => "personal"})

    assert {:ok, _} = Billing.set_personal(personal.id, false)
    assert %{total: 2, issued: 1, percent: percent} = Bookings.advance_coverage(%{})
    assert Decimal.equal?(percent, 50)
  end

  test "legacy calculation states never imply issued documents or money", %{booking: booking} do
    for state <- ~w(draft generated sent advance_paid paid) do
      {:ok, _} = Bookings.update_invoice_state(Billing.calculation(booking.id), state)
      assert %{state: "no_document", payment_state: nil, outstanding: nil} = summary(booking)
      assert_filter(booking, "no_document")
      assert {:ok, {[], _}} = Bookings.list_bookings_with_flop(%{"invoice_state" => "paid"})
    end
  end

  test "multiple requests and fully paid advances do not imply a final invoice", %{
    booking: booking
  } do
    issue!(booking, "advance")
    issue!(booking, "advance", %{"amount" => "1000"})
    assert %{state: "advance_issued", payment_state: nil} = summary(booking)
    assert_filter(booking, "advance_issued")
    receipt!(booking, "5700")
    assert %{state: "advance_received", payment_state: nil, outstanding: nil} = summary(booking)
    assert_filter(booking, "advance_received")
    final = issue!(booking, "final")
    assert %{state: "final", payment_state: "paid", final_id: id} = summary(booking)
    assert id == final.id
    assert_filter(booking, "paid")
  end

  test "payer advance percentages sum immutable issuance values without counting receipts", %{
    booking: booking
  } do
    payer = Billing.account(booking.id)
    {:ok, other} = Billing.save_account(booking.id, %{"name" => "Jiný plátce", "adults" => "1"})
    issue!(booking, "advance", %{"percent" => "30"})
    issue!(booking, "advance", %{"percent" => "20"})
    issue!(booking, "advance", %{"amount" => "570"})

    attrs = %{"percent" => "80"}
    {:ok, preview} = Billing.preview(other, "advance", attrs)

    assert {:ok, _} =
             Billing.issue(
               other,
               "advance",
               Map.put(attrs, "preview_token", preview.token),
               Ecto.UUID.generate()
             )

    receipt!(booking, "570")

    summaries = BookingSummary.for_accounts(booking.id)
    assert summaries[payer.id].advance_count == 3
    assert Decimal.equal?(summaries[payer.id].advance_percent, "60")
    assert Decimal.equal?(summaries[other.id].advance_percent, "80")

    item = Enum.find(Billing.calculation(payer).items, &(&1.name == "Dospělí"))
    assert {:ok, _} = Billing.save_item(payer, %{"price_per_night" => "1900"}, item.id)
    assert Decimal.equal?(BookingSummary.for_accounts(booking.id)[payer.id].advance_percent, "60")
  end

  test "legacy advance without issuance basis leaves total percentage unknown", %{
    booking: booking
  } do
    document = issue!(booking, "advance", %{"percent" => "30"})

    attrs =
      document
      |> Map.take([
        :billing_account_id,
        :booking_id,
        :kind,
        :issued_on,
        :tax_date,
        :due_on,
        :lines,
        :total,
        :pdf,
        :pdf_sha256
      ])
      |> Map.merge(%{
        number: "LEGACY-#{Ecto.UUID.generate()}",
        variable_symbol: "legacy-#{Ecto.UUID.generate()}",
        request_id: Ecto.UUID.generate(),
        snapshot: %{}
      })

    Repo.insert!(struct(CozyCheckout.Billing.Document, attrs))
    payer = Billing.account(booking.id)
    summary = BookingSummary.for_accounts(booking.id)[payer.id]
    assert summary.advance_count == 2
    assert is_nil(summary.advance_percent)
  end

  test "final balance, partial payments, due dates and overpayment match the billing ledger", %{
    booking: booking
  } do
    final = issue!(booking, "final", %{"due_on" => to_string(Date.add(Billing.today(), -1))})
    assert %{payment_state: "unpaid", overdue: true} = summary(booking)
    assert_filter(booking, "unpaid")
    assert_filter(booking, "overdue")
    receipt!(booking, "1000", %{"paid_on" => to_string(Billing.today())})
    assert %{payment_state: "partial", overdue: true} = summary(booking)
    assert_filter(booking, "partial")
    receipt!(booking, "4800", %{"paid_on" => to_string(Billing.today())})
    assert %{payment_state: "overpaid", overdue: false} = summary(booking)
    assert_filter(booking, "overpaid")
    assert Decimal.equal?(summary(booking).outstanding, Billing.balance(booking.id).outstanding)

    assert {:ok, _} =
             Billing.record_payment(booking.id, %{
               "request_id" => Ecto.UUID.generate(),
               "kind" => "refund",
               "amount" => "100",
               "paid_on" => to_string(Billing.today()),
               "method" => "bank"
             })

    assert %{payment_state: "paid", overdue: false} = summary(booking)
    assert_filter(booking, "paid")
    # Later calculation edits must never replace the issued final's immutable price.
    item = hd(Billing.calculation(booking.id).items)
    assert {:ok, _} = Billing.save_item(booking.id, %{"quantity" => "10"}, item.id)
    assert Decimal.equal?(summary(booking).outstanding, 0)
    assert summary(booking).final_number == final.number
  end

  test "final corrections and refunds change the derived status without counting advance receipts twice",
       %{booking: booking} do
    receipt!(booking, "1000")
    final = issue!(booking, "final")
    assert Decimal.equal?(summary(booking).outstanding, "4700")

    assert {:ok, _} =
             Billing.correct(
               final.id,
               %{"amount" => "5700", "reason" => "Zrušení pobytu"},
               Ecto.UUID.generate()
             )

    assert %{payment_state: "overpaid"} = summary(booking)
    assert Decimal.equal?(summary(booking).outstanding, "-1000")

    assert {:ok, _} =
             Billing.record_payment(booking.id, %{
               "request_id" => Ecto.UUID.generate(),
               "kind" => "refund",
               "amount" => "1000",
               "paid_on" => to_string(Billing.today()),
               "method" => "bank"
             })

    assert %{payment_state: "paid"} = summary(booking)
    assert Decimal.equal?(summary(booking).outstanding, Billing.balance(booking.id).outstanding)
  end

  test "a refunded advance is no longer shown as received", %{booking: booking} do
    payment = receipt!(booking, "1000")

    assert {:ok, _} =
             Billing.correct(
               payment.tax_document_id,
               %{"amount" => "1000", "reason" => "Vrácení zálohy"},
               Ecto.UUID.generate()
             )

    assert {:ok, _} =
             Billing.record_payment(booking.id, %{
               "request_id" => Ecto.UUID.generate(),
               "kind" => "refund",
               "amount" => "1000",
               "paid_on" => to_string(Billing.today()),
               "method" => "bank"
             })

    assert %{state: "advance_returned", payment_state: nil} = summary(booking)
    assert_filter(booking, "advance_returned")
  end

  test "private stays preserve occupancy and have no financial summary", %{booking: booking} do
    assert {:ok, _} = Billing.set_personal(booking.id)

    assert %{state: "personal", payment_state: nil, outstanding: nil, overdue: false} =
             summary(booking)

    assert_filter(booking, "personal")
    assert Bookings.get_occupancy_for_date(booking.check_in_date) == 2
    assert {:error, _} = Billing.preview(booking.id, "final")
    assert {:ok, _} = Billing.set_personal(booking.id, false)
    assert %{state: "no_document"} = summary(booking)
  end

  test "filters count and paginate bookings without multiplying documents", %{booking: booking} do
    for n <- 1..2 do
      Repo.insert!(%CozyCheckout.Bookings.Booking{
        guest_id: booking.guest_id,
        check_in_date: Date.add(booking.check_in_date, n)
      })
    end

    issue!(booking, "advance")
    issue!(booking, "advance")

    assert {:ok, {rows, meta}} =
             Bookings.list_bookings_with_flop(%{
               "invoice_state" => "no_document",
               "page_size" => "1"
             })

    assert length(rows) == 1
    assert meta.total_count == 2
    assert_filter(booking, "advance_issued")
  end

  test "a final due today is not overdue", %{booking: booking} do
    issue!(booking, "final", %{"due_on" => to_string(Billing.today())})
    assert %{payment_state: "unpaid", overdue: false} = summary(booking)
    assert {:ok, {[], _}} = Bookings.list_bookings_with_flop(%{"invoice_state" => "overdue"})
  end
end

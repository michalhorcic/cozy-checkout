defmodule CozyCheckout.BillingAccountsTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Bookings, Meals, QueryRecorder}
  alias CozyCheckout.Billing.{Account, BookingSummary, Document, Payment}

  setup do: billing_fixture()

  defp payer!(booking, attrs \\ %{}) do
    {:ok, payer} =
      Billing.save_account(
        booking.id,
        Map.merge(
          %{
            "name" => "Rodina Novákova",
            "adults" => "1",
            "infants" => "0",
            "children" => "0"
          },
          attrs
        )
      )

    payer
  end

  defp issue_for!(payer, attrs \\ %{}) do
    {:ok, preview} = Billing.preview(payer, "final", attrs)

    {:ok, doc} =
      Billing.issue(
        payer,
        "final",
        Map.put(attrs, "preview_token", preview.token),
        Ecto.UUID.generate()
      )

    doc
  end

  defp receive!(payer, amount, date) do
    {:ok, payment} =
      Billing.record_payment(payer, %{
        "request_id" => Ecto.UUID.generate(),
        "amount" => amount,
        "paid_on" => to_string(date),
        "method" => "bank"
      })

    payment
  end

  defp summary(booking), do: BookingSummary.for_bookings([booking.id])[booking.id]

  test "one reservation supplies occupancy and meals before and after payer invoices", %{
    booking: booking
  } do
    {:ok, booking} =
      Bookings.update_booking(booking, %{
        adults: 22,
        children: 13,
        meal_plan: "full_board",
        meal_adults: 22,
        meal_children: 13,
        first_meal: "dinner",
        last_meal: "breakfast"
      })

    occupancy = Bookings.get_occupancy_for_range(booking.check_in_date, booking.check_out_date)

    meals =
      Meals.PortionCounts.for_range(
        [Bookings.get_booking!(booking.id)],
        booking.check_in_date,
        booking.check_out_date
      )

    payer = payer!(booking, %{"adults" => "2", "children" => "1"})
    issue_for!(payer)
    issue!(booking, "final")

    assert Bookings.get_occupancy_for_range(booking.check_in_date, booking.check_out_date) ==
             occupancy

    assert Bookings.get_occupancy_for_date(booking.check_in_date) == 35

    assert Meals.PortionCounts.for_range(
             [Bookings.get_booking!(booking.id)],
             booking.check_in_date,
             booking.check_out_date
           ) == meals

    assert length(Bookings.list_bookings_for_calendar()) == 1
    assert Repo.aggregate(CozyCheckout.Bookings.Booking, :count) == 1
    assert Repo.aggregate(CozyCheckout.Bookings.BookingRoom, :count) == 0
  end

  test "new payers inherit stored prices, clear identity and omit shared extras", %{
    booking: booking,
    season: season
  } do
    {:ok, _} =
      Billing.save_item(booking.id, %{
        "name" => "Služba skupině",
        "item_type" => "extra",
        "quantity" => "1",
        "nights" => "1",
        "price_per_night" => "500",
        "vat_rate" => "21"
      })

    {:ok, _} = Billing.save_season(%{adult: "9999", infant: "1", child: "2"}, season.id)
    payer = payer!(booking)
    assert Billing.customer(payer).data["name"] == "Rodina Novákova"

    refute Billing.customer(payer).data["company_id"] ==
             Billing.customer(booking.id).data["company_id"]

    invoice = Billing.calculation(payer)
    assert length(invoice.items) == 4
    fee = Enum.find(invoice.items, &(&1.name == "Rekreační poplatek"))
    assert fee.quantity == 0
    assert fee.nights == 3
    assert Decimal.equal?(fee.price_per_night, "35")
    refute Enum.any?(invoice.items, &(&1.name == "Služba skupině"))
    assert Decimal.equal?(hd(invoice.items).price_per_night, "950")
    assert Decimal.equal?(invoice.total_price, "2850")
    assert Billing.list_payments(payer) == []
    assert Billing.list_documents(%{"billing_account_id" => payer.id}) == []
  end

  test "each payer has its own advances, deductions and final; issuing one leaves the other open",
       %{booking: booking} do
    first = Billing.account(booking.id)
    second = payer!(booking)
    p1 = receive!(first, "1000", Date.add(Billing.today(), -15))
    p2 = receive!(second, "1000", Date.add(Billing.today(), -15))
    doc1 = issue_for!(first)
    assert {:ok, _} = Billing.preview(second, "advance")
    receive!(second, "500", Date.add(Billing.today(), -14))
    doc2 = issue_for!(second)

    assert Enum.map(doc1.snapshot["deductions"], & &1["source_document_id"]) == [
             p1.tax_document_id
           ]

    sources = Enum.map(doc2.snapshot["deductions"], & &1["source_document_id"])
    assert p2.tax_document_id in sources
    refute p1.tax_document_id in sources
    assert Decimal.equal?(Billing.balance(first).outstanding, "4700")
    assert Decimal.equal?(Billing.balance(second).outstanding, "1350")
    assert doc1.variable_symbol != doc2.variable_symbol
    assert {:error, _} = Billing.preview(first, "final")
    assert {:error, _} = Billing.preview(second, "final")
  end

  test "overpayment never masks another family's overdue debt", %{booking: booking} do
    first = Billing.account(booking.id)
    second = payer!(booking)
    issue_for!(first)
    issue_for!(second, %{"due_on" => to_string(Date.add(Billing.today(), -1))})
    receive!(first, "8550", Billing.today())
    Billing.complete_allocation(booking.id)

    assert %{payment_state: "unpaid", overdue: true, final_count: 2, paid_count: 0} =
             summary(booking)

    assert Decimal.equal?(summary(booking).outstanding, "0")
    assert {:ok, {[], _}} = Bookings.list_bookings_with_flop(%{"invoice_state" => "paid"})

    assert {:ok, {[row], meta}} =
             Bookings.list_bookings_with_flop(%{"invoice_state" => "overdue"})

    assert row.id == booking.id
    assert meta.total_count == 1
  end

  test "paid documents do not complete an unfinished split; allocation edits reopen it", %{
    booking: booking
  } do
    first = Billing.account(booking.id)
    second = payer!(booking)
    issue_for!(first)
    issue_for!(second)
    receive!(first, "5700", Billing.today())
    receive!(second, "2850", Billing.today())
    assert %{payment_state: "unpaid", paid_count: 2} = summary(booking)
    assert {:ok, _} = Billing.complete_allocation(booking.id)
    assert %{payment_state: "paid", paid_count: 2} = summary(booking)
    item = hd(Billing.calculation(second).items)
    assert {:ok, _} = Billing.save_item(second, %{"quantity" => "2"}, item.id)
    assert is_nil(Bookings.get_booking!(booking.id).allocation_completed_at)
    assert %{payment_state: "unpaid", paid_count: 2} = summary(booking)
    assert Decimal.equal?(Billing.balance(second).outstanding, 0)
  end

  test "count mismatch permits explicit completion, but adding or removing a draft reopens it", %{
    booking: booking
  } do
    second = payer!(booking, %{"children" => "3"})
    assert {:ok, _} = Billing.complete_allocation(booking.id)
    assert Bookings.get_booking!(booking.id).allocation_completed_at
    assert {:ok, _} = Billing.delete_account(booking.id, second.id)
    assert is_nil(Bookings.get_booking!(booking.id).allocation_completed_at)
    assert Repo.get!(Account, second.id).deleted_at
    assert {:ok, _} = Billing.complete_allocation(booking.id)
    payer!(booking)
    assert is_nil(Bookings.get_booking!(booking.id).allocation_completed_at)
  end

  test "payer dates and calculation changes never rewrite the common stay or issued snapshot", %{
    booking: booking
  } do
    second = payer!(booking, %{"check_in_date" => to_string(Date.add(booking.check_in_date, 1))})
    doc = issue_for!(second)
    assert hd(Billing.calculation(second).items).nights == 2
    assert doc.snapshot["check_in"] == to_string(Date.add(booking.check_in_date, 1))

    assert {:ok, _} =
             Billing.save_item(
               second,
               %{"price_per_night" => "500"},
               hd(Billing.calculation(second).items).id
             )

    assert Billing.get_document!(doc.id).snapshot == doc.snapshot
    assert Billing.get_document!(doc.id).lines == doc.lines
    assert Bookings.get_booking!(booking.id).check_in_date == booking.check_in_date
    assert Bookings.get_occupancy_for_date(booking.check_in_date) == 2
    assert {:error, _} = Billing.delete_account(booking.id, second.id)
  end

  test "foreign payment links and request reuse across payers are rejected", %{booking: booking} do
    first = Billing.account(booking.id)
    second = payer!(booking)
    doc1 = issue_for!(first)
    doc2 = issue_for!(second)
    request = Ecto.UUID.generate()

    attrs = %{
      "request_id" => request,
      "amount" => "100",
      "paid_on" => to_string(Billing.today()),
      "method" => "bank",
      "document_id" => doc1.id
    }

    assert {:error, _} = Billing.record_payment(second, attrs)
    assert {:ok, payment} = Billing.record_payment(first, attrs)
    assert {:ok, replayed} = Billing.record_payment(first, attrs)
    assert replayed.id == payment.id
    assert replayed.billing_account_id == payment.billing_account_id
    assert Decimal.equal?(replayed.amount, payment.amount)
    assert {:error, _} = Billing.record_payment(second, Map.put(attrs, "document_id", doc2.id))
    assert Repo.aggregate(Payment, :count) == 1
    forged = %{second | booking_id: Ecto.UUID.generate()}
    assert_raise Ecto.NoResultsError, fn -> Billing.account(forged) end
  end

  test "stale previews cannot issue after payer edits, and issued single stays cannot be split",
       %{booking: booking} do
    second = payer!(booking)
    {:ok, preview} = Billing.preview(second, "final")
    assert {:ok, _} = Billing.save_customer(second, %{"name" => "Změna"})

    assert {:error, _} =
             Billing.issue(
               second,
               "final",
               %{"preview_token" => preview.token},
               Ecto.UUID.generate()
             )

    assert Repo.aggregate(Document, :count) == 0
    assert {:ok, _} = Billing.delete_account(booking.id, second.id)
    issue!(booking, "final")

    assert {:error, _} =
             Billing.save_account(booking.id, %{"name" => "Pozdní rodina", "adults" => "1"})
  end

  test "database enforces owner and source-account links", %{booking: booking} do
    first = Billing.account(booking.id)
    second = payer!(booking)
    doc = issue_for!(first)

    assert_raise Postgrex.Error, fn ->
      Repo.transaction(fn ->
        Repo.query!(
          "INSERT INTO billing_payments (id, booking_id, billing_account_id, document_id, request_id, kind, amount, paid_on, method, inserted_at, updated_at) VALUES (gen_random_uuid(), $1, $2, $3, gen_random_uuid(), 'receipt', 100, CURRENT_DATE, 'bank', NOW(), NOW())",
          [Ecto.UUID.dump!(booking.id), Ecto.UUID.dump!(second.id), Ecto.UUID.dump!(doc.id)]
        )
      end)
    end
  end

  test "summaries and timeline preload query counts stay constant as payers and bookings grow", %{
    booking: booking
  } do
    {_, before_queries} =
      QueryRecorder.record(fn -> BookingSummary.for_bookings([booking.id]) end)

    for n <- 1..5, do: payer!(booking, %{"name" => "Rodina #{n}"})
    {_, after_queries} = QueryRecorder.record(fn -> BookingSummary.for_bookings([booking.id]) end)
    assert length(after_queries) == length(before_queries)

    {rows, _} =
      QueryRecorder.record(fn ->
        Bookings.list_bookings_for_date_range(booking.check_in_date, booking.check_out_date)
        |> Repo.preload([:rooms, invoice: :items], in_parallel: false)
      end)

    assert length(rows) == 1

    {_, one} =
      QueryRecorder.record(fn ->
        Bookings.list_bookings_for_date_range(booking.check_in_date, booking.check_out_date)
        |> Repo.preload([:rooms, invoice: :items], in_parallel: false)
      end)

    for n <- 1..3 do
      {:ok, _} =
        Bookings.create_booking(%{
          guest_id: booking.guest_id,
          adults: 2,
          check_in_date: Date.add(booking.check_in_date, n),
          check_out_date: booking.check_out_date
        })
    end

    {_, many} =
      QueryRecorder.record(fn ->
        Bookings.list_bookings_for_date_range(booking.check_in_date, booking.check_out_date)
        |> Repo.preload([:rooms, invoice: :items], in_parallel: false)
      end)

    assert length(many) == length(one)
  end

  test "unavailable rooms roll back booking dates and all room assignments", %{booking: booking} do
    {:ok, first_room} = CozyCheckout.Rooms.create_room(%{room_number: "101", capacity: 4})
    {:ok, occupied_room} = CozyCheckout.Rooms.create_room(%{room_number: "102", capacity: 4})
    {:ok, _} = Bookings.set_booking_rooms(booking.id, [first_room.id])
    {:ok, guest} = CozyCheckout.Guests.create_guest(%{name: "Jiná skupina"})

    {:ok, other} =
      Bookings.create_booking(%{
        guest_id: guest.id,
        check_in_date: Date.add(booking.check_in_date, 10),
        check_out_date: Date.add(booking.check_in_date, 15)
      })

    {:ok, _} = Bookings.set_booking_rooms(other.id, [occupied_room.id])

    assert {:error, {:rooms_not_available, _}} =
             Bookings.save_booking_with_rooms(
               booking,
               %{
                 check_in_date: other.check_in_date,
                 check_out_date: other.check_out_date,
                 adults: 35
               },
               [occupied_room.id]
             )

    unchanged = Bookings.get_booking!(booking.id)
    assert unchanged.check_in_date == booking.check_in_date
    assert unchanged.adults == booking.adults
    assert Enum.map(Bookings.list_booking_rooms(booking.id), & &1.id) == [first_room.id]
    count = Repo.aggregate(CozyCheckout.Bookings.Booking, :count)

    assert {:error, {:rooms_not_available, _}} =
             Bookings.save_booking_with_rooms(
               %CozyCheckout.Bookings.Booking{},
               %{
                 guest_id: booking.guest_id,
                 check_in_date: other.check_in_date,
                 check_out_date: other.check_out_date
               },
               [occupied_room.id]
             )

    assert Repo.aggregate(CozyCheckout.Bookings.Booking, :count) == count
    assert Repo.aggregate(Account, :count) == count
  end

  test "later default-payer price exceptions do not change the stored group prices", %{
    booking: booking
  } do
    payer!(booking)
    item = hd(Billing.calculation(booking.id).items)
    {:ok, _} = Billing.save_item(booking.id, %{"price_per_night" => "500"}, item.id)
    next = payer!(booking, %{"name" => "Další rodina"})
    assert Decimal.equal?(hd(Billing.calculation(next).items).price_per_night, "950")
  end
end

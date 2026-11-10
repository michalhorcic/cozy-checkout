defmodule CozyCheckout.BillingManualDeliveryTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.Billing
  alias CozyCheckout.Billing.{Delivery, ManualDelivery}
  alias CozyCheckout.Bookings.CommunicationSummary

  setup do: billing_fixture()

  test "external sending is idempotent and leaves documents and email jobs unchanged", %{
    booking: booking
  } do
    document = issue!(booking, "final")
    jobs = Repo.aggregate(Oban.Job, :count)
    balance = Billing.balance(booking.id)
    key = Ecto.UUID.generate()
    attrs = %{"sent_on" => to_string(Date.add(Billing.today(), -1)), "note" => "Ekonomce školy"}

    assert {:ok, row} = Billing.record_manual_delivery(document.id, attrs, key)
    assert {:ok, same} = Billing.record_manual_delivery(document.id, attrs, key)
    assert row.id == same.id
    assert row.note == "Ekonomce školy"
    assert Repo.aggregate(ManualDelivery, :count) == 1
    assert Repo.aggregate(Delivery, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == jobs
    assert Billing.get_document!(document.id) == document
    assert Billing.balance(booking.id) == balance
    assert CommunicationSummary.for_bookings([booking.id])[booking.id].invoice_sent == 1

    email = %{
      "recipient" => "test@example.com",
      "subject" => "Faktura",
      "body" => "Příloha",
      "consent" => "true"
    }

    assert {:ok, queued} = Billing.enqueue_email(document.id, email, Ecto.UUID.generate())
    assert queued.state == "queued"
    assert {:ok, _} = Billing.cancel_manual_delivery(document.id, row.id)
    assert Repo.get!(Delivery, queued.id).state == "queued"
    assert CommunicationSummary.for_bookings([booking.id])[booking.id].invoice_sent == 0
    assert CommunicationSummary.for_bookings([booking.id])[booking.id].invoice_pending == 1
  end

  test "corrections preserve the original and reject stale edits without losing valid history", %{
    booking: booking
  } do
    document = issue!(booking, "final")
    original_date = Date.add(Billing.today(), -2)

    assert {:ok, original} =
             Billing.record_manual_delivery(
               document.id,
               %{"sent_on" => to_string(original_date), "note" => "Původní"},
               Ecto.UUID.generate()
             )

    assert {:error, %Ecto.Changeset{}} =
             Billing.record_manual_delivery(
               document.id,
               %{"sent_on" => ""},
               Ecto.UUID.generate(),
               original.id
             )

    assert is_nil(Repo.get!(ManualDelivery, original.id).voided_at)

    attrs = %{"sent_on" => to_string(Billing.today()), "note" => "Opravená poznámka"}
    key = Ecto.UUID.generate()
    assert {:ok, corrected} = Billing.record_manual_delivery(document.id, attrs, key, original.id)
    assert {:ok, same} = Billing.record_manual_delivery(document.id, attrs, key, original.id)
    assert same.id == corrected.id
    preserved = Repo.get!(ManualDelivery, original.id)
    assert preserved.note == "Původní"
    assert preserved.sent_on == original_date
    assert preserved.void_reason == "corrected"
    assert corrected.replaces_id == original.id

    assert {:error, _} =
             Billing.record_manual_delivery(document.id, attrs, Ecto.UUID.generate(), original.id)

    assert {:error, _} = Billing.cancel_manual_delivery(document.id, original.id)
    assert {:ok, cancelled} = Billing.cancel_manual_delivery(document.id, corrected.id)
    assert cancelled.void_reason == "cancelled"
    assert {:ok, _} = Billing.cancel_manual_delivery(document.id, corrected.id)
    assert length(Billing.list_manual_deliveries(document.id)) == 2
    assert Billing.manual_delivery_summaries([document]) == %{}
    assert CommunicationSummary.for_bookings([booking.id])[booking.id].invoice_sent == 0
  end

  test "validates dates and prevents changing a different document's records", %{booking: booking} do
    advance = issue!(booking, "advance")
    final = issue!(booking, "final")
    attrs = %{"sent_on" => to_string(Billing.today())}
    key = Ecto.UUID.generate()
    assert {:ok, row} = Billing.record_manual_delivery(advance.id, attrs, key)
    assert {:error, _} = Billing.record_manual_delivery(final.id, attrs, key)

    assert {:error, _} =
             Billing.record_manual_delivery(final.id, attrs, Ecto.UUID.generate(), row.id)

    assert {:error, _} = Billing.cancel_manual_delivery(final.id, row.id)
    assert {:error, _} = Billing.cancel_manual_delivery(final.id, "invalid")
    assert {:error, _} = Billing.record_manual_delivery(final.id, %{}, Ecto.UUID.generate())

    assert {:error, _} =
             Billing.record_manual_delivery(
               final.id,
               %{"sent_on" => "invalid"},
               Ecto.UUID.generate()
             )

    assert {:error, _} =
             Billing.record_manual_delivery(
               final.id,
               %{"sent_on" => to_string(Date.add(Billing.today(), 1))},
               Ecto.UUID.generate()
             )

    assert {:error, _} =
             Billing.record_manual_delivery(
               final.id,
               Map.put(attrs, "note", String.duplicate("x", 2001)),
               Ecto.UUID.generate()
             )

    assert Repo.aggregate(ManualDelivery, :count) == 1
    assert Billing.manual_delivery_summaries([advance, final]) == %{advance.id => Billing.today()}
  end
end

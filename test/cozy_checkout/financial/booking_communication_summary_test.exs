defmodule CozyCheckout.BookingCommunicationSummaryTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Bookings, Repo}
  alias CozyCheckout.Bookings.CommunicationSummary

  setup do: billing_fixture()

  defp summary(booking), do: CommunicationSummary.for_bookings([booking.id])[booking.id]

  defp invoice_email(document, state) do
    Repo.insert!(%CozyCheckout.Billing.Delivery{
      document_id: document.id,
      request_id: Ecto.UUID.generate(),
      recipient: "guest@example.com",
      subject: "Faktura",
      body: "V příloze",
      consented_at: DateTime.utc_now() |> DateTime.truncate(:second),
      state: state
    })
  end

  defp guest_email(booking, state, mode \\ "template", template \\ "cs_winter") do
    Repo.insert!(%CozyCheckout.GuestEmails.Delivery{
      booking_id: booking.id,
      batch_id: Ecto.UUID.generate(),
      recipient_email: "guest@example.com",
      booking_name: "Host",
      subject: "Uvítání",
      content_mode: mode,
      template_id: template,
      state: state
    })
  end

  test "counts documents, preserves prior acceptance and excludes tax receipts", %{
    booking: booking
  } do
    advance = issue!(booking, "advance")
    receipt = receipt!(booking, "500")
    final = issue!(booking, "final")
    invoice_email(Billing.get_document!(receipt.tax_document_id), "accepted")
    invoice_email(advance, "accepted")
    invoice_email(advance, "accepted")
    invoice_email(advance, "failed")
    invoice_email(final, "failed")

    assert %{invoice_count: 2, invoice_sent: 1, invoice_pending: 0, invoice_failed: 1} =
             summary(booking)

    invoice_email(final, "retrying")
    assert %{invoice_sent: 1, invoice_pending: 1, invoice_failed: 0} = summary(booking)
    invoice_email(final, "accepted")
    assert %{invoice_sent: 2, invoice_pending: 0, invoice_failed: 0} = summary(booking)
  end

  test "welcome only counts catalog templates, never custom messages", %{booking: booking} do
    assert %{welcome: :unsent} = summary(booking)
    guest_email(booking, "accepted", "custom", nil)
    guest_email(booking, "accepted", "template", "unrelated")
    assert %{welcome: :unsent} = summary(booking)
    guest_email(booking, "failed")
    assert %{welcome: :failed} = summary(booking)
    guest_email(booking, "queued")
    assert %{welcome: :pending} = summary(booking)
    guest_email(booking, "accepted", "template", "de_summer")
    guest_email(booking, "failed")
    assert %{welcome: :sent} = summary(booking)
  end

  test "bulk room lookup preserves room order, excludes deleted rooms and isolates reservations",
       %{booking: booking} do
    {:ok, other} =
      Bookings.create_booking(%{guest_id: booking.guest_id, check_in_date: Billing.today()})

    rooms =
      for number <- ["302", "301", "303"] do
        Repo.insert!(%CozyCheckout.Rooms.Room{room_number: number, capacity: 2})
      end

    for room <- rooms do
      Repo.insert!(%CozyCheckout.Bookings.BookingRoom{booking_id: booking.id, room_id: room.id})
    end

    List.last(rooms)
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update!()

    result = CozyCheckout.Rooms.rooms_for_bookings([booking.id, other.id])
    assert Enum.map(result[booking.id], & &1.room_number) == ["301", "302"]
    assert Map.get(result, other.id, []) == []
    assert CozyCheckout.Rooms.rooms_for_bookings([]) == %{}
  end

  test "bulk summaries do not leak between bookings and include empty histories", %{
    booking: booking
  } do
    {:ok, other} =
      Bookings.create_booking(%{guest_id: booking.guest_id, check_in_date: Billing.today()})

    guest_email(booking, "accepted")
    summaries = CommunicationSummary.for_bookings([booking.id, other.id])
    assert summaries[booking.id].welcome == :sent
    assert %{welcome: :unsent, invoice_count: 0, invoice_sent: 0} = summaries[other.id]
    assert CommunicationSummary.for_bookings([]) == %{}
  end
end

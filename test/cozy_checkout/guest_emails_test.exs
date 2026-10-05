defmodule CozyCheckout.GuestEmailsTest do
  use CozyCheckout.DataCase, async: false

  import Swoosh.TestAssertions

  alias CozyCheckout.Bookings
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.GuestEmails
  alias CozyCheckout.GuestEmails.TemplateCatalog
  alias CozyCheckout.Guests.Guest
  alias CozyCheckout.Repo
  alias CozyCheckout.Workers.BookingEmailWorker

  setup :set_swoosh_global

  test "catalog renders all four email-ready language and season variants" do
    assert length(TemplateCatalog.list()) == 4

    for template <- TemplateCatalog.list() do
      assert {:ok, rendered} = TemplateCatalog.render(template.id)
      assert rendered.html =~ "<!doctype html>"
      assert rendered.html =~ "<html lang=\"#{template.language}\">"
      assert rendered.html =~ "Jindřichův dům"
      refute rendered.html =~ "<script"
    end
  end

  test "unknown template ids are rejected" do
    assert {:error, :unknown_template} = TemplateCatalog.render("../outside")
  end

  test "booking email listing defaults to future arrivals and supports previous stays" do
    today = Date.utc_today()
    future_booking = insert_booking("Future Host", "future@example.com", Date.add(today, 3))

    past_booking =
      insert_booking("Past Host", "past@example.com", Date.add(today, -3), "completed")

    insert_booking("Cancelled Host", "cancelled@example.com", Date.add(today, 4), "cancelled")

    assert Enum.map(Bookings.list_bookings_for_email(), & &1.id) == [future_booking.id]
    assert Enum.map(Bookings.list_bookings_for_email(:past), & &1.id) == [past_booking.id]

    assert Enum.map(Bookings.list_bookings_for_email(:all), & &1.id) ==
             [past_booking.id, future_booking.id]
  end

  test "a batch snapshots the selected template for each recipient" do
    booking = insert_booking("Email Host", "host@example.com", Date.add(Date.utc_today(), 2))

    deliveries = [
      %{
        booking_id: booking.id,
        booking_name: booking.guest.name,
        recipient_email: "host@example.com"
      },
      %{
        booking_id: booking.id,
        booking_name: booking.guest.name,
        recipient_email: "partner@example.com"
      }
    ]

    assert {:ok, %{batch_id: batch_id, jobs: jobs}} =
             GuestEmails.enqueue_batch(
               "cs_summer",
               "Informace k pobytu",
               deliveries
             )

    assert length(jobs) == 2

    assert Enum.map(GuestEmails.list_batch_jobs(batch_id), & &1.args["recipient_email"]) ==
             ["host@example.com", "partner@example.com"]

    assert Enum.all?(jobs, &(&1.worker == inspect(BookingEmailWorker)))

    [queued_job | _] = GuestEmails.list_batch_jobs(batch_id)
    assert {:ok, template} = TemplateCatalog.render("cs_summer")
    assert queued_job.args["html_body"] == template.html
    assert queued_job.args["html_body"] =~ "V létě je možné"
    refute queued_job.args["html_body"] =~ "V zimním období"
    assert :ok = BookingEmailWorker.perform(queued_job)

    assert_email_sent(fn email ->
      email.subject == "Informace k pobytu" and email.html_body =~ "V létě je možné" and
        email.html_body =~ "Jindřichův dům"
    end)
  end

  test "custom text is snapshotted, escaped in HTML, and sent as plain text" do
    booking =
      insert_booking("Custom Email Host", "custom@example.com", Date.add(Date.utc_today(), 2))

    message = "Ahoj <script>alert('test')</script>\nDruhý řádek"

    assert {:ok, %{batch_id: batch_id}} =
             GuestEmails.enqueue_batch(
               %{type: :custom, body: message},
               "Vlastní zpráva",
               [
                 %{
                   booking_id: booking.id,
                   booking_name: booking.guest.name,
                   recipient_email: "custom@example.com"
                 }
               ]
             )

    [job] = GuestEmails.list_batch_jobs(batch_id)
    assert job.args["text_body"] == message
    assert job.args["html_body"] =~ "&lt;script&gt;"
    refute job.args["html_body"] =~ "<script>"

    assert :ok = BookingEmailWorker.perform(job)

    assert_email_sent(fn email ->
      email.subject == "Vlastní zpráva" and email.text_body == message and
        email.html_body =~ "&lt;script&gt;"
    end)
  end

  test "custom email content cannot be blank" do
    assert {:error, :empty_body} =
             TemplateCatalog.render_custom(" \n ")
  end

  test "invalid recipient addresses and unknown templates cannot be queued" do
    booking = insert_booking("No Email Host", nil, Date.add(Date.utc_today(), 2))

    assert {:error, :unknown_template} =
             GuestEmails.enqueue_batch("unknown", "Subject", [
               %{
                 booking_id: booking.id,
                 booking_name: booking.guest.name,
                 recipient_email: "ok@example.com"
               }
             ])

    assert {:error, :invalid_recipient} =
             GuestEmails.enqueue_batch("cs_winter", "Subject", [
               %{
                 booking_id: booking.id,
                 booking_name: booking.guest.name,
                 recipient_email: "not-an-email"
               }
             ])
  end

  defp insert_booking(name, email, check_in_date, status \\ "upcoming") do
    guest =
      %Guest{}
      |> Guest.changeset(%{name: name, email: email})
      |> Repo.insert!()

    %Booking{}
    |> Booking.changeset(%{
      guest_id: guest.id,
      check_in_date: check_in_date,
      check_out_date: Date.add(check_in_date, 1),
      status: status
    })
    |> Repo.insert!()
    |> Repo.preload(:guest)
  end
end

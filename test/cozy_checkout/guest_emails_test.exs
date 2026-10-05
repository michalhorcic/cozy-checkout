defmodule CozyCheckout.GuestEmailsTest do
  use CozyCheckout.DataCase, async: false

  import Swoosh.TestAssertions

  alias CozyCheckout.Bookings
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.GuestEmails
  alias CozyCheckout.GuestEmails.Delivery
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

  test "personalizes template subject and body and escapes guest data" do
    booking = insert_booking("<Host>", "host@example.com", ~D[2026-10-08])
    booking = %{booking | check_out_date: nil}

    assert {:ok, rendered} = TemplateCatalog.render("cs_winter", booking)
    assert rendered.subject =~ "08.10.2026"
    assert rendered.html =~ "Dobrý den, &lt;Host&gt;"
    assert rendered.html =~ "začíná <strong>08.10.2026</strong>"
    assert rendered.html =~ "končí <strong>bude upřesněno</strong>"
    refute rendered.html =~ "{{guest_name}}"

    assert {:ok, overridden} =
             TemplateCatalog.render(
               "cs_winter",
               booking,
               "Dobrý den, {{guest_name}}",
               "Petře Nováku"
             )

    assert overridden.subject == "Dobrý den, Petře Nováku"
    assert overridden.html =~ "Dobrý den, Petře Nováku"
  end

  test "German templates use the German missing check-out fallback" do
    booking = insert_booking("Gast", "gast@example.com", ~D[2026-10-08])
    booking = %{booking | check_out_date: nil}

    assert {:ok, rendered} = TemplateCatalog.render("de_summer", booking)
    assert rendered.subject =~ "08.10.2026"
    assert rendered.html =~ "wird noch bekannt gegeben"
  end

  test "each booking in a batch gets its own personalized snapshot" do
    first = insert_booking("First Guest", "first@example.com", ~D[2026-10-08])
    second = insert_booking("Second Guest", "second@example.com", ~D[2026-11-09])
    {:ok, template} = TemplateCatalog.fetch("cs_summer")

    assert {:ok, %{batch_id: batch_id}} =
             GuestEmails.enqueue_batch(
               %{type: :template, template_id: "cs_summer"},
               template.subject,
               [
                 %{
                   booking_id: first.id,
                   booking_name: first.guest.name,
                   greeting_name: "První hoste",
                   recipient_email: first.guest.email
                 },
                 %{
                   booking_id: second.id,
                   booking_name: second.guest.name,
                   recipient_email: second.guest.email
                 }
               ]
             )

    [first_job, second_job] =
      GuestEmails.list_batch_jobs(batch_id)
      |> Enum.sort_by(& &1.args["recipient_email"])

    assert first_job.args["html_body"] =~ "První hoste"
    assert first_job.args["html_body"] =~ "08.10.2026"
    assert first_job.args["subject"] =~ "08.10.2026"
    refute first_job.args["html_body"] =~ "Second Guest"

    assert second_job.args["html_body"] =~ "Second Guest"
    assert second_job.args["html_body"] =~ "09.11.2026"
    assert second_job.args["subject"] =~ "09.11.2026"
    refute second_job.args["html_body"] =~ "First Guest"
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
    assert {:ok, template} = TemplateCatalog.render("cs_summer", booking, "Informace k pobytu")
    assert queued_job.args["html_body"] == template.html
    assert queued_job.args["html_body"] =~ "V létě je možné"
    refute queued_job.args["html_body"] =~ "V zimním období"

    queued_delivery =
      Enum.find(
        GuestEmails.list_booking_deliveries(booking.id),
        &(&1.recipient_email == "partner@example.com")
      )

    assert queued_delivery.state == "queued"
    assert queued_delivery.subject == "Informace k pobytu"
    refute Map.has_key?(queued_delivery, :html_body)
    assert :ok = BookingEmailWorker.perform(queued_job)

    assert_email_sent(fn email ->
      email.subject == "Informace k pobytu" and email.html_body =~ "V létě je možné" and
        email.html_body =~ "Email Host" and email.html_body =~ "Jindřichův dům" and
        email.reply_to == {"", "jindrichuvdum@jindrichuvdum.cz"}
    end)

    accepted_delivery =
      Enum.find(
        GuestEmails.list_booking_deliveries(booking.id),
        &(&1.recipient_email == "host@example.com")
      )

    assert accepted_delivery.state == "accepted"
    assert accepted_delivery.accepted_at

    Repo.get!(Oban.Job, queued_delivery.oban_job_id) |> Repo.delete!()
    assert Repo.get!(Delivery, queued_delivery.id).oban_job_id == nil
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
    [delivery] = GuestEmails.list_booking_deliveries(booking.id)
    assert delivery.content_mode == "custom"
    assert delivery.template_id == nil

    assert :ok = BookingEmailWorker.perform(job)

    assert GuestEmails.list_booking_deliveries(booking.id) |> hd() |> Map.fetch!(:state) ==
             "accepted"

    assert_email_sent(fn email ->
      email.subject == "Vlastní zpráva" and email.text_body == message and
        email.html_body =~ "&lt;script&gt;"
    end)
  end

  test "delivery lifecycle records transient retry and final failure" do
    booking = insert_booking("Retry Host", "retry@example.com", Date.add(Date.utc_today(), 2))

    assert {:ok, %{batch_id: batch_id}} =
             GuestEmails.enqueue_batch("cs_winter", "Retry", [
               %{
                 booking_id: booking.id,
                 booking_name: booking.guest.name,
                 recipient_email: "retry@example.com"
               }
             ])

    [job] = GuestEmails.list_batch_jobs(batch_id)
    [delivery] = GuestEmails.list_booking_deliveries(booking.id)

    assert :ok = GuestEmails.mark_sending(delivery.id, 1)
    assert :ok = GuestEmails.mark_retrying(delivery.id, :temporary_failure)

    assert %{state: "retrying", attempt_count: 1, last_error: error} =
             Repo.get!(Delivery, delivery.id)

    assert error != ""

    assert :ok = GuestEmails.mark_sending(delivery.id, 2)
    assert :ok = GuestEmails.mark_failed(delivery.id, {422, :invalid_recipient})

    assert %{
             state: "failed",
             attempt_count: 2,
             last_error: "Poskytovatel odmítl email (HTTP 422)"
           } = Repo.get!(Delivery, delivery.id)

    Repo.delete!(job)
  end

  test "email history survives deletion of its booking and Oban job" do
    booking = insert_booking("Retained Guest", "retained@example.com", ~D[2026-10-08])

    assert {:ok, %{batch_id: batch_id}} =
             GuestEmails.enqueue_batch("cs_winter", "History", [
               %{
                 booking_id: booking.id,
                 booking_name: booking.guest.name,
                 recipient_email: "retained@example.com"
               }
             ])

    [job] = GuestEmails.list_batch_jobs(batch_id)
    [delivery] = GuestEmails.list_booking_deliveries(booking.id)
    Repo.delete!(job)
    Repo.delete!(booking)

    retained = Repo.get!(Delivery, delivery.id)
    assert retained.booking_id == nil
    assert retained.oban_job_id == nil
    assert retained.recipient_email == "retained@example.com"
    assert retained.subject == "History"
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

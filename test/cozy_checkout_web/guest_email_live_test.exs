defmodule CozyCheckoutWeb.GuestEmailLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Guests.Guest
  alias CozyCheckout.Repo
  alias CozyCheckoutWeb.AdminAuth

  setup %{conn: conn} do
    previous_hash = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    on_exit(fn ->
      if previous_hash do
        Application.put_env(:cozy_checkout, :admin_pin_hash, previous_hash)
      else
        Application.delete_env(:cozy_checkout, :admin_pin_hash)
      end
    end)

    authenticated_conn =
      Plug.Test.init_test_session(conn, %{
        AdminAuth.session_key() => System.system_time(:second)
      })

    {:ok, conn: authenticated_conn}
  end

  test "defaults to future bookings and provides past-booking search", %{conn: conn} do
    today = Date.utc_today()
    upcoming = insert_booking("Upcoming Guest", "upcoming@example.com", Date.add(today, 2))

    previous =
      insert_booking("Previous Guest", "previous@example.com", Date.add(today, -2), "completed")

    {:ok, view, _html} = live(conn, "/admin/emails")

    assert has_element?(view, "#bookings-#{upcoming.id}")
    refute has_element?(view, "#bookings-#{previous.id}")
    assert has_element?(view, "#email-template")
    assert has_element?(view, "#email-subject")
    assert has_element?(view, "#email-template-preview")

    view
    |> element("#email-content-form")
    |> render_change(%{
      "email_content" => %{
        "mode" => "template",
        "template_id" => "cs_summer",
        "subject" => "Stávající předmět",
        "custom_body" => ""
      }
    })

    assert render(view) =~ "V létě je možné"
    refute render(view) =~ "V zimním období"
    assert render(view) =~ "Informace k pobytu od bude upřesněno"

    view
    |> element("#email-content-form")
    |> render_change(%{
      "email_content" => %{
        "mode" => "custom",
        "template_id" => "cs_summer",
        "subject" => "Vlastní předmět",
        "custom_body" => ""
      }
    })

    assert has_element?(view, "#email-custom-body")

    view
    |> element("#email-content-form")
    |> render_change(%{
      "email_content" => %{
        "mode" => "custom",
        "subject" => "Vlastní předmět",
        "custom_body" => "Ahoj <script>test</script>"
      }
    })

    assert render(view) =~ "Ahoj &lt;script&gt;test&lt;/script&gt;"
    assert render(view) =~ "Předmět: Vlastní předmět"
    assert has_element?(view, "#email-content-mode option[value=custom][selected]")

    view
    |> element("#booking-email-filters")
    |> render_change(%{"filters" => %{"period" => "past", "search" => "Previous"}})

    assert has_element?(view, "#bookings-#{previous.id}")
    refute has_element?(view, "#bookings-#{upcoming.id}")
  end

  test "shows bookings without an email and accepts a manual recipient", %{conn: conn} do
    booking = insert_booking("Manual Recipient Guest", nil, Date.add(Date.utc_today(), 1))

    {:ok, view, _html} = live(conn, "/admin/emails")

    assert has_element?(view, "#bookings-#{booking.id}")
    assert has_element?(view, "#extra-emails-#{booking.id}")
    assert has_element?(view, "#email-booking-#{booking.id}")

    view
    |> element("#extra-email-form-#{booking.id}")
    |> render_change(%{"emails" => "partner@example.com"})

    view
    |> element("#email-booking-#{booking.id}")
    |> render_click()

    assert render(view) =~ "1 adresát"

    view
    |> element("#email-content-form")
    |> render_change(%{
      "email_content" => %{
        "mode" => "custom",
        "template_id" => "cs_winter",
        "subject" => "Testovací zpráva",
        "custom_body" => "Vlastní text rezervace"
      }
    })

    view
    |> element("#queue-booking-emails")
    |> render_click()

    assert has_element?(view, "#current-email-batch")
    assert render(view) =~ "partner@example.com"
    assert render(view) =~ "Čeká ve frontě"
    assert render(view) =~ "alert-success"

    job =
      Repo.one!(
        from job in Oban.Job,
          where: fragment("? ->> 'recipient_email' = ?", job.args, "partner@example.com")
      )

    assert job.args["subject"] == "Testovací zpráva"
    assert job.args["text_body"] == "Vlastní text rezervace"
    assert job.args["html_body"] =~ "Vlastní text rezervace"
  end

  test "personalized preview defaults to the first selected booking and can switch", %{conn: conn} do
    first = insert_booking("První host", "first@example.com", ~D[2026-10-08])
    second = insert_booking("Druhý host", "second@example.com", ~D[2026-11-09])

    {:ok, view, _html} = live(conn, "/admin/emails")

    view
    |> element("#email-booking-#{first.id}")
    |> render_click()

    view
    |> element("#email-booking-#{second.id}")
    |> render_click()

    assert has_element?(view, "#email-preview-booking")
    assert has_element?(view, "#email-preview-booking option[value='#{first.id}'][selected]")

    view
    |> element("#email-content-form")
    |> render_change(%{
      "email_content" => %{
        "mode" => "template",
        "template_id" => "cs_winter",
        "preview_booking_id" => second.id,
        "subject" => "Příjezd {{check_in_date}}",
        "custom_body" => ""
      }
    })

    assert has_element?(view, "#email-preview-booking option[value='#{second.id}'][selected]")
    assert render(view) =~ "Druhý host"
    assert render(view) =~ "Předmět: Příjezd 09.11.2026"
    assert render(view) =~ "10.11.2026"
    assert has_element?(view, "#email-greeting-name")

    view
    |> element("#email-greeting-form")
    |> render_change(%{"greeting" => %{"booking_id" => second.id, "name" => "Petře Nováku"}})

    assert render(view) =~ "Dobrý den, Petře Nováku"
    assert has_element?(view, "#email-greeting-name[value='Petře Nováku']")

    view
    |> element("#queue-booking-emails")
    |> render_click()

    job =
      Repo.one!(
        from job in Oban.Job,
          where: fragment("? ->> 'recipient_email' = ?", job.args, "second@example.com")
      )

    assert job.args["html_body"] =~ "Dobrý den, Petře Nováku"
    assert job.args["html_body"] =~ "09.11.2026"
  end

  test "booking details show the durable recipient-level email history", %{conn: conn} do
    booking = insert_booking("History Host", "history@example.com", Date.add(Date.utc_today(), 3))

    assert {:ok, _batch} =
             CozyCheckout.GuestEmails.enqueue_batch("cs_summer", "Pobyt", [
               %{
                 booking_id: booking.id,
                 booking_name: "History Host",
                 recipient_email: "history@example.com"
               }
             ])

    delivery =
      Repo.one!(
        from delivery in CozyCheckout.GuestEmails.Delivery,
          where: delivery.booking_id == ^booking.id
      )

    {:ok, view, _html} = live(conn, "/admin/bookings/#{booking.id}")

    assert has_element?(view, "#booking-email-history")
    assert has_element?(view, "#booking-email-delivery-#{delivery.id}")
    assert render(view) =~ "history@example.com"
    assert render(view) =~ "Pobyt"
    assert render(view) =~ "Queued"
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
  end
end

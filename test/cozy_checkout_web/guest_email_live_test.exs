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
    assert render(view) =~ "Informace k vašemu letnímu pobytu"

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

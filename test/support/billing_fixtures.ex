defmodule CozyCheckout.BillingFixtures do
  alias CozyCheckout.{Billing, Repo}
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Guests.Guest

  def billing_fixture do
    today = Billing.today()

    guest =
      %Guest{}
      |> Guest.changeset(%{name: "Host fakturace", email: "#{Ecto.UUID.generate()}@example.com"})
      |> Repo.insert!()

    booking =
      %Booking{}
      |> Booking.changeset(%{
        guest_id: guest.id,
        check_in_date: Date.add(today, -10),
        check_out_date: Date.add(today, -7)
      })
      |> Repo.insert!()

    {:ok, _} = Billing.save_profile(supplier_attrs())

    {:ok, _} =
      Billing.save_customer(booking.id, %{
        "name" => "Základní škola",
        "street" => "Školní 1",
        "city" => "Praha",
        "postcode" => "11000",
        "country" => "CZ",
        "company_id" => "12345678",
        "email" => "school@example.com"
      })

    for {_, kind} <- Billing.kinds() do
      {:ok, _} =
        Billing.save_series(%{
          "kind" => kind,
          "year" => to_string(today.year),
          "prefix" =>
            if(kind == "advance",
              do: "COZY-ZF",
              else: kind |> String.upcase() |> String.replace("_", "")
            ),
          "digits" => "5",
          "next_number" => "1"
        })
    end

    {:ok, season} =
      Billing.save_season(%{
        name: "Zimní",
        valid_from: Date.add(today, -30),
        valid_to: Date.add(today, 30),
        adult: "950",
        infant: "210",
        child: "880",
        vat_rate: "12"
      })

    {:ok, invoice} = Billing.create_calculation(booking.id)
    %{booking: booking, season: season, invoice: invoice}
  end

  def supplier_attrs do
    %{
      "name" => "Moruška s.r.o.",
      "street" => "Skutečné sídlo 1",
      "city" => "Praha",
      "postcode" => "11000",
      "country" => "CZ",
      "company_id" => "23741457",
      "vat_id" => "CZ23741457",
      "registry" => "Městský soud, C 123",
      "email" => "billing@example.com",
      "phone" => "+420123456789",
      "bank_account" => "123456789/0100",
      "iban" => "",
      "due_days" => "14"
    }
  end

  def issue!(booking, kind, attrs \\ %{}) do
    {:ok, preview} = Billing.preview(booking.id, kind, attrs)

    {:ok, doc} =
      Billing.issue(
        booking.id,
        kind,
        Map.put(attrs, "preview_token", preview.token),
        Ecto.UUID.generate()
      )

    doc
  end

  def receipt!(booking, amount, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          "request_id" => Ecto.UUID.generate(),
          "kind" => "receipt",
          "amount" => amount,
          "paid_on" => to_string(Date.add(Billing.today(), -15)),
          "method" => "bank"
        },
        overrides
      )

    {:ok, payment} = Billing.record_payment(booking.id, attrs)
    payment
  end
end

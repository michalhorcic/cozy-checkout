defmodule CozyCheckout.BookingBillingTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Bookings}
  alias CozyCheckout.Billing.{Document, Money, Payment, Series}

  setup do
    billing_fixture()
  end

  test "season boundaries, overlapping seasons and saved prices", %{
    booking: booking,
    season: season
  } do
    assert Billing.season_on(season.valid_from).id == season.id
    assert Billing.season_on(season.valid_to).id == season.id
    assert is_nil(Billing.season_on(Date.add(season.valid_from, -1)))

    assert {:error, cs} =
             Billing.save_season(%{
               name: "Overlap",
               valid_from: season.valid_to,
               valid_to: Date.add(season.valid_to, 3),
               adult: "1000",
               infant: "200",
               child: "900",
               vat_rate: "12"
             })

    assert errors_on(cs).valid_from != []
    assert {:ok, _} = Billing.save_season(%{adult: "1000"}, season.id)
    assert hd(Billing.calculation(booking.id).items).price_per_night == Decimal.new("950.00")
    assert {:ok, invoice} = Billing.apply_pricing(booking.id)
    assert_amount(invoice.total_price, "6000")
    assert Bookings.get_occupancy_for_date(booking.check_in_date) == 2
  end

  test "a stay spanning two seasons uses arrival prices for every night", %{
    booking: booking,
    season: season
  } do
    assert {:ok, _} = Billing.save_season(%{valid_to: booking.check_in_date}, season.id)

    assert {:ok, _} =
             Billing.save_season(%{
               name: "Druhá",
               valid_from: Date.add(booking.check_in_date, 1),
               valid_to: Date.add(booking.check_out_date, 10),
               adult: "2000",
               infant: "0",
               child: "0",
               vat_rate: "12"
             })

    assert {:ok, invoice} = Billing.apply_pricing(booking.id)
    assert_amount(invoice.total_price, "5700")
  end

  test "missing prices are not replaced by hardcoded defaults", %{season: season} do
    Billing.delete_season(season.id)
    guest = Repo.insert!(%CozyCheckout.Guests.Guest{name: "Bez ceníku"})

    booking =
      Repo.insert!(%CozyCheckout.Bookings.Booking{
        guest_id: guest.id,
        check_in_date: Billing.today(),
        check_out_date: Date.add(Billing.today(), 3)
      })

    assert {:ok, invoice} = Billing.create_calculation(booking.id)
    assert Enum.all?(invoice.items, &is_nil(&1.price_per_night))
    assert invoice.total_price == nil
    assert {:error, _} = Billing.apply_pricing(booking.id)
  end

  test "two partial advances and final settlement retain VAT and occupancy", %{booking: booking} do
    advance = issue!(booking, "advance")
    assert_amount(advance.total, "2850")
    first = receipt!(booking, "1000", %{"document_id" => advance.id})
    second = receipt!(booking, "1850", %{"document_id" => advance.id})
    assert first.tax_document_id != second.tax_document_id
    final = issue!(booking, "final")
    assert_amount(final.total, "5700")
    deductions = final.snapshot["deductions"]
    assert_amount(Money.total(deductions), "-2850")
    assert_amount(Billing.balance(booking.id).outstanding, "2850")
    all_vat = (final.lines ++ deductions) |> Enum.map(&Money.value(&1, "vat")) |> Money.sum()
    assert_amount(all_vat, "305.36")
    assert Bookings.get_occupancy_for_date(booking.check_in_date) == 2
    receipt!(booking, "2850", %{"paid_on" => to_string(booking.check_out_date)})
    assert_amount(Billing.balance(booking.id).outstanding, "0")
    assert length(Billing.list_documents(%{"booking_id" => booking.id})) == 4
  end

  test "unpaid requests do not reduce the final and a final cannot be duplicated", %{
    booking: booking
  } do
    issue!(booking, "advance")
    final = issue!(booking, "final")
    assert final.snapshot["deductions"] == []
    assert_amount(Billing.balance(booking.id).outstanding, "5700")
    assert {:error, _} = Billing.preview(booking.id, "final")
  end

  test "idempotent issue and payment plus stale preview rejection", %{booking: booking} do
    {:ok, preview} = Billing.preview(booking.id, "advance")
    attrs = %{"preview_token" => preview.token}
    key = Ecto.UUID.generate()
    assert {:ok, doc} = Billing.issue(booking.id, "advance", attrs, key)
    assert {:ok, same} = Billing.issue(booking.id, "advance", attrs, key)
    assert doc.id == same.id
    payment = receipt!(booking, "1000")

    assert {:ok, same_payment} =
             Billing.record_payment(booking.id, %{"request_id" => payment.request_id})

    assert payment.id == same_payment.id
    {:ok, final_preview} = Billing.preview(booking.id, "final")
    receipt!(booking, "100")

    assert {:error, message} =
             Billing.issue(
               booking.id,
               "final",
               %{"preview_token" => final_preview.token},
               Ecto.UUID.generate()
             )

    assert message =~ "Podklady se změnily"
  end

  test "receipts without requests, overpayments, corrections and refunds", %{booking: booking} do
    payment = receipt!(booking, "6000")
    tax_doc = Billing.get_document!(payment.tax_document_id)
    assert_amount(tax_doc.total, "6000")

    assert {:error, _} =
             Billing.record_payment(booking.id, %{
               "request_id" => Ecto.UUID.generate(),
               "kind" => "refund",
               "amount" => "300",
               "paid_on" => to_string(Billing.today()),
               "method" => "bank"
             })

    final = issue!(booking, "final")
    assert_amount(Billing.balance(booking.id).outstanding, "-300")

    assert {:ok, _} =
             Billing.record_payment(booking.id, %{
               "request_id" => Ecto.UUID.generate(),
               "kind" => "refund",
               "amount" => "300",
               "paid_on" => to_string(Billing.today()),
               "method" => "bank"
             })

    assert {:ok, credit} =
             Billing.correct(
               final.id,
               %{"amount" => "5700", "reason" => "Zrušení"},
               Ecto.UUID.generate()
             )

    assert_amount(credit.total, "-5700")
    assert Billing.get_document!(final.id).lines == final.lines

    assert {:ok, _} =
             Billing.record_payment(booking.id, %{
               "request_id" => Ecto.UUID.generate(),
               "kind" => "refund",
               "amount" => "5700",
               "paid_on" => to_string(Billing.today()),
               "method" => "bank"
             })

    assert_amount(Billing.balance(booking.id).outstanding, "0")
  end

  test "advance corrections preserve original rounded VAT on full reversal", %{booking: booking} do
    payment = receipt!(booking, "2850")
    doc = Billing.get_document!(payment.tax_document_id)

    {:ok, _} =
      Billing.correct(doc.id, %{"amount" => "1000", "reason" => "Změna"}, Ecto.UUID.generate())

    {:ok, _} =
      Billing.correct(doc.id, %{"amount" => "1850", "reason" => "Zrušení"}, Ecto.UUID.generate())

    assert_amount(Billing.adjusted_total(doc), "0")
    assert_amount(Money.sum(Enum.map(Billing.adjusted_lines(doc), &Money.value(&1, "vat"))), "0")

    assert {:ok, _} =
             Billing.record_payment(booking.id, %{
               "request_id" => Ecto.UUID.generate(),
               "kind" => "refund",
               "amount" => "2850",
               "paid_on" => to_string(Billing.today()),
               "method" => "bank"
             })

    final = issue!(booking, "final")
    assert_amount(Money.total(final.snapshot["deductions"]), "0")
  end

  test "positive correction increases the amount owed", %{booking: booking} do
    final = issue!(booking, "final")

    assert {:ok, debit} =
             Billing.correct(
               final.id,
               %{"direction" => "increase", "amount" => "500", "reason" => "Další služba"},
               Ecto.UUID.generate()
             )

    assert_amount(debit.total, "500")
    assert_amount(Billing.balance(booking.id).outstanding, "6200")
  end

  test "outside VAT fee is separate from zero VAT and does not affect occupancy", %{
    booking: booking
  } do
    assert {:ok, _} =
             Billing.save_item(booking.id, %{
               "name" => "Poplatek z pobytu",
               "quantity" => "2",
               "nights" => "3",
               "price_per_night" => "50",
               "vat_rate" => "0",
               "tax_mode" => "outside",
               "item_type" => "extra"
             })

    final = issue!(booking, "final")
    assert_amount(final.total, "6000")
    fee = Enum.find(final.lines, &(&1["tax_mode"] == "outside"))
    assert_amount(Money.value(fee, "vat"), "0")
    assert Bookings.get_occupancy_for_date(booking.check_in_date) == 2
  end

  test "supplier, customer, pricing and issued documents have independent snapshots", %{
    booking: booking,
    invoice: invoice
  } do
    final = issue!(booking, "final")
    {:ok, _} = Billing.save_profile(Map.put(supplier_attrs(), "name", "Nový název"))
    item = hd(invoice.items)
    {:ok, _} = Billing.save_item(booking.id, %{"price_per_night" => "2000"}, item.id)
    assert Billing.get_document!(final.id).snapshot["supplier"]["name"] == "Moruška s.r.o."
    assert_amount(Billing.get_document!(final.id).total, "5700")
    assert {:error, _} = Billing.save_customer(booking.id, %{"name" => "Jiný odběratel"})
    assert {:error, _} = Billing.set_personal(booking.id)
  end

  test "old headers remain internal, preserve totals and never become documents or payments", %{
    booking: booking,
    invoice: invoice
  } do
    invoice
    |> change(pricing_basis: "legacy_net", invoice_number: "260800123", state: "paid")
    |> Repo.update!()

    assert Billing.list_documents(%{"booking_id" => booking.id}) == []
    assert Billing.list_payments(booking.id) == []
    assert_amount(Billing.balance(booking.id).received, "0")
    assert Billing.calculation(booking.id).invoice_number == "260800123"
    assert Repo.aggregate(Document, :count) == 0
    assert Repo.aggregate(Payment, :count) == 0
  end

  test "missing parties and series block issuance and do not consume numbers", %{booking: booking} do
    Repo.delete_all(Series)
    assert {:ok, preview} = Billing.preview(booking.id, "final")

    assert {:error, _} =
             Billing.issue(
               booking.id,
               "final",
               %{"preview_token" => preview.token},
               Ecto.UUID.generate()
             )

    assert Repo.aggregate(Document, :count) == 0
    Billing.save_profile(%{"name" => "Nedoplněný"})
    assert {:error, _} = Billing.preview(booking.id, "advance")
  end

  test "tiny advances across four tax groups never create a negative allocation" do
    lines = [
      Money.line("Ubytování", 1, 1, "1", "12"),
      Money.line("Služba", 1, 1, "1", "21"),
      Money.line("Nulová sazba", 1, 1, "1", "0"),
      Money.line("Mimo DPH", 1, 1, "1", "0", "outside")
    ]

    result = Money.allocate(lines, Decimal.new("0.02"))
    assert_amount(Money.total(result), "0.02")
    assert Enum.all?(result, &(Decimal.compare(Money.value(&1, "gross"), 0) != :lt))
    assert length(result) == 4
  end

  test "bank account and IBAN must agree and stale pricing needs another preview", %{
    booking: booking,
    season: season
  } do
    assert {:error, _} =
             Billing.save_profile(Map.put(supplier_attrs(), "iban", "CZ0000000000000000000000"))

    iban = Billing.profile().data["iban"]
    assert Regex.match?(~r/\ACZ\d{22}\z/, iban)

    qr =
      CozyCheckout.Payments.QrCode.generate_qr_data(%{
        account_number: supplier_attrs()["bank_account"],
        amount: Decimal.new(1),
        variable_symbol: "1"
      })

    assert qr =~ "ACC:#{iban}*"
    preview = Billing.pricing_preview(booking.id)
    assert {:ok, _} = Billing.save_season(%{adult: "1200"}, season.id)
    assert {:error, _} = Billing.apply_pricing(booking.id, preview.token)
    assert_amount(hd(Billing.calculation(booking.id).items).price_per_night, "950")
  end

  test "final tax date cannot precede an advance and invalid amounts do not record payments", %{
    booking: booking
  } do
    receipt!(booking, "1000", %{"paid_on" => to_string(Date.add(booking.check_out_date, -1))})

    assert {:error, _} =
             Billing.preview(booking.id, "final", %{
               "tax_date" => to_string(Date.add(booking.check_out_date, -2))
             })

    assert {:error, _} =
             Billing.record_payment(booking.id, %{
               "request_id" => Ecto.UUID.generate(),
               "kind" => "receipt",
               "amount" => "-1",
               "paid_on" => to_string(Billing.today()),
               "method" => "bank"
             })

    assert length(Billing.list_payments(booking.id)) == 1
  end

  test "copying a season and changing departure require explicit recalculation", %{
    booking: booking,
    season: season
  } do
    assert {:ok, copy} = Billing.copy_season(season.id)
    assert copy.valid_from.year == season.valid_from.year + 1
    assert_amount(copy.adult, "950")

    assert {:ok, updated} =
             Bookings.update_booking(booking, %{
               check_out_date: Date.add(booking.check_out_date, 2)
             })

    assert Billing.pricing_preview(booking.id).changed_nights
    assert hd(Billing.calculation(booking.id).items).nights == 3
    assert {:ok, invoice} = Billing.apply_pricing(updated.id)
    assert_amount(invoice.total_price, "9500")
    refute Billing.pricing_preview(booking.id).changed_nights
  end

  test "an overlong Czech account is rejected instead of being stored as an IBAN" do
    assert {:error, reason} =
             Billing.save_profile(
               supplier_attrs()
               |> Map.put("bank_account", "1234567890123/2010")
               |> Map.put("iban", "")
             )

    assert reason =~ "10 číslic"
  end

  defp assert_amount(actual, expected), do: assert(Decimal.equal?(actual, Decimal.new(expected)))
end

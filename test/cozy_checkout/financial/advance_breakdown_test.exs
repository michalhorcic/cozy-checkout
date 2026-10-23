defmodule CozyCheckout.AdvanceBreakdownTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  alias CozyCheckout.{Billing, Bookings}
  alias CozyCheckout.Billing.{Money, Pdf, Presentation}

  setup do
    %{booking: booking} = fixture = billing_fixture()

    for item <- Billing.calculation(booking.id).items do
      quantity =
        case item.name do
          "Děti do 2 let" -> "1"
          "Děti do 12 let" -> "3"
          _ -> "2"
        end

      assert {:ok, _} = Billing.save_item(booking.id, %{"quantity" => quantity}, item.id)
    end

    fixture
  end

  test "the advance snapshots the same adult and child breakdown as the final, before allocation",
       %{booking: booking} do
    assert {:ok, preview} = Billing.preview(booking.id, "advance", %{"percent" => "33.33"})
    calculation = Presentation.advance_breakdown(preview)
    assert calculation["method"] == "percent"
    assert calculation["percent"] == "33.33"
    assert Decimal.equal?(Money.decimal(calculation["stay_total"]), "14250")
    assert Decimal.equal?(preview.total, "4749.53")

    assert Presentation.advance_explanation(calculation) ==
             "33,33 % z 14 250,00 CZK = 4 749,53 CZK"

    assert {:ok, final} = Billing.preview(booking.id, "final")
    assert calculation["lines"] == final.lines

    assert Enum.map(calculation["lines"], & &1["name"]) |> Enum.sort() ==
             Enum.sort(["Dospělí", "Děti do 2 let", "Děti do 12 let"])

    assert Enum.all?(calculation["lines"], &(&1["nights"] == 3))
    assert Decimal.equal?(Money.total(preview.lines), preview.total)
    assert Bookings.get_occupancy_for_date(booking.check_in_date) == 6
  end

  test "an explicit amount takes precedence and does not claim to be percentage-based", %{
    booking: booking
  } do
    attrs = %{"amount" => "2000", "percent" => "invalid"}
    assert {:ok, preview} = Billing.preview(booking.id, "advance", attrs)
    calculation = Presentation.advance_breakdown(preview)
    assert calculation["method"] == "amount"
    assert is_nil(calculation["percent"])
    assert Presentation.advance_explanation(calculation) == "Záloha zadaná částkou: 2 000,00 CZK"
    assert Decimal.equal?(preview.total, "2000")

    assert {:ok, doc} =
             Billing.issue(
               booking.id,
               "advance",
               Map.put(attrs, "preview_token", preview.token),
               Ecto.UUID.generate()
             )

    assert Presentation.advance_breakdown(doc) == calculation
  end

  test "changes to guest counts invalidate a preview even when the total stays the same", %{
    booking: booking
  } do
    assert {:ok, preview} = Billing.preview(booking.id, "advance")
    adult = Enum.find(Billing.calculation(booking.id).items, &(&1.name == "Dospělí"))

    assert {:ok, _} =
             Billing.save_item(
               booking.id,
               %{"quantity" => "4", "price_per_night" => "475"},
               adult.id
             )

    assert {:ok, fresh} = Billing.preview(booking.id, "advance")
    assert Decimal.equal?(fresh.total, preview.total)
    assert fresh.token != preview.token

    assert {:error, _} =
             Billing.issue(
               booking.id,
               "advance",
               %{"preview_token" => preview.token},
               Ecto.UUID.generate()
             )
  end

  test "the saved breakdown and generated PDF remain independent of later calculation changes", %{
    booking: booking
  } do
    doc = issue!(booking, "advance", %{"percent" => "25"})
    original = Presentation.advance_breakdown(doc)
    assert {:ok, stored} = Billing.ensure_pdf(doc.id)
    pdf = stored.pdf
    assert pdf =~ "%PDF-"
    adult = Enum.find(Billing.calculation(booking.id).items, &(&1.name == "Dospělí"))

    assert {:ok, _} =
             Billing.save_item(
               booking.id,
               %{"quantity" => "9", "price_per_night" => "1200"},
               adult.id
             )

    saved = Billing.get_document!(doc.id)
    assert Presentation.advance_breakdown(saved) == original
    assert {:ok, regenerated} = Billing.ensure_pdf(doc.id)
    assert regenerated.pdf == pdf
    html = Pdf.html(saved)
    assert html =~ "Děti do 2 let"
    assert html =~ "Děti do 12 let"
    assert html =~ "950,00"
    assert html =~ "25,00 % z 14 250,00 CZK = 3 562,50 CZK"
    refute html =~ "<th>Základ"
    refute html =~ "<th>DPH"
    refute html =~ "Rekapitulace"
    refute html =~ "1 200,00"
  end

  test "old advances without a saved breakdown keep the generic historical presentation", %{
    booking: booking
  } do
    doc = issue!(booking, "advance")
    old_doc = %{doc | snapshot: Map.delete(doc.snapshot, "advance_calculation")}
    assert Presentation.advance_breakdown(old_doc) == nil
    html = Pdf.html(old_doc)
    assert html =~ "Záloha na pobyt a objednané služby"
    refute html =~ "Rozpis pobytu"
    refute html =~ "Výpočet zálohy"
  end

  test "gross units respect legacy net and outside-VAT lines without changing their totals" do
    legacy =
      Money.line(
        "Historická cena",
        2,
        3,
        Decimal.new("100"),
        Decimal.new("12"),
        "taxable",
        "legacy_net"
      )

    assert Decimal.equal?(Presentation.gross_unit_price(legacy), "112")
    assert Decimal.equal?(Money.value(legacy, "gross"), "672")

    outside =
      Money.line("Poplatek", 2, 3, Decimal.new("50"), Decimal.new("12"), "outside", "legacy_net")

    assert Decimal.equal?(Presentation.gross_unit_price(outside), "50")
  end

  test "ordered services retain their gross price and do not increase occupancy", %{
    booking: booking
  } do
    assert {:ok, _} =
             Billing.save_item(booking.id, %{
               "name" => "Další služba",
               "item_type" => "extra",
               "quantity" => "2",
               "nights" => "1",
               "price_per_night" => "100",
               "vat_rate" => "21"
             })

    assert {:ok, preview} = Billing.preview(booking.id, "advance")
    calculation = Presentation.advance_breakdown(preview)
    service = Enum.find(calculation["lines"], &(&1["name"] == "Další služba"))
    assert Decimal.equal?(Presentation.gross_unit_price(service), "100")
    assert Decimal.equal?(Money.value(service, "gross"), "200")
    assert Decimal.equal?(Money.decimal(calculation["stay_total"]), "14450")
    assert Decimal.equal?(preview.total, "7225")
    assert Decimal.equal?(Money.total(preview.lines), "7225")
    assert Bookings.get_occupancy_for_date(booking.check_in_date) == 6
  end

  test "changing from a percentage to an equal explicit amount requires a new preview", %{
    booking: booking
  } do
    assert {:ok, preview} = Billing.preview(booking.id, "advance", %{"percent" => "50"})
    attrs = %{"amount" => to_string(preview.total), "preview_token" => preview.token}
    assert {:error, _} = Billing.issue(booking.id, "advance", attrs, Ecto.UUID.generate())
    assert {:ok, fresh} = Billing.preview(booking.id, "advance", attrs)
    assert fresh.token != preview.token
    assert Presentation.advance_breakdown(fresh)["method"] == "amount"
  end
end

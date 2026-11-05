defmodule CozyCheckout.IncomingDocuments.TranscriptionTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.{Builder, Transcription, XML}

  defp source,
    do: "test/fixtures/incoming_documents/penny.json" |> File.read!() |> Jason.decode!()

  defp doc(agenda),
    do: %{agenda: agenda, template_xml: XML.template(agenda), external_id: "ext:test"}

  for agenda <- XML.agendas() do
    test "#{agenda}: Penny keeps all 21 source rows and matches the printed VAT summary" do
      doc = doc(unquote(agenda))
      assert {:ok, raw} = Builder.build(source(), doc)
      assert {:ok, xml} = XML.normalize(raw, doc.agenda, doc.template_xml, doc.external_id)
      assert {:ok, fields} = XML.parse(xml, doc.agenda)
      rows = XML.items(fields)
      assert length(rows) == 21
      assert fields["cisDosle"] == "0052-20261105-01-0039"
      assert fields["sumOsv"] == "0.00"
      assert fields["sumZklZakl"] == "0.00"
      assert fields["sumZklSniz"] == "1052.09"
      assert fields["sumDphSniz"] == "126.25"
      assert fields["sumCelkem"] == "1178.34"
      assert Enum.at(rows, 4)["mnozMj"] == "5"
      assert Enum.at(rows, 4)["cenaMj"] == "32.90"
      assert List.last(rows)["mnozMj"] == "12"
      assert Enum.count(rows, &(&1["nazev"] == "Chléb konzumní 1200 g")) == 2
      assert Enum.all?(rows, &(&1["typSzbDphK"] == "typSzbDph.dphSniz"))
      assert {:ok, [adjustment]} = XML.rounding_adjustments(xml, doc.agenda)
      assert Decimal.equal?(Decimal.new(adjustment["sumZkl"]), Decimal.new("0.01"))
      assert Decimal.equal?(Decimal.new(adjustment["sumDph"]), Decimal.new("-0.01"))
      assert adjustment["sumCelkem"] == "0.00"
      refute Map.has_key?(adjustment, "mnozMj")
      refute Map.has_key?(adjustment, "cenaMj")
      assert {:ok, payload} = XML.import_xml(xml, doc.agenda)
      assert {:ok, imported} = XML.parse(payload, doc.agenda)
      assert length(XML.items(imported)) == 22
      assert List.last(XML.items(imported))["typPolozkyK"] == "typPolozky.ucetni"
      refute Map.has_key?(imported, "sumCelkem")

      for {field, expected} <- [
            {"sumZkl", "1052.09"},
            {"sumDph", "126.25"},
            {"sumCelkem", "1178.34"}
          ] do
        actual =
          Enum.reduce(
            XML.items(imported),
            Decimal.new(0),
            &Decimal.add(Decimal.new(&1[field]), &2)
          )

        assert Decimal.equal?(actual, Decimal.new(expected))
      end
    end
  end

  test "strict source contract rejects missing keys, injected accounting fields and 201 rows" do
    assert :ok = Transcription.validate(source())
    assert {:error, _} = Transcription.validate(Map.delete(source(), "complete"))
    assert {:error, _} = Transcription.validate(Map.put(source(), "primUcet", "code:999999"))

    assert {:error, _} =
             Transcription.validate(
               Map.put(source(), "items", List.duplicate(hd(source()["items"]), 201))
             )
  end

  test "unknown legends, contradictory rates, payment numbers and missing rows fail closed" do
    original = source()

    for bad <- [
          Map.put(original, "vat_legend", []),
          Map.put(original, "items", [Map.put(hd(original["items"]), "vat_rate", "21")]),
          Map.put(original, "document_number_label", "PENNY KARTA"),
          Map.put(original, "items", [])
        ] do
      assert {:error, _, nil} = Builder.build(bad, doc("zavazek"))
    end
  end

  test "missing rows, large discrepancies and invented penny corrections cannot be normalized" do
    for data <- [
          Map.put(source(), "items", tl(source()["items"])),
          Map.put(source(), "total", "2602.90"),
          Map.put(source(), "vat_summary", [
            %{"rate" => "12", "net" => "1052.10", "vat" => "126.24", "gross" => nil}
          ])
        ] do
      doc = doc("zavazek")
      assert {:ok, raw} = Builder.build(data, doc)
      assert {:error, _} = XML.normalize(raw, doc.agenda, doc.template_xml, doc.external_id)
    end

    assert {:error, _, _} = Builder.build(Map.put(source(), "complete", false), doc("zavazek"))
  end
end

defmodule CozyCheckout.IncomingDocuments.TranscriptionTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.{Builder, Transcription, XML}

  defp source,
    do: "test/fixtures/incoming_documents/penny.json" |> File.read!() |> Jason.decode!()

  defp doc(agenda),
    do: %{agenda: agenda, template_xml: XML.template(agenda), external_id: "ext:test"}

  test "header-only contract excludes item fields and remains strict about required header data" do
    schema = Transcription.header_schema()
    header = Map.delete(source(), "items")
    refute Map.has_key?(schema["properties"], "items")
    refute "items" in schema["required"]
    assert :ok = Transcription.validate(header, schema)
    assert {:error, _} = Transcription.validate(source(), schema)
    assert {:error, _} = Transcription.validate(Map.delete(header, "document_number"), schema)
    assert {:error, _} = Transcription.validate(header)
    assert :ok = Transcription.validate(source())
  end

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

  test "O2 Czech numeric formatting is canonicalized without changing amounts" do
    data =
      source()
      |> Map.put("total", "1 803,34")
      |> Map.put("vat_summary", [
        %{"gross" => "1 803,34", "net" => "1 490,36", "rate" => "21", "vat" => "312,98"}
      ])

    row =
      hd(source()["items"])
      |> Map.merge(%{
        "unit_price" => "1 803,34",
        "line_total" => "1 803,34",
        "vat_marker" => nil,
        "vat_rate" => "21"
      })

    data = Map.put(data, "items", [row])
    assert Builder.summary_issues(data) == []
    assert {:ok, raw} = Builder.build(data, doc("faktura-prijata"))
    assert {:ok, fields} = XML.parse(raw, "faktura-prijata")
    assert fields["sumZklZakl"] == "1490.36"
    assert fields["sumDphZakl"] == "312.98"
    assert fields["sumCelkem"] == "1803.34"
    assert data["vat_summary"] |> hd() |> Map.fetch!("vat") == "312,98"

    for value <- ["1\u00a0803,34", "1\u202f803,34"] do
      assert Transcription.canonicalize(Map.put(data, "total", value))["total"] == "1803.34"
    end
  end

  test "missing VAT produces an exact field error but preserves a diagnostic XML draft" do
    data =
      put_in(source(), ["vat_summary"], [
        %{"rate" => "21", "net" => "1490,36", "vat" => nil, "gross" => "1803,34"}
      ])

    assert [%{path: "vat_summary.0.vat", message: message}] = Builder.summary_issues(data)
    assert message =~ "DPH"
    assert message =~ "nil"
    assert {:error, reason, raw} = Builder.build(data, doc("zavazek"))
    assert reason =~ "vat_summary.0.vat"
    assert is_binary(raw)
    assert {:ok, _} = XML.parse(raw, "zavazek")
    assert {:error, _} = XML.normalize(raw, "zavazek", doc("zavazek").template_xml, "ext:test")
  end

  test "numeric normalization does not change identifiers or guess ambiguous numbers" do
    data = source() |> Map.put("document_number", "000123") |> Map.put("total", "1,803.34")
    assert Transcription.canonicalize(data)["document_number"] == "000123"
    assert Transcription.canonicalize(data)["total"] == "1,803.34"
    assert Transcription.canonicalize(Map.put(data, "total", "1 80,34"))["total"] == "1 80,34"
  end

  test "O2 incomplete extraction strips CZK labels but never invents the missing service or a zero VAT rate" do
    data = File.read!("test/fixtures/incoming_documents/o2_incomplete.json") |> Jason.decode!()
    canonical = Transcription.canonicalize(data)
    assert canonical["total"] == "1902.34"
    assert hd(canonical["items"])["unit_price"] == "99.00"
    assert hd(canonical["vat_summary"])["vat"] == "312.98"
    assert canonical["document_number"] == data["document_number"]
    assert hd(canonical["items"])["raw_text"] == hd(data["items"])["raw_text"]
    issues = Builder.source_issues(data)
    assert Enum.any?(issues, &(&1.path == "items" and &1.message =~ "1803.34"))
    assert Enum.any?(issues, &(&1.path == "items.0.vat_rate"))
    assert Enum.any?(issues, &(&1.path == "items.0.price_includes_vat"))
    assert {:error, reason, raw} = Builder.build(data, doc("faktura-prijata"))
    assert reason =~ "1803.34"
    assert {:ok, fields} = XML.parse(raw, "faktura-prijata")
    assert length(XML.items(fields)) == 1
    assert hd(XML.items(fields))["cenaMj"] == "99.00"
    assert hd(XML.items(fields))["typSzbDphK"] == ""
    assert hd(XML.items(fields))["typCenyDphK"] == ""
    refute raw =~ ">99.00 Kč<"
  end

  test "currency labels are stripped only from money in the declared CZK currency" do
    for value <- ["99,00 Kč", "CZK 99.00", "99.00 CZK", "99,00\u00a0Kč"] do
      assert Transcription.canonicalize(Map.put(source(), "total", value))["total"] == "99.00"
    end

    assert Transcription.canonicalize(Map.put(source(), "total", "99.00 EUR"))["total"] ==
             "99.00 EUR"

    assert Transcription.canonicalize(Map.put(source(), "total", "99.00 Kč/kg"))["total"] ==
             "99.00 Kč/kg"

    data = source() |> Map.put("currency", "EUR") |> Map.put("total", "99 Kč")
    assert Transcription.canonicalize(data)["total"] == "99 Kč"
    data = put_in(source(), ["items", Access.at(0), "quantity"], "1 Kč")
    assert hd(Transcription.canonicalize(data)["items"])["quantity"] == "1 Kč"
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
      assert {:error, _, raw} = Builder.build(bad, doc("zavazek"))
      assert is_binary(raw)
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
      assert {:ok, raw} = Builder.draft(data, doc)
      assert {:error, _} = XML.normalize(raw, doc.agenda, doc.template_xml, doc.external_id)
    end

    assert {:error, _, _} = Builder.build(Map.put(source(), "complete", false), doc("zavazek"))
  end
end

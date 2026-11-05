defmodule CozyCheckout.IncomingDocuments.HeaderFormTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.{Document, HeaderForm, XML}

  defp doc(agenda),
    do: %Document{
      agenda: agenda,
      template_xml: XML.template(agenda),
      external_id: "ext:cozy-incoming:test"
    }

  defp attrs do
    %{
      "nazFirmy" => "Dodavatel & syn",
      "cisDosle" => "2026/42",
      "datVyst" => "2026-11-05",
      "datSplat" => "2026-11-19",
      "duzpPuv" => "2026-11-04",
      "duzpUcto" => "2026-11-05",
      "sumOsv" => "10,00",
      "sumZklSniz" => "100,00",
      "sumDphSniz" => "12,00",
      "sumZklZakl" => "1 000,00",
      "sumDphZakl" => "210,00",
      "sumCelkem" => "1 332,00",
      "poznam" => "Položka <orientační> & další"
    }
  end

  test "each agenda keeps its template and sends only header totals and a note" do
    for agenda <- XML.agendas() do
      document = doc(agenda)
      assert {:ok, values, xml} = HeaderForm.build(attrs(), document)
      assert values["sumCelkem"] == "1332.00"
      assert {:ok, fields} = XML.parse(xml, agenda)
      assert fields["bezPolozek"] == "true"
      assert fields["poznam"] == attrs()["poznam"]
      assert fields["nazFirmy"] == "Dodavatel & syn"
      assert fields["id"] == document.external_id
      assert XML.items(fields) == []
      assert {:ok, ^xml} = XML.import_xml(xml, agenda)
      assert {:ok, template} = XML.parse(document.template_xml, agenda)

      for key <- XML.fixed(),
          Map.has_key?(template, key),
          do: assert(fields[key] == template[key])

      refute xml =~ "polozkyDokladu"
    end
  end

  test "requires matching totals, original number, valid dates and invoice due date" do
    assert {:error, reason} = HeaderForm.build(Map.put(attrs(), "sumCelkem", "1"), doc("zavazek"))
    assert reason =~ "sumCelkem"

    assert {:error, _} =
             HeaderForm.build(Map.put(attrs(), "sumCelkem", "13 32,00"), doc("zavazek"))

    assert {:error, _} = HeaderForm.build(Map.put(attrs(), "cisDosle", ""), doc("zavazek"))

    assert {:error, _} =
             HeaderForm.build(Map.put(attrs(), "datVyst", "2026-13-99"), doc("zavazek"))

    assert {:error, _} =
             HeaderForm.build(Map.put(attrs(), "datSplat", ""), doc("faktura-prijata"))

    assert {:error, _} = HeaderForm.build(Map.put(attrs(), "duzpUcto", ""), doc("zavazek"))
    assert {:error, _} = HeaderForm.build(Map.put(attrs(), "duzpPuv", ""), doc("zavazek"))
  end

  test "model cannot set accounting fields or create invoice items" do
    for key <- ~w(typUcOp primUcet mena polozkyDokladu) do
      assert {:error, _} = HeaderForm.build(Map.put(attrs(), key, "injected"), doc("zavazek"))
    end
  end

  test "incomplete items and complete=false remain usable suggestions with text notes" do
    data = File.read!("test/fixtures/incoming_documents/penny.json") |> Jason.decode!()

    data = %{
      data
      | "complete" => false,
        "items" => Enum.take(data["items"], 1),
        "uncertainties" => ["Chybí položky"],
        "vat_summary" => [
          %{"rate" => "21.0", "net" => "100,00", "vat" => "21,00", "gross" => "121,00"}
        ]
    }

    suggestions = HeaderForm.suggestions(data)
    assert suggestions["sumZklZakl"] == "100.00"
    assert suggestions["sumDphZakl"] == "21.00"
    assert suggestions["poznam"] =~ "Orientační přepis"
    refute Map.has_key?(suggestions, "items")
  end

  test "reopening the form reflects later XML edits rather than an old saved form" do
    document = doc("zavazek")
    assert {:ok, _values, xml} = HeaderForm.build(attrs(), document)

    assert HeaderForm.values(%{document | current_xml: xml, edited_data: %{"header_form" => %{}}})[
             "cisDosle"
           ] == "2026/42"
  end
end

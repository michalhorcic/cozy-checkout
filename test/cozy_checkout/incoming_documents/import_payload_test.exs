defmodule CozyCheckout.IncomingDocuments.ImportPayloadTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.{Document, ImportPayload, XML}

  test "all agendas retain reviewed amounts, identity and notes in a native JSON envelope" do
    for agenda <- XML.agendas() do
      doc = %Document{agenda: agenda, external_id: "ext:cozy-incoming:test"}
      {:ok, fields} = XML.parse(XML.template(agenda), agenda)

      fields =
        Map.merge(fields, %{
          "nazFirmy" => "O2 & dodavatel",
          "cisDosle" => "2026/123",
          "datVyst" => "2026-11-05",
          "sumOsv" => "99.00",
          "sumZklZakl" => "1000.00",
          "sumDphZakl" => "210.00",
          "sumCelkem" => "1309.00",
          "poznam" => "Služby <21 %>\nSplátka bez DPH: 99 Kč"
        })

      xml = XML.render(fields, agenda, doc.external_id)
      assert {:ok, %{"winstrom" => envelope}} = ImportPayload.from_xml(xml, doc)
      assert Map.keys(envelope) == [agenda]
      assert [record] = envelope[agenda]
      assert record["@create"] == "ok"
      assert record["@update"] == "fail"
      assert record["id"] == doc.external_id
      assert record["bezPolozek"] === true
      assert record["ucetni"] === true
      assert record["poznam"] == fields["poznam"]
      assert record["nazFirmy"] == "O2 & dodavatel"

      for field <-
            ~w(sumOsv sumZklZakl sumDphZakl sumCelkem typDokl typUcOp primUcet protiUcet mena),
          do: assert(record[field] == fields[field])

      refute Map.has_key?(record, "polozkyDokladu")

      for field <- ~w(datSplat datUcto duzpUcto varSym iban),
          do: refute(Map.has_key?(record, field))

      assert Jason.decode!(Jason.encode!(%{"winstrom" => envelope}))["winstrom"][agenda] == [
               record
             ]
    end
  end

  test "false booleans and zero amounts are preserved while read-only exported fields are omitted" do
    doc = %Document{agenda: "zavazek", external_id: "ext:cozy-incoming:stable"}

    xml =
      XML.render(
        %{"bezPolozek" => "true", "ucetni" => "false", "sumOsv" => "0.00"},
        doc.agenda,
        "other-id"
      )
      |> String.replace("</zavazek>", "<lastUpdate>ignored</lastUpdate></zavazek>")

    assert {:ok, %{"winstrom" => %{"zavazek" => [record]}}} = ImportPayload.from_xml(xml, doc)
    assert record["ucetni"] === false
    assert record["sumOsv"] == "0.00"
    assert record["id"] == doc.external_id
    refute Map.has_key?(record, "lastUpdate")
  end

  test "legacy collections become JSON arrays without XML child wrappers or numeric conversions" do
    doc = %Document{agenda: "pokladni-pohyb", external_id: "ext:cozy-incoming:item"}

    row = %{
      "nazev" => "Položka",
      "mnozMj" => "2.5",
      "cenaMj" => "12.30",
      "typSzbDphK" => "typSzbDph.dphZakl"
    }

    xml = XML.render(%{"polozkyDokladu" => [row]}, doc.agenda, doc.external_id)

    assert {:ok, %{"winstrom" => %{"pokladni-pohyb" => [record]}}} =
             ImportPayload.from_xml(xml, doc)

    assert [item] = record["polozkyDokladu"]
    assert item["nazev"] == row["nazev"]
    assert item["mnozMj"] == "2.5"
    assert item["cenaMj"] == "12.30"
    assert record["bezPolozek"] === false
    refute Map.has_key?(item, "pokladni-pohyb-polozka")
  end

  test "rejects malformed XML and external entities before projection" do
    doc = %Document{agenda: "zavazek", external_id: "ext:cozy-incoming:test"}
    assert {:error, _} = ImportPayload.from_xml("<html>login</html>", doc)

    assert {:error, _} =
             ImportPayload.from_xml(
               "<!DOCTYPE winstrom [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><winstrom><zavazek><popis>&secret;</popis></zavazek></winstrom>",
               doc
             )
  end
end

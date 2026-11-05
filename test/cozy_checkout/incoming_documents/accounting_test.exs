defmodule CozyCheckout.IncomingDocuments.AccountingTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.{Accounting, XML}

  test "expense presets replace old food accounts; absent accounts are omitted, not inherited" do
    row = %{
      "kod" => "SLUZBY",
      "nazev" => "Telefon",
      "modulFap" => "true",
      "protiUcetVydej" => "code:518100"
    }

    assert {:ok, settings} = Accounting.select(row, "faktura-prijata", "FP1")

    doc = %{
      agenda: "faktura-prijata",
      template_xml: XML.template("faktura-prijata"),
      accounting_settings: settings
    }

    assert {:ok, template} = XML.parse(XML.template_for(doc), doc.agenda)
    assert template["typUcOp"] == "code:SLUZBY"
    assert template["protiUcet"] == "code:518100"
    refute Map.has_key?(template, "dphZaklUcet")
    assert template["primUcet"] == "code:321001"
    assert template["kod"] == "FP1"
    assert {:error, _} = Accounting.select(row, "zavazek", "")

    assert {:error, _} =
             Accounting.select(Map.put(row, "protiUcetVydej", "123"), "faktura-prijata", "")

    assert {:error, _} = Accounting.internal_code(String.duplicate("A", 21))
  end

  test "model-provided old code never overrides an explicitly selected internal code" do
    doc = %{
      agenda: "zavazek",
      template_xml: XML.template("zavazek"),
      accounting_settings: %{"kod" => "NEW"}
    }

    {:ok, fields} = XML.parse(XML.template_for(doc), doc.agenda)

    fields =
      Map.merge(fields, %{
        "kod" => "OLD",
        "nazFirmy" => "Dodavatel",
        "cisDosle" => "O2-001",
        "datVyst" => "2026-11-05",
        "sumZklZakl" => "100.00",
        "sumDphZakl" => "21.00",
        "sumCelkem" => "121.00"
      })

    assert {:ok, normalized} =
             XML.normalize(
               XML.render(fields, doc.agenda),
               doc.agenda,
               XML.template_for(doc),
               "ext:new"
             )

    assert normalized =~ "<kod>NEW</kod>"
    refute normalized =~ "<kod>OLD</kod>"
  end
end

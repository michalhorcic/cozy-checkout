defmodule CozyCheckout.IncomingDocuments.XMLTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.XML

  for agenda <- XML.agendas() do
    test "#{agenda}: sanitizes identity, preserves accounting defaults and edits exact XML" do
      agenda = unquote(agenda)
      template = XML.template(agenda)
      {:ok, fields} = XML.parse(template, agenda)

      fields =
        Map.merge(fields, %{
          "nazFirmy" => "Nový & syn",
          "cisDosle" => "2026-1",
          "datVyst" => "2026-11-05",
          "sumZklZakl" => "100.00",
          "sumDphZakl" => "21.00",
          "sumCelkem" => "121.00"
        })

      raw =
        XML.render(fields, agenda, "key:original")
        |> String.replace("<id>", "<kod>OLD</kod><datUhr>2026-01-01</datUhr><id>")

      assert {:ok, xml} = XML.normalize(raw, agenda, template, "ext:cozy-incoming:uuid")
      assert xml =~ "create=\"ok\" update=\"fail\""
      assert xml =~ "ext:cozy-incoming:uuid"
      refute xml =~ "key:original"
      refute xml =~ "<kod>"
      refute xml =~ "<datUhr>"
      assert xml =~ "Nový &amp; syn"

      assert {:ok, edited} =
               XML.edit(
                 xml,
                 %{"cisDosle" => "opraveno"},
                 agenda,
                 template,
                 "ext:cozy-incoming:uuid"
               )

      {:ok, edited_fields} = XML.parse(edited, agenda)
      assert edited_fields["cisDosle"] == "opraveno"
      assert edited_fields["typDokl"] == fields["typDokl"]
      assert {:error, _} = XML.edit(xml, %{"sumCelkem" => "120.99"}, agenda, template, "ext:test")

      assert {:error, _} =
               XML.edit(xml, %{"primUcet" => "code:999999"}, agenda, template, "ext:test")
    end
  end

  test "rejects DTD, entities, actions, attributes, nested records, duplicates and wrong agenda" do
    for xml <- [
          "<!DOCTYPE winstrom [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><winstrom><zavazek><popis>&x;</popis></zavazek></winstrom>",
          "<winstrom><zavazek><sparovani/></zavazek></winstrom>",
          "<winstrom><zavazek><nazFirmy if-not-found=\"create\">new</nazFirmy></zavazek></winstrom>",
          "<winstrom><zavazek><popis><id>42</id></popis></zavazek></winstrom>",
          "<winstrom><zavazek/><zavazek/></winstrom>",
          "<winstrom><zavazek><popis>a</popis><popis>b</popis></zavazek></winstrom>",
          "<winstrom><faktura-prijata/></winstrom>",
          "<winstrom xmlns=\"evil\"><zavazek/></winstrom>"
        ] do
      assert {:error, _} = XML.parse(xml, "zavazek")
    end

    assert {:error, _} = XML.parse(String.duplicate("x", 100_001), "zavazek")
  end

  test "rejects foreign currency, changed accounting, invalid dates and non-decimal amounts" do
    template = XML.template("zavazek")
    {:ok, fields} = XML.parse(template, "zavazek")

    fields =
      Map.merge(fields, %{
        "nazFirmy" => "Shop",
        "cisDosle" => "A",
        "datVyst" => "2026-11-05",
        "sumOsv" => "1.00",
        "sumCelkem" => "1.00"
      })

    for attrs <- [
          %{"mena" => "code:EUR"},
          %{"primUcet" => "code:999999"},
          %{"datVyst" => "2026-02-30"},
          %{"sumOsv" => "NaN"},
          %{"sumOsv" => "1e0"},
          %{"sumOsv" => "1.001"}
        ] do
      assert {:error, _} =
               XML.normalize(
                 XML.render(Map.merge(fields, attrs), "zavazek"),
                 "zavazek",
                 template,
                 "ext:test"
               )
    end
  end
end

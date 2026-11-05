defmodule CozyCheckout.IncomingDocuments.ItemsTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.XML

  defp document(agenda) do
    template = XML.template(agenda)
    {:ok, fields} = XML.parse(template, agenda)

    rows = [
      %{
        "nazev" => "Pečivo",
        "mnozMj" => "2",
        "cenaMj" => "28.00",
        "typCenyDphK" => "typCeny.sDph",
        "typSzbDphK" => "typSzbDph.dphSniz"
      },
      %{
        "nazev" => "Drogerie",
        "mnozMj" => "1",
        "cenaMj" => "121.00",
        "slevaPol" => "10",
        "typCenyDphK" => "typCeny.sDph",
        "typSzbDphK" => "typSzbDph.dphZakl"
      },
      %{
        "nazev" => "Vratný obal",
        "mnozMj" => "1",
        "cenaMj" => "3.00",
        "typCenyDphK" => "typCeny.sDph",
        "typSzbDphK" => "typSzbDph.dphOsv"
      }
    ]

    fields =
      Map.merge(fields, %{
        "nazFirmy" => "Obchod",
        "cisDosle" => "U-42",
        "datVyst" => "2026-11-05",
        "sumOsv" => "3.00",
        "sumZklSniz" => "50.00",
        "sumDphSniz" => "6.00",
        "sumZklZakl" => "90.00",
        "sumDphZakl" => "18.90",
        "sumCelkem" => "167.90",
        "polozkyDokladu" => rows
      })

    {fields, template}
  end

  for agenda <- XML.agendas() do
    test "#{agenda}: preserves every item, fixes header rates, and imports without header amounts" do
      agenda = unquote(agenda)
      {fields, template} = document(agenda)

      raw =
        fields
        |> Map.put("szbDphSniz", "6.00")
        |> Map.put("szbDphZakl", "18.90")
        |> XML.render(agenda, "key:wrong")

      assert {:ok, normalized} = XML.normalize(raw, agenda, template, "ext:test")
      assert {:ok, parsed} = XML.parse(normalized, agenda)
      assert parsed["bezPolozek"] == "false"
      assert parsed["szbDphSniz"] == "12.0"
      assert parsed["szbDphZakl"] == "21.0"
      assert Enum.map(XML.items(parsed), & &1["nazev"]) == ["Pečivo", "Drogerie", "Vratný obal"]
      assert Enum.at(XML.items(parsed), 1)["sumCelkem"] == "108.90"
      assert hd(XML.items(parsed))["slevaPol"] == "0"
      assert {:ok, imported} = XML.import_xml(normalized, agenda)
      assert {:ok, payload} = XML.parse(imported, agenda)
      refute Map.has_key?(payload, "sumCelkem")
      refute Map.has_key?(payload, "sumDphZakl")
      assert length(XML.items(payload)) == 3
      assert payload["id"] == "ext:test"
      refute imported =~ "key:wrong"
      assert {:ok, draft} = XML.restore_accounting(raw, agenda, template, "ext:test")
      assert {:ok, restored} = XML.normalize(draft, agenda, template, "ext:test")
      assert {:ok, restored} = XML.parse(restored, agenda)
      assert length(XML.items(restored)) == 3
    end
  end

  test "item edits recompute amounts and must agree with the reviewed receipt summary" do
    {fields, template} = document("zavazek")

    assert {:ok, xml} =
             XML.normalize(XML.render(fields, "zavazek"), "zavazek", template, "ext:test")

    {:ok, parsed} = XML.parse(xml, "zavazek")

    attrs =
      XML.items(parsed)
      |> Enum.with_index()
      |> Map.new(fn {row, i} -> {to_string(i), Map.take(row, XML.item_editable())} end)

    attrs = put_in(attrs, ["0", "mnozMj"], "3")
    assert {:error, reason} = XML.edit(xml, %{"items" => attrs}, "zavazek", template, "ext:test")
    assert reason =~ "sumCelkem"

    assert {:ok, corrected} =
             XML.edit(
               xml,
               %{
                 "items" => attrs,
                 "sumZklSniz" => "75.00",
                 "sumDphSniz" => "9.00",
                 "sumCelkem" => "195.90"
               },
               "zavazek",
               template,
               "ext:test"
             )

    {:ok, parsed} = XML.parse(corrected, "zavazek")
    assert hd(XML.items(parsed))["sumCelkem"] == "84.00"

    assert {:error, _} =
             XML.edit(xml, %{"items" => %{"99" => %{}}}, "zavazek", template, "ext:test")
  end

  test "rejects wrong item rate, row totals, unknown nested operations and foreign identities" do
    {fields, template} = document("zavazek")

    for {key, value, expected} <- [
          {"szbDph", "15", "szbDph"},
          {"sumCelkem", "99.00", "sumCelkem"},
          {"typSzbDphK", "", "typSzbDphK"},
          {"mnozMj", "0", "mnozMj"}
        ] do
      rows = List.update_at(XML.items(fields), 0, &Map.put(&1, key, value))

      assert {:error, reason} =
               XML.normalize(
                 XML.render(Map.put(fields, "polozkyDokladu", rows), "zavazek"),
                 "zavazek",
                 template,
                 "ext:test"
               )

      assert reason =~ "Položka 1"
      assert reason =~ expected
    end

    raw = XML.render(fields, "zavazek")

    for replacement <- [
          "<sparovani/>",
          "<cenik>code:stock</cenik>",
          "<firma if-not-found=\"create\">code:BAD</firma>"
        ] do
      assert {:error, _} =
               XML.parse(String.replace(raw, "<nazev>Pečivo</nazev>", replacement), "zavazek")
    end

    raw = String.replace(raw, "<nazev>Pečivo</nazev>", "<id>key:OLD</id><nazev>Pečivo</nazev>")
    assert {:ok, normalized} = XML.normalize(raw, "zavazek", template, "ext:test")
    refute normalized =~ "key:OLD"
  end

  test "net prices, weighted quantities, and explicit negative discounts use Decimal" do
    {fields, template} = document("zavazek")

    rows = [
      %{
        "nazev" => "Vážené zboží",
        "mnozMj" => "0.125",
        "cenaMj" => "800",
        "typCenyDphK" => "typCeny.bezDph",
        "typSzbDphK" => "typSzbDph.dphZakl"
      },
      %{
        "nazev" => "Sleva",
        "mnozMj" => "1",
        "cenaMj" => "-12.10",
        "typCenyDphK" => "typCeny.sDph",
        "typSzbDphK" => "typSzbDph.dphZakl"
      }
    ]

    fields =
      Map.merge(fields, %{
        "polozkyDokladu" => rows,
        "sumOsv" => "0.00",
        "sumZklSniz" => "0.00",
        "sumDphSniz" => "0.00",
        "sumZklZakl" => "90.00",
        "sumDphZakl" => "18.90",
        "sumCelkem" => "108.90"
      })

    assert {:ok, xml} =
             XML.normalize(XML.render(fields, "zavazek"), "zavazek", template, "ext:test")

    assert {:ok, parsed} = XML.parse(xml, "zavazek")
    assert hd(XML.items(parsed))["sumCelkem"] == "121.00"
    assert Enum.at(XML.items(parsed), 1)["sumCelkem"] == "-12.10"
  end

  test "limits item count, disallows duplicate wrappers and keeps old flat imports unchanged" do
    {fields, template} = document("zavazek")

    assert {:error, _} =
             XML.parse(
               :unicode.characters_to_binary(
                 "<winstrom><zavazek/></winstrom>",
                 :utf8,
                 {:utf16, :big}
               ),
               "zavazek"
             )

    rows = List.duplicate(hd(XML.items(fields)), 201)

    assert {:error, _} =
             XML.parse(XML.render(Map.put(fields, "polozkyDokladu", rows), "zavazek"), "zavazek")

    raw =
      XML.render(fields, "zavazek") |> String.replace("</zavazek>", "<polozkyDokladu/></zavazek>")

    assert {:error, _} = XML.parse(raw, "zavazek")
    flat = fields |> Map.delete("polozkyDokladu") |> XML.render("zavazek")
    assert {:ok, normalized} = XML.normalize(flat, "zavazek", template, "ext:test")
    assert {:ok, ^normalized} = XML.import_xml(normalized, "zavazek")
  end
end

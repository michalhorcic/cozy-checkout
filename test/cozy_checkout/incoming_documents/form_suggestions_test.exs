defmodule CozyCheckout.IncomingDocuments.FormSuggestionsTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.{Document, FormSuggestions, HeaderForm, XML}

  defp data(overrides \\ %{}) do
    "test/fixtures/incoming_documents/penny.json"
    |> File.read!()
    |> Jason.decode!()
    |> Map.merge(overrides)
  end

  defp row(rate, net, vat, gross),
    do: %{"rate" => rate, "net" => net, "vat" => vat, "gross" => gross}

  test "VAT rows prefill the correct fields including percent labels, comma decimals and no-VAT amounts" do
    result =
      FormSuggestions.from(
        data(%{
          "vat_summary" => [
            row("21,00 %", "1 000,00", "210,00", "1 210,00"),
            row("12 %", "100,00", "12,00", "112,00"),
            row("0 %", nil, nil, "99,00")
          ]
        })
      )

    assert result.vat == %{
             "sumZklZakl" => "1000.00",
             "sumDphZakl" => "210.00",
             "sumZklSniz" => "100.00",
             "sumDphSniz" => "12.00",
             "sumOsv" => "99.00"
           }

    assert result.messages == []
  end

  test "multiple rows of the same rate are summed once and no tax is recalculated from the rate" do
    result =
      FormSuggestions.from(
        data(%{
          "vat_summary" => [
            row("21", "10.00", "2.11", "12.11"),
            row("21.0 %", "20.00", "4.19", "24.19")
          ]
        })
      )

    assert result.vat["sumZklZakl"] == "30.00"
    assert result.vat["sumDphZakl"] == "6.30"
    assert result.messages == []
  end

  test "a missing component can be obtained from the other two source amounts" do
    result =
      FormSuggestions.from(
        data(%{
          "vat_summary" => [row("21", nil, "21.00", "121.00"), row("12", "100.00", nil, "112.00")]
        })
      )

    assert result.vat["sumZklZakl"] == "100.00"
    assert result.vat["sumDphSniz"] == "12.00"
  end

  test "unsupported, incomplete and conflicting rows are visible instead of silently mapped" do
    result =
      FormSuggestions.from(
        data(%{
          "vat_summary" => [
            row("15 %", "100.00", "15.00", "115.00"),
            row("21 %", "100.00", "21.00", "999.00"),
            row("12 %", nil, nil, "112.00")
          ]
        })
      )

    assert result.vat == %{}
    assert length(result.messages) == 3

    assert FormSuggestions.from(data(%{"vat_summary" => [row("0", "99.00", "1.00", "100.00")]})).vat ==
             %{}
  end

  test "Czech source dates become ISO and missing accounting dates receive reviewable defaults" do
    result =
      FormSuggestions.from(
        data(%{
          "issue_date" => "5. 11. 2026",
          "tax_date" => "31.10.2026",
          "due_date" => "19. 11. 2026"
        })
      )

    assert result.dates == %{
             "datVyst" => "2026-11-05",
             "duzpPuv" => "2026-10-31",
             "datSplat" => "2026-11-19",
             "duzpUcto" => "2026-11-05",
             "datUcto" => "2026-11-05"
           }

    later_tax =
      FormSuggestions.from(data(%{"issue_date" => "2026-11-05", "tax_date" => "2026-11-10"}))

    assert later_tax.dates["duzpUcto"] == "2026-11-10"
  end

  test "missing dates are suggested from issue or tax date without inventing today's date" do
    result =
      FormSuggestions.from(
        data(%{"issue_date" => "2026-11-05", "tax_date" => nil, "due_date" => nil})
      )

    assert Enum.all?(result.dates, fn {_, value} -> value == "2026-11-05" end)
    assert map_size(result.dates) == 5

    assert FormSuggestions.from(
             data(%{"issue_date" => nil, "tax_date" => nil, "due_date" => nil})
           ).dates == %{}

    assert FormSuggestions.from(
             data(%{"issue_date" => "31.02.2026", "tax_date" => nil, "due_date" => nil})
           ).dates == %{}
  end

  test "date proposals respect dates already supplied by the operator" do
    values = %{
      "datVyst" => "2026-11-05",
      "duzpPuv" => "2026-10-31",
      "datSplat" => "2026-12-01",
      "datUcto" => "2026-11-07",
      "duzpUcto" => "2026-12-01"
    }

    assert FormSuggestions.dates(values) == values
  end

  test "fresh source suggestions fill VAT and all dates but reopening saved XML preserves edits" do
    source =
      data(%{
        "issue_date" => "5.11.2026",
        "tax_date" => nil,
        "due_date" => nil,
        "vat_summary" => [row("21 %", "100.00", "21.00", "121.00")],
        "total" => "121.00"
      })

    doc = %Document{
      agenda: "zavazek",
      extracted_data: source,
      template_xml: XML.template("zavazek"),
      external_id: "ext:cozy-incoming:test"
    }

    proposed = HeaderForm.values(doc)
    assert proposed["sumZklZakl"] == "100.00"
    assert proposed["datSplat"] == "2026-11-05"
    assert proposed["datUcto"] == "2026-11-05"
    assert {:ok, _, xml} = HeaderForm.build(Map.put(proposed, "datUcto", "2026-11-06"), doc)
    assert HeaderForm.values(%{doc | current_xml: xml})["datUcto"] == "2026-11-06"
  end
end

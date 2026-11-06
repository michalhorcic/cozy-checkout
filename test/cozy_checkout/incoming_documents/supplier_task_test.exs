defmodule CozyCheckout.IncomingDocuments.SupplierTaskTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.{SupplierTask, Transcription}

  defp original do
    File.read!("test/fixtures/incoming_documents/penny.json") |> Jason.decode!()
  end

  defp result,
    do: %{
      "fields" => [
        %{
          "field" => "document_number",
          "value" => "0052-20261105-01-0039",
          "source_text" => "EV-č: 0052-20261105-01-0039"
        }
      ],
      "vat_summary" => nil,
      "uncertainties" => []
    }

  test "a focused number replaces the general guess while preserving unrelated source fields" do
    data = original() |> Map.put("document_number", "39")
    assert :ok = SupplierTask.validate(result())
    merged = SupplierTask.merge(data, result())
    assert merged["document_number"] == "0052-20261105-01-0039"
    assert Map.delete(merged, "document_number") == Map.delete(data, "document_number")
    assert :ok = Transcription.validate(merged)
  end

  test "explicit unknown removes a wrong general number and supplier changes remain detectable" do
    result = put_in(result(), ["fields", Access.at(0), "value"], nil)
    assert :ok = SupplierTask.validate(result)
    assert SupplierTask.merge(original(), result)["document_number"] == nil

    result =
      put_in(result, ["fields"], [
        %{"field" => "supplier.ic", "value" => "00006947", "source_text" => "IČO 00006947"}
      ])

    assert :ok = SupplierTask.validate(result)
    assert SupplierTask.merge(original(), result)["supplier"]["ic"] == "00006947"
  end

  test "sparse VAT correction preserves dates and identity" do
    vat = [%{"rate" => "21", "net" => "100", "vat" => "21", "gross" => "121"}]
    result = %{"fields" => [], "vat_summary" => vat, "uncertainties" => ["Ověřte rekapitulaci."]}
    assert :ok = SupplierTask.validate(result)
    merged = SupplierTask.merge(original(), result)
    assert merged["vat_summary"] == vat
    assert merged["issue_date"] == original()["issue_date"]
    assert merged["supplier"] == original()["supplier"]

    assert merged["uncertainties"] ==
             Enum.uniq(result["uncertainties"] ++ original()["uncertainties"])
  end

  test "strict whitelist rejects accounting, items, duplicates, invalid types and missing evidence" do
    for invalid <- [
          nil,
          %{},
          Map.put(result(), "account", "321"),
          Map.put(result(), "fields", [42]),
          Map.put(result(), "fields", result()["fields"] ++ result()["fields"]),
          put_in(result(), ["fields", Access.at(0), "field"], "primUcet"),
          put_in(result(), ["fields", Access.at(0), "field"], "items"),
          put_in(result(), ["fields", Access.at(0), "value"], 39),
          put_in(result(), ["fields", Access.at(0), "source_text"], nil),
          put_in(result(), ["fields", Access.at(0), "source_text"], ""),
          put_in(result(), ["fields", Access.at(0), "value"], String.duplicate("x", 2001)),
          Map.put(result(), "vat_summary", [%{"rate" => 21}]),
          Map.put(result(), "uncertainties", [nil])
        ] do
      assert {:error, _} = SupplierTask.validate(invalid)
    end
  end
end

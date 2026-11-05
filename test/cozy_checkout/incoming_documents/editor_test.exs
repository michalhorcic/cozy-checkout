defmodule CozyCheckout.IncomingDocuments.EditorTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.{Editor, Transcription}

  test "form updates preserve source types, identifiers, all rows and explicit false" do
    data = File.read!("test/fixtures/incoming_documents/penny.json") |> Jason.decode!()

    edited =
      Editor.apply(data, %{
        "document_number" => "00001",
        "complete" => "true",
        "uncertainties" => "",
        "vat_summary" => %{"0" => %{"vat" => "126,25"}},
        "items" => %{"0" => %{"quantity" => "1,00", "price_includes_vat" => "false"}}
      })

    assert edited["document_number"] == "00001"
    assert edited["items"] |> hd() |> Map.fetch!("price_includes_vat") == false
    assert length(edited["items"]) == 21
    assert edited["supplier"] == data["supplier"]
    assert edited["uncertainties"] == []
    assert :ok = Transcription.validate(edited)
    assert Editor.value(edited, ["items", 0, "price_includes_vat"]) == "false"
    assert Editor.name(["vat_summary", 0, "vat"]) == "fields[source][vat_summary][0][vat]"
    added = Editor.add(edited, "vat_summary")
    assert :ok = Transcription.validate(added)
    assert length(added["vat_summary"]) == 2
    assert Editor.delete(added, "vat_summary", "1") == edited
    assert Editor.add(edited, "unknown") == edited
  end
end

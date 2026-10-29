defmodule CozyCheckoutWeb.EconomicsIdentificationTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias CozyCheckoutWeb.EconomicsLive.Components

  test "identification is visible and free text remains escaped" do
    record = %{
      "module" => "FAV",
      "document_id" => "17",
      "identification" => %{
        "company" => "Čaj & káva s.r.o.",
        "document_number" => "FV-2026-0017",
        "description" => "Prodej čaje <script>alert(1)</script>",
        "variable_symbol" => "0017",
        "supplier_number" => "OBJ-17",
        "counter_account" => "311001: Odběratelé"
      }
    }

    html = render_component(&Components.document_identity/1, record: record)
    assert html =~ "Čaj &amp; káva s.r.o."
    assert html =~ "FV-2026-0017"
    assert html =~ "Vydaná faktura"
    assert html =~ "VS: 0017"
    assert html =~ "OBJ-17"
    assert html =~ "311001: Odběratelé"
    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>"
  end

  test "legacy snapshots show their reference and a refresh hint" do
    html =
      render_component(&Components.document_identity/1,
        record: %{"module" => "FAV", "document_id" => "17"}
      )

    assert html =~ "Firma neuvedena"
    assert html =~ "ABRA FAV / 17"
    assert html =~ "Další údaje doplní aktualizace z ABRY."
  end
end

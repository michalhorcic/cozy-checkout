defmodule CozyCheckout.IncomingDocuments.ResponseDiagnosticsTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.ResponseDiagnostics, as: Diagnostic

  test "FreeMarker error after a malformed body excludes navigation and script contents" do
    raw = File.read!("test/fixtures/incoming_documents/freemarker_error.html")
    result = Diagnostic.describe(200, raw, %{"content-type" => "text/html"})
    assert result["kind"] == "server_template_error"
    assert result["title"] == "Doklady faktur | ABRA Flexi"
    assert result["version_in_html"] == "2026.6.7"
    assert result["text"] =~ "==> object"
    refute result["text"] =~ "Obchodní partneři"
    refute result["text"] =~ "SCRIPT_CONTENT"
  end

  test "redirects, authentication and server failures are distinct without claiming validation" do
    for {status, kind} <- [
          {302, "redirect"},
          {401, "authentication"},
          {403, "access_denied"},
          {502, "server_error"}
        ] do
      assert Diagnostic.describe(status, "<html><body>Error</body></html>")["kind"] == kind
    end

    assert Diagnostic.describe(200, "<html><form><input type='password'></form></html>")["kind"] ==
             "login_page"

    assert Diagnostic.describe(
             200,
             "<html><title>Doklady faktur</title><body>Výpis</body></html>"
           )["kind"] == "html_page"
  end

  test "text decoding is bounded and never treats encoded tags as markup" do
    result =
      Diagnostic.describe(
        200,
        "<html><body>&lt;script&gt;&#65;&#x42;&lt;/script&gt;" <>
          String.duplicate("x", 20_000) <> "</body></html>"
      )

    assert result["text"] =~ "<script>AB</script>"
    assert String.length(result["text"]) <= 6000

    assert Diagnostic.safe_url("https://user:secret@example.test/login?token=private#code") ==
             "https://example.test/login"

    assert Diagnostic.safe_url("/login?token=private") == "/login"
  end

  test "script contents cannot masquerade as a visible template error" do
    response =
      Diagnostic.describe(
        200,
        "<html><body><script>console.log('FreeMarker template error!')</script>Doklady</body></html>"
      )

    assert response["kind"] == "html_page"
    assert response["text"] == "Doklady"
    assert Diagnostic.describe(502, <<255>>)["kind"] == "server_error"
  end

  test "stored valid JSON and parsed JSON with a misleading HTML content type stay unchanged" do
    response = %{
      "http_status" => 200,
      "content_type" => "text/html",
      "raw_body" => ~s({"winstrom":{"success":true}})
    }

    assert Diagnostic.for_display(response) == response
    parsed = Map.put(response, "body", %{"success" => true})
    assert Diagnostic.for_display(parsed) == parsed
  end
end

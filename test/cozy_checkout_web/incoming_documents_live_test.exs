defmodule CozyCheckoutWeb.IncomingDocumentsLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckout.{IncomingDocuments, Repo}
  alias CozyCheckout.IncomingDocuments.XML
  alias CozyCheckoutWeb.AdminAuth

  setup do
    old_pin = Application.get_env(:cozy_checkout, :admin_pin_hash)
    old_config = IncomingDocuments.config()
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    Application.put_env(:cozy_checkout, :incoming_documents,
      enabled: true,
      base_url: "https://accounting.test",
      company_id: "pilot",
      username: "test",
      password: "test"
    )

    on_exit(fn ->
      if old_pin,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, old_pin),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)

      Application.put_env(:cozy_checkout, :incoming_documents, old_config)
    end)

    :ok
  end

  defp admin(conn),
    do:
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

  test "list and private originals require admin PIN and list exposes only the new form", %{
    conn: conn
  } do
    assert {:error, {:redirect, %{to: to}}} = live(conn, "/admin/incoming-documents")
    assert to =~ "/admin/login"
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "private.pdf", "zavazek")
    response = get(conn, "/admin/incoming-documents/#{doc.id}/original")
    assert redirected_to(response) =~ "/admin/login"
    conn = conn |> admin() |> get("/admin/incoming-documents/#{doc.id}/original")
    assert response(conn, 200) == "%PDF-test"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    {:ok, view, _} = live(admin(build_conn()), "/admin/incoming-documents/all")
    assert has_element?(view, "#incoming-list")
    assert has_element?(view, "a[href='/admin/incoming-document-form/#{doc.id}']")
    refute has_element?(view, "#incoming-upload")
  end

  test "old detail URL opens the new form and saving converts a legacy draft", %{conn: conn} do
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "old.pdf", "zavazek")
    {:ok, fields} = XML.parse(doc.template_xml, doc.agenda)

    fields =
      Map.merge(fields, %{
        "nazFirmy" => "Dodavatel",
        "cisDosle" => "OLD",
        "datVyst" => "2026-11-05",
        "datSplat" => "2026-11-05",
        "sumOsv" => "10.00",
        "sumCelkem" => "10.00"
      })

    doc
    |> Ecto.Changeset.change(
      state: "review",
      current_xml: XML.render(fields, doc.agenda, doc.external_id)
    )
    |> Repo.update!()

    {:ok, view, _} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(view, "#incoming-header-form")
    refute has_element?(view, "#incoming-fields")
    refute has_element?(view, "#incoming-source-fields")
    refute has_element?(view, "#incoming-header-form input[type=checkbox]")

    view
    |> form("#incoming-header-form", %{"document" => %{"cisDosle" => "NEW"}})
    |> render_submit()

    refute_patched(view)
    changed = IncomingDocuments.get!(doc.id)
    assert changed.extraction_metadata["strategy"] == "header_form"
    assert changed.current_xml =~ "<cisDosle>NEW</cisDosle>"
    assert has_element?(view, "#incoming-accounting-form")
    assert has_element?(view, "#incoming-actions button[phx-click=send-next]")
  end

  test "stored FreeMarker responses are escaped and displayed within the new form", %{conn: conn} do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "error.pdf", "zavazek", "header_form")

    doc
    |> Ecto.Changeset.change(
      state: "review",
      dry_run: %{
        "http_status" => 500,
        "raw_body" =>
          "<html><body>FreeMarker template error!<script>alert(1)</script></body></html>",
        "response_headers" => %{"content-type" => "text/html"}
      }
    )
    |> Repo.update!()

    {:ok, view, html} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(view, "[data-abra-response]")
    assert html =~ "FreeMarker"
    refute html =~ "<script>alert(1)</script>"
    refute has_element?(view, "#incoming-fields")
  end
end

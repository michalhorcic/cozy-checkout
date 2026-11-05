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

  test "list and private originals require admin PIN", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, "/admin/incoming-documents")
    assert to =~ "/admin/login"
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "private.pdf", "zavazek")
    response = get(conn, "/admin/incoming-documents/#{doc.id}/original")
    assert redirected_to(response) =~ "/admin/login"
    conn = conn |> admin() |> get("/admin/incoming-documents/#{doc.id}/original")
    assert response(conn, 200) == "%PDF-test"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    {:ok, view, _} = live(admin(build_conn()), "/admin/incoming-documents")
    assert has_element?(view, "#incoming-list")
    assert has_element?(view, "option[value='pokladni-pohyb']")
    assert has_element?(view, "option[value='zavazek']")
    assert has_element?(view, "option[value='faktura-prijata']")
  end

  test "upload opens detail, corrections update XML and hide approval until validation", %{
    conn: conn
  } do
    {:ok, view, _} = live(admin(conn), "/admin/incoming-documents")

    upload =
      file_input(view, "#incoming-upload", :original, [
        %{name: "test.pdf", content: "%PDF-test", type: "application/pdf"}
      ])

    render_upload(upload, "test.pdf")
    view |> form("#incoming-upload", %{"agenda" => "zavazek"}) |> render_submit()
    [%{id: id}] = IncomingDocuments.list()
    assert_patch(view, "/admin/incoming-documents/#{id}")
    doc = IncomingDocuments.get!(id)
    {:ok, fields} = XML.parse(doc.template_xml, doc.agenda)

    fields =
      Map.merge(fields, %{
        "nazFirmy" => "Dodavatel",
        "cisDosle" => "OLD",
        "datVyst" => "2026-11-05",
        "sumOsv" => "10.00",
        "sumCelkem" => "10.00"
      })

    xml = XML.render(fields, doc.agenda, doc.external_id)
    doc |> Ecto.Changeset.change(state: "review", current_xml: xml) |> Repo.update!()
    {:ok, view, _} = live(admin(build_conn()), "/admin/incoming-documents/#{id}")
    assert has_element?(view, "#incoming-fields")
    refute has_element?(view, "#incoming-approve")
    view |> form("#incoming-fields", %{"fields" => %{"cisDosle" => "NEW"}}) |> render_submit()
    assert IncomingDocuments.get!(id).current_xml =~ "<cisDosle>NEW</cisDosle>"
    assert has_element?(view, "#incoming-validate")
    assert has_element?(view, "iframe")
  end
end

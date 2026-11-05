defmodule CozyCheckoutWeb.IncomingDocumentFormLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckout.{IncomingDocuments, Repo}
  alias CozyCheckoutWeb.AdminAuth

  setup do
    previous = IncomingDocuments.config()
    req_options = Req.default_options()
    Req.default_options(plug: {Req.Test, __MODULE__})
    Req.Test.verify_on_exit!()
    pin = Application.get_env(:cozy_checkout, :admin_pin_hash)
    Application.put_env(:cozy_checkout, :admin_pin_hash, AdminAuth.hash_pin("482731"))

    Application.put_env(:cozy_checkout, :incoming_documents,
      enabled: true,
      base_url: "https://accounting.test",
      company_id: "pilot",
      username: "test",
      password: "test"
    )

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :incoming_documents, previous)
      Req.default_options(req_options)

      if pin,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, pin),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    :ok
  end

  defp admin(conn),
    do:
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

  defp attrs,
    do: %{
      "nazFirmy" => "Dodavatel",
      "cisDosle" => "R42",
      "datVyst" => "2026-11-05",
      "datSplat" => "2026-11-05",
      "sumOsv" => "123,45",
      "sumCelkem" => "123,45"
    }

  test "form requires admin PIN", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, "/admin/incoming-document-form")
    assert to =~ "/admin/login"
  end

  test "manual form requires confirmation and stays in the new form with accounting and delivery",
       %{conn: conn} do
    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form")
    params = %{"agenda" => "zavazek", "document" => attrs()}
    view |> form("#incoming-header-form", params) |> render_submit()
    assert IncomingDocuments.list() == []
    view |> form("#incoming-header-form", Map.put(params, "reviewed", "true")) |> render_change()
    assert has_element?(view, "input[name=reviewed][type=checkbox][checked]")
    view |> form("#incoming-header-form", Map.put(params, "reviewed", "true")) |> render_submit()
    [doc] = IncomingDocuments.list()
    assert_patch(view, "/admin/incoming-document-form/#{doc.id}")
    {:ok, detail, _} = live(admin(build_conn()), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(detail, "#incoming-accounting")
    assert has_element?(detail, "#incoming-header-form")
    assert has_element?(detail, "#incoming-send")
    refute has_element?(detail, "iframe")
    refute has_element?(detail, "img[data-original]")

    assert_error_sent 404, fn ->
      get(admin(build_conn()), "/admin/incoming-documents/#{doc.id}/original")
    end
  end

  test "partial proposals can be opened in either detail without the item editor crashing", %{
    conn: conn
  } do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "partial.pdf", "zavazek", "header_form")

    data =
      File.read!("test/fixtures/incoming_documents/penny.json")
      |> Jason.decode!()
      |> Map.put("complete", false)

    doc |> Ecto.Changeset.change(state: "review", extracted_data: data) |> Repo.update!()
    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    assert has_element?(view, "textarea[name='document[poznam]']")
    assert has_element?(view, "iframe")
    {:ok, detail, _} = live(admin(build_conn()), "/admin/incoming-documents/#{doc.id}")
    refute has_element?(detail, "#incoming-approve")
    refute has_element?(detail, "#incoming-source-form")
  end

  test "accounting picker saves the preset on the same page and preserves pending header edits",
       %{conn: conn} do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())

    row = %{
      "kod" => "SLUŽBY",
      "nazev" => "Služby",
      "modulZav" => true,
      "protiUcetVydej" => "code:518100",
      "dphZaklUcet" => "code:343100"
    }

    for _ <- 1..2 do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/c/pilot/predpis-zauctovani.json"
        Req.Test.json(conn, %{"winstrom" => %{"predpis-zauctovani" => [row]}})
      end)
    end

    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    view |> element("button[phx-click=accounting-load]") |> render_click()

    render_click(view, "accounting-select", %{"id" => Base.url_encode64("SLUŽBY", padding: false)})

    view
    |> form("#incoming-header-form", %{"document" => %{"cisDosle" => "DRAFT"}})
    |> render_change()

    view |> form("#incoming-accounting-form") |> render_submit()
    assert has_element?(view, "input[name='document[cisDosle]'][value='DRAFT']")
    assert IncomingDocuments.get!(doc.id).accounting_settings["typUcOp"] == "code:SLUŽBY"
    assert has_element?(view, "#incoming-send button[disabled]")
    view |> form("#incoming-header-form", %{"reviewed" => "true"}) |> render_submit()
    updated = IncomingDocuments.get!(doc.id)
    assert updated.current_xml =~ "<cisDosle>DRAFT</cisDosle>"
    assert updated.current_xml =~ "<protiUcet>code:518100</protiUcet>"
    refute has_element?(view, "#incoming-send button[disabled]")
  end

  test "dry-run HTML is shown in place and explicit real send remains available", %{conn: conn} do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())

    Req.Test.expect(__MODULE__, fn conn ->
      assert Plug.Conn.fetch_query_params(conn).query_params["dry-run"] == "true"

      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(500, "<html>FreeMarker template error!</html>")
    end)

    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    view |> element("#incoming-validate") |> render_click()
    assert IncomingDocuments.get!(doc.id).state == "validating"
    IncomingDocuments.perform(doc.id, "validate")
    send(view.pid, :refresh)
    assert render(view) =~ "FreeMarker"
    view |> form("#incoming-send") |> render_submit()
    assert IncomingDocuments.get!(doc.id).state == "review"
    view |> form("#incoming-send", %{"confirm_send" => "true"}) |> render_submit()
    assert IncomingDocuments.get!(doc.id).state == "sending"
    assert has_element?(view, "#incoming-header-form input[name='document[cisDosle]'][disabled]")
  end
end

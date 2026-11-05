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

  test "failed XML shows a difference table and can be repaired without extraction", %{conn: conn} do
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "repair.pdf", "zavazek")
    {:ok, fields} = XML.parse(doc.template_xml, doc.agenda)

    raw =
      fields
      |> Map.merge(%{
        "primUcet" => "code:999999",
        "nazFirmy" => "Dodavatel",
        "cisDosle" => "A-1",
        "datVyst" => "2026-11-05",
        "sumOsv" => "10.00",
        "sumCelkem" => "10.00"
      })
      |> XML.render(doc.agenda)

    doc
    |> Ecto.Changeset.change(
      state: "failed",
      error_stage: "extraction",
      error: "Účetní nastavení se liší od vzoru",
      generated_xml: raw
    )
    |> Repo.update!()

    {:ok, view, html} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(view, "#incoming-accounting-differences", "primUcet")
    assert html =~ "code:325000"
    assert html =~ "code:999999"
    assert has_element?(view, "#incoming-repair textarea")
    refute has_element?(view, "#incoming-validate")

    view
    |> form("#incoming-repair", %{"fields" => %{"xml" => raw}})
    |> render_submit(%{"action" => "save"})

    assert IncomingDocuments.get!(doc.id).state == "failed"

    view
    |> form("#incoming-repair", %{"fields" => %{"xml" => raw}})
    |> render_submit(%{"action" => "restore"})

    assert IncomingDocuments.get!(doc.id).state == "failed"
    refute has_element?(view, "#incoming-accounting-differences")
    view |> form("#incoming-repair") |> render_submit(%{"action" => "save"})
    assert IncomingDocuments.get!(doc.id).state == "review"
    assert IncomingDocuments.get!(doc.id).generated_xml == raw
    assert has_element?(view, "#incoming-fields")
    assert has_element?(view, "#incoming-validate")
    refute has_element?(view, "#incoming-approve")
    refute has_element?(view, "#incoming-repair")
  end

  test "source JSON can be repaired and a rounding adjustment is clearly shown", %{conn: conn} do
    data = "test/fixtures/incoming_documents/penny.json" |> File.read!() |> Jason.decode!()
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "penny.pdf", "zavazek")

    doc
    |> Ecto.Changeset.change(
      state: "failed",
      error_stage: "extraction",
      extracted_data: data,
      extraction_attempts: 2,
      error: "Zkontrolujte přepis"
    )
    |> Repo.update!()

    {:ok, view, _} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(view, "#incoming-transcription")
    assert has_element?(view, "#incoming-repair-data")
    view |> form("#incoming-repair-data", fields: %{data: Jason.encode!(data)}) |> render_submit()
    assert IncomingDocuments.get!(doc.id).state == "review"
    assert has_element?(view, "#incoming-rounding")
    assert render(view) =~ "samostatnou účetní položku"
  end

  test "a second prompt can be explicitly selected without removing the original", %{conn: conn} do
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "receipt.pdf", "zavazek")
    doc |> Ecto.Changeset.change(state: "failed", error_stage: "extraction") |> Repo.update!()
    {:ok, view, _} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(view, "button[phx-value-strategy=structured]")
    view |> element("button[phx-value-strategy=simple_xml]") |> render_click()
    queued = IncomingDocuments.get!(doc.id)
    assert queued.state == "uploaded"
    assert queued.extraction_metadata["strategy"] == "simple_xml"
  end

  test "source form highlights missing VAT, preserves invalid edits and offers a PIN-protected XML download",
       %{conn: conn} do
    data = "test/fixtures/incoming_documents/penny.json" |> File.read!() |> Jason.decode!()
    data = put_in(data, ["vat_summary", Access.at(0), "vat"], nil)
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "o2.pdf", "faktura-prijata")

    doc
    |> Ecto.Changeset.change(state: "failed", error_stage: "extraction", extracted_data: data)
    |> Repo.update!()

    {:ok, view, html} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(view, "#incoming-source-form")
    assert html =~ "DPH má nečitelnou nebo chybějící hodnotu"

    view
    |> form("#incoming-source-form", %{
      "fields" => %{"source" => %{"vat_summary" => %{"0" => %{"vat" => ""}}}}
    })
    |> render_submit()

    saved = IncomingDocuments.get!(doc.id)
    assert saved.edited_data["vat_summary"] |> hd() |> Map.fetch!("vat") == nil
    assert saved.state == "failed"
    assert has_element?(view, "#incoming-draft-download a")
    path = "/admin/incoming-documents/#{doc.id}/draft.xml"
    assert get(build_conn(), path) |> redirected_to() =~ "/admin/login"
    downloaded = build_conn() |> admin() |> get(path)
    assert get_resp_header(downloaded, "cache-control") == ["private, no-store"]

    assert get_resp_header(downloaded, "content-disposition") == [
             "attachment; filename=\"NEOVERENO-abra.xml\""
           ]

    assert {:ok, _} = XML.parse(response(downloaded, 200), "faktura-prijata")
    assert IncomingDocuments.get!(doc.id).sent_xml == nil
  end

  test "accounting form lets the operator fill the internal ABRA code", %{conn: conn} do
    data = "test/fixtures/incoming_documents/penny.json" |> File.read!() |> Jason.decode!()
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "o2.pdf", "faktura-prijata")

    doc
    |> Ecto.Changeset.change(state: "failed", error_stage: "extraction", extracted_data: data)
    |> Repo.update!()

    {:ok, view, _} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(view, "#fields_preset-picker")

    view
    |> form("#incoming-accounting-form", fields: %{internal_code: "FP2026-001"})
    |> render_submit()

    saved = IncomingDocuments.get!(doc.id)
    assert saved.current_xml =~ "<kod>FP2026-001</kod>"
    assert saved.dry_run == %{}
    assert has_element?(view, "#incoming-diagnose")
  end

  test "incomplete O2 extraction warns about missing service coverage before download", %{
    conn: conn
  } do
    data = File.read!("test/fixtures/incoming_documents/o2_incomplete.json") |> Jason.decode!()
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "o2.pdf", "faktura-prijata")

    doc
    |> Ecto.Changeset.change(state: "failed", error_stage: "extraction", extracted_data: data)
    |> Repo.update!()

    {:ok, view, _} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(view, "#incoming-export-issues", "1803.34")
    assert has_element?(view, "#incoming-source-issues", "Neurčená sazba neznamená")
    assert has_element?(view, "#incoming-draft-download a")

    download =
      build_conn()
      |> admin()
      |> get("/admin/incoming-documents/#{doc.id}/draft.xml")
      |> response(200)

    assert {:ok, fields} = XML.parse(download, "faktura-prijata")
    assert length(XML.items(fields)) == 1
    assert hd(XML.items(fields))["cenaMj"] == "99.00"
    assert IncomingDocuments.get!(doc.id).sent_xml == nil
  end

  test "legacy extraction failures explain the need for one new extraction", %{conn: conn} do
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "legacy.pdf", "zavazek")

    doc
    |> Ecto.Changeset.change(
      state: "failed",
      error_stage: "extraction",
      error: "Účetní nastavení se liší od vzoru"
    )
    |> Repo.update!()

    {:ok, view, html} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert html =~ "XML z tohoto pokusu není uložené"
    assert has_element?(view, "button[phx-click=retry]")
    refute has_element?(view, "#incoming-repair")
  end

  test "itemized review shows editable lines and the actual XML payload", %{conn: conn} do
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "items.pdf", "zavazek")
    {:ok, fields} = XML.parse(doc.template_xml, doc.agenda)

    row = %{
      "nazev" => "Pečivo",
      "mnozMj" => "2",
      "cenaMj" => "28.00",
      "typCenyDphK" => "typCeny.sDph",
      "typSzbDphK" => "typSzbDph.dphSniz"
    }

    fields =
      Map.merge(fields, %{
        "nazFirmy" => "Obchod",
        "cisDosle" => "U-1",
        "datVyst" => "2026-11-05",
        "sumZklSniz" => "50.00",
        "sumDphSniz" => "6.00",
        "sumCelkem" => "56.00",
        "polozkyDokladu" => [row]
      })

    {:ok, xml} =
      XML.normalize(XML.render(fields, doc.agenda), doc.agenda, doc.template_xml, doc.external_id)

    doc |> Ecto.Changeset.change(state: "review", current_xml: xml) |> Repo.update!()
    {:ok, view, _} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(view, "input[name='fields[items][0][nazev]'][value='Pečivo']")
    assert has_element?(view, "#incoming-items", "Položky dokladu (1)")

    view
    |> form("#incoming-fields", %{
      "fields" => %{"items" => %{"0" => %{"nazev" => "Opravené pečivo"}}}
    })
    |> render_submit()

    {:ok, parsed} = XML.parse(IncomingDocuments.get!(doc.id).current_xml, doc.agenda)
    assert hd(XML.items(parsed))["nazev"] == "Opravené pečivo"
    assert IncomingDocuments.get!(doc.id).dry_run == %{}
  end

  test "previously stored FreeMarker HTML is shown as a readable technical diagnosis", %{
    conn: conn
  } do
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "o2.pdf", "faktura-prijata")
    html = File.read!("test/fixtures/incoming_documents/freemarker_error.html")

    doc
    |> Ecto.Changeset.change(
      state: "review",
      dry_run: %{"http_status" => 200, "content_type" => "text/html", "raw_body" => html}
    )
    |> Repo.update!()

    {:ok, view, rendered} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(view, "details[data-abra-response][open]")
    assert has_element?(view, "[data-abra-diagnostic]", "FreeMarker")
    assert has_element?(view, "[data-abra-diagnostic]", "==> object")
    assert has_element?(view, "[data-abra-diagnostic]", "2026.6.7")
    assert has_element?(view, "[data-abra-diagnostic]", "evidence/faktura-prijata/view.ftl")
    refute has_element?(view, "[data-abra-diagnostic]", "SCRIPT_CONTENT")
    assert rendered =~ "&lt;script&gt;"
    refute rendered =~ "<script>window.secret"
  end

  test "ABRA response details show status and content safely as text", %{conn: conn} do
    {:ok, %{document: doc}} = IncomingDocuments.upload("%PDF-test", "diagnostic.pdf", "zavazek")

    doc
    |> Ecto.Changeset.change(
      state: "review",
      error: "ABRA HTTP 200: neplatný obsah",
      dry_run: %{
        "http_status" => 200,
        "content_type" => "text/html",
        "raw_body" => "<script>bad</script>",
        "errors" => ["pole: sumZkl · cesta: zavazek[0]"],
        "warnings" => []
      }
    )
    |> Repo.update!()

    {:ok, view, html} = live(admin(conn), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(view, "details[data-abra-response]", "HTTP 200")
    assert html =~ "text/html"
    assert html =~ "sumZkl"
    assert html =~ "&lt;script&gt;bad&lt;/script&gt;"
    refute html =~ "<script>bad</script>"
  end
end

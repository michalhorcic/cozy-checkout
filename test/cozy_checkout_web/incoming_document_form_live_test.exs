defmodule CozyCheckoutWeb.IncomingDocumentFormLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckout.{IncomingDocuments, Repo}
  alias CozyCheckoutWeb.AdminAuth

  setup do
    previous = IncomingDocuments.config()
    req_options = Req.default_options()

    Req.Test.stub({__MODULE__, :catalog}, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"predpis-zauctovani" => []}})
    end)

    Req.default_options(
      plug: fn conn ->
        name =
          if String.ends_with?(conn.request_path, "/predpis-zauctovani.json"),
            do: {__MODULE__, :catalog},
            else: __MODULE__

        Req.Test.call(conn, name)
      end
    )

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

  test "manual form validates amounts and saves directly without consent checkboxes",
       %{conn: conn} do
    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form")
    params = %{"agenda" => "zavazek", "document" => attrs()}
    refute has_element?(view, "#incoming-header-form input[type=checkbox]")

    view
    |> form("#incoming-header-form", put_in(params, ["document", "sumCelkem"], "10"))
    |> render_submit()

    assert IncomingDocuments.list() == []
    view |> form("#incoming-header-form", params) |> render_submit()
    [doc] = IncomingDocuments.list()
    assert_patch(view, "/admin/incoming-document-form/#{doc.id}")
    {:ok, detail, _} = live(admin(build_conn()), "/admin/incoming-documents/#{doc.id}")
    assert has_element?(detail, "#incoming-accounting")
    assert has_element?(detail, "#incoming-header-form")
    assert has_element?(detail, "#incoming-actions button[phx-click=send-next]")
    refute has_element?(detail, "#incoming-actions input[type=checkbox]")
    refute has_element?(detail, "#supplier-instructions-form input[type=checkbox]")
    refute has_element?(detail, "iframe")
    refute has_element?(detail, "img[data-original]")

    assert_error_sent 404, fn ->
      get(admin(build_conn()), "/admin/incoming-documents/#{doc.id}/original")
    end
  end

  test "identity warning remains visible but saving needs no additional agreement", %{conn: conn} do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())

    doc
    |> Ecto.Changeset.change(
      extraction_metadata:
        Map.put(
          doc.extraction_metadata,
          "identity_conflict",
          "IČO se liší od zvoleného dodavatele."
        )
    )
    |> Repo.update!()

    {:ok, view, html} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    assert html =~ "IČO se liší od zvoleného dodavatele."
    refute has_element?(view, "#incoming-header-form input[type=checkbox]")

    view
    |> form("#incoming-header-form", %{"document" => Map.put(attrs(), "cisDosle", "OPRAVENO")})
    |> render_submit()

    saved = IncomingDocuments.get!(doc.id)
    assert saved.state == "review"
    assert saved.current_xml =~ "<cisDosle>OPRAVENO</cisDosle>"
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
      Req.Test.expect({__MODULE__, :catalog}, fn conn ->
        assert conn.request_path == "/c/pilot/predpis-zauctovani.json"
        Req.Test.json(conn, %{"winstrom" => %{"predpis-zauctovani" => [row]}})
      end)
    end

    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    render_async(view)
    assert has_element?(view, "section#incoming-accounting")

    render_click(view, "accounting-select", %{"id" => Base.url_encode64("SLUŽBY", padding: false)})

    view
    |> form("#incoming-header-form", %{"document" => %{"cisDosle" => "DRAFT"}})
    |> render_change()

    view |> form("#incoming-accounting-form") |> render_submit()
    assert has_element?(view, "input[name='document[cisDosle]'][value='DRAFT']")
    assert IncomingDocuments.get!(doc.id).accounting_settings["typUcOp"] == "code:SLUŽBY"
    refute has_element?(view, "#incoming-actions button[phx-click=send-next][disabled]")
    view |> form("#incoming-header-form") |> render_submit()
    updated = IncomingDocuments.get!(doc.id)
    assert updated.current_xml =~ "<cisDosle>DRAFT</cisDosle>"
    assert updated.current_xml =~ "<protiUcet>code:518100</protiUcet>"
    refute has_element?(view, "#incoming-actions button[phx-click=send-next][disabled]")
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
    view |> element("button[phx-click=send-next]") |> render_click()
    assert IncomingDocuments.get!(doc.id).state == "sending"
    assert has_element?(view, "#incoming-header-form input[name='document[cisDosle]'][disabled]")
  end

  test "VAT and all dates prefill from the origin and summary can be reapplied without losing other edits",
       %{conn: conn} do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "summary.pdf", "zavazek", "header_form")

    source = File.read!("test/fixtures/incoming_documents/penny.json") |> Jason.decode!()

    source =
      Map.merge(source, %{
        "issue_date" => "5.11.2026",
        "tax_date" => "31.10.2026",
        "due_date" => nil,
        "vat_summary" => [
          %{"rate" => "21 %", "net" => "100.00", "vat" => "21.00", "gross" => "121.00"}
        ]
      })

    doc |> Ecto.Changeset.change(state: "review", extracted_data: source) |> Repo.update!()
    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    assert has_element?(view, "input[name='document[sumZklZakl]'][value='100.00']")
    assert has_element?(view, "input[name='document[sumDphZakl]'][value='21.00']")
    assert has_element?(view, "input[name='document[datUcto]'][value='2026-11-05']")
    assert has_element?(view, "input[name='document[duzpUcto]'][value='2026-11-05']")
    assert has_element?(view, "input[name='document[datSplat]'][value='2026-11-05']")

    view
    |> form("#incoming-header-form", %{
      "document" => %{
        "sumDphZakl" => "0",
        "nazFirmy" => "Ruční dodavatel",
        "datSplat" => "2026-12-01",
        "datUcto" => ""
      }
    })
    |> render_change()

    view |> element("button[phx-click=prefill-vat]") |> render_click()
    assert has_element?(view, "input[name='document[sumDphZakl]'][value='21.00']")
    assert has_element?(view, "input[name='document[nazFirmy]'][value='Ruční dodavatel']")
    view |> element("button[phx-click=prefill-dates]") |> render_click()
    assert has_element?(view, "input[name='document[datUcto]'][value='2026-11-05']")
    assert has_element?(view, "input[name='document[datSplat]'][value='2026-12-01']")
    assert IncomingDocuments.get!(doc.id).current_xml == nil
  end

  test "extraction completion fills VAT and dates even after recovery of the empty form", %{
    conn: conn
  } do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "pending.pdf", "zavazek", "header_form")

    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")

    render_change(view, "change", %{
      "document" => CozyCheckout.IncomingDocuments.HeaderForm.defaults()
    })

    source = File.read!("test/fixtures/incoming_documents/o2_incomplete.json") |> Jason.decode!()
    doc |> Ecto.Changeset.change(state: "review", extracted_data: source) |> Repo.update!()
    send(view.pid, :refresh)
    render(view)
    assert has_element?(view, "input[name='document[sumZklZakl]'][value='1490.36']")
    assert has_element?(view, "input[name='document[sumDphZakl]'][value='312.98']")
    assert has_element?(view, "input[name='document[datVyst]'][value='2026-10-31']")
    assert has_element?(view, "input[name='document[duzpUcto]'][value='2026-10-31']")
    assert has_element?(view, "input[name='document[datSplat]'][value='2026-11-23']")
  end

  test "source update preserves individual edits while filling the other fields", %{conn: conn} do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "pending.pdf", "zavazek", "header_form")

    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")

    render_change(view, "change", %{
      "document" =>
        Map.put(
          CozyCheckout.IncomingDocuments.HeaderForm.defaults(),
          "nazFirmy",
          "Ruční dodavatel"
        )
    })

    source = File.read!("test/fixtures/incoming_documents/o2_incomplete.json") |> Jason.decode!()
    doc |> Ecto.Changeset.change(state: "review", extracted_data: source) |> Repo.update!()
    send(view.pid, :refresh)
    render(view)
    assert has_element?(view, "input[name='document[nazFirmy]'][value='Ruční dodavatel']")
    assert has_element?(view, "input[name='document[sumDphZakl]'][value='312.98']")
  end

  test "date button uses the original when all dates in a saved draft are empty", %{conn: conn} do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "old.pdf", "zavazek", "header_form")

    source = File.read!("test/fixtures/incoming_documents/o2_incomplete.json") |> Jason.decode!()

    doc
    |> Ecto.Changeset.change(
      state: "review",
      extracted_data: source,
      current_xml: doc.template_xml
    )
    |> Repo.update!()

    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    view |> element("button[phx-click=prefill-dates]") |> render_click()
    assert has_element?(view, "input[name='document[datVyst]'][value='2026-10-31']")
    assert has_element?(view, "input[name='document[datSplat]'][value='2026-11-23']")
    view |> element("button[phx-click=prefill-vat]") |> render_click()
    assert has_element?(view, "input[name='document[sumZklZakl]'][value='1490.36']")
    assert IncomingDocuments.get!(doc.id).current_xml == doc.template_xml
  end

  test "supplier instructions can be saved on a sent manual document without changing it or invoking AI",
       %{conn: conn} do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())

    doc =
      doc
      |> Ecto.Changeset.change(state: "sent", sent_xml: doc.current_xml, remote_id: "42")
      |> Repo.update!()

    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    assert has_element?(view, "#incoming-supplier")
    refute has_element?(view, "button[phx-click=content-retry]")

    params = %{
      "supplier" => %{
        "profile_id" => "",
        "identity_kind" => "ic",
        "name" => "PENNY MARKET",
        "ic" => "64945880",
        "dic" => "CZ64945880",
        "country_code" => "CZ",
        "instructions" => "<script>test</script>"
      }
    }

    html =
      view |> form("#supplier-instructions-form", params) |> render_submit(%{"action" => "save"})

    assert html =~ "Instrukce uloženy pro příště"
    assert html =~ "&lt;script&gt;test&lt;/script&gt;"
    assert IncomingDocuments.get!(doc.id) == doc
    [profile] = IncomingDocuments.supplier_profiles(doc.id)
    assert profile.revision == 1
    assert IncomingDocuments.list_extraction_runs(doc.id) == []
  end

  test "supplier editor detects a stale revision and preserves unsaved header edits", %{
    conn: conn
  } do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())

    supplier = %{
      "name" => "PENNY",
      "ic" => "64945880",
      "dic" => "CZ64945880",
      "country_code" => "CZ",
      "identity_kind" => "ic",
      "instructions" => "První revize"
    }

    {:ok, profile} =
      IncomingDocuments.save_supplier_instructions(doc.id, nil, supplier, nil, true)

    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    view |> element("input[phx-focus=supplier-open]") |> render_focus()

    view |> element("#supplier_profile_id-option-#{profile.id}") |> render_click()

    view
    |> form("#incoming-header-form", %{
      "document" => Map.put(attrs(), "nazFirmy", "Neuložená změna")
    })
    |> render_change()

    assert {:ok, _} =
             IncomingDocuments.save_supplier_instructions(
               doc.id,
               profile.id,
               Map.put(supplier, "instructions", "Druhé okno"),
               1,
               true
             )

    params =
      Map.merge(supplier, %{
        "profile_id" => profile.id,
        "instructions" => "Moje změna"
      })

    html =
      view
      |> form("#supplier-instructions-form", %{"supplier" => params})
      |> render_submit(%{"action" => "save"})

    assert html =~ "Instrukce mezitím někdo změnil"
    assert has_element?(view, "input[name='document[nazFirmy]'][value='Neuložená změna']")
    view |> element("button[phx-click=supplier-reload]") |> render_click()
    assert render(view) =~ "Druhé okno"
  end

  test "document disclosures preserve browser-controlled open state while editor and polling update content",
       %{conn: conn} do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "receipt.pdf", "zavazek", "header_form")

    data = File.read!("test/fixtures/incoming_documents/penny.json") |> Jason.decode!()

    doc
    |> Ecto.Changeset.change(
      state: "review",
      extracted_data: data,
      dry_run: %{"http_status" => 200},
      response: %{"http_status" => 500}
    )
    |> Repo.update!()

    {:ok, view, html} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")

    selectors = [
      "#incoming-source-vat",
      "#incoming-supplier",
      "#incoming-used-instructions",
      "#extraction-history",
      "#extraction-run-instructions-#{doc.active_extraction_run_id}",
      "details[data-abra-response]",
      "details[data-abra-response] > details"
    ]

    ids = assert_client_disclosures(html, selectors)
    instructions = "Nové instrukce během psaní"

    html =
      view
      |> form("#supplier-instructions-form", %{"supplier" => %{"instructions" => instructions}})
      |> render_change()

    assert html =~ instructions
    assert html =~ "Instrukce mají neuložené změny"
    assert assert_client_disclosures(html, selectors) == ids
    send(view.pid, :refresh)
    html = render(view)
    assert html =~ instructions
    assert assert_client_disclosures(html, selectors) == ids
  end

  test "item extraction defaults off and the checkbox affects only a newly requested run", %{
    conn: conn
  } do
    {:ok, new_view, _} = live(admin(conn), "/admin/incoming-document-form")

    refute has_element?(
             new_view,
             "#incoming-extraction-options input[name=include_items][type=checkbox][checked]"
           )

    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "receipt.pdf", "zavazek", "header_form")

    CozyCheckout.IncomingDocuments.ExtractionRuns.interrupt(doc.id, doc.active_extraction_run_id)
    {:ok, view, _} = live(admin(build_conn()), "/admin/incoming-document-form/#{doc.id}")
    view |> form("#incoming-extraction-options", %{"include_items" => "true"}) |> render_change()

    assert has_element?(
             view,
             "#incoming-extraction-options input[name=include_items][type=checkbox][checked]"
           )

    view |> element("button[phx-click=generic-extract]") |> render_click()
    queued = IncomingDocuments.get!(doc.id)
    assert queued.extraction_metadata["include_items"] == true
    run = IncomingDocuments.active_extraction_run(queued)
    assert Map.has_key?(run.schemas["content"]["properties"], "items")
    view |> form("#incoming-extraction-options", %{"include_items" => "false"}) |> render_change()
    send(view.pid, :refresh)
    render(view)

    refute has_element?(
             view,
             "#incoming-extraction-options input[name=include_items][type=checkbox][checked]"
           )

    assert IncomingDocuments.active_extraction_run(queued).schemas == run.schemas
  end

  test "focused answer and quoted source are visible without losing disclosure state", %{
    conn: conn
  } do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "receipt.pdf", "zavazek", "header_form")

    data = File.read!("test/fixtures/incoming_documents/penny.json") |> Jason.decode!()

    result = %{
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

    run = IncomingDocuments.active_extraction_run(doc)

    run
    |> Ecto.Changeset.change(
      state: "completed",
      active_step: "done",
      supplier_instructions: "Přečti pouze EV-Č",
      supplier_task_result: result,
      supplier_task: %{"state" => "completed", "usage" => %{"input_tokens" => 123}}
    )
    |> Repo.update!()

    doc |> Ecto.Changeset.change(state: "review", extracted_data: data) |> Repo.update!()
    {:ok, view, html} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    assert html =~ "Samostatné dodavatelské instrukce"
    assert html =~ "EV-č: 0052-20261105-01-0039"
    assert has_element?(view, "input[name='document[cisDosle]'][value='0052-20261105-01-0039']")
    assert_client_disclosures(html, ["#incoming-supplier-task-result"])
  end

  defp assert_client_disclosures(html, selectors) do
    tree = LazyHTML.from_fragment(html)

    Enum.flat_map(selectors, fn selector ->
      nodes = LazyHTML.query(tree, selector)
      refute Enum.empty?(nodes)

      Enum.map(nodes, fn node ->
        [id] = LazyHTML.attribute(node, "id")
        [mounted] = LazyHTML.attribute(node, "phx-mounted")
        assert Jason.decode!(mounted) == [["ignore_attrs", %{"attrs" => ["open"]}]]
        # Only the native open attribute is ignored; dynamic children must still patch.
        assert LazyHTML.attribute(node, "phx-update") == []
        id
      end)
    end)
  end

  test "a source attachment can be retried on a sent document without another accounting send", %{
    conn: conn
  } do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())
    bytes = "%PDF-source"

    doc =
      doc
      |> Ecto.Changeset.change(
        state: "sent",
        remote_id: "42",
        sent_xml: doc.current_xml,
        original: bytes,
        content_type: "application/pdf",
        sha256: IncomingDocuments.digest(bytes),
        source_attachment: %{"state" => "failed", "error" => "Attachment permission denied"}
      )
      |> Repo.update!()

    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    assert has_element?(view, "#incoming-source-attachment", "Attachment permission denied")
    view |> element("button[phx-click=source-attachment-retry]") |> render_click()
    queued = IncomingDocuments.get!(doc.id)
    assert queued.source_attachment["state"] == "queued"
    assert queued.state == "sent"
    assert queued.sent_xml == doc.sent_xml
    refute has_element?(view, "#incoming-send")

    queued
    |> Ecto.Changeset.change(
      source_attachment: Map.put(queued.source_attachment, "state", "uploaded")
    )
    |> Repo.update!()

    send(view.pid, :refresh)
    assert render(view) =~ "Obrázek / PDF je přiložený a jeho obsah byl ověřen"
  end

  test "review actions stay together, mobile preview preserves edits and invalid send saves nothing",
       %{conn: conn} do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())

    doc =
      doc
      |> Ecto.Changeset.change(
        original: "%PDF-preview",
        content_type: "application/pdf",
        sha256: IncomingDocuments.digest("%PDF-preview")
      )
      |> Repo.update!()

    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-form/#{doc.id}")
    assert has_element?(view, "#incoming-actions button[phx-click=workflow-save]")
    assert has_element?(view, "#incoming-actions button[phx-click=send-next]")
    refute has_element?(view, "#incoming-advanced[open]")
    assert has_element?(view, "#incoming-advanced #incoming-validate")

    view
    |> form("#incoming-header-form", document: %{cisDosle: "KEEP-ME", sumCelkem: "1"})
    |> render_change()

    view |> element("button[phx-value-view=original]") |> render_click()
    assert has_element?(view, "#incoming-header-form.hidden")
    view |> element("button[phx-value-view=form]") |> render_click()
    assert has_element?(view, "input[name='document[cisDosle]'][value=KEEP-ME]")
    view |> element("button[phx-click=send-next]") |> render_click()
    assert has_element?(view, "#incoming-actions [role=alert]")
    assert IncomingDocuments.get!(doc.id).current_xml == doc.current_xml
    assert IncomingDocuments.get!(doc.id).sent_xml == nil
  end
end

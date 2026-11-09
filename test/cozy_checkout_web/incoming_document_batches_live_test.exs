defmodule CozyCheckoutWeb.IncomingDocumentBatchesLiveTest do
  use CozyCheckoutWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CozyCheckout.{IncomingDocuments, Repo}
  alias CozyCheckout.IncomingDocuments.{Batches, ExtractionRun}
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
      password: "test",
      openai_api_key: "test",
      openai_model: "test-model"
    )

    on_exit(fn ->
      Req.default_options(req_options)
      Application.put_env(:cozy_checkout, :incoming_documents, previous)

      if pin,
        do: Application.put_env(:cozy_checkout, :admin_pin_hash, pin),
        else: Application.delete_env(:cozy_checkout, :admin_pin_hash)
    end)

    :ok
  end

  defp admin(conn),
    do:
      Plug.Test.init_test_session(conn, %{AdminAuth.session_key() => System.system_time(:second)})

  defp batch do
    {:ok, batch} = Batches.create(%{"agenda" => "zavazek", "name" => "Kartou test"})
    batch
  end

  defp source(batch, content) do
    {:ok, %{id: id}} = Batches.add_source(batch.id, content, "synthetic.pdf")
    id
  end

  defp ready(batch, ids) do
    Batches.start(batch.id)

    Enum.each(ids, fn id ->
      doc = IncomingDocuments.get!(id)

      Repo.get!(ExtractionRun, doc.initial_extraction_run_id)
      |> Ecto.Changeset.change(state: "failed")
      |> Repo.update!()

      doc
      |> Ecto.Changeset.change(
        state: "failed",
        error_stage: "extraction",
        error: "Synthetic failure"
      )
      |> Repo.update!()
    end)

    Batches.refresh(batch.id)
  end

  test "PIN protects batch routes", %{conn: conn} do
    for path <- ["/admin/incoming-document-batches", "/admin/incoming-document-batches/new"] do
      assert redirected_to(get(conn, path)) == "/admin/login"
    end
  end

  test "create batch and persist uploads without extraction; refresh preserves sources", %{
    conn: conn
  } do
    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-batches/new")

    {:error, {:live_redirect, %{to: path}}} =
      view |> form("#batch-create", batch: %{agenda: "zavazek", name: "Pilot"}) |> render_submit()

    {:ok, view, _} = live(admin(build_conn()), path)

    upload =
      file_input(view, "#batch-upload", :sources, [
        %{name: "one.pdf", content: "%PDF-synthetic", type: "application/pdf"}
      ])

    render_upload(upload, "one.pdf")
    assert render(view) =~ "one.pdf"
    assert has_element?(view, "#batch-camera[capture=environment][accept='image/*']")
    assert has_element?(view, "label[for=batch-camera]", "Vyfotit doklad")
    render_hook(view, "upload-queue", %{"names" => [], "preparing" => true})
    render_click(view, "start")
    assert is_nil(Batches.get!(String.split(path, "/") |> List.last()).started_at)
    assert has_element?(view, "#batch-start[disabled]")
    render_hook(view, "upload-queue", %{"names" => [], "preparing" => false})
    assert Repo.aggregate(ExtractionRun, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0
    {:ok, refreshed, _} = live(admin(build_conn()), path)
    assert has_element?(refreshed, "#batch-documents", "one.pdf")
    refreshed |> element("#batch-start") |> render_click()
    assert Repo.aggregate(ExtractionRun, :count) == 1
    refute has_element?(refreshed, "#batch-upload")
  end

  test "searched accounting preset replaces the query and remains selected after polling and saving",
       %{conn: conn} do
    batch = batch()

    target = %{
      "kod" => "2.NÁKUP POTRAVINY",
      "nazev" => "Nákup potravin",
      "modulZav" => true,
      "protiUcetVydej" => "code:501100"
    }

    rows =
      Enum.map(1..35, &%{"kod" => "TEST#{&1}", "nazev" => "Předpis #{&1}", "modulZav" => true}) ++
        [target]

    for _ <- 1..2 do
      Req.Test.expect(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"winstrom" => %{"predpis-zauctovani" => rows}})
      end)
    end

    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-batches/#{batch.id}")
    view |> element("button[phx-click=accounting-load]") |> render_click()
    refute has_element?(view, "button[phx-value-id='2.NÁKUP POTRAVINY']")
    render_change(view, "accounting-search", %{"accounting_search" => %{"0" => "potrav"}})
    view |> element("button[phx-value-id='2.NÁKUP POTRAVINY']") |> render_click()
    assert has_element?(view, "#fields_preset-search[value='2.NÁKUP POTRAVINY — Nákup potravin']")
    refute has_element?(view, "#fields_preset-options")
    send(view.pid, :refresh)
    assert has_element?(view, "#fields_preset-search[value='2.NÁKUP POTRAVINY — Nákup potravin']")
    render_click(view, "settings-save")
    assert Batches.get!(batch.id).accounting_settings["typUcOp"] == "code:2.NÁKUP POTRAVINY"
    assert Batches.get!(batch.id).accounting_settings["protiUcet"] == "code:501100"
    render_click(view, "accounting-select", %{"id" => "unlisted"})
    assert has_element?(view, "#fields_preset-search[value='2.NÁKUP POTRAVINY — Nákup potravin']")
    render_change(view, "accounting-search", %{"accounting_search" => %{"0" => "TEST35"}})
    assert has_element?(view, "#fields_preset-options button[phx-value-id=TEST35]")
    view |> element("button[phx-value-id=TEST35]") |> render_click()
    assert has_element?(view, "#fields_preset-search[value='TEST35 — Předpis 35']")
  end

  test "readiness and membership are checked on the server; direct staged details redirect", %{
    conn: conn
  } do
    batch = batch()
    id = source(batch, "%PDF-one")

    assert_error_sent 404, fn ->
      live(admin(conn), "/admin/incoming-document-batches/#{batch.id}/review/#{id}")
    end

    assert {:error, {kind, %{to: path}}} =
             live(admin(build_conn()), "/admin/incoming-document-form/#{id}")

    assert kind in [:redirect, :live_redirect]
    assert path == "/admin/incoming-document-batches/#{batch.id}"
    ready(batch, [id])
    other = source(batch(), "%PDF-other")

    assert_error_sent 404, fn ->
      live(admin(build_conn()), "/admin/incoming-document-batches/#{batch.id}/review/#{other}")
    end

    {:ok, review, _} =
      live(admin(build_conn()), "/admin/incoming-document-batches/#{batch.id}/review/#{id}")

    assert has_element?(review, "#batch-review", "1 z 1")
    assert has_element?(review, "#incoming-header-form")
  end

  test "navigation protects unsaved edits and deferral survives returning", %{conn: conn} do
    batch = batch()
    one = source(batch, "%PDF-one")
    two = source(batch, "%PDF-two")
    ready(batch, [one, two])

    {:ok, view, _} =
      live(admin(conn), "/admin/incoming-document-batches/#{batch.id}/review/#{one}")

    view
    |> form("#incoming-header-form", document: %{nazFirmy: "Unsaved supplier"})
    |> render_change()

    view
    |> element("button[phx-click=review-move][phx-value-id='#{two}']", "Další")
    |> render_click()

    assert has_element?(view, "[role=dialog]", "Neuložené")
    view |> element("button[phx-click=review-stay]") |> render_click()
    assert has_element?(view, "input[name='document[nazFirmy]'][value='Unsaved supplier']")

    view
    |> element("button[phx-click=review-move][phx-value-id='#{two}']", "Další")
    |> render_click()

    view |> element("button[phx-click=review-discard]") |> render_click()
    assert_patch(view, "/admin/incoming-document-batches/#{batch.id}/review/#{two}")
    view |> element("button[phx-click=review-defer]") |> render_click()
    assert IncomingDocuments.get!(two).deferred_at
    assert_patch(view, "/admin/incoming-document-batches/#{batch.id}/review/#{one}")
    {:ok, index, _} = live(admin(build_conn()), "/admin/incoming-documents")
    assert render(index) =~ "Kartou test"
    assert render(index) =~ "připravena ke kontrole"
  end

  test "failed-only batch presents errors and retry does not remove the completion notice", %{
    conn: conn
  } do
    batch = batch()
    id = source(batch, "%PDF-failure")
    ready(batch, [id])
    {:ok, view, _} = live(admin(conn), "/admin/incoming-document-batches/#{batch.id}")
    assert render(view) =~ "Vytěžení všech dokladů selhalo"
    assert render(view) =~ "Synthetic failure"
    assert {:ok, _} = IncomingDocuments.retry_extraction(id, "header_form")
    send(view.pid, :refresh)
    assert render(view) =~ "Zkontrolovat doklady"
  end

  test "send-and-continue advances only on confirmed sent and uncertainty only verifies", %{
    conn: conn
  } do
    batch = batch()
    one = source(batch, "%PDF-send-one")
    two = source(batch, "%PDF-send-two")
    ready(batch, [one, two])

    attrs = %{
      "nazFirmy" => "Test",
      "cisDosle" => "R42",
      "datVyst" => "2026-11-05",
      "datSplat" => "2026-11-05",
      "sumOsv" => "123.45",
      "sumCelkem" => "123.45"
    }

    doc = IncomingDocuments.get!(one)

    assert {:ok, _} =
             IncomingDocuments.save_header(
               one,
               attrs,
               IncomingDocuments.transcription_hash(doc),
               true
             )

    {:ok, view, _} =
      live(admin(conn), "/admin/incoming-document-batches/#{batch.id}/review/#{one}")

    view |> form("#incoming-header-form", document: %{cisDosle: "R42-EDIT"}) |> render_change()
    view |> element("button[phx-click=send-next]") |> render_click()
    assert IncomingDocuments.get!(one).sent_xml =~ "R42-EDIT"
    assert IncomingDocuments.get!(one).state == "sending"
    refute has_element?(view, "#batch-review", "2 z 2")
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "<html>unknown</html>")
    end)

    IncomingDocuments.perform(one, "send")
    send(view.pid, :refresh)
    assert render(view) =~ "Nutno ověřit v ABRA"
    assert has_element?(view, "#batch-review", "1 z 2")

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      Req.Test.json(conn, %{"winstrom" => %{"zavazek" => [%{"id" => 42}]}})
    end)

    view |> element("button[phx-click=verify]") |> render_click()
    IncomingDocuments.perform(one, "send")
    send(view.pid, :refresh)
    # A previous uncertain send stopped auto-navigation. Verification remains
    # explicit; retrying send-next on the sent document cannot create a POST.
    assert render(view) =~ "Odesláno"
    assert IncomingDocuments.get!(one).state == "sent"
    refute has_element?(view, "button[phx-click=send-next]")

    # The normal confirmed path keeps the intent to advance until sent.
    doc = IncomingDocuments.get!(two)

    assert {:ok, _} =
             IncomingDocuments.save_header(
               two,
               Map.put(attrs, "cisDosle", "R43"),
               IncomingDocuments.transcription_hash(doc),
               true
             )

    {:ok, second_view, _} =
      live(admin(build_conn()), "/admin/incoming-document-batches/#{batch.id}/review/#{two}")

    second_view |> element("button[phx-click=send-next]") |> render_click()
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"success" => true, "results" => [%{"id" => 43}]}})
    end)

    IncomingDocuments.perform(two, "send")
    send(second_view.pid, :refresh)
    assert_redirect(second_view, "/admin/incoming-document-batches/#{batch.id}")
  end
end

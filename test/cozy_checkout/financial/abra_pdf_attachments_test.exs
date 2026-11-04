defmodule CozyCheckout.AbraPdfAttachmentsTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import CozyCheckout.BillingFixtures
  use Oban.Testing, repo: CozyCheckout.Repo
  alias CozyCheckout.Abra.{AccommodationExport, PdfAttachments, PdfClient, PdfTransfer}
  alias CozyCheckout.Workers.AbraPdfWorker

  setup do
    old_pdf = Application.get_env(:cozy_checkout, :abra_pdf)
    old_cfg = Application.get_env(:cozy_checkout, :abra_accommodation)
    old_req = Req.default_options()

    cfg = [
      base_url: "https://accounting.test",
      company_id: "test",
      username: "test-user",
      password: "test-password",
      enabled: false
    ]

    Application.put_env(:cozy_checkout, :abra_accommodation, cfg)
    Application.put_env(:cozy_checkout, :abra_pdf, enabled: true)
    Req.default_options(plug: {Req.Test, PdfClient})
    Req.Test.verify_on_exit!()

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :abra_pdf, old_pdf)
      Application.put_env(:cozy_checkout, :abra_accommodation, old_cfg)
      Req.default_options(old_req)
    end)

    %{booking: booking} = billing_fixture()
    doc = issue_without_abra!(booking, "advance", %{"amount" => "1000"})
    bytes = "%PDF-1.4 immutable issued PDF"
    doc = doc |> Ecto.Changeset.change(pdf: bytes) |> Repo.update!()

    export =
      Repo.insert!(%AccommodationExport{
        document_id: doc.id,
        base_url: cfg[:base_url],
        company_id: cfg[:company_id],
        external_id: "ext:test:#{doc.id}",
        payload: %{},
        remote_id: "42",
        state: "synced",
        synced_at: DateTime.utc_now(:second)
      })

    %{
      doc: doc,
      export: export,
      bytes: bytes,
      cfg: cfg,
      filename: "#{doc.number}.pdf"
    }
  end

  test "an explicit advance update replaces only the previously verified PDF attachment", ctx do
    ctx.export
    |> Ecto.Changeset.change(verification: %{"advance_update" => true})
    |> Repo.update!()

    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    old_bytes = "%PDF previous advance"
    transfer |> Ecto.Changeset.change(sha256: digest(old_bytes)) |> Repo.update!()
    expect_list([%{"id" => 7, "nazSoub" => ctx.filename}])
    expect_content(old_bytes)

    Req.Test.expect(PdfClient, fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/c/test/faktura-vydana/42/prilohy/7.json"
      Plug.Conn.send_resp(conn, 200, "")
    end)

    Req.Test.expect(PdfClient, fn conn ->
      assert conn.method == "PUT"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body == ctx.bytes
      Plug.Conn.send_resp(conn, 201, "")
    end)

    expect_list([%{"id" => 7, "nazSoub" => ctx.filename}])
    expect_content(ctx.bytes)
    assert :ok = PdfAttachments.deliver(transfer.id)
    assert PdfAttachments.status(ctx.doc.id).sha256 == digest(ctx.bytes)
  end

  test "an advance update cannot replace an attachment whose previous checksum does not match",
       ctx do
    ctx.export
    |> Ecto.Changeset.change(verification: %{"advance_update" => true})
    |> Repo.update!()

    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    transfer |> Ecto.Changeset.change(sha256: digest("previous")) |> Repo.update!()
    expect_list([%{"id" => 7, "nazSoub" => ctx.filename}])
    expect_content("unrelated PDF")
    assert {:error, "Obsah PDF přílohy v ABRA nesouhlasí"} = PdfAttachments.deliver(transfer.id)
  end

  test "uploads original bytes, verifies content and never changes the accounting export", ctx do
    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    expect_list([])

    Req.Test.expect(PdfClient, fn conn ->
      assert conn.method == "PUT"
      assert conn.request_path == "/c/test/faktura-vydana/42/prilohy/new/#{ctx.filename}"
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/pdf"]

      assert Plug.Conn.get_req_header(conn, "authorization") ==
               ["Basic " <> Base.encode64("test-user:test-password")]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body == ctx.bytes
      Plug.Conn.send_resp(conn, 201, "")
    end)

    expect_list([%{"id" => 7, "nazSoub" => ctx.filename}])
    expect_content(ctx.bytes)
    assert :ok = PdfAttachments.deliver(transfer.id)
    assert %{state: "uploaded", sha256: hash} = PdfAttachments.status(ctx.doc.id)
    assert hash == digest(ctx.bytes)
    assert Repo.get!(AccommodationExport, ctx.export.id) == ctx.export
    assert :ok = PdfAttachments.deliver(transfer.id)
    assert {:ok, %{state: "uploaded"}} = PdfAttachments.enqueue(ctx.doc.id)
  end

  test "recognizes the old UUID and hash filename after a lost upload response", ctx do
    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    legacy_filename = "cozy-#{ctx.doc.id}-#{digest(ctx.bytes)}.pdf"
    expect_list([%{"id" => 7, "nazSoub" => legacy_filename}])
    expect_content(ctx.bytes)

    assert :ok = PdfAttachments.deliver(transfer.id)
    assert PdfAttachments.status(ctx.doc.id).state == "uploaded"
    assert Repo.get!(AccommodationExport, ctx.export.id) == ctx.export
  end

  test "legacy filenames still require matching PDF content", ctx do
    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    legacy_filename = "cozy-#{ctx.doc.id}-#{digest(ctx.bytes)}.pdf"
    expect_list([%{"id" => 7, "nazSoub" => legacy_filename}])
    expect_content("different bytes")

    assert {:error, "Obsah PDF přílohy v ABRA nesouhlasí"} = PdfAttachments.deliver(transfer.id)
    assert PdfAttachments.status(ctx.doc.id).state == "failed"
  end

  test "reconciles a timed out upload before retrying; does not PUT a duplicate", ctx do
    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    expect_list([])
    Req.Test.expect(PdfClient, fn conn -> Req.Test.transport_error(conn, :timeout) end)
    assert {:error, _} = PdfAttachments.deliver(transfer.id)
    assert PdfAttachments.status(ctx.doc.id).state == "failed"
    expect_list([%{"id" => 7, "nazSoub" => ctx.filename}])
    expect_content(ctx.bytes)
    assert :ok = PdfAttachments.deliver(transfer.id)
    assert Repo.get!(AccommodationExport, ctx.export.id) == ctx.export
  end

  test "a different file with the same name is an error, never overwritten", ctx do
    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    expect_list([%{"id" => 7, "nazSoub" => ctx.filename}])
    expect_content("different bytes")
    assert {:error, "Obsah PDF přílohy v ABRA nesouhlasí"} = PdfAttachments.deliver(transfer.id)
    assert Repo.get!(AccommodationExport, ctx.export.id) == ctx.export
  end

  test "listing failures never trigger upload and manual retry preserves one intent", ctx do
    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    Req.Test.expect(PdfClient, fn conn -> Plug.Conn.send_resp(conn, 403, "denied") end)
    assert {:error, _} = PdfAttachments.deliver(transfer.id)
    assert {:ok, retried} = PdfAttachments.enqueue(ctx.doc.id)
    assert retried.id == transfer.id
    assert Repo.aggregate(PdfTransfer, :count) == 1
  end

  test "disabled switch and changed target prevent all HTTP", ctx do
    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    Application.put_env(:cozy_checkout, :abra_pdf, enabled: false)
    assert {:error, _} = PdfAttachments.enqueue(ctx.doc.id)
    assert {:snooze, 60} = PdfAttachments.deliver(transfer.id)
    Application.put_env(:cozy_checkout, :abra_pdf, enabled: true)

    Application.put_env(
      :cozy_checkout,
      :abra_accommodation,
      Keyword.put(ctx.cfg, :company_id, "other")
    )

    assert {:error, _} = PdfAttachments.deliver(transfer.id)
    assert Repo.get!(AccommodationExport, ctx.export.id) == ctx.export
  end

  test "malformed attachment listings fail closed without uploading", ctx do
    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    expect_list([%{"unexpected" => "response"}])
    assert {:error, "ABRA PDF: neplatný seznam příloh"} = PdfAttachments.deliver(transfer.id)
  end

  test "does not queue unsynchronized documents", ctx do
    ctx.export |> Ecto.Changeset.change(state: "failed") |> Repo.update!()
    assert {:error, _} = PdfAttachments.enqueue(ctx.doc.id)
    assert PdfAttachments.status(ctx.doc.id) == nil
  end

  test "automatic scan only requires the enabled switch and includes historical exports", ctx do
    ctx.export
    |> Ecto.Changeset.change(synced_at: ~U[2020-01-01 00:00:00Z])
    |> Repo.update!()

    Application.put_env(:cozy_checkout, :abra_pdf, enabled: false)
    assert :ok = PdfAttachments.scan()
    assert PdfAttachments.status(ctx.doc.id) == nil

    Application.put_env(:cozy_checkout, :abra_pdf, enabled: true)
    assert :ok = PdfAttachments.scan()
    assert :ok = PdfAttachments.scan()
    transfer = PdfAttachments.status(ctx.doc.id)
    assert transfer.state == "queued"
    assert_enqueued(worker: AbraPdfWorker, args: %{transfer_id: transfer.id})
    assert Repo.aggregate(PdfTransfer, :count) == 1
  end

  test "reads further pages before deciding the attachment is absent", ctx do
    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    expect_list(for i <- 1..100, do: %{"id" => i, "nazSoub" => "unrelated-#{i}.pdf"})

    Req.Test.expect(PdfClient, fn conn ->
      assert Plug.Conn.fetch_query_params(conn).query_params["start"] == "100"

      Req.Test.json(conn, %{
        "winstrom" => %{"priloha" => [%{"id" => 7, "nazSoub" => ctx.filename}]}
      })
    end)

    expect_content(ctx.bytes)
    assert :ok = PdfAttachments.deliver(transfer.id)
  end

  test "supports final invoices through the same attachment path", ctx do
    ctx.doc |> Ecto.Changeset.change(kind: "final") |> Repo.update!()
    {:ok, transfer} = PdfAttachments.enqueue(ctx.doc.id)
    expect_list([%{"id" => 7, "nazSoub" => ctx.filename}])
    expect_content(ctx.bytes)
    assert :ok = PdfAttachments.deliver(transfer.id)
  end

  defp expect_list(rows) do
    Req.Test.expect(PdfClient, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/c/test/faktura-vydana/42/prilohy.json"
      Req.Test.json(conn, %{"winstrom" => %{"priloha" => rows}})
    end)
  end

  defp expect_content(bytes) do
    Req.Test.expect(PdfClient, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/c/test/faktura-vydana/42/prilohy/7/content"

      conn
      |> Plug.Conn.put_resp_content_type("application/pdf")
      |> Plug.Conn.send_resp(200, bytes)
    end)
  end

  defp digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end

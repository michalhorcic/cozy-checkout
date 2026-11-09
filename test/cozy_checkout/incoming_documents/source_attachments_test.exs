defmodule CozyCheckout.IncomingDocuments.SourceAttachmentsTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  alias CozyCheckout.{IncomingDocuments, Repo}
  alias CozyCheckout.IncomingDocuments.{Document, SourceAttachments, XML}
  alias CozyCheckout.Workers.IncomingDocumentAttachmentWorker

  setup do
    previous = IncomingDocuments.config()
    req = Req.default_options()

    Application.put_env(:cozy_checkout, :incoming_documents,
      enabled: true,
      base_url: "https://accounting.test/",
      company_id: "pilot",
      username: "test",
      password: "test"
    )

    Req.default_options(plug: {Req.Test, __MODULE__})
    Req.Test.verify_on_exit!()

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :incoming_documents, previous)
      Req.default_options(req)
    end)

    :ok
  end

  defp document(agenda \\ "zavazek", mime \\ "application/pdf", bytes \\ "%PDF-source") do
    id = Ecto.UUID.generate()

    Repo.insert!(%Document{
      id: id,
      agenda: agenda,
      state: "sent",
      remote_id: "42",
      filename: "source",
      content_type: mime,
      original: bytes,
      sha256: IncomingDocuments.digest(bytes),
      base_url: "https://accounting.test/",
      company_id: "pilot",
      external_id: "ext:cozy-incoming:#{id}",
      template_xml: XML.template(agenda),
      sent_xml: XML.template(agenda)
    })
  end

  defp job(doc) do
    Repo.one!(
      from j in Oban.Job,
        where:
          j.worker == "CozyCheckout.Workers.IncomingDocumentAttachmentWorker" and
            fragment("?->>'delivery_id'", j.args) == ^doc.source_attachment["delivery_id"]
    )
    |> Map.put(:attempt, 1)
  end

  defp list(rows) do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert String.ends_with?(conn.request_path, "/prilohy.json")
      Req.Test.json(conn, %{"winstrom" => %{"priloha" => rows}})
    end)
  end

  defp content(bytes) do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert String.ends_with?(conn.request_path, "/prilohy/7/content")
      Plug.Conn.send_resp(conn, 200, bytes)
    end)
  end

  defp row(doc), do: %{"id" => 7, "nazSoub" => doc.source_attachment["filename"]}

  test "all incoming agendas upload exact stored PDF/JPEG/PNG bytes and verify content" do
    for {agenda, mime, bytes, extension} <- [
          {"faktura-prijata", "application/pdf", "%PDF-source", ".pdf"},
          {"pokladni-pohyb", "image/jpeg", <<255, 216, 255, 1, 2>>, ".jpg"},
          {"zavazek", "image/png", <<137, 80, 78, 71, 13, 10, 26, 10, 1>>, ".png"}
        ] do
      doc = document(agenda, mime, bytes)
      {:ok, queued} = SourceAttachments.enqueue(doc.id)
      assert String.ends_with?(queued.source_attachment["filename"], extension)
      assert {:ok, again} = SourceAttachments.enqueue(doc.id)
      assert again.source_attachment == queued.source_attachment
      job = job(queued)
      list([])

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "PUT"

        assert conn.request_path ==
                 "/c/pilot/#{agenda}/42/prilohy/new/#{queued.source_attachment["filename"]}"

        assert Plug.Conn.get_req_header(conn, "content-type") == [mime]
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body == bytes
        # A concurrent duplicate delivery cannot reserve or send another PUT.
        assert :ok = SourceAttachments.deliver(job)
        Plug.Conn.send_resp(conn, 201, "")
      end)

      list([row(queued)])
      content(bytes)
      assert :ok = SourceAttachments.deliver(job)
      result = IncomingDocuments.get!(doc.id)
      assert result.source_attachment["state"] == "uploaded"
      assert result.sent_xml == doc.sent_xml
      assert result.state == "sent"
      assert :ok = SourceAttachments.deliver(job)
    end
  end

  test "lost upload response is reconciled by hash without another PUT" do
    doc = document()
    {:ok, queued} = SourceAttachments.enqueue(doc.id)
    job = job(queued)
    list([])

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "PUT"
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, _} = SourceAttachments.deliver(job)
    assert IncomingDocuments.get!(doc.id).source_attachment["upload_reserved"]
    list([row(queued)])
    content(doc.original)
    assert :ok = SourceAttachments.deliver(%{job | attempt: 2})
    assert IncomingDocuments.get!(doc.id).source_attachment["state"] == "uploaded"
  end

  test "uncertain absent upload is never silently repeated and explicit retry supersedes old jobs" do
    doc = document()
    {:ok, queued} = SourceAttachments.enqueue(doc.id)
    old_job = job(queued)
    list([])
    Req.Test.expect(__MODULE__, &Req.Test.transport_error(&1, :timeout))
    assert {:error, _} = SourceAttachments.deliver(old_job)
    list([])
    assert {:error, reason} = SourceAttachments.deliver(%{old_job | attempt: 2})
    assert reason =~ "Předchozí přenos"
    {:ok, retried} = SourceAttachments.enqueue(doc.id)
    assert retried.source_attachment["delivery_id"] != queued.source_attachment["delivery_id"]
    refute retried.source_attachment["upload_reserved"]
    assert :ok = SourceAttachments.deliver(%{old_job | attempt: 3})
    list([row(retried)])
    content(doc.original)
    assert :ok = SourceAttachments.deliver(job(retried))
  end

  test "different or ambiguous remote content is never replaced" do
    for multiple <- [false, true] do
      doc = document()
      {:ok, queued} = SourceAttachments.enqueue(doc.id)
      rows = if multiple, do: [row(queued), Map.put(row(queued), "id", 8)], else: [row(queued)]
      list(rows)
      unless multiple, do: content("unrelated source")
      assert {:error, _} = SourceAttachments.deliver(job(queued))
      assert IncomingDocuments.get!(doc.id).state == "sent"
      assert IncomingDocuments.get!(doc.id).sent_xml == doc.sent_xml
    end
  end

  test "duplicate attachment names on later pages fail closed" do
    doc = document()
    {:ok, queued} = SourceAttachments.enqueue(doc.id)
    fillers = Enum.map(1..99, &%{"id" => &1 + 100, "nazSoub" => "other#{&1}.pdf"})
    list([row(queued) | fillers])

    Req.Test.expect(__MODULE__, fn conn ->
      assert Plug.Conn.fetch_query_params(conn).query_params["start"] == "100"
      Req.Test.json(conn, %{"winstrom" => %{"priloha" => [Map.put(row(queued), "id", 8)]}})
    end)

    assert {:error, reason} = SourceAttachments.deliver(job(queued))
    assert reason =~ "nejednoznačnou"
  end

  test "target changes and changed source bytes block every external request" do
    doc = document()
    {:ok, queued} = SourceAttachments.enqueue(doc.id)
    cfg = IncomingDocuments.config()

    Application.put_env(
      :cozy_checkout,
      :incoming_documents,
      Keyword.put(cfg, :company_id, "other")
    )

    assert {:error, reason} = SourceAttachments.deliver(job(queued))
    assert reason =~ "Cílová firma"
    Application.put_env(:cozy_checkout, :incoming_documents, cfg)
    doc |> Ecto.Changeset.change(original: "changed") |> Repo.update!()
    assert {:error, reason} = SourceAttachments.deliver(%{job(queued) | attempt: 2})
    assert reason =~ "podklad se změnil"
  end

  test "manual documents without sources queue nothing and unsent documents are blocked" do
    doc = document()

    doc =
      doc
      |> Ecto.Changeset.change(original: nil, content_type: nil, sha256: nil)
      |> Repo.update!()

    assert {:ok, _} = SourceAttachments.enqueue(doc.id)
    assert Repo.aggregate(Oban.Job, :count) == 0
    other = document() |> Ecto.Changeset.change(state: "review", remote_id: nil) |> Repo.update!()
    assert {:error, _} = SourceAttachments.enqueue(other.id)
    assert Repo.aggregate(Oban.Job, :count) == 0
  end

  test "terminal jobs with unfinished transfers are recovered without network requests" do
    doc = document()
    {:ok, queued} = SourceAttachments.enqueue(doc.id)
    job = job(queued)

    Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
      set: [state: "cancelled", cancelled_at: DateTime.utc_now()]
    )

    assert :ok = SourceAttachments.reconcile()
    assert IncomingDocuments.get!(doc.id).source_attachment["state"] == "failed"
    assert IncomingDocuments.get!(doc.id).state == "sent"
  end

  test "worker records only a safe failure without exception bodies or source bytes" do
    doc = document()
    {:ok, queued} = SourceAttachments.enqueue(doc.id)
    list([])
    Req.Test.expect(__MODULE__, fn _ -> raise "private receipt or credentials" end)
    assert {:error, _} = IncomingDocumentAttachmentWorker.perform(job(queued))
    attachment = IncomingDocuments.get!(doc.id).source_attachment
    assert attachment["state"] == "failed"
    refute attachment["error"] =~ "private"
  end
end

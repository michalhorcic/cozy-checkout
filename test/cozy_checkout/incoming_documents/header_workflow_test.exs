defmodule CozyCheckout.IncomingDocuments.HeaderWorkflowTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  alias CozyCheckout.{IncomingDocuments, Repo}
  alias CozyCheckout.IncomingDocuments.{HeaderForm, XML}

  setup do
    previous = IncomingDocuments.config()
    req_options = Req.default_options()

    Application.put_env(:cozy_checkout, :incoming_documents,
      enabled: true,
      base_url: "https://accounting.test",
      company_id: "pilot",
      username: "test",
      password: "test",
      openai_api_key: "test",
      openai_model: "test"
    )

    Req.default_options(plug: {Req.Test, __MODULE__})
    Req.Test.verify_on_exit!()

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :incoming_documents, previous)
      Req.default_options(req_options)
    end)

    :ok
  end

  defp attrs,
    do: %{
      "nazFirmy" => "Dodavatel",
      "cisDosle" => "R42",
      "datVyst" => "2026-11-05",
      "datSplat" => "2026-11-05",
      "sumOsv" => "123,45",
      "sumCelkem" => "123,45"
    }

  test "manual document needs neither original nor model and remains protected by dry-run approval" do
    assert {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())
    assert doc.original == nil
    assert doc.state == "review"
    assert {:error, _} = IncomingDocuments.retry_extraction(doc.id)

    assert {:error, reason} =
             IncomingDocuments.approve(doc.id, IncomingDocuments.digest(doc.current_xml))

    assert reason =~ "kontrolu"
    assert {:ok, payload} = XML.import_xml(doc.current_xml, doc.agenda)
    assert payload == doc.current_xml
  end

  test "saving header invalidates validation and rejects stale edits and changes after send" do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())
    doc = doc |> Ecto.Changeset.change(dry_run: %{"ok" => true}) |> Repo.update!()
    hash = IncomingDocuments.transcription_hash(doc)

    assert {:ok, changed} =
             IncomingDocuments.save_header(doc.id, Map.put(attrs(), "cisDosle", "NEW"), hash)

    assert changed.dry_run == %{}
    assert {:error, _} = IncomingDocuments.save_header(doc.id, attrs(), hash)

    sent =
      changed
      |> Ecto.Changeset.change(sent_xml: changed.current_xml, state: "sending")
      |> Repo.update!()

    assert {:error, _} =
             IncomingDocuments.save_header(
               sent.id,
               attrs(),
               IncomingDocuments.transcription_hash(sent)
             )
  end

  test "dry-run validates the same item-free payload that approval freezes for sending" do
    {:ok, doc} =
      IncomingDocuments.create_header(
        "zavazek",
        Map.put(attrs(), "poznam", "Položky jen orientačně")
      )

    Req.Test.expect(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["dry-run"] == "true"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body == doc.current_xml
      refute body =~ "polozkyDokladu"
      assert body =~ "<poznam>Položky jen orientačně</poznam>"

      Req.Test.json(conn, %{
        "winstrom" => %{"success" => true, "results" => [%{"id" => "-1", "warnings" => []}]}
      })
    end)

    assert {:ok, _} =
             IncomingDocuments.validate(doc.id, IncomingDocuments.digest(doc.current_xml))

    assert :ok = IncomingDocuments.perform(doc.id, "validate")

    assert {:ok, approved} =
             IncomingDocuments.approve(doc.id, IncomingDocuments.digest(doc.current_xml))

    assert approved.state == "sending"
    assert approved.sent_xml == doc.current_xml
  end

  test "partial extraction produces editable suggestions without items, XML or automatic retries" do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "receipt.pdf", "pokladni-pohyb", "header_form")

    data = File.read!("test/fixtures/incoming_documents/penny.json") |> Jason.decode!()

    data = %{
      data
      | "document_number" => nil,
        "total" => nil,
        "items" => Enum.take(data["items"], 1),
        "complete" => false
    }

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      assert request["store"] == false
      assert request["instructions"] =~ "orientační text do poznámky"

      Req.Test.json(conn, %{
        "status" => "completed",
        "output" => [
          %{
            "type" => "message",
            "content" => [%{"type" => "output_text", "text" => Jason.encode!(data)}]
          }
        ]
      })
    end)

    IncomingDocuments.perform(doc.id, "extract")
    doc = IncomingDocuments.get!(doc.id)
    assert doc.state == "review"
    assert doc.extraction_attempts == 1
    assert doc.current_xml == nil
    assert doc.extracted_data["complete"] == false
    assert {:error, _} = IncomingDocuments.diagnostic_xml(doc)
    assert {:error, _} = IncomingDocuments.approve(doc.id, "anything")
    assert HeaderForm.values(doc)["poznam"] =~ "Orientační přepis"

    assert {:ok, saved} =
             IncomingDocuments.save_header(
               doc.id,
               attrs(),
               IncomingDocuments.transcription_hash(doc)
             )

    assert saved.current_xml =~ "<bezPolozek>true</bezPolozek>"
    refute saved.current_xml =~ "polozkyDokladu"
  end
end

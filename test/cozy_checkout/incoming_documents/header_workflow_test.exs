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

      assert {:ok, expected} =
               CozyCheckout.IncomingDocuments.ImportPayload.from_xml(doc.current_xml, doc)

      assert Jason.decode!(body) == expected
      [record] = Jason.decode!(body)["winstrom"][doc.agenda]
      refute Map.has_key?(record, "polozkyDokladu")
      assert record["poznam"] == "Položky jen orientačně"

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

  test "direct send after a FreeMarker dry-run freezes locally validated XML without another dry-run" do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())

    doc =
      doc
      |> Ecto.Changeset.change(
        dry_run: %{"http_status" => 500, "ok" => false, "raw_body" => "<html>FreeMarker</html>"}
      )
      |> Repo.update!()

    assert {:error, _} =
             IncomingDocuments.send_header(
               doc.id,
               IncomingDocuments.digest(doc.current_xml),
               false
             )

    assert {:error, _} = IncomingDocuments.send_header(doc.id, "stale", true)

    assert {:ok, approved} =
             IncomingDocuments.send_header(
               doc.id,
               IncomingDocuments.digest(doc.current_xml),
               true
             )

    assert approved.sent_xml == doc.current_xml
    assert approved.extraction_metadata["delivery"]["mode"] == "direct_header"

    assert {:error, _} =
             IncomingDocuments.send_header(
               doc.id,
               IncomingDocuments.digest(doc.current_xml),
               true
             )

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"

      assert conn.request_path =~ "ext:cozy-incoming:" or
               conn.request_path =~ "ext%3Acozy-incoming%3A"

      Plug.Conn.send_resp(conn, 404, "")
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/c/pilot/zavazek.json"
      refute Map.has_key?(Plug.Conn.fetch_query_params(conn).query_params, "dry-run")
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert {:ok, expected} =
               CozyCheckout.IncomingDocuments.ImportPayload.from_xml(approved.sent_xml, approved)

      assert Jason.decode!(body) == expected
      Req.Test.json(conn, %{"winstrom" => %{"success" => true, "results" => [%{"id" => "42"}]}})
    end)

    assert :ok = IncomingDocuments.perform(doc.id, "send")
    assert IncomingDocuments.get!(doc.id).state == "sent"
    assert IncomingDocuments.get!(doc.id).remote_id == "42"
    assert :ok = IncomingDocuments.perform(doc.id, "send")
  end

  test "direct send finds a manually imported external ID and performs no POST" do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())

    {:ok, _} =
      IncomingDocuments.send_header(doc.id, IncomingDocuments.digest(doc.current_xml), true)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      Req.Test.json(conn, %{"winstrom" => %{"zavazek" => [%{"id" => 88}]}})
    end)

    assert :ok = IncomingDocuments.perform(doc.id, "send")
    assert IncomingDocuments.get!(doc.id).state == "sent"
    assert IncomingDocuments.get!(doc.id).response["verified_by_external_id"] == true
  end

  test "HTML returned by a real import is uncertain and retries only look up the document" do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())

    {:ok, _} =
      IncomingDocuments.send_header(doc.id, IncomingDocuments.digest(doc.current_xml), true)

    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"

      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(500, "<html>FreeMarker template error!</html>")
    end)

    assert :ok = IncomingDocuments.perform(doc.id, "send")
    uncertain = IncomingDocuments.get!(doc.id)
    assert uncertain.state == "uncertain"
    assert uncertain.response["format_diagnostic"]["kind"] == "server_template_error"

    assert {:error, _} =
             IncomingDocuments.send_header(
               doc.id,
               IncomingDocuments.digest(doc.current_xml),
               true
             )

    assert {:error, _} =
             IncomingDocuments.save_header(
               doc.id,
               attrs(),
               IncomingDocuments.transcription_hash(uncertain)
             )

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      Req.Test.json(conn, %{"winstrom" => %{"zavazek" => [%{"id" => 99}]}})
    end)

    assert :ok = IncomingDocuments.perform(doc.id, "send")
    assert IncomingDocuments.get!(doc.id).state == "sent"
  end

  test "direct send revalidates local totals and target company" do
    {:ok, doc} = IncomingDocuments.create_header("zavazek", attrs())

    broken =
      doc
      |> Ecto.Changeset.change(
        current_xml:
          String.replace(
            doc.current_xml,
            "<sumCelkem>123.45</sumCelkem>",
            "<sumCelkem>1.00</sumCelkem>"
          )
      )
      |> Repo.update!()

    assert {:error, _} =
             IncomingDocuments.send_header(
               broken.id,
               IncomingDocuments.digest(broken.current_xml),
               true
             )

    wrong_target =
      broken
      |> Ecto.Changeset.change(current_xml: doc.current_xml, company_id: "other-company")
      |> Repo.update!()

    assert {:error, _} =
             IncomingDocuments.send_header(
               wrong_target.id,
               IncomingDocuments.digest(wrong_target.current_xml),
               true
             )
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
      Req.Test.json(conn, %{
        "status" => "completed",
        "output" => [
          %{
            "type" => "message",
            "content" => [
              %{
                "type" => "output_text",
                "text" =>
                  Jason.encode!(%{
                    "name" => nil,
                    "ic" => nil,
                    "dic" => nil,
                    "country_code" => nil,
                    "ambiguous" => false,
                    "uncertainties" => []
                  })
              }
            ]
          }
        ]
      })
    end)

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
    assert doc.extraction_attempts == 2
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

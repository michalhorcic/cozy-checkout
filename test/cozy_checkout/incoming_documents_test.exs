defmodule CozyCheckout.IncomingDocumentsTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  alias CozyCheckout.IncomingDocuments, as: Incoming
  alias CozyCheckout.IncomingDocuments.{Client, Extractor, XML}

  setup do
    old = Incoming.config()
    options = Req.default_options()

    Application.put_env(:cozy_checkout, :incoming_documents,
      enabled: true,
      base_url: "https://accounting.test",
      company_id: "pilot",
      username: "test",
      password: "test",
      openai_api_key: "test",
      openai_model: "test-vision"
    )

    Req.default_options(plug: {Req.Test, __MODULE__})
    Req.Test.verify_on_exit!()

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :incoming_documents, old)
      Req.default_options(options)
    end)

    :ok
  end

  defp upload(agenda \\ "zavazek") do
    assert {:ok, %{document: doc}} = Incoming.upload("%PDF-test", "doklad.pdf", agenda)
    doc
  end

  defp extracted(doc) do
    {:ok, fields} = XML.parse(doc.template_xml, doc.agenda)

    fields =
      Map.merge(fields, %{
        "nazFirmy" => "Dodavatel",
        "cisDosle" => "OLD",
        "datVyst" => "2026-11-05",
        "sumZklZakl" => "100.00",
        "sumDphZakl" => "21.00",
        "sumCelkem" => "121.00"
      })

    xml = XML.render(fields, doc.agenda, doc.external_id)

    doc
    |> Ecto.Changeset.change(state: "review", generated_xml: xml, current_xml: xml)
    |> Repo.update!()
  end

  defp transcription do
    "test/fixtures/incoming_documents/penny.json" |> File.read!() |> Jason.decode!()
  end

  defp model_response(conn, data) do
    Req.Test.json(conn, %{
      "status" => "completed",
      "output" => [
        %{
          "type" => "message",
          "content" => [%{"type" => "output_text", "text" => Jason.encode!(data)}]
        }
      ]
    })
  end

  defp success(conn, id \\ "42", warnings \\ []) do
    Req.Test.json(conn, %{
      "winstrom" => %{"success" => true, "results" => [%{"id" => id, "warnings" => warnings}]}
    })
  end

  defp dry_run(doc, warnings \\ []) do
    Repo.update_all(Oban.Job, set: [state: "completed"])

    Req.Test.expect(__MODULE__, fn conn ->
      assert Plug.Conn.fetch_query_params(conn).query_params["dry-run"] == "true"
      success(conn, "-1", warnings)
    end)

    assert {:ok, _} = Incoming.validate(doc.id, Incoming.digest(doc.current_xml))
    assert :ok = Incoming.perform(doc.id, "validate")
    Incoming.get!(doc.id)
  end

  test "upload is private, checks file signatures and warns about duplicate hashes" do
    doc = upload()

    assert {:ok, %{duplicate?: true}} =
             Incoming.upload("%PDF-test", "other.pdf", "pokladni-pohyb")

    assert Incoming.get!(doc.id).original == "%PDF-test"
    assert [%{id: _} | _] = Incoming.list()
    refute Map.has_key?(hd(Incoming.list()), :original)
    assert {:error, _} = Incoming.upload("<script/>", "fake.pdf", "zavazek")
    assert {:error, _} = Incoming.upload("%PDF-test", "ok.pdf", "faktura-vydana")
  end

  test "extraction uses store=false, protects against document instructions and validates the result" do
    doc = upload()

    data = transcription() |> Map.put("document_number", "0007-20261105-A")

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.host == "api.openai.com"
      assert conn.request_path == "/v1/responses"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["store"] == false
      assert payload["model"] == "test-vision"
      assert payload["instructions"] =~ "nedůvěryhodná data"
      assert payload["instructions"] =~ "EV-č"
      assert payload["instructions"] =~ "Počáteční nuly"
      assert payload["text"]["format"]["type"] == "json_schema"
      assert payload["text"]["format"]["strict"]
      refute Jason.encode!(payload) =~ "primUcet"
      refute Map.has_key?(payload, "previous_response_id")

      assert [%{"content" => [_, %{"type" => "input_file", "file_data" => file_data}]}] =
               payload["input"]

      assert file_data == "data:application/pdf;base64," <> Base.encode64(doc.original)

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

    assert :ok = Incoming.perform(doc.id, "extract")
    assert Incoming.get!(doc.id).state == "review"
    {:ok, fields} = XML.parse(Incoming.get!(doc.id).current_xml, doc.agenda)
    assert fields["cisDosle"] == "0007-20261105-A"
  end

  test "simple XML strategy sends the original and exact saved template with a short prompt" do
    assert {:ok, %{document: doc}} =
             Incoming.upload("%PDF-simple", "simple.pdf", "zavazek", "simple_xml")

    raw = extracted(doc).current_xml

    doc
    |> Ecto.Changeset.change(state: "uploaded", current_xml: nil, generated_xml: nil)
    |> Repo.update!()

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["store"] == false
      assert payload["max_output_tokens"] == 24000
      assert payload["instructions"] == Extractor.instructions("simple_xml")
      assert String.length(payload["instructions"]) < String.length(Extractor.instructions())
      refute Map.has_key?(payload, "text")

      assert [%{"content" => [%{"text" => template}, %{"type" => "input_file"}]}] =
               payload["input"]

      assert template =~ doc.template_xml

      Req.Test.json(conn, %{
        "status" => "completed",
        "output" => [
          %{"type" => "message", "content" => [%{"type" => "output_text", "text" => raw}]}
        ]
      })
    end)

    assert :ok = Incoming.perform(doc.id, "extract")
    result = Incoming.get!(doc.id)
    assert result.state == "review"
    assert result.generated_xml == raw
    assert result.extracted_data == %{}
    assert result.extraction_attempts == 1

    assert hd(result.extraction_metadata["calls"])["prompt_version"] ==
             Extractor.prompt_version("simple_xml")

    assert result.dry_run == %{}
    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest(result.current_xml))
  end

  test "simple XML strategy retains invalid accounting XML and never makes a correction call" do
    assert {:ok, %{document: doc}} =
             Incoming.upload("%PDF-simple", "simple.pdf", "zavazek", "simple_xml")

    raw = extracted(doc).current_xml |> String.replace("code:325000", "code:999999")

    doc
    |> Ecto.Changeset.change(state: "uploaded", current_xml: nil, generated_xml: nil)
    |> Repo.update!()

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "status" => "completed",
        "output" => [
          %{"type" => "message", "content" => [%{"type" => "output_text", "text" => raw}]}
        ]
      })
    end)

    assert :ok = Incoming.perform(doc.id, "extract")
    failed = Incoming.get!(doc.id)
    assert failed.state == "failed"
    assert failed.generated_xml == raw
    assert failed.error =~ "primUcet"
    assert failed.extraction_attempts == 1
    assert failed.sent_xml == nil
    assert :ok = Incoming.perform(doc.id, "extract")
    assert {:error, _} = Incoming.retry_extraction(doc.id, "unknown")
    assert {:ok, queued} = Incoming.retry_extraction(doc.id, "structured")
    assert queued.extraction_metadata == %{"strategy" => "structured"}
    assert queued.extraction_attempts == 0
  end

  test "token exhaustion reports the exact reason without retrying" do
    doc = upload()

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "status" => "incomplete",
        "incomplete_details" => %{"reason" => "max_output_tokens"},
        "output" => [],
        "usage" => %{"output_tokens" => 24000}
      })
    end)

    assert :ok = Incoming.perform(doc.id, "extract")
    failed = Incoming.get!(doc.id)
    assert failed.state == "failed"
    assert failed.error =~ "max_output_tokens"
    assert failed.extraction_attempts == 1
    assert hd(failed.extraction_metadata["calls"])["incomplete_reason"] == "max_output_tokens"
  end

  test "invalid extraction fails and never queues a write" do
    doc = upload()

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "status" => "completed",
        "output" => [
          %{
            "type" => "message",
            "content" => [%{"type" => "output_text", "text" => "<winstrom><banka/></winstrom>"}]
          }
        ]
      })
    end)

    assert :ok = Incoming.perform(doc.id, "extract")
    assert %{state: "failed", error_stage: "extraction", sent_xml: nil} = Incoming.get!(doc.id)
    assert {:error, _} = Incoming.approve(doc.id, "invalid")
  end

  test "image inputs use input_image and incomplete responses are rejected" do
    doc = %{upload() | content_type: "image/png", original: <<137, 80, 78, 71>>}

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert [%{"content" => [_, %{"type" => "input_image"}]}] = Jason.decode!(body)["input"]
      Req.Test.json(conn, %{"status" => "incomplete", "output" => []})
    end)

    assert {:error, _, _} =
             Extractor.extract(doc, Incoming.config(), [
               %{
                 type: "input_image",
                 image_url: "data:image/png;base64," <> Base.encode64(doc.original),
                 detail: "high"
               }
             ])
  end

  test "correction invalidates dry run and the exact approved XML is sent once" do
    doc = upload("faktura-prijata") |> extracted() |> dry_run()
    old_hash = Incoming.digest(doc.current_xml)
    assert {:ok, doc} = Incoming.save(doc.id, %{"cisDosle" => "CORRECTED"}, old_hash)
    assert doc.dry_run == %{}
    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
    assert {:error, _} = Incoming.save(doc.id, %{"popis" => "stale"}, old_hash)
    doc = dry_run(doc)
    hash = Incoming.digest(doc.current_xml)
    assert {:ok, approved} = Incoming.approve(doc.id, hash)
    assert approved.sent_xml == doc.current_xml
    assert {:error, _} = Incoming.approve(doc.id, hash)
    assert {:error, _} = Incoming.save(doc.id, %{"cisDosle" => "LATE"}, hash)

    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/c/pilot/faktura-prijata.json"
      refute Map.has_key?(Plug.Conn.fetch_query_params(conn).query_params, "dry-run")
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert {:ok, expected} =
               CozyCheckout.IncomingDocuments.ImportPayload.from_xml(approved.sent_xml, approved)

      assert Jason.decode!(body) == expected
      assert body =~ "CORRECTED"

      assert Jason.decode!(body)["winstrom"][doc.agenda] |> hd() |> Map.fetch!("@update") ==
               "fail"

      assert Plug.Conn.get_req_header(conn, "authorization") == [
               "Basic " <> Base.encode64("test:test")
             ]

      success(conn)
    end)

    assert :ok = Incoming.perform(doc.id, "send")
    assert :ok = Incoming.perform(doc.id, "send")
    assert %{state: "sent", remote_id: "42"} = Incoming.get!(doc.id)
  end

  test "dry-run rejection and warnings block approval until explicitly resolved" do
    doc = upload() |> extracted()

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "winstrom" => %{
          "success" => false,
          "results" => [%{"errors" => [%{"message" => "Invalid VAT"}]}]
        }
      })
    end)

    assert {:ok, _} = Incoming.validate(doc.id, Incoming.digest(doc.current_xml))
    assert :ok = Incoming.perform(doc.id, "validate")
    assert %{state: "review", error: "Invalid VAT"} = Incoming.get!(doc.id)
    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
    doc = dry_run(doc, [%{"message" => "Check VAT"}])
    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
    assert {:ok, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml), true)
  end

  test "timeout freezes payload and retries only look up the external ID" do
    doc = upload("pokladni-pohyb") |> extracted() |> dry_run()
    assert {:ok, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)
    Req.Test.expect(__MODULE__, fn conn -> Req.Test.transport_error(conn, :timeout) end)
    assert :ok = Incoming.perform(doc.id, "send")
    assert %{state: "uncertain", sent_xml: sent} = Incoming.get!(doc.id)
    assert sent == doc.current_xml
    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))

    assert {:error, _} =
             Incoming.save(doc.id, %{"popis" => "unsafe"}, Incoming.digest(doc.current_xml))

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert URI.decode(conn.request_path) =~ doc.external_id
      Plug.Conn.send_resp(conn, 404, "")
    end)

    assert :ok = Incoming.perform(doc.id, "send")
    assert Incoming.get!(doc.id).state == "uncertain"

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      Req.Test.json(conn, %{"winstrom" => %{doc.agenda => [%{"id" => 88}]}})
    end)

    assert :ok = Incoming.perform(doc.id, "send")
    assert %{state: "sent", remote_id: "88"} = Incoming.get!(doc.id)
  end

  test "uncertain state persisted before POST also survives process failure" do
    doc = upload() |> extracted() |> dry_run()
    assert {:ok, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)
    Req.Test.expect(__MODULE__, fn _conn -> raise "simulated crash" end)
    assert_raise RuntimeError, fn -> Incoming.perform(doc.id, "send") end
    assert Incoming.get!(doc.id).state == "uncertain"

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      Plug.Conn.send_resp(conn, 404, "")
    end)

    assert :ok = Incoming.perform(doc.id, "send")
    assert Incoming.get!(doc.id).state == "uncertain"
  end

  test "target changes block approval and ABRA rejections never mark sent" do
    doc = upload() |> extracted() |> dry_run()
    cfg = Incoming.config()

    Application.put_env(
      :cozy_checkout,
      :incoming_documents,
      Keyword.put(cfg, :company_id, "different")
    )

    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
    Application.put_env(:cozy_checkout, :incoming_documents, cfg)
    assert {:ok, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "winstrom" => %{
          "success" => false,
          "results" => [%{"errors" => [%{"message" => "Rejected"}]}]
        }
      })
    end)

    assert :ok = Incoming.perform(doc.id, "send")

    assert %{state: "review", remote_id: nil, error: "Rejected", dry_run: %{}} =
             Incoming.get!(doc.id)
  end

  test "malformed import success is uncertain and lookup failure cannot trigger POST" do
    doc = upload() |> extracted()

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"winstrom" => %{"success" => true}})
    end)

    assert {:uncertain, _, _} = Client.import(doc, doc.current_xml, false, Incoming.config())
    doc = dry_run(doc)
    assert {:ok, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 503, "offline") end)
    assert :ok = Incoming.perform(doc.id, "send")
    assert Incoming.get!(doc.id).state == "uncertain"
  end

  test "failed source data is retained and can be repaired without another model call" do
    doc = upload()
    bad = transcription() |> Map.put("total", "999.00")

    for _ <- 1..2 do
      Req.Test.expect(__MODULE__, fn conn -> model_response(conn, bad) end)
    end

    assert :ok = Incoming.perform(doc.id, "extract")
    failed = Incoming.get!(doc.id)
    assert failed.state == "failed"
    assert failed.extraction_attempts == 2
    assert failed.extracted_data == bad
    assert failed.generated_xml =~ "999.00"
    assert failed.current_xml == nil
    hash = Incoming.transcription_hash(failed)

    assert {:error, _} =
             Incoming.repair_transcription(doc.id, Jason.encode!(transcription()), "stale")

    assert {:ok, repaired} =
             Incoming.repair_transcription(doc.id, Jason.encode!(transcription()), hash)

    assert repaired.state == "review"
    assert repaired.extracted_data == bad
    assert repaired.current_xml =~ "code:325000"
    assert repaired.dry_run == %{}
    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest(repaired.current_xml))
  end

  test "a single correction rereads the source with validation feedback" do
    doc = upload()
    bad = transcription() |> Map.put("total", "999.00")
    Req.Test.expect(__MODULE__, fn conn -> model_response(conn, bad) end)

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      [input] = payload["input"]
      [context, source] = input["content"]
      assert context["text"] =~ "sumCelkem"
      assert context["text"] =~ "999.00"
      assert source["type"] == "input_file"
      assert payload["store"] == false
      model_response(conn, transcription())
    end)

    assert :ok = Incoming.perform(doc.id, "extract")
    assert %{state: "review", extraction_attempts: 2} = Incoming.get!(doc.id)
    assert :ok = Incoming.perform(doc.id, "extract")
  end

  test "resuming an exhausted worker never makes a third paid call" do
    doc = upload()
    bad = transcription() |> Map.put("total", "999.00")

    doc
    |> Ecto.Changeset.change(state: "processing", extracted_data: bad, extraction_attempts: 2)
    |> Repo.update!()

    assert :ok = Incoming.perform(doc.id, "extract")
    assert %{state: "failed", extraction_attempts: 2, sent_xml: nil} = Incoming.get!(doc.id)
  end

  test "a reserved call lost in a crash still counts towards the limit" do
    doc = upload()
    doc |> Ecto.Changeset.change(state: "processing", extraction_attempts: 1) |> Repo.update!()
    Req.Test.expect(__MODULE__, fn conn -> model_response(conn, transcription()) end)
    assert :ok = Incoming.perform(doc.id, "extract")
    assert %{state: "review", extraction_attempts: 2} = Incoming.get!(doc.id)
  end

  test "HTTP authentication errors do not consume a corrective call" do
    doc = upload()
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 401, "unauthorized") end)
    assert :ok = Incoming.perform(doc.id, "extract")
    assert %{state: "failed", extraction_attempts: 1} = Incoming.get!(doc.id)
  end

  test "receipt rounding requires confirmation and locks the exact checked payload" do
    doc = upload()
    Req.Test.expect(__MODULE__, fn conn -> model_response(conn, transcription()) end)
    assert :ok = Incoming.perform(doc.id, "extract")
    doc = Incoming.get!(doc.id) |> dry_run()
    hash = Incoming.digest(doc.current_xml)
    assert {:error, reason} = Incoming.approve(doc.id, hash)
    assert reason =~ "haléřovou korekci"
    assert {:ok, approved} = Incoming.approve(doc.id, hash, false, true)
    assert approved.sent_xml =~ "typPolozky.ucetni"
    refute approved.sent_xml == doc.current_xml
    assert Incoming.digest(approved.sent_xml) == doc.dry_run["payload_hash"]
  end

  test "accounting selection uses the company's expense and VAT accounts and preserves corrected XML" do
    doc = upload("faktura-prijata") |> extracted()

    assert {:ok, doc} =
             Incoming.save(doc.id, %{"cisDosle" => "CORRECTED"}, Incoming.digest(doc.current_xml))

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/c/pilot/predpis-zauctovani.json"
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["relations"] == "code"

      Req.Test.json(conn, %{
        "winstrom" => %{
          "predpis-zauctovani" => [
            %{
              "kod" => "SLUZBY",
              "nazev" => "Telefonní služby",
              "modulFap" => "true",
              "protiUcetVydej" => "code:518100",
              "dphZaklUcet" => "code:343100"
            }
          ]
        }
      })
    end)

    assert {:ok, saved} =
             Incoming.save_accounting(
               doc.id,
               %{"preset" => "SLUZBY", "internal_code" => "fp-2026-001"},
               Incoming.transcription_hash(doc)
             )

    assert {:ok, fields} = XML.parse(saved.current_xml, doc.agenda)
    assert fields["typUcOp"] == "code:SLUZBY"
    assert fields["protiUcet"] == "code:518100"
    assert fields["primUcet"] == "code:321001"
    assert fields["kod"] == "FP-2026-001"
    assert fields["cisDosle"] == "CORRECTED"
    assert fields["sumCelkem"] == "121.00"
    assert saved.template_xml == doc.template_xml
    assert saved.dry_run == %{}
    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest(saved.current_xml))
    assert {:ok, payload} = Incoming.diagnostic_xml(saved)
    assert payload =~ "<kod>FP-2026-001</kod>"

    assert {:error, _} =
             Incoming.save_accounting(
               doc.id,
               %{"internal_code" => "OTHER"},
               Incoming.transcription_hash(doc)
             )
  end

  test "presets are paginated in batches and filtered for the selected agenda" do
    doc = upload("faktura-prijata")

    page =
      for i <- 1..200, do: %{"kod" => "P#{i}", "nazev" => "Předpis #{i}", "modulFap" => "true"}

    Req.Test.expect(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["start"] == "0"
      Req.Test.json(conn, %{"winstrom" => %{"predpis-zauctovani" => page}})
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["start"] == "200"

      Req.Test.json(conn, %{
        "winstrom" => %{
          "predpis-zauctovani" => [
            %{"kod" => "POKLADNA", "modulFap" => "false", "modulPokV" => "true"}
          ]
        }
      })
    end)

    assert {:ok, rows} = Incoming.accounting_presets(doc.id)
    assert length(rows) == 200
    refute Enum.any?(rows, &(&1["kod"] == "POKLADNA"))
  end

  test "unavailable accounting catalog never changes the draft" do
    doc = upload("faktura-prijata") |> extracted()
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 403, "forbidden") end)

    assert {:error, reason} =
             Incoming.save_accounting(
               doc.id,
               %{"preset" => "SLUZBY"},
               Incoming.transcription_hash(doc)
             )

    assert reason =~ "403"
    assert Incoming.get!(doc.id).current_xml == doc.current_xml
    assert Incoming.get!(doc.id).accounting_settings == %{}
  end

  test "internal code is optional, editable without catalog access, and retained through subsequent source edits" do
    doc = upload() |> extracted()

    assert {:ok, changed} =
             Incoming.save_accounting(
               doc.id,
               %{"internal_code" => "Z2026-1"},
               Incoming.transcription_hash(doc)
             )

    assert changed.current_xml =~ "<kod>Z2026-1</kod>"

    assert {:ok, changed} =
             Incoming.save(
               changed.id,
               %{"popis" => "Oprava"},
               Incoming.digest(changed.current_xml)
             )

    assert changed.current_xml =~ "<kod>Z2026-1</kod>"

    assert {:ok, cleared} =
             Incoming.save_accounting(
               doc.id,
               %{"internal_code" => ""},
               Incoming.transcription_hash(changed)
             )

    refute cleared.current_xml =~ "<kod>"
  end

  test "diagnostic dry-run checks an invalid draft without granting permission to send" do
    doc = upload()
    data = put_in(transcription(), ["vat_summary", Access.at(0), "vat"], nil)

    doc =
      doc
      |> Ecto.Changeset.change(
        state: "failed",
        error_stage: "extraction",
        error: "Chybí daň",
        extracted_data: data
      )
      |> Repo.update!()

    assert {:ok, _} = Incoming.diagnose(doc.id, Incoming.transcription_hash(doc))

    Req.Test.expect(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["dry-run"] == "true"
      success(conn, "-1")
    end)

    assert :ok = Incoming.perform(doc.id, "validate")
    checked = Incoming.get!(doc.id)
    assert checked.state == "failed"
    assert checked.dry_run["diagnostic"] == true
    assert checked.dry_run["accepted"] == true
    assert checked.dry_run["ok"] == false
    refute checked.dry_run["hash"]
    assert checked.sent_xml == nil
    assert checked.error == "Chybí daň"
    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest("anything"))
  end

  test "dry-run preview exposes generated internal code without reserving or copying it" do
    doc = upload() |> extracted()

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "winstrom" => %{
          "success" => true,
          "results" => [
            %{
              "id" => "-1",
              "content" => %{"zavazek" => [%{"kod" => "ZV-123", "protiUcet" => "code:518100"}]}
            }
          ]
        }
      })
    end)

    assert {:ok, response} = Client.import(doc, doc.current_xml, true, Incoming.config())
    assert response["preview"] == [%{"kod" => "ZV-123", "protiUcet" => "code:518100"}]
    assert Incoming.get!(doc.id).accounting_settings == %{}
  end

  test "invalid source edits are saved for correction and diagnostic export without authorizing a write" do
    doc = upload()
    original = transcription()

    doc =
      doc
      |> Ecto.Changeset.change(
        state: "failed",
        error_stage: "extraction",
        extracted_data: original
      )
      |> Repo.update!()

    bad = put_in(original, ["vat_summary", Access.at(0), "vat"], nil)
    hash = Incoming.transcription_hash(doc)
    assert {:ok, saved} = Incoming.save_transcription(doc.id, bad, hash)
    assert saved.state == "failed"
    assert saved.current_xml == nil
    assert saved.extracted_data == original
    assert saved.edited_data == bad
    assert saved.error =~ "vat_summary.0.vat"
    assert saved.dry_run == %{}
    assert {:ok, payload} = Incoming.diagnostic_xml(saved.id)
    assert {:ok, fields} = XML.parse(payload, doc.agenda)
    assert fields["id"] == doc.external_id
    refute Map.has_key?(fields, "sumCelkem")
    assert length(XML.items(fields)) == 21
    assert Incoming.get!(doc.id).sent_xml == nil
    assert {:error, _} = Incoming.validate(doc.id, Incoming.digest(payload))
    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest(payload))
    assert {:error, _} = Incoming.save_transcription(doc.id, original, hash)

    assert {:ok, repaired} =
             Incoming.save_transcription(doc.id, original, Incoming.transcription_hash(saved))

    assert repaired.state == "review"
    assert repaired.edited_data == original
  end

  test "source edits cannot overwrite an XML correction from another tab" do
    doc = upload() |> extracted()
    doc = doc |> Ecto.Changeset.change(extracted_data: transcription()) |> Repo.update!()
    hash = Incoming.transcription_hash(doc)

    assert {:ok, _} =
             Incoming.save(doc.id, %{"cisDosle" => "CHANGED"}, Incoming.digest(doc.current_xml))

    assert {:error, _} = Incoming.save_transcription(doc.id, transcription(), hash)
  end

  test "repair never edits approved or uncertain imports" do
    doc = upload() |> extracted() |> dry_run()
    assert {:ok, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))

    assert {:error, _} =
             Incoming.repair_xml(doc.id, doc.current_xml, Incoming.digest(doc.generated_xml))

    sending = Incoming.get!(doc.id)
    sending |> Ecto.Changeset.change(state: "uncertain") |> Repo.update!()

    assert {:error, _} =
             Incoming.repair_xml(doc.id, doc.current_xml, Incoming.digest(doc.generated_xml))

    assert Incoming.get!(doc.id).sent_xml == doc.current_xml
  end

  test "itemized dry run and create send identical JSON projected from approved item XML" do
    doc = upload("pokladni-pohyb") |> extracted()
    {:ok, fields} = XML.parse(doc.current_xml, doc.agenda)

    row = %{
      "nazev" => "Účtenka — položka",
      "mnozMj" => "2",
      "cenaMj" => "60.50",
      "typCenyDphK" => "typCeny.sDph",
      "typSzbDphK" => "typSzbDph.dphZakl"
    }

    raw = fields |> Map.put("polozkyDokladu", [row]) |> XML.render(doc.agenda, doc.external_id)
    assert {:ok, reviewed} = XML.normalize(raw, doc.agenda, doc.template_xml, doc.external_id)
    doc = doc |> Ecto.Changeset.change(current_xml: reviewed) |> Repo.update!()
    {:ok, payload} = XML.import_xml(reviewed, doc.agenda)

    Req.Test.expect(__MODULE__, fn conn ->
      assert Plug.Conn.fetch_query_params(conn).query_params["dry-run"] == "true"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert {:ok, expected} = CozyCheckout.IncomingDocuments.ImportPayload.from_xml(payload, doc)
      assert Jason.decode!(body) == expected
      success(conn, "-1")
    end)

    hash = Incoming.digest(reviewed)
    assert {:ok, _} = Incoming.validate(doc.id, hash)
    assert :ok = Incoming.perform(doc.id, "validate")
    assert {:ok, approved} = Incoming.approve(doc.id, hash)
    assert approved.sent_xml == payload
    refute approved.sent_xml == reviewed
    {:ok, parsed} = XML.parse(approved.sent_xml, doc.agenda)
    refute Map.has_key?(parsed, "sumCelkem")
    assert length(XML.items(parsed)) == 1
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert {:ok, expected} = CozyCheckout.IncomingDocuments.ImportPayload.from_xml(payload, doc)
      assert Jason.decode!(body) == expected
      success(conn)
    end)

    assert :ok = Incoming.perform(doc.id, "send")
    assert Incoming.get!(doc.id).state == "sent"
  end

  test "ABRA HTTP 200 with non-JSON body retains diagnostic content and never approves import" do
    doc = upload() |> extracted()

    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "<html><body>Proxy login page</body></html>")
    end)

    assert {:ok, _} = Incoming.validate(doc.id, Incoming.digest(doc.current_xml))
    assert :ok = Incoming.perform(doc.id, "validate")
    failed = Incoming.get!(doc.id)
    assert failed.state == "review"
    assert failed.error =~ "HTTP 200"
    assert failed.error =~ "XML nebo HTML"
    assert failed.dry_run["raw_body"] =~ "Proxy login page"
    assert failed.dry_run["content_type"] =~ "text/html"
    assert failed.dry_run["http_status"] == 200
    refute failed.dry_run["ok"]
    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
  end

  test "FreeMarker HTML is diagnosed with the API request and never treated as a dry-run success" do
    doc = upload("faktura-prijata") |> extracted()
    html = File.read!("test/fixtures/incoming_documents/freemarker_error.html")

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/c/pilot/faktura-prijata.json"
      assert Plug.Conn.get_req_header(conn, "accept") == ["application/json"]
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["dry-run"] == "true"

      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.put_resp_header("set-cookie", "session=DO_NOT_STORE")
      |> Plug.Conn.send_resp(200, html)
    end)

    assert {:ok, _} = Incoming.validate(doc.id, Incoming.digest(doc.current_xml))
    assert :ok = Incoming.perform(doc.id, "validate")
    checked = Incoming.get!(doc.id)
    assert checked.state == "review"
    assert checked.error =~ "FreeMarker"
    assert checked.dry_run["format_diagnostic"]["kind"] == "server_template_error"
    assert checked.dry_run["format_diagnostic"]["text"] =~ "==> object"
    assert checked.dry_run["format_diagnostic"]["text"] =~ "evidence/faktura-prijata/view.ftl"
    refute checked.dry_run["format_diagnostic"]["text"] =~ "SCRIPT_CONTENT"

    assert checked.dry_run["request"]["url"] ==
             "https://accounting.test/c/pilot/faktura-prijata.json"

    assert checked.dry_run["request"]["dry_run"] == true
    refute Map.has_key?(checked.dry_run["response_headers"], "set-cookie")
    refute checked.dry_run["ok"]
    assert {:error, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
  end

  test "HTML from a real write remains uncertain and is never blindly posted twice" do
    doc = upload() |> extracted() |> dry_run()
    assert {:ok, approved} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(
        200,
        File.read!("test/fixtures/incoming_documents/freemarker_error.html")
      )
    end)

    assert :ok = Incoming.perform(doc.id, "send")
    checked = Incoming.get!(doc.id)
    assert checked.state == "uncertain"
    assert checked.sent_xml == approved.sent_xml
    assert checked.response["format_diagnostic"]["kind"] == "server_template_error"

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      Plug.Conn.send_resp(conn, 404, "")
    end)

    assert :ok = Incoming.perform(doc.id, "send")
    assert Incoming.get!(doc.id).state == "uncertain"
  end

  test "ABRA errors include affected field, path, code and value" do
    doc = upload() |> extracted()

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "winstrom" => %{
          "success" => false,
          "results" => [
            %{
              "errors" => [
                %{
                  "message" => "Součet nesouhlasí",
                  "for" => "sumZkl",
                  "path" => "zavazek[0].polozkyDokladu[2].sumZkl",
                  "code" => "PROP",
                  "messageCode" => "inputDiffComputed",
                  "value" => "12.34"
                }
              ]
            }
          ]
        }
      })
    end)

    assert {:rejected, reason, response} =
             Client.import(doc, doc.current_xml, true, Incoming.config())

    for expected <- [
          "Součet nesouhlasí",
          "sumZkl",
          "polozkyDokladu[2]",
          "PROP",
          "inputDiffComputed",
          "12.34"
        ],
        do: assert(reason =~ expected)

    assert response["raw_body"] =~ "inputDiffComputed"
  end

  test "valid JSON is parsed even if ABRA sends a misleading content type" do
    doc = upload() |> extracted()

    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{"winstrom" => %{"success" => true, "results" => [%{"id" => "42"}]}})
      )
    end)

    assert {:ok, response} = Client.import(doc, doc.current_xml, false, Incoming.config())
    assert response["id"] == "42"
    assert response["content_type"] =~ "text/plain"
  end

  test "unknown write response preserves diagnostics, freezes payload and only permits lookup" do
    doc = upload() |> extracted() |> dry_run()
    assert {:ok, approved} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)
    Req.Test.expect(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 200, "not-json") end)
    assert :ok = Incoming.perform(doc.id, "send")
    uncertain = Incoming.get!(doc.id)
    assert uncertain.state == "uncertain"
    assert uncertain.sent_xml == approved.sent_xml
    assert uncertain.response["raw_body"] == "not-json"

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "GET"
      Req.Test.json(conn, %{"winstrom" => %{doc.agenda => [%{"id" => 42}]}})
    end)

    assert :ok = Incoming.perform(doc.id, "send")
    assert Incoming.get!(doc.id).state == "sent"
    assert Incoming.get!(doc.id).response["raw_body"] == "not-json"
  end

  test "reviewed documents can be explicitly extracted again, approved imports cannot" do
    doc = upload() |> extracted() |> dry_run()
    assert {:ok, queued} = Incoming.retry_extraction(doc.id)
    assert queued.state == "uploaded"
    assert queued.dry_run == %{}
    assert queued.current_xml == nil
    assert queued.generated_xml == nil
    doc = upload() |> extracted() |> dry_run()
    assert {:ok, _} = Incoming.approve(doc.id, Incoming.digest(doc.current_xml))
    assert {:error, _} = Incoming.retry_extraction(doc.id)
  end
end

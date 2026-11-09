defmodule CozyCheckout.IncomingDocuments.ExtractionRunsTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  alias CozyCheckout.{IncomingDocuments, Repo}

  alias CozyCheckout.IncomingDocuments.{
    Document,
    ExtractionRun,
    ExtractionRuns,
    HeaderForm,
    SupplierProfiles
  }

  setup do
    previous = IncomingDocuments.config()
    defaults = Req.default_options()

    Application.put_env(:cozy_checkout, :incoming_documents,
      enabled: true,
      base_url: "https://accounting.test/",
      company_id: "pilot",
      username: "test",
      password: "test",
      openai_api_key: "private-test-key",
      openai_model: "test-model"
    )

    Req.default_options(plug: {Req.Test, __MODULE__})
    Req.Test.verify_on_exit!()

    on_exit(fn ->
      Application.put_env(:cozy_checkout, :incoming_documents, previous)
      Req.default_options(defaults)
    end)

    :ok
  end

  defp upload do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "test.pdf", "zavazek", "header_form")

    doc
  end

  defp identity,
    do: %{
      "name" => "PENNY MARKET",
      "ic" => "64945880",
      "dic" => "CZ64945880",
      "country_code" => "CZ",
      "ambiguous" => false,
      "uncertainties" => []
    }

  defp attrs(text \\ "Přečti datum podle popisku."),
    do: Map.merge(identity(), %{"identity_kind" => "ic", "instructions" => text})

  defp data,
    do:
      File.read!("test/fixtures/incoming_documents/penny.json")
      |> Jason.decode!()
      |> Map.delete("items")

  defp profile(doc, text \\ "Přečti datum podle popisku.") do
    {:ok, profile} =
      IncomingDocuments.save_supplier_instructions(doc.id, nil, attrs(text), nil, true)

    profile
  end

  defp response(conn, value) do
    Req.Test.json(conn, %{
      "status" => "completed",
      "usage" => %{"input_tokens" => 100, "output_tokens" => 50},
      "output" => [
        %{
          "type" => "message",
          "content" => [%{"type" => "output_text", "text" => Jason.encode!(value)}]
        }
      ]
    })
  end

  defp expect(value), do: Req.Test.expect(__MODULE__, &response(&1, value))

  defp empty_task, do: %{"fields" => [], "vat_summary" => nil, "uncertainties" => []}

  defp number_task,
    do: %{
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

  defp finish(doc) do
    expect(identity())
    expect(data())
    expect(empty_task())
    assert :ok = IncomingDocuments.perform(doc.id, "extract")
    IncomingDocuments.get!(doc.id)
  end

  defp header_attrs,
    do: %{
      "nazFirmy" => "Ruční oprava",
      "cisDosle" => "MANUAL",
      "datVyst" => "2026-11-05",
      "datSplat" => "2026-11-05",
      "sumOsv" => "123.45",
      "sumCelkem" => "123.45"
    }

  test "default extraction asks only for header and VAT and restores the compatible internal empty items" do
    doc = upload()
    expect(identity())

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      schema = payload["text"]["format"]["schema"]
      refute Map.has_key?(schema["properties"], "items")
      refute "items" in schema["required"]
      assert payload["instructions"] =~ "Položky zboží nečti ani nepřepisuj"
      refute payload["instructions"] =~ "Položky přepiš podle možností"
      response(conn, data())
    end)

    IncomingDocuments.perform(doc.id, "extract")
    doc = IncomingDocuments.get!(doc.id)
    assert doc.state == "review"
    assert doc.extracted_data["document_number"] == "0052-20261105-01-0039"
    assert doc.extracted_data["items"] == []
    assert doc.extraction_metadata["include_items"] == false
    assert HeaderForm.values(doc)["cisDosle"] == "0052-20261105-01-0039"
  end

  test "items are opt-in and each subsequent extraction keeps its chosen schema snapshot" do
    {:ok, %{document: doc}} =
      IncomingDocuments.upload("%PDF-test", "test.pdf", "zavazek", "header_form",
        include_items: true
      )

    full = File.read!("test/fixtures/incoming_documents/penny.json") |> Jason.decode!()
    expect(identity())

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert Map.has_key?(payload["text"]["format"]["schema"]["properties"], "items")
      assert payload["instructions"] =~ "Položky přepiš podle možností"
      response(conn, full)
    end)

    IncomingDocuments.perform(doc.id, "extract")
    doc = IncomingDocuments.get!(doc.id)
    assert doc.extracted_data["items"] == full["items"]
    original_run = IncomingDocuments.active_extraction_run(doc)

    assert {:ok, queued} =
             IncomingDocuments.retry_content_extraction(doc.id, include_items: false)

    header_run = IncomingDocuments.active_extraction_run(queued)
    refute Map.has_key?(header_run.schemas["content"]["properties"], "items")
    assert Map.has_key?(original_run.schemas["content"]["properties"], "items")
    expect(data())
    IncomingDocuments.perform(doc.id, "extract")
    assert IncomingDocuments.get!(doc.id).extracted_data["items"] == []
    assert Repo.get!(ExtractionRun, original_run.id).schemas == original_run.schemas

    assert {:ok, queued} =
             IncomingDocuments.retry_extraction(doc.id, "header_form", include_items: true)

    assert Map.has_key?(
             IncomingDocuments.active_extraction_run(queued).schemas["content"]["properties"],
             "items"
           )
  end

  test "known supplier sends independent general and focused requests with frozen instructions and matching original" do
    doc = upload()
    p = profile(doc, "Přečti pouze číslo dokladu za označením EV-Č v patičce.")
    owner = self()

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      assert request["store"] == false
      assert request["max_output_tokens"] == 2000
      assert request["text"]["format"]["name"] == "supplier_identity"
      refute request["instructions"] =~ p.instructions
      send(owner, {:input, request["input"] |> hd() |> Map.fetch!("content") |> tl()})
      response(conn, identity())
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      assert request["store"] == false
      assert request["text"]["format"]["name"] == "receipt_transcription"
      refute request["instructions"] =~ p.instructions
      assert_receive {:input, parts}
      assert tl(hd(request["input"])["content"]) == parts
      send(owner, {:input, parts})
      run = IncomingDocuments.active_extraction_run(IncomingDocuments.get!(doc.id))
      assert run.profile_revision == 1
      assert run.supplier_instructions == p.instructions
      # Concurrent editor changes must not alter this call or the saved snapshot.
      assert {:ok, updated} =
               IncomingDocuments.save_supplier_instructions(
                 doc.id,
                 p.id,
                 attrs("Nová revize"),
                 1,
                 true
               )

      assert updated.revision == 2
      response(conn, Map.put(data(), "document_number", "39"))
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      assert request["store"] == false
      assert request["text"]["format"]["name"] == "supplier_task"
      run = IncomingDocuments.active_extraction_run(IncomingDocuments.get!(doc.id))
      assert request["instructions"] == run.supplier_task_instructions
      refute request["instructions"] =~ run.common_instructions
      [text | parts] = hd(request["input"])["content"]
      assert text["text"] == p.instructions
      assert_receive {:input, expected_parts}
      assert parts == expected_parts
      refute Map.has_key?(request, "previous_response_id")
      assert run.content_result["document_number"] == "39"
      response(conn, number_task())
    end)

    IncomingDocuments.perform(doc.id, "extract")
    result = IncomingDocuments.get!(doc.id)
    run = IncomingDocuments.active_extraction_run(result)
    assert run.state == "completed"
    assert run.selection == "exact_ic"
    assert run.supplier_instructions == p.instructions
    assert run.profile_revision == 1
    assert run.identification["attempts"] == 1
    assert run.content["attempts"] == 1
    assert run.content["usage"]["input_tokens"] == 100
    assert run.schemas["identity"]["additionalProperties"] == false
    assert run.common_instructions_hash == IncomingDocuments.digest(run.common_instructions)
    refute Jason.encode!(Map.from_struct(run) |> Map.delete(:__meta__)) =~ "private-test-key"
    assert result.state == "review"
    assert result.current_xml == nil
    assert result.extraction_attempts == 3
    assert run.supplier_task["attempts"] == 1
    assert run.supplier_task["usage"]["input_tokens"] == 100
    assert run.content_result["document_number"] == "39"
    assert run.supplier_task_result == number_task()
    assert result.extracted_data["document_number"] == "0052-20261105-01-0039"
    assert :ok = IncomingDocuments.perform(doc.id, "extract")
    assert :ok = IncomingDocuments.perform_extraction(doc.id, run.id, 2)
  end

  test "a known supplier with empty instructions does not add a focused request" do
    doc = upload()
    profile(doc, "")
    expect(identity())
    expect(data())
    IncomingDocuments.perform(doc.id, "extract")
    result = IncomingDocuments.get!(doc.id)
    run = IncomingDocuments.active_extraction_run(result)
    assert result.state == "review"
    assert result.extraction_attempts == 2
    assert run.supplier_task == %{}
  end

  test "pre-existing pending snapshots retain their combined prompt and original call count" do
    doc = upload()
    p = profile(doc)
    run = IncomingDocuments.active_extraction_run(doc)

    run
    |> Ecto.Changeset.change(
      schemas: Map.delete(run.schemas, "supplier_task"),
      supplier_task_instructions: nil
    )
    |> Repo.update!()

    expect(identity())

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body)["instructions"] =~ p.instructions
      response(conn, data())
    end)

    IncomingDocuments.perform(doc.id, "extract")
    assert IncomingDocuments.get!(doc.id).state == "review"
    assert IncomingDocuments.get!(doc.id).extraction_attempts == 2
  end

  test "focused HTTP failure preserves the completed general reading and never falls back silently" do
    doc = upload()
    profile(doc)
    expect(identity())
    expect(data())
    Req.Test.expect(__MODULE__, &Plug.Conn.send_resp(&1, 500, "{}"))
    IncomingDocuments.perform(doc.id, "extract")
    failed = IncomingDocuments.get!(doc.id)
    run = IncomingDocuments.active_extraction_run(failed)
    assert failed.state == "failed"
    assert failed.current_xml == nil
    assert failed.extracted_data == %{}
    assert run.content["state"] == "completed"
    assert run.content_result["document_number"] == data()["document_number"]
    assert run.supplier_task["state"] == "failed"
    assert run.supplier_task["http_status"] == 500
    IncomingDocuments.perform_extraction(doc.id, run.id, 2)
    assert IncomingDocuments.get!(doc.id).extraction_attempts == 3
  end

  test "restart after committed general reading runs only the unreserved focused request" do
    doc = upload()
    run = prepare_task_phase(doc)
    expect(number_task())
    IncomingDocuments.perform_extraction(doc.id, run.id, 2)
    result = IncomingDocuments.get!(doc.id)
    assert result.state == "review"
    assert result.extracted_data["document_number"] == "0052-20261105-01-0039"

    assert IncomingDocuments.active_extraction_run(result).content_result["document_number"] ==
             "39"

    assert result.extraction_attempts == 3
    IncomingDocuments.perform_extraction(doc.id, run.id, 3)
  end

  test "uncertain focused reservation requires a manual new run" do
    doc = upload()
    run = prepare_task_phase(doc)

    run
    |> Ecto.Changeset.change(
      supplier_task: %{"state" => "reserved", "token" => "old", "attempts" => 1}
    )
    |> Repo.update!()

    IncomingDocuments.perform_extraction(doc.id, run.id, 2)
    failed = IncomingDocuments.get!(doc.id)
    run = IncomingDocuments.active_extraction_run(failed)
    assert failed.state == "failed"
    assert run.supplier_task["state"] == "failed"
    assert run.supplier_task["attempts"] == 1
    assert run.content["state"] == "completed"
    assert run.content_result["document_number"] == "39"
  end

  test "duplicate focused worker and its late reply cannot replace a newer generation" do
    doc = upload()
    run = prepare_task_phase(doc)
    parent = self()

    Req.Test.expect(__MODULE__, fn conn ->
      send(parent, :focused_reserved)

      receive do
        :release -> response(conn, number_task())
      after
        5000 -> raise "test synchronization timeout"
      end
    end)

    task =
      Task.async(fn ->
        receive do
          :go -> IncomingDocuments.perform_extraction(doc.id, run.id)
        end
      end)

    Req.Test.allow(__MODULE__, self(), task.pid)
    send(task.pid, :go)
    assert_receive :focused_reserved, 5000
    assert :ok = IncomingDocuments.perform_extraction(doc.id, run.id)
    assert IncomingDocuments.get!(doc.id).extraction_attempts == 3
    ExtractionRuns.interrupt(doc.id, run.id)
    assert {:ok, next} = IncomingDocuments.retry_extraction(doc.id)
    send(task.pid, :release)
    assert :ok = Task.await(task)
    current = IncomingDocuments.get!(doc.id)
    assert current.active_extraction_run_id == next.active_extraction_run_id
    assert current.extracted_data == %{}
    assert current.extraction_attempts == 0
  end

  defp prepare_task_phase(doc) do
    run = IncomingDocuments.active_extraction_run(doc)
    doc |> Ecto.Changeset.change(state: "processing", extraction_attempts: 2) |> Repo.update!()

    run
    |> Ecto.Changeset.change(
      state: "running",
      active_step: "supplier_task",
      identity: identity(),
      identity_result: identity(),
      supplier_instructions: "Přečti EV-Č",
      identification: %{"state" => "completed", "attempts" => 1},
      content: %{"state" => "completed", "attempts" => 1},
      content_result: data() |> Map.put("items", []) |> Map.put("document_number", "39")
    )
    |> Repo.update!()
  end

  test "worker reports the old two-call database constraint without hiding the reason or paying for a third request" do
    # Reproduce a local database which has not received the new migration.
    Ecto.Adapters.SQL.query!(
      Repo,
      "ALTER TABLE incoming_documents DROP CONSTRAINT incoming_extraction_attempts"
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "ALTER TABLE incoming_documents ADD CONSTRAINT incoming_extraction_attempts CHECK (extraction_attempts BETWEEN 0 AND 2)"
    )

    doc = upload()
    profile(doc)
    expect(identity())
    expect(data())

    job = %Oban.Job{
      args: %{
        "document_id" => doc.id,
        "operation" => "extract",
        "run_id" => doc.active_extraction_run_id
      },
      attempt: 1,
      max_attempts: 3
    }

    assert {:error, _} = CozyCheckout.Workers.IncomingDocumentWorker.perform(job)
    failed = IncomingDocuments.get!(doc.id)
    run = IncomingDocuments.active_extraction_run(failed)
    assert failed.state == "failed"
    assert failed.error =~ "Databáze odmítla počet volání"
    assert failed.error =~ "migrace"
    assert failed.extraction_attempts == 2
    assert run.identification["state"] == "completed"
    assert run.content["state"] == "completed"
    assert run.supplier_task["state"] == "failed"
    assert run.supplier_task["exception_type"] == "Ecto.ConstraintError"
    assert run.supplier_task["constraint"] == "incoming_extraction_attempts"
    assert :ok = CozyCheckout.Workers.IncomingDocumentWorker.perform(%{job | attempt: 2})
    assert IncomingDocuments.get!(doc.id).sent_xml == nil
  end

  test "worker records an exception category immediately without exposing private error text" do
    doc = upload()
    private = "private document text and authorization-header-value"
    Req.Test.expect(__MODULE__, fn _conn -> raise private end)

    job = %Oban.Job{
      args: %{
        "document_id" => doc.id,
        "operation" => "extract",
        "run_id" => doc.active_extraction_run_id
      },
      attempt: 1,
      max_attempts: 3
    }

    assert {:error, message} = CozyCheckout.Workers.IncomingDocumentWorker.perform(job)
    failed = IncomingDocuments.get!(doc.id)
    run = IncomingDocuments.active_extraction_run(failed)
    assert failed.state == "failed"
    assert failed.error =~ "RuntimeError"
    assert run.identification["state"] == "failed"
    assert run.identification["exception_type"] == "RuntimeError"
    refute message =~ private
    refute failed.error =~ private
    refute Jason.encode!(run.identification) =~ private
    assert :ok = CozyCheckout.Workers.IncomingDocumentWorker.perform(%{job | attempt: 2})
    assert IncomingDocuments.get!(doc.id).extraction_attempts == 1
  end

  test "database allows three calls but still rejects a fourth and negative counters" do
    doc = upload()
    assert {:ok, _} = doc |> Ecto.Changeset.change(extraction_attempts: 3) |> Repo.update()

    for count <- [4, -1] do
      change =
        doc
        |> Ecto.Changeset.change(extraction_attempts: count)
        |> Ecto.Changeset.check_constraint(:extraction_attempts,
          name: :incoming_extraction_attempts
        )

      assert {:error, _} = Repo.update(change, mode: :savepoint)
    end
  end

  test "late exception reporting cannot mark a newer generation as failed" do
    doc = upload()
    old_run = IncomingDocuments.active_extraction_run(doc)
    ExtractionRuns.interrupt(doc.id, old_run.id)
    assert {:ok, next} = IncomingDocuments.retry_extraction(doc.id)

    assert {:error, :stale} =
             ExtractionRuns.worker_exception(doc.id, old_run.id, %RuntimeError{message: "private"})

    assert IncomingDocuments.get!(doc.id).active_extraction_run_id ==
             next.active_extraction_run_id

    assert IncomingDocuments.get!(doc.id).state == "uploaded"
  end

  test "ambiguous, missing, invalid, foreign, name-only and conflicting VAT identities stay generic" do
    doc = upload()
    profile(doc)

    for value <- [
          Map.put(identity(), "ambiguous", true),
          Map.put(identity(), "ic", "64945881"),
          Map.put(identity(), "ic", nil),
          Map.put(identity(), "country_code", nil),
          Map.put(identity(), "country_code", "SK"),
          Map.put(identity(), "dic", "CZ00000001")
        ] do
      assert {nil, _, reason} = SupplierProfiles.resolve(doc, value)
      assert is_binary(reason)
    end

    expect(Map.put(identity(), "ambiguous", true))

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      refute Jason.decode!(body)["instructions"] =~ "Přečti datum podle popisku."
      response(conn, data())
    end)

    IncomingDocuments.perform(doc.id, "extract")
    run = IncomingDocuments.active_extraction_run(IncomingDocuments.get!(doc.id))
    assert run.selection == "none"
    assert run.supplier_profile_id == nil
  end

  test "namespace, unique identity, explicit DIČ and revision protect profiles without model calls" do
    doc = upload()
    p = profile(doc)
    other = %{doc | company_id: "other"}
    assert {nil, _, _} = SupplierProfiles.resolve(other, identity())

    assert {found, _, _} =
             SupplierProfiles.resolve(%{doc | base_url: "https://accounting.test"}, identity())

    assert found.id == p.id

    assert {:error, _} =
             IncomingDocuments.save_supplier_instructions(doc.id, nil, attrs(), nil, true)

    assert {:error, _} =
             IncomingDocuments.save_supplier_instructions(doc.id, p.id, attrs(), 0, true)

    assert {:error, _} =
             IncomingDocuments.save_supplier_instructions(doc.id, p.id, attrs(), 1, false)

    assert {:error, _} =
             IncomingDocuments.save_supplier_instructions(
               doc.id,
               p.id,
               attrs(String.duplicate("x", 8001)),
               1,
               true
             )

    assert {:error, _} = SupplierProfiles.save(other, p.id, attrs(), 1, true)

    assert {:ok, changed} =
             IncomingDocuments.save_supplier_instructions(doc.id, p.id, attrs(""), 1, true)

    assert changed.revision == 2
    assert IncomingDocuments.get!(doc.id) == doc
    dic_attrs = attrs() |> Map.put("identity_kind", "dic") |> Map.put("ic", nil)

    assert {:error, _} =
             IncomingDocuments.save_supplier_instructions(doc.id, nil, dic_attrs, nil, false)

    assert {:ok, dic_profile} =
             IncomingDocuments.save_supplier_instructions(doc.id, nil, dic_attrs, nil, true)

    assert dic_profile.ic == nil
    assert dic_profile.identity_kind == "dic"
  end

  test "save and retry creates content and focused calls, archives manual draft and invalidates its approval" do
    doc = upload()
    p = profile(doc)
    doc = finish(doc)

    {:ok, saved} =
      IncomingDocuments.save_header(
        doc.id,
        header_attrs(),
        IncomingDocuments.transcription_hash(doc)
      )

    saved = saved |> Ecto.Changeset.change(dry_run: %{"ok" => true}) |> Repo.update!()

    assert {:ok, queued} =
             IncomingDocuments.save_supplier_and_retry(
               saved.id,
               p.id,
               attrs("Druhá revize"),
               1,
               true
             )

    assert queued.dry_run == %{}
    assert queued.current_xml == nil
    assert queued.edited_data == nil
    run = IncomingDocuments.active_extraction_run(queued)
    assert run.mode == "extract_only"
    assert run.previous_draft["current_xml"] == saved.current_xml
    assert run.previous_draft["header_values"]["cisDosle"] == "MANUAL"
    assert run.profile_revision == 2
    expect(data())
    expect(empty_task())
    IncomingDocuments.perform_extraction(queued.id, run.id)
    assert IncomingDocuments.get!(queued.id).extraction_attempts == 2
    assert {:ok, restored} = IncomingDocuments.restore_draft_from_run(queued.id, run.id)
    assert restored.current_xml == nil
    assert restored.dry_run == %{}
    assert HeaderForm.values(restored)["cisDosle"] == "MANUAL"
    assert {:error, _} = IncomingDocuments.send_header(restored.id, "old", true)
  end

  test "identification HTTP failure never calls content; explicit generic retry is a new run" do
    doc = upload()
    Req.Test.expect(__MODULE__, &Plug.Conn.send_resp(&1, 429, "{}"))
    IncomingDocuments.perform(doc.id, "extract")
    failed = IncomingDocuments.get!(doc.id)
    run = IncomingDocuments.active_extraction_run(failed)
    assert failed.state == "failed"
    assert run.identification["http_status"] == 429
    assert run.content == %{}
    IncomingDocuments.perform_extraction(doc.id, run.id, 2)

    assert {:ok, generic} =
             IncomingDocuments.retry_content_extraction(doc.id, without_supplier: true)

    expect(data())
    IncomingDocuments.perform(doc.id, "extract")
    assert IncomingDocuments.get!(generic.id).state == "review"
    assert IncomingDocuments.active_extraction_run(generic).mode == "extract_only"
    assert Repo.get!(ExtractionRun, run.id) == run
  end

  test "invalid identity JSON and a timeout stop at their own phase without automatic replay" do
    doc = upload()
    expect(%{"name" => "missing required fields"})
    IncomingDocuments.perform(doc.id, "extract")
    run = IncomingDocuments.active_extraction_run(IncomingDocuments.get!(doc.id))
    assert run.identification["state"] == "failed"
    assert run.content == %{}

    next = upload()
    expect(identity())

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    IncomingDocuments.perform(next.id, "extract")
    run = IncomingDocuments.active_extraction_run(IncomingDocuments.get!(next.id))
    assert run.identification["state"] == "completed"
    assert run.content["state"] == "failed"
    IncomingDocuments.perform_extraction(next.id, run.id, 2)
    assert IncomingDocuments.get!(next.id).extraction_attempts == 2
  end

  test "content failure preserves identity and malformed JSON cannot add an automatic third call" do
    doc = upload()
    p = profile(doc)
    expect(identity())
    expect(%{"wrong" => true})
    IncomingDocuments.perform(doc.id, "extract")
    failed = IncomingDocuments.get!(doc.id)
    run = IncomingDocuments.active_extraction_run(failed)
    assert run.identity["ic"] == "64945880"
    assert run.content["state"] == "failed"
    assert run.supplier_instructions == p.instructions
    IncomingDocuments.perform_extraction(doc.id, run.id, 2)
    assert {:ok, next} = IncomingDocuments.retry_content_extraction(doc.id)
    expect(data())
    expect(empty_task())
    IncomingDocuments.perform(doc.id, "extract")
    assert IncomingDocuments.active_extraction_run(next).origin_run_id == run.id
  end

  test "an uncertain reservation is never sent again by an Oban retry" do
    doc = upload()
    run = IncomingDocuments.active_extraction_run(doc)

    run
    |> Ecto.Changeset.change(
      state: "running",
      identification: %{"state" => "reserved", "token" => "old", "attempts" => 1}
    )
    |> Repo.update!()

    IncomingDocuments.perform_extraction(doc.id, run.id, 2)
    failed = IncomingDocuments.get!(doc.id)
    assert failed.state == "failed"
    assert failed.error =~ "není jisté"
    assert IncomingDocuments.active_extraction_run(failed).identification["attempts"] == 1
  end

  test "restart after committed identity resumes only unreserved content" do
    doc = upload()
    run = IncomingDocuments.active_extraction_run(doc)

    run
    |> Ecto.Changeset.change(
      state: "running",
      active_step: "content",
      identity: identity(),
      identity_result: identity(),
      identification: %{"state" => "completed", "attempts" => 1}
    )
    |> Repo.update!()

    expect(data())
    IncomingDocuments.perform_extraction(doc.id, run.id, 2)
    assert IncomingDocuments.get!(doc.id).state == "review"
  end

  test "late response of an interrupted run cannot replace a newer draft" do
    doc = upload()
    old_run = IncomingDocuments.active_extraction_run(doc)
    parent = self()

    Req.Test.expect(__MODULE__, fn conn ->
      send(parent, :reserved)

      receive do
        :release -> response(conn, identity())
      after
        5000 -> raise "test synchronization timeout"
      end
    end)

    task =
      Task.async(fn ->
        receive do
          :go -> IncomingDocuments.perform_extraction(doc.id, old_run.id)
        end
      end)

    Req.Test.allow(__MODULE__, self(), task.pid)
    send(task.pid, :go)
    assert_receive :reserved, 5000
    # A concurrent worker and a double click cannot reserve another call or run.
    assert :ok = IncomingDocuments.perform_extraction(doc.id, old_run.id)
    assert IncomingDocuments.get!(doc.id).extraction_attempts == 1
    assert {:error, _} = IncomingDocuments.retry_extraction(doc.id)
    ExtractionRuns.interrupt(doc.id, old_run.id)
    assert {:ok, next} = IncomingDocuments.retry_extraction(doc.id)
    send(task.pid, :release)
    assert :ok = Task.await(task)
    current = IncomingDocuments.get!(doc.id)
    assert current.active_extraction_run_id == next.active_extraction_run_id
    assert current.extracted_data == %{}
    assert current.extraction_attempts == 0
    assert Repo.get!(ExtractionRun, old_run.id).state == "failed"
  end

  test "changed source and changed accounting target block model calls" do
    doc = upload()
    doc |> Ecto.Changeset.change(sha256: "changed") |> Repo.update!()
    IncomingDocuments.perform(doc.id, "extract")
    assert IncomingDocuments.get!(doc.id).state == "failed"
    assert {:error, _} = IncomingDocuments.retry_content_extraction(doc.id)
    other = upload()

    Application.put_env(
      :cozy_checkout,
      :incoming_documents,
      Keyword.put(IncomingDocuments.config(), :company_id, "changed")
    )

    IncomingDocuments.perform(other.id, "extract")
    assert IncomingDocuments.get!(other.id).state == "failed"
  end

  test "identity conflict requires separate manual acknowledgment before saving a usable XML" do
    doc = upload()
    expect(identity())
    value = put_in(data(), ["supplier", "ic"], "00006947")
    expect(value)
    IncomingDocuments.perform(doc.id, "extract")
    doc = IncomingDocuments.get!(doc.id)
    assert doc.extraction_metadata["identity_conflict"] =~ "liší"

    assert {:error, _} =
             IncomingDocuments.save_header(
               doc.id,
               header_attrs(),
               IncomingDocuments.transcription_hash(doc)
             )

    assert {:ok, saved} =
             IncomingDocuments.save_header(
               doc.id,
               header_attrs(),
               IncomingDocuments.transcription_hash(doc),
               true
             )

    assert saved.current_xml
  end

  test "sent documents allow future instructions but reject AI, restore and atomic save-retry" do
    doc = upload()
    p = profile(doc)
    doc = finish(doc)
    doc = doc |> Ecto.Changeset.change(state: "sent", sent_xml: "immutable") |> Repo.update!()

    assert {:ok, changed} =
             IncomingDocuments.save_supplier_instructions(doc.id, p.id, attrs("Budoucí"), 1, true)

    assert {:error, _} = IncomingDocuments.retry_extraction(doc.id)
    assert {:error, _} = IncomingDocuments.retry_content_extraction(doc.id)

    assert {:error, _} =
             IncomingDocuments.restore_draft_from_run(doc.id, doc.active_extraction_run_id)

    assert {:error, _} =
             IncomingDocuments.save_supplier_and_retry(doc.id, p.id, attrs("Rollback"), 2, true)

    assert IncomingDocuments.supplier_profile(doc.id, p.id).revision == changed.revision
    assert IncomingDocuments.get!(doc.id) == doc
  end

  test "old jobs gain exactly one run, and an already reserved old call requires manual recovery" do
    {:ok, %{document: old}} =
      IncomingDocuments.upload("%PDF-old", "old.pdf", "zavazek", "structured")

    old
    |> Ecto.Changeset.change(extraction_metadata: %{"strategy" => "header_form"})
    |> Repo.update!()

    expect(identity())
    expect(data())
    IncomingDocuments.perform_extraction(old.id, nil)
    IncomingDocuments.perform_extraction(old.id, nil, 2)
    assert length(IncomingDocuments.list_extraction_runs(old.id)) == 1

    {:ok, %{document: reserved}} =
      IncomingDocuments.upload("%PDF-other", "old.pdf", "zavazek", "structured")

    reserved
    |> Ecto.Changeset.change(
      extraction_metadata: %{"strategy" => "header_form"},
      extraction_attempts: 1
    )
    |> Repo.update!()

    IncomingDocuments.perform_extraction(reserved.id, nil, 2)
    assert IncomingDocuments.get!(reserved.id).state == "failed"
    assert IncomingDocuments.list_extraction_runs(reserved.id) == []
  end

  test "document listing and exact lookup use a constant number of bounded queries" do
    doc = upload()
    profile(doc)
    upload()
    key = {__MODULE__, make_ref()}
    Process.put(key, [])

    :telemetry.attach(
      key,
      [:cozy_checkout, :repo, :query],
      fn _, _, meta, _ ->
        Process.put(key, [meta.query | Process.get(key, [])])
      end,
      nil
    )

    try do
      rows = IncomingDocuments.list()
      assert length(Process.get(key)) == 1
      refute Enum.any?(rows, &Map.has_key?(&1, :original))
      Process.put(key, [])
      assert {_, _, _} = SupplierProfiles.resolve(doc, identity())
      assert length(Process.get(key)) == 1
      Process.put(key, [])
      IncomingDocuments.list_extraction_runs(doc.id)
      assert length(Process.get(key)) == 1
    after
      :telemetry.detach(key)
      Process.delete(key)
    end
  end

  test "database rejects a run pointer belonging to another document" do
    first = upload()
    second = upload()

    changes =
      first
      |> Ecto.Changeset.change(active_extraction_run_id: second.active_extraction_run_id)
      |> Ecto.Changeset.foreign_key_constraint(:active_extraction_run_id,
        name: :incoming_active_run_document
      )

    assert {:error, _} = Repo.update(changes, mode: :savepoint)

    assert Repo.get!(Document, first.id).active_extraction_run_id ==
             first.active_extraction_run_id
  end
end

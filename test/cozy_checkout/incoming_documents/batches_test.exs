defmodule CozyCheckout.IncomingDocuments.BatchesTest do
  use CozyCheckout.DataCase, async: false
  @moduletag :financial
  import Ecto.Query
  alias CozyCheckout.{IncomingDocuments, Repo}
  alias CozyCheckout.IncomingDocuments.{Batches, ExtractionRun, ExtractionRuns}

  setup do
    previous = IncomingDocuments.config()
    defaults = Req.default_options()

    Application.put_env(:cozy_checkout, :incoming_documents,
      enabled: true,
      base_url: "https://accounting.test/",
      company_id: "pilot",
      username: "test",
      password: "test",
      openai_api_key: "test-key",
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

  defp batch(agenda \\ "zavazek") do
    {:ok, batch} = Batches.create(%{"agenda" => agenda})
    batch
  end

  defp source(batch, content \\ "%PDF-synthetic") do
    {:ok, %{id: id}} = Batches.add_source(batch.id, content, "receipt.pdf")
    IncomingDocuments.get!(id)
  end

  defp update_record(record, attrs), do: record |> Ecto.Changeset.change(attrs) |> Repo.update!()

  defp finish(doc, state) do
    run = Repo.get!(ExtractionRun, doc.initial_extraction_run_id)
    update_record(run, state: state)

    update_record(doc,
      state: if(state == "completed", do: "review", else: "failed"),
      error_stage: if(state == "failed", do: "extraction")
    )
  end

  test "staging survives reload without jobs or runs; invalid source does not undo good uploads" do
    batch = batch()
    doc = source(batch)
    assert doc.state == "staged"
    assert doc.original == "%PDF-synthetic"
    assert is_nil(doc.active_extraction_run_id)
    assert Repo.aggregate(ExtractionRun, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0
    assert {:error, _} = Batches.add_source(batch.id, "not a PDF", "bad.pdf")
    assert [%{id: id}] = Batches.documents(batch.id)
    assert id == doc.id
  end

  test "same batch retries are idempotent at the limit and removed sources can be readded" do
    Application.put_env(
      :cozy_checkout,
      :incoming_documents,
      Keyword.put(IncomingDocuments.config(), :batch_max_files, 1)
    )

    batch = batch()
    doc = source(batch)

    assert {:ok, %{id: id, duplicate?: true}} =
             Batches.add_source(batch.id, doc.original, "retry.pdf")

    assert id == doc.id
    assert {:error, _} = Batches.add_source(batch.id, "%PDF-other", "other.pdf")
    assert {:ok, :ok} = Batches.remove_source(batch.id, doc.id)
    replacement = source(batch)
    assert replacement.id != doc.id
    assert replacement.batch_position == 2
  end

  test "a later configuration change does not hide sources or alter an existing batch limit" do
    batch = batch()
    source(batch, "%PDF-one")
    source(batch, "%PDF-two")

    Application.put_env(
      :cozy_checkout,
      :incoming_documents,
      Keyword.put(IncomingDocuments.config(), :batch_max_files, 1)
    )

    assert length(Batches.documents(batch.id)) == 2
    assert {:ok, _} = Batches.add_source(batch.id, "%PDF-three", "three.pdf")
    new_batch = batch()
    assert new_batch.max_files == 1
  end

  test "cross-batch duplicates require an explicit override and are isolated by target" do
    first = batch()
    doc = source(first)
    second = batch()

    assert {:error, {:duplicate, %{id: id}}} =
             Batches.add_source(second.id, doc.original, doc.filename)

    assert id == doc.id
    assert Batches.documents(second.id) == []

    assert {:ok, _} =
             Batches.add_source(second.id, doc.original, doc.filename, allow_duplicate: true)

    Application.put_env(
      :cozy_checkout,
      :incoming_documents,
      Keyword.put(IncomingDocuments.config(), :company_id, "other")
    )

    other = batch()
    assert {:ok, _} = Batches.add_source(other.id, doc.original, doc.filename)
  end

  test "start is idempotent and pins model, agenda and accounting independently for each document" do
    for agenda <- ~w(faktura-prijata pokladni-pohyb zavazek) do
      batch = batch(agenda)
      one = source(batch, "%PDF-#{agenda}-1")
      two = source(batch, "%PDF-#{agenda}-2")
      assert {:ok, started} = Batches.start(batch.id)
      assert started.model == "test-model"
      assert {:ok, same} = Batches.start(batch.id)
      assert same.started_at == started.started_at

      for id <- [one.id, two.id] do
        doc = IncomingDocuments.get!(id)
        run = Repo.get!(ExtractionRun, doc.initial_extraction_run_id)
        assert doc.state == "uploaded"
        assert doc.agenda == agenda
        assert run.model == "test-model"
        refute Map.has_key?(run.schemas["content"]["properties"], "items")

        assert Repo.aggregate(
                 from(j in Oban.Job,
                   where:
                     fragment("?->>'run_id'", j.args) == ^run.id and
                       j.queue == "incoming_extraction"
                 ),
                 :count
               ) == 1

        assert doc.accounting_settings["kod"] in [nil, ""]
      end

      assert {:error, _} = Batches.add_source(batch.id, "%PDF-too-late", "late.pdf")
      assert {:error, _} = Batches.remove_source(batch.id, one.id)
      assert {:error, _} = Batches.save_settings(batch.id, "", false)
    end
  end

  test "concurrent starts and repeated uploads create one document, run and job" do
    batch = batch()

    results =
      1..2
      |> Task.async_stream(
        fn _ -> Batches.add_source(batch.id, "%PDF-concurrent", "same.pdf") end,
        max_concurrency: 2
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))
    [doc] = Batches.documents(batch.id)

    starts =
      1..2
      |> Task.async_stream(fn _ -> Batches.start(batch.id) end, max_concurrency: 2)
      |> Enum.to_list()

    assert Enum.all?(starts, &match?({:ok, {:ok, _}}, &1))
    assert Repo.aggregate(from(r in ExtractionRun, where: r.document_id == ^doc.id), :count) == 1

    assert Repo.aggregate(
             from(j in Oban.Job, where: fragment("?->>'document_id'", j.args) == ^doc.id),
             :count
           ) == 1
  end

  test "empty batches, missing AI config and changed targets cannot start" do
    batch = batch()
    assert {:error, _} = Batches.start(batch.id)
    source(batch)

    Application.put_env(
      :cozy_checkout,
      :incoming_documents,
      Keyword.delete(IncomingDocuments.config(), :openai_api_key)
    )

    assert {:error, _} = Batches.start(batch.id)
    assert is_nil(Batches.get!(batch.id).started_at)
    assert Repo.aggregate(ExtractionRun, :count) == 0

    Application.put_env(
      :cozy_checkout,
      :incoming_documents,
      Keyword.put(IncomingDocuments.config(), :company_id, "other")
    )

    assert {:error, _} = Batches.start(batch.id)
  end

  test "a job insertion failure rolls back every run, job and document state" do
    batch = batch()
    one = source(batch, "%PDF-one")
    two = source(batch, "%PDF-two")
    # Fail the second job, after the first document's run, job and state were updated.
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      CREATE FUNCTION pg_temp.reject_batch_job() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.args->>'document_id' = '#{two.id}' THEN
          RAISE EXCEPTION 'synthetic failure';
        END IF;
        RETURN NEW;
      END $$
      """
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "CREATE TRIGGER reject_batch_job BEFORE INSERT ON oban_jobs FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_batch_job()"
    )

    error = assert_raise Postgrex.Error, fn -> Batches.start(batch.id) end
    assert error.postgres.message == "synthetic failure"
    assert is_nil(Batches.get!(batch.id).started_at)

    for original <- [one, two] do
      doc = IncomingDocuments.get!(original.id)
      assert doc.state == "staged"
      assert is_nil(doc.active_extraction_run_id)
      assert is_nil(doc.initial_extraction_run_id)
    end

    assert Repo.aggregate(ExtractionRun, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0
  end

  test "shared accounting is validated once for the batch and copied as a snapshot" do
    batch = batch()
    one = source(batch, "%PDF-one")
    two = source(batch, "%PDF-two")

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "winstrom" => %{
          "predpis-zauctovani" => [
            %{
              "kod" => "NAKLAD",
              "nazev" => "Náklad",
              "modulZav" => true,
              "protiUcetVydej" => "code:501000"
            }
          ]
        }
      })
    end)

    assert {:ok, saved} = Batches.save_settings(batch.id, "NAKLAD", false)
    assert saved.accounting_settings["kod"] == ""
    assert {:ok, _} = Batches.start(batch.id)
    assert IncomingDocuments.get!(one.id).accounting_settings == saved.accounting_settings
    assert IncomingDocuments.get!(two.id).accounting_settings == saved.accounting_settings
  end

  test "start commits pending common settings with the initial jobs and rolls back empty batches" do
    batch = batch()
    pending = %{preset: "", include_items: true}
    assert {:error, _} = Batches.start(batch.id, pending)
    refute Batches.get!(batch.id).include_items
    doc = source(batch)
    assert {:ok, started} = Batches.start(batch.id, pending)
    assert started.include_items
    run = Repo.get!(ExtractionRun, IncomingDocuments.get!(doc.id).initial_extraction_run_id)
    assert Map.has_key?(run.schemas["content"]["properties"], "items")
  end

  test "mixed and all-failed batches become ready only after every first run ended" do
    for states <- [["completed", "failed"], ["failed", "failed"]] do
      batch = batch()
      one = source(batch, "%PDF-#{inspect(states)}-1")
      two = source(batch, "%PDF-#{inspect(states)}-2")
      Batches.start(batch.id)
      one = IncomingDocuments.get!(one.id)
      two = IncomingDocuments.get!(two.id)
      finish(one, hd(states))
      assert {:ok, %{extraction_finished_at: nil}} = Batches.refresh(batch.id)
      assert_raise Ecto.NoResultsError, fn -> Batches.review!(batch.id, one.id) end
      finish(two, List.last(states))
      assert {:ok, ready} = Batches.refresh(batch.id)
      assert ready.extraction_finished_at
      assert {_, rows} = Batches.review!(batch.id, one.id)
      assert Enum.map(rows, & &1.id) == [one.id, two.id]
      assert {:ok, again} = Batches.refresh(batch.id)
      assert again.extraction_finished_at == ready.extraction_finished_at
    end
  end

  test "retry and late stale results do not close a ready batch; deferral is durable" do
    batch = batch()
    doc = source(batch)
    Batches.start(batch.id)
    doc = IncomingDocuments.get!(doc.id)
    finish(doc, "failed")
    {:ok, ready} = Batches.refresh(batch.id)
    assert {:ok, _} = Batches.defer(batch.id, doc.id)
    assert IncomingDocuments.get!(doc.id).deferred_at
    assert {:ok, retried} = ExtractionRuns.start(doc.id)
    assert retried.active_extraction_run_id != doc.initial_extraction_run_id
    assert {:error, :stale} = ExtractionRuns.interrupt(doc.id, doc.initial_extraction_run_id)
    assert Batches.progress(batch.id).failed == 1
    assert Batches.progress(batch.id).waiting == 0
    assert {:ok, still_ready} = Batches.refresh(batch.id)
    assert ready.extraction_finished_at == still_ready.extraction_finished_at
  end

  test "review rejects a document from another batch" do
    batch = batch()
    doc = source(batch)
    Batches.start(batch.id)
    finish(IncomingDocuments.get!(doc.id), "completed")
    assert {:ok, ready} = Batches.refresh(batch.id)
    assert ready.extraction_finished_at
    foreign = source(batch(), "%PDF-foreign")
    assert_raise Ecto.NoResultsError, fn -> Batches.review!(batch.id, foreign.id) end
  end

  test "reconciliation interrupts terminal jobs only, without creating new jobs" do
    batch = batch()
    one = source(batch, "%PDF-one")
    two = source(batch, "%PDF-two")
    Batches.start(batch.id)
    one = IncomingDocuments.get!(one.id)

    Repo.update_all(
      from(j in Oban.Job,
        where: fragment("?->>'run_id'", j.args) == ^one.initial_extraction_run_id
      ),
      set: [state: "discarded", discarded_at: DateTime.utc_now()]
    )

    assert :ok = Batches.reconcile()
    assert IncomingDocuments.get!(one.id).state == "failed"
    assert IncomingDocuments.get!(two.id).state == "uploaded"
    assert is_nil(Batches.get!(batch.id).extraction_finished_at)
    assert Repo.aggregate(Oban.Job, :count) == 2
    assert :ok = Batches.reconcile()
    assert Repo.aggregate(Oban.Job, :count) == 2
  end

  test "model snapshot controls both image preparation and paid phases after config changes" do
    batch = batch()
    doc = source(batch)
    Batches.start(batch.id)
    doc = IncomingDocuments.get!(doc.id)

    Application.put_env(
      :cozy_checkout,
      :incoming_documents,
      Keyword.put(IncomingDocuments.config(), :openai_model, "changed-model")
    )

    Req.Test.expect(__MODULE__, fn conn ->
      request =
        (fn ->
           {:ok, body, _} = Plug.Conn.read_body(conn)
           Jason.decode!(body)
         end).()

      assert request["model"] == "test-model"

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
                    "name" => "Test",
                    "ic" => nil,
                    "dic" => nil,
                    "country_code" => "CZ",
                    "ambiguous" => true,
                    "uncertainties" => []
                  })
              }
            ]
          }
        ]
      })
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      request =
        (fn ->
           {:ok, body, _} = Plug.Conn.read_body(conn)
           Jason.decode!(body)
         end).()

      assert request["model"] == "test-model"
      Req.Test.json(Plug.Conn.put_status(conn, 400), %{"error" => %{"message" => "synthetic"}})
    end)

    ExtractionRuns.perform(doc.id, doc.initial_extraction_run_id)
    run = Repo.get!(ExtractionRun, doc.initial_extraction_run_id)
    assert run.identification["model"] == "test-model"
    assert run.content["model"] == "test-model"
  end

  test "list queries remain bounded and never select private source columns" do
    batch = batch()
    source(batch)

    queries =
      capture_queries(fn ->
        Batches.list()
        Batches.documents(batch.id, batch.max_files)
        Batches.progress(batch.id)
      end)

    for n <- 1..8, do: source(batch, "%PDF-#{n}")

    more =
      capture_queries(fn ->
        Batches.list()
        Batches.documents(batch.id, batch.max_files)
        Batches.progress(batch.id)
      end)

    assert length(queries) == 3
    assert length(more) == 3

    refute Enum.any?(
             more,
             &String.contains?(&1, ["\"original\"", "\"current_xml\"", "\"content_result\""])
           )
  end

  defp capture_queries(fun) do
    id = "batch-query-#{System.unique_integer()}"
    parent = self()

    :telemetry.attach(
      id,
      [:cozy_checkout, :repo, :query],
      fn _, _, meta, _ -> send(parent, {:batch_query, meta.query}) end,
      nil
    )

    try do
      fun.()
      collect_queries([])
    after
      :telemetry.detach(id)
    end
  end

  defp collect_queries(result) do
    receive do
      {:batch_query, sql} -> collect_queries([sql | result])
    after
      0 -> result
    end
  end
end

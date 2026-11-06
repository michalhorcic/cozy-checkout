defmodule CozyCheckout.IncomingDocuments.ExtractionRuns do
  @moduledoc "Durable extraction with an independent supplier task. Reservations prevent automatic replay of uncertain paid calls."
  import Ecto.Query
  alias CozyCheckout.{IncomingDocuments, Repo}

  alias CozyCheckout.IncomingDocuments.{
    Document,
    ExtractionRun,
    Extractor,
    SourceImages,
    SupplierIdentity,
    SupplierProfiles,
    SupplierTask,
    Transcription
  }

  alias CozyCheckout.Workers.IncomingDocumentWorker

  def active(%{active_extraction_run_id: nil}), do: nil
  def active(doc), do: Repo.get(ExtractionRun, doc.active_extraction_run_id)

  def active_for_display(%{active_extraction_run_id: nil}), do: nil

  def active_for_display(doc),
    do:
      Repo.one(
        from r in display_query(),
          where: r.id == ^doc.active_extraction_run_id and r.document_id == ^doc.id
      )

  def list(document_id, page \\ 0) do
    Repo.all(
      from r in display_query(),
        where: r.document_id == ^document_id,
        order_by: [desc: r.generation],
        limit: 10,
        offset: ^(max(page, 0) * 10)
    )
  end

  defp display_query do
    from r in ExtractionRun,
      select:
        struct(r, [
          :id,
          :generation,
          :mode,
          :schemas,
          :state,
          :active_step,
          :identity,
          :identity_result,
          :selection,
          :selection_reason,
          :supplier_profile_id,
          :profile_revision,
          :supplier_instructions,
          :supplier_task_instructions,
          :supplier_task_result,
          :common_instructions_hash,
          :supplier_instructions_hash,
          :identity_conflict,
          :inserted_at
        ])
        |> merge(%{
          identification: fragment("? - 'raw_output' - 'images' - 'token'", r.identification),
          content: fragment("? - 'raw_output' - 'images' - 'token'", r.content),
          supplier_task: fragment("? - 'raw_output' - 'images' - 'token'", r.supplier_task)
        })
  end

  def start(id, opts \\ []) do
    locked(id, fn doc -> start_locked(doc, opts) end)
  end

  # Caller must already hold the document row lock (upload owns its new row).
  def start_locked(doc, opts \\ []) do
    unless is_nil(doc.sent_xml) and is_nil(doc.deleted_at) and
             (doc.state == "review" or (doc.state == "failed" and doc.error_stage == "extraction") or
                (opts[:initial] && doc.state in ["uploaded", "processing"] &&
                   is_nil(doc.active_extraction_run_id))),
           do: Repo.rollback("Vytěžení je uzamčené nebo již probíhá.")

    unless is_binary(doc.original) and IncomingDocuments.digest(doc.original) == doc.sha256,
      do: Repo.rollback("Chybí originál nebo se změnil jeho hash.")

    require_target!(doc)

    previous = active(doc)
    mode = opts[:mode] || "identify_and_extract"

    unless mode in ["identify_and_extract", "extract_only"],
      do: Repo.rollback("Neplatný režim běhu.")

    generation =
      (Repo.one(
         from r in ExtractionRun,
           where: r.document_id == ^doc.id,
           select: max(r.generation)
       ) || 0) + 1

    include_items = Keyword.get(opts, :include_items, false)
    unless is_boolean(include_items), do: Repo.rollback("Neplatná volba načítání položek.")
    common = Extractor.instructions("header_form", include_items)

    run = %ExtractionRun{
      document_id: doc.id,
      generation: generation,
      mode: mode,
      source_sha256: doc.sha256,
      base_url: doc.base_url,
      company_id: doc.company_id,
      active_step: if(mode == "extract_only", do: "content", else: "identify"),
      common_instructions: common,
      common_instructions_hash: IncomingDocuments.digest(common),
      identity_instructions: Extractor.identity_instructions(),
      supplier_task_instructions: Extractor.supplier_task_instructions(),
      supplier_instructions_hash: IncomingDocuments.digest(""),
      schemas: %{
        "identity" => SupplierIdentity.schema(),
        "supplier_task" => SupplierTask.schema(),
        "content" =>
          if(include_items, do: Transcription.schema(), else: Transcription.header_schema())
      },
      previous_draft: draft(doc),
      origin_run_id: previous && previous.id
    }

    run = if mode == "extract_only", do: select_for_retry(run, doc, previous, opts), else: run
    run = Repo.insert!(run, log: false)

    case %{document_id: doc.id, operation: "extract", run_id: run.id}
         |> IncomingDocumentWorker.new()
         |> Oban.insert() do
      {:ok, %{conflict?: false}} -> :ok
      _ -> Repo.rollback("Nové vytěžení se nepodařilo zařadit do fronty.")
    end

    update!(doc,
      active_extraction_run_id: run.id,
      state: "uploaded",
      current_xml: nil,
      generated_xml: nil,
      extracted_data: %{},
      edited_data: nil,
      dry_run: %{},
      extraction_metadata: %{
        "strategy" => "header_form",
        "run_id" => run.id,
        "include_items" => include_items
      },
      extraction_attempts: 0,
      error: nil,
      error_stage: nil
    )
  end

  defp select_for_retry(run, doc, previous, opts) do
    cond do
      opts[:without_supplier] ->
        %{run | selection_reason: "Obsluha výslovně zvolila obecné vytěžení bez dodavatele."}

      opts[:profile_id] ->
        profile = SupplierProfiles.get(doc, opts[:profile_id])

        unless profile && opts[:confirmed] == true,
          do: Repo.rollback("Vyberte a potvrďte dodavatele cílové firmy.")

        snapshot(
          %{
            run
            | identity: SupplierProfiles.identity(profile),
              selection: "manual",
              selection_reason: "Dodavatel výslovně vybrán obsluhou."
          },
          profile
        )

      previous && previous.source_sha256 == doc.sha256 && previous.identity != %{} ->
        {profile, identity, reason} =
          if previous.selection == "manual" do
            profile = SupplierProfiles.get(doc, previous.supplier_profile_id)
            {profile, previous.identity, "Převzata ručně potvrzená identita předchozího běhu."}
          else
            SupplierProfiles.resolve(doc, previous.identity_result)
          end

        snapshot(
          %{
            run
            | identity: identity,
              identity_result: previous.identity_result,
              selection: if(profile, do: previous.selection, else: "none"),
              selection_reason: reason
          },
          profile
        )

      true ->
        Repo.rollback(
          "Není dostupná identita stejného originálu. Určete dodavatele nebo zvolte obecné vytěžení."
        )
    end
  end

  defp snapshot(run, nil), do: run

  defp snapshot(run, profile),
    do: %{
      run
      | supplier_profile_id: profile.id,
        profile_revision: profile.revision,
        supplier_instructions: profile.instructions,
        supplier_instructions_hash: IncomingDocuments.digest(profile.instructions)
    }

  defp draft(doc) do
    Map.new(
      ~w(extracted_data edited_data current_xml generated_xml accounting_settings extraction_metadata)a,
      &{Atom.to_string(&1), Map.get(doc, &1)}
    )
    |> Map.put("header_values", CozyCheckout.IncomingDocuments.HeaderForm.values(doc))
  end

  def restore(id, run_id) do
    locked(id, fn doc ->
      unless is_nil(doc.sent_xml) and doc.state in ["failed", "review"],
        do: Repo.rollback("Pracovní návrh je uzamčený.")

      run = Repo.one(from r in ExtractionRun, where: r.id == ^run_id and r.document_id == ^id)

      unless run && run.source_sha256 == doc.sha256 && run.previous_draft != %{} &&
               (run.previous_draft["current_xml"] || run.previous_draft["extracted_data"] != %{}),
             do: Repo.rollback("Tento běh nemá obnovitelný návrh stejného originálu.")

      values =
        Enum.map(
          ~w(extracted_data edited_data current_xml generated_xml accounting_settings)a,
          &{&1, run.previous_draft[Atom.to_string(&1)]}
        )

      values =
        Keyword.put(values, :edited_data, %{"header_form" => run.previous_draft["header_values"]})

      metadata =
        doc.extraction_metadata
        |> Map.put("restored_from_run", run.id)
        |> Map.put(
          "identity_conflict",
          get_in(run.previous_draft, ["extraction_metadata", "identity_conflict"])
        )
        |> Map.put("identity_confirmed", false)

      # No prior XML can be approved until the operator saves and reviews the restored form again.
      update!(
        doc,
        Keyword.merge(values,
          state: "review",
          current_xml: nil,
          dry_run: %{},
          extraction_metadata: metadata,
          error: nil,
          error_stage: nil
        )
      )
    end)
  end

  def ensure_legacy(id) do
    locked(id, fn doc ->
      cond do
        doc.active_extraction_run_id ->
          doc.active_extraction_run_id

        doc.state not in ["uploaded", "processing"] ->
          nil

        doc.extraction_attempts > 0 ->
          update!(doc,
            state: "failed",
            error_stage: "extraction",
            error: "Starší vytěžení bylo přerušeno. Spusťte nový běh ručně."
          )

          nil

        true ->
          start_locked(doc, initial: true) |> Map.fetch!(:active_extraction_run_id)
      end
    end)
  end

  def perform(id, run_id, attempt \\ 1) do
    run = Repo.get(ExtractionRun, run_id)
    doc = IncomingDocuments.get!(id)

    if run && run.document_id == id && doc.active_extraction_run_id == run_id &&
         run.state in ["pending", "running"] && doc.state in ["uploaded", "processing"] do
      cond do
        attempt > 1 && reserved?(run) ->
          interrupt(id, run_id)

        true ->
          preparation =
            with {:ok, _} <- locked(id, fn current -> guard!(current, run) end),
                 do: SourceImages.prepare(doc, IncomingDocuments.config())

          case preparation do
            {:ok, parts, images} ->
              step(id, run_id, "identify", parts, images)
              step(id, run_id, "content", parts, images)
              step(id, run_id, "supplier_task", parts, images)

            {:error, reason} when is_binary(reason) ->
              fail(id, run_id, reason)

            _ ->
              :ok
          end
      end
    end

    :ok
  end

  defp reserved?(run),
    do:
      Enum.any?(
        [run.identification, run.content, run.supplier_task],
        &(&1["state"] == "reserved")
      )

  defp step(id, run_id, phase, parts, images) do
    case locked(id, fn doc ->
           run = Repo.get!(ExtractionRun, run_id)
           guard!(doc, run)
           if run.active_step != phase || metadata(run, phase) != %{}, do: Repo.rollback(:skip)
           token = Ecto.UUID.generate()

           meta = %{
             "state" => "reserved",
             "token" => token,
             "attempts" => 1,
             "started_at" => now(),
             "model" =>
               run.identification["model"] || run.content["model"] ||
                 IncomingDocuments.config()[:openai_model],
             "images" => images
           }

           run = update!(run, [{field(phase), meta}, {:state, "running"}])
           update!(doc, state: "processing", extraction_attempts: doc.extraction_attempts + 1)
           {run, token}
         end) do
      {:ok, {run, token}} ->
        cfg =
          Keyword.put(IncomingDocuments.config(), :openai_model, metadata(run, phase)["model"])

        result =
          case phase do
            "identify" -> Extractor.identify(run, cfg, parts)
            "content" -> Extractor.extract_content(run, cfg, parts)
            "supplier_task" -> Extractor.extract_supplier_task(run, cfg, parts)
          end

        case persist(id, run, phase, token, result) do
          {:error, reason} when is_binary(reason) -> fail(id, run_id, reason)
          _ -> :ok
        end

      {:error, reason} when is_binary(reason) ->
        fail(id, run_id, reason)

      _ ->
        :ok
    end
  end

  defp persist(id, reserved, phase, token, result) do
    locked(id, fn doc ->
      run = Repo.get!(ExtractionRun, reserved.id)
      guard!(doc, run)

      unless run.active_step == phase && metadata(run, phase)["token"] == token &&
               metadata(run, phase)["state"] == "reserved",
             do: Repo.rollback(:stale)

      {state, data, extra, reason} =
        case result do
          {:ok, data, extra} -> {"completed", data, extra, nil}
          {:error, reason, extra} -> {"failed", %{}, extra, reason}
        end

      meta =
        Map.merge(metadata(run, phase), extra)
        |> Map.merge(%{
          "state" => state,
          "finished_at" => now(),
          "error" => reason
        })

      run = update!(run, [{field(phase), meta}])
      call = meta |> Map.drop(["raw_output", "images", "token"]) |> Map.put("phase", phase)
      summary = Map.update(doc.extraction_metadata, "calls", [call], &(&1 ++ [call]))

      cond do
        reason ->
          update!(run, state: "failed")

          update!(doc,
            state: "failed",
            error_stage: "extraction",
            error: reason,
            extraction_metadata: summary
          )

        phase == "identify" ->
          {profile, identity, reason} = SupplierProfiles.resolve(doc, data)

          selected =
            snapshot(
              %{
                run
                | identity_result: data,
                  identity: identity,
                  selection: if(profile, do: "exact_ic", else: "none"),
                  selection_reason: reason,
                  active_step: "content"
              },
              profile
            )

          Repo.update!(
            Ecto.Changeset.change(
              run,
              Map.take(
                Map.from_struct(selected),
                ~w(identity_result identity selection selection_reason
              active_step supplier_profile_id profile_revision supplier_instructions supplier_instructions_hash)a
              )
            ),
            log: false
          )

          update!(doc, extraction_metadata: summary)

        phase == "content" and Extractor.has_supplier_task?(run) ->
          update!(run, content_result: data, active_step: "supplier_task")
          update!(doc, extraction_metadata: summary)

        phase == "supplier_task" ->
          merged = SupplierTask.merge(run.content_result, data)

          case Transcription.validate(merged) do
            :ok ->
              run = update!(run, supplier_task_result: data)
              complete!(doc, run, merged, summary)

            {:error, reason} ->
              Repo.rollback(reason)
          end

        true ->
          run = update!(run, content_result: data)
          complete!(doc, run, data, summary)
      end
    end)
  end

  defp complete!(doc, run, data, summary) do
    conflict = SupplierIdentity.conflict(run.identity, data["supplier"])

    update!(run,
      result: data,
      state: "completed",
      active_step: "done",
      identity_conflict: conflict
    )

    update!(doc,
      state: "review",
      extracted_data: data,
      edited_data: nil,
      current_xml: nil,
      generated_xml: nil,
      dry_run: %{},
      error: nil,
      error_stage: nil,
      extraction_metadata: Map.put(summary, "identity_conflict", conflict)
    )
  end

  defp metadata(run, "identify"), do: run.identification
  defp metadata(run, "content"), do: run.content
  defp metadata(run, "supplier_task"), do: run.supplier_task
  defp field("supplier_task"), do: :supplier_task
  defp field("identify"), do: :identification
  defp field("content"), do: :content

  def interrupt(id, run_id),
    do:
      fail(
        id,
        run_id,
        "Fáze vytěžení byla přerušena; není jisté, zda OpenAI dotaz provedlo. Nový placený pokus spusťte ručně."
      )

  defp fail(id, run_id, reason) do
    locked(id, fn doc ->
      run = Repo.get!(ExtractionRun, run_id)
      guard!(doc, run, false)

      meta =
        metadata(run, run.active_step)
        |> Map.merge(%{
          "state" => "failed",
          "error" => reason,
          "finished_at" => now()
        })

      update!(run, [{:state, "failed"}, {field(run.active_step), meta}])

      update!(doc,
        state: "failed",
        error_stage: "extraction",
        error: reason,
        current_xml: nil,
        dry_run: %{}
      )
    end)
  end

  defp guard!(doc, run, verify_source \\ true) do
    unless doc.active_extraction_run_id == run.id && run.document_id == doc.id &&
             run.state in ["pending", "running"] && doc.state in ["uploaded", "processing"] &&
             is_nil(doc.sent_xml),
           do: Repo.rollback(:stale)

    if verify_source do
      require_target!(doc)

      unless doc.sha256 == run.source_sha256 && doc.base_url == run.base_url &&
               doc.company_id == run.company_id && is_binary(doc.original) &&
               IncomingDocuments.digest(doc.original) == run.source_sha256,
             do: Repo.rollback("Originál se změnil.")
    end
  end

  defp require_target!(doc) do
    cfg = IncomingDocuments.config()

    unless cfg[:enabled] == true &&
             SupplierProfiles.base_url(doc.base_url) ==
               SupplierProfiles.base_url(cfg[:base_url] || "") &&
             doc.company_id == cfg[:company_id],
           do: Repo.rollback("Cílová firma se změnila; vytěžení je blokováno.")
  end

  defp now, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()

  defp update!(record, attrs),
    do: record |> Ecto.Changeset.change(attrs) |> Repo.update!(log: false)

  defp locked(id, fun) do
    Repo.transaction(fn ->
      doc =
        Repo.one!(
          from d in Document, where: d.id == ^id and is_nil(d.deleted_at), lock: "FOR UPDATE"
        )

      fun.(doc)
    end)
  end
end

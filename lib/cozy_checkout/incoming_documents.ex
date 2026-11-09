defmodule CozyCheckout.IncomingDocuments do
  @moduledoc "Admin-reviewed received documents with immutable create-only ABRA delivery."
  import Ecto.Query
  alias CozyCheckout.Repo

  alias CozyCheckout.IncomingDocuments.{
    Accounting,
    Builder,
    Client,
    Document,
    Extractor,
    ExtractionRuns,
    SupplierProfiles,
    SourceImages,
    XML
  }

  alias CozyCheckout.Workers.IncomingDocumentWorker

  @max_size 10_000_000
  def max_size, do: @max_size
  def config, do: Application.get_env(:cozy_checkout, :incoming_documents, [])
  def enabled?, do: config()[:enabled] == true

  def agendas,
    do: [
      {"Přijatá faktura", "faktura-prijata"},
      {"Pokladna — výdaj", "pokladni-pohyb"},
      {"Ostatní závazky — platba kartou", "zavazek"}
    ]

  def agenda_label(agenda),
    do: Enum.find_value(agendas(), agenda, fn {label, key} -> if key == agenda, do: label end)

  def digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  # One bounded query; never load original files or XML for list rows.
  def list do
    Repo.all(
      from d in Document,
        where: is_nil(d.deleted_at),
        order_by: [desc: d.inserted_at, desc: d.id],
        limit: 100,
        select: map(d, [:id, :filename, :agenda, :state, :inserted_at, :company_id])
    )
  end

  def get!(id), do: Repo.one!(from d in Document, where: d.id == ^id and is_nil(d.deleted_at))

  def duplicate?(sha),
    do: Repo.exists?(from d in Document, where: d.sha256 == ^sha and is_nil(d.deleted_at))

  def upload(bytes, filename, agenda, strategy \\ "structured", opts \\ []) do
    cfg = config()

    with :ok <- configured(cfg),
         true <- agenda in XML.agendas() and strategy in Extractor.strategies(),
         {:ok, mime} <- content_type(bytes, filename) do
      id = Ecto.UUID.generate()
      sha = digest(bytes)
      duplicate = duplicate?(sha)

      Repo.transaction(fn ->
        doc =
          Repo.insert!(
            %Document{
              id: id,
              agenda: agenda,
              original: bytes,
              filename: Path.basename(filename),
              content_type: mime,
              sha256: sha,
              template_xml: XML.template(agenda),
              extraction_metadata: %{"strategy" => strategy},
              base_url: cfg[:base_url],
              company_id: cfg[:company_id],
              external_id: "ext:cozy-incoming:#{id}"
            },
            log: false
          )

        doc =
          if strategy == "header_form" do
            ExtractionRuns.start_locked(doc, Keyword.put(opts, :initial, true))
          else
            job!(doc.id, "extract")
            doc
          end

        %{document: doc, duplicate?: duplicate}
      end)
    else
      false -> {:error, "Vyberte podporovanou agendu a způsob vytěžení"}
      error -> error
    end
  end

  @doc "Creates a reviewed manual header without requiring a source file or OpenAI."
  def create_header(agenda, attrs) do
    cfg = config()

    with :ok <- configured(cfg),
         true <- agenda in XML.agendas() do
      id = Ecto.UUID.generate()

      doc = %Document{
        id: id,
        agenda: agenda,
        filename: "Ruční doklad",
        template_xml: XML.template(agenda),
        external_id: "ext:cozy-incoming:#{id}",
        base_url: cfg[:base_url],
        company_id: cfg[:company_id],
        extraction_metadata: %{"strategy" => "header_form"}
      }

      with {:ok, values, xml} <- CozyCheckout.IncomingDocuments.HeaderForm.build(attrs, doc) do
        Repo.insert(
          %{
            doc
            | state: "review",
              edited_data: %{"header_form" => values},
              current_xml: xml,
              generated_xml: xml
          },
          log: false
        )
      end
    else
      false -> {:error, "Vyberte podporovanou agendu"}
      error -> error
    end
  end

  def save_header(id, attrs, expected_hash, identity_confirmed \\ false) do
    locked(id, fn doc ->
      unless is_nil(doc.sent_xml) and
               (doc.state == "review" or
                  (doc.state == "failed" and doc.error_stage == "extraction")),
             do: Repo.rollback("Formulář je uzamčen")

      unless transcription_hash(doc) == expected_hash,
        do: Repo.rollback("Doklad mezitím někdo upravil. Obnovte stránku.")

      if doc.extraction_metadata["identity_conflict"] && identity_confirmed != true,
        do: Repo.rollback("Potvrďte samostatně kontrolu rozporu identity dodavatele.")

      case CozyCheckout.IncomingDocuments.HeaderForm.build(attrs, doc) do
        {:ok, values, xml} ->
          update!(doc,
            state: "review",
            edited_data: %{"header_form" => values},
            extraction_metadata:
              doc.extraction_metadata
              |> Map.put("strategy", "header_form")
              |> Map.put("identity_confirmed", identity_confirmed),
            current_xml: xml,
            dry_run: %{},
            error: nil,
            error_stage: nil
          )

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def content_type(bytes, filename)
      when is_binary(bytes) and byte_size(bytes) > 0 and byte_size(bytes) <= @max_size do
    case {String.downcase(Path.extname(filename)), bytes} do
      {".pdf", <<"%PDF-", _::binary>>} -> {:ok, "application/pdf"}
      {ext, <<0xFF, 0xD8, 0xFF, _::binary>>} when ext in [".jpg", ".jpeg"] -> {:ok, "image/jpeg"}
      {".png", <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>} -> {:ok, "image/png"}
      _ -> {:error, "Podporujeme pouze PDF, JPEG a PNG se správným obsahem"}
    end
  end

  def content_type(_, _), do: {:error, "Soubor je prázdný nebo větší než 10 MB"}

  def save(id, attrs, expected_hash) do
    locked(id, fn doc ->
      require_state!(doc, ["review"])
      require_hash!(doc, expected_hash)

      case XML.edit(doc.current_xml, attrs, doc.agenda, XML.template_for(doc), doc.external_id) do
        {:ok, xml} -> update!(doc, current_xml: xml, dry_run: %{}, error: nil, error_stage: nil)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Repairs a failed extraction without calling OpenAI or allowing an unvalidated import."
  def repair_xml(id, xml, expected_hash) do
    locked(id, fn doc ->
      require_state!(doc, ["failed"])

      unless doc.error_stage == "extraction" and is_binary(doc.generated_xml) and
               is_nil(doc.sent_xml),
             do: Repo.rollback("Tento doklad nelze opravit jako neúspěšné vytěžení")

      if digest(doc.generated_xml) != expected_hash,
        do: Repo.rollback("Výstup vytěžení se mezitím změnil. Obnovte stránku.")

      case XML.normalize(xml, doc.agenda, XML.template_for(doc), doc.external_id) do
        {:ok, normalized} ->
          update!(doc,
            state: "review",
            current_xml: normalized,
            dry_run: %{},
            error: nil,
            error_stage: nil
          )

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def retry_extraction(id, strategy \\ nil, opts \\ []) do
    doc = get!(id)

    if (strategy || Extractor.strategy(doc)) == "header_form",
      do: ExtractionRuns.start(id, opts),
      else: retry_legacy_extraction(id, strategy)
  end

  defp retry_legacy_extraction(id, strategy) do
    locked(id, fn doc ->
      require_state!(doc, ["failed", "review"])

      if not is_nil(doc.sent_xml) or (doc.state == "failed" and doc.error_stage != "extraction"),
        do: Repo.rollback("Vytěžení nelze opakovat po zahájení importu")

      if is_nil(doc.original), do: Repo.rollback("Ruční doklad nemá originál k vytěžení")

      strategy = strategy || Extractor.strategy(doc)
      unless strategy in Extractor.strategies(), do: Repo.rollback("Neplatný způsob vytěžení")
      job!(id, "extract")

      update!(doc,
        state: "uploaded",
        current_xml: nil,
        generated_xml: nil,
        dry_run: %{},
        extracted_data: %{},
        edited_data: nil,
        extraction_metadata: %{"strategy" => strategy},
        extraction_attempts: 0,
        error: nil,
        error_stage: nil
      )
    end)
  end

  def supplier_profiles(%Document{} = doc), do: SupplierProfiles.list(doc)
  def supplier_profiles(id), do: id |> supplier_scope!() |> SupplierProfiles.list()
  def supplier_profile(%Document{} = doc, profile_id), do: SupplierProfiles.get(doc, profile_id)

  def supplier_profile(id, profile_id),
    do: id |> supplier_scope!() |> SupplierProfiles.get(profile_id)

  def active_extraction_run(doc), do: ExtractionRuns.active(doc)
  def extraction_status(doc), do: ExtractionRuns.active_for_display(doc)

  defp supplier_scope!(id) do
    Repo.one!(
      from d in Document,
        where: d.id == ^id and is_nil(d.deleted_at),
        select: struct(d, [:id, :base_url, :company_id])
    )
  end

  def list_extraction_runs(id, page \\ 0), do: ExtractionRuns.list(id, page)

  def retry_content_extraction(id, opts \\ []),
    do: ExtractionRuns.start(id, Keyword.put(opts, :mode, "extract_only"))

  def restore_draft_from_run(id, run_id), do: ExtractionRuns.restore(id, run_id)

  def save_supplier_instructions(id, profile_id, attrs, expected_revision, confirmed) do
    SupplierProfiles.save(supplier_scope!(id), profile_id, attrs, expected_revision, confirmed)
  end

  def save_supplier_and_retry(id, profile_id, attrs, expected_revision, confirmed, opts \\ []) do
    locked(id, fn doc ->
      case SupplierProfiles.save(doc, profile_id, attrs, expected_revision, confirmed) do
        {:ok, profile} ->
          ExtractionRuns.start_locked(
            doc,
            Keyword.merge(opts, mode: "extract_only", profile_id: profile.id, confirmed: true)
          )

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def accounting_presets(id) do
    doc = get!(id)

    with :ok <- target(doc), {:ok, rows} <- Client.presets(doc, config()) do
      {:ok, Enum.filter(rows, &Accounting.applicable?(&1, doc.agenda))}
    end
  end

  def save_accounting(id, attrs, expected_hash) do
    snapshot = get!(id)
    preset = attrs["preset"] || ""

    with :ok <- target(snapshot),
         {:ok, code} <- Accounting.internal_code(attrs["internal_code"] || ""),
         {:ok, settings} <- accounting_choice(snapshot, preset, code) do
      locked(id, fn doc ->
        require_state!(doc, ["failed", "review"])

        if not is_nil(doc.sent_xml) or (doc.state == "failed" and doc.error_stage != "extraction"),
          do: Repo.rollback("Účetní nastavení je uzamčené")

        if transcription_hash(doc) != expected_hash,
          do: Repo.rollback("Doklad se mezitím změnil; obnovte stránku")

        require_target!(doc)
        changed = %{doc | accounting_settings: settings}

        built =
          cond do
            Extractor.strategy(doc) == "header_form" and is_nil(doc.current_xml) ->
              :header_pending

            is_nil(doc.current_xml) and transcription(doc) != %{} ->
              build_transcription(transcription(doc), changed)

            true ->
              with {:ok, raw} <-
                     XML.restore_accounting(
                       doc.current_xml || doc.generated_xml || "",
                       doc.agenda,
                       XML.template_for(changed),
                       doc.external_id
                     ) do
                case XML.normalize(raw, doc.agenda, XML.template_for(changed), doc.external_id) do
                  {:ok, xml} -> {:ok, raw, xml}
                  {:error, reason} -> {:error, reason, raw}
                end
              else
                {:error, reason} -> {:error, reason, nil}
              end
          end

        case built do
          :header_pending ->
            update!(doc, accounting_settings: settings, dry_run: %{})

          {:ok, _raw, xml} ->
            update!(doc,
              accounting_settings: settings,
              current_xml: xml,
              state: "review",
              dry_run: %{},
              error: nil,
              error_stage: nil
            )

          {:error, reason, raw} ->
            update!(doc,
              accounting_settings: settings,
              current_xml: nil,
              generated_xml: raw || doc.generated_xml,
              state: "failed",
              dry_run: %{},
              error: reason,
              error_stage: "extraction"
            )
        end
      end)
    end
  end

  defp accounting_choice(doc, "", code), do: {:ok, Map.put(doc.accounting_settings, "kod", code)}

  defp accounting_choice(doc, preset, code) do
    with {:ok, rows} <- Client.presets(doc, config()),
         row when not is_nil(row) <- Enum.find(rows, &(&1["kod"] == preset)),
         {:ok, settings} <- Accounting.select(row, doc.agenda, code),
         do: {:ok, settings},
         else: (
           nil -> {:error, "Předpis není v číselníku ABRA"}
           error -> error
         )
  end

  def diagnose(id, expected_hash) do
    locked(id, fn doc ->
      require_state!(doc, ["failed", "review"])

      if not is_nil(doc.sent_xml) or (doc.state == "failed" and doc.error_stage != "extraction"),
        do: Repo.rollback("Tento návrh již nelze měnit ani diagnostikovat")

      if transcription_hash(doc) != expected_hash,
        do: Repo.rollback("Návrh se změnil; obnovte stránku")

      require_target!(doc)

      case diagnostic_xml(doc) do
        {:ok, _} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      job!(id, "validate")

      update!(doc,
        state: "validating",
        dry_run: %{
          "diagnostic" => true,
          "resume_state" => doc.state,
          "original_error" => doc.error,
          "original_error_stage" => doc.error_stage
        }
      )
    end)
  end

  def validate(id, expected_hash) do
    locked(id, fn doc ->
      require_state!(doc, ["review"])
      require_hash!(doc, expected_hash)
      require_target!(doc)
      job!(id, "validate")
      update!(doc, state: "validating", dry_run: %{}, error: nil, error_stage: nil)
    end)
  end

  def approve(id, expected_hash, warnings_confirmed \\ false, rounding_confirmed \\ false) do
    locked(id, fn doc ->
      require_state!(doc, ["review"])
      require_hash!(doc, expected_hash)
      require_target!(doc)

      unless doc.dry_run["hash"] == expected_hash and doc.dry_run["ok"] == true,
        do: Repo.rollback("Nejprve spusťte kontrolu aktuálního XML v ABRA")

      if doc.dry_run["warnings"] != [] and not warnings_confirmed,
        do: Repo.rollback("Výslovně potvrďte, že jste zkontrolovali upozornění ABRA")

      case XML.rounding_adjustments(doc.current_xml, doc.agenda) do
        {:ok, []} -> :ok
        {:ok, _} when rounding_confirmed -> :ok
        {:ok, _} -> Repo.rollback("Potvrďte haléřovou korekci DPH podle rekapitulace originálu")
        {:error, reason} -> Repo.rollback(reason)
      end

      payload =
        case XML.import_xml(doc.current_xml, doc.agenda) do
          {:ok, payload} -> payload
          {:error, reason} -> Repo.rollback(reason)
        end

      unless doc.dry_run["payload_hash"] == digest(payload),
        do: Repo.rollback("XML k odeslání se změnilo. Zopakujte kontrolu ABRA.")

      job!(id, "send")
      update!(doc, state: "sending", sent_xml: payload, error: nil, error_stage: nil)
    end)
  end

  @doc "Explicit real import of a locally validated header, independent of ABRA dry-run availability."
  def send_header(id, expected_hash, confirmed) do
    locked(id, fn doc ->
      require_state!(doc, ["review"])
      require_hash!(doc, expected_hash)
      require_target!(doc)

      unless confirmed == true, do: Repo.rollback("Potvrďte skutečné vytvoření dokladu v ABRA")

      unless Extractor.strategy(doc) == "header_form" and is_nil(doc.sent_xml),
        do: Repo.rollback("Nejprve uložte nový formulář; již zahájený přenos nelze opakovat")

      payload =
        with {:ok, fields} <- XML.parse(doc.current_xml, doc.agenda),
             true <- XML.items(fields) == [],
             {:ok, _values, _xml} <-
               CozyCheckout.IncomingDocuments.HeaderForm.build(
                 Map.take(fields, CozyCheckout.IncomingDocuments.HeaderForm.keys()),
                 doc
               ),
             {:ok, normalized} <-
               XML.normalize(doc.current_xml, doc.agenda, XML.template_for(doc), doc.external_id) do
          normalized
        else
          false -> Repo.rollback("Přímé odeslání je dostupné jen pro doklad bez položek")
          {:error, reason} -> Repo.rollback(reason)
        end

      metadata =
        Map.put(doc.extraction_metadata, "delivery", %{
          "mode" => "direct_header",
          "payload_hash" => digest(payload),
          "confirmed_at" => DateTime.to_iso8601(DateTime.utc_now(:second))
        })

      job!(id, "send")

      update!(doc,
        state: "sending",
        sent_xml: payload,
        extraction_metadata: metadata,
        error: nil,
        error_stage: nil
      )
    end)
  end

  def verify(id) do
    locked(id, fn doc ->
      require_state!(doc, ["uncertain"])
      require_target!(doc)
      job!(id, "send")
      doc
    end)
  end

  def perform_extraction(id, run_id, attempt \\ 1)

  def perform_extraction(id, nil, attempt) do
    if Extractor.strategy(get!(id)) == "header_form" do
      case ExtractionRuns.ensure_legacy(id) do
        {:ok, run_id} when is_binary(run_id) -> ExtractionRuns.perform(id, run_id, attempt)
        _ -> :ok
      end
    else
      perform(id, "extract")
    end
  end

  def perform_extraction(id, run_id, attempt), do: ExtractionRuns.perform(id, run_id, attempt)

  def perform(id, "extract") do
    doc = get!(id)

    if Extractor.strategy(doc) == "header_form" do
      case ExtractionRuns.ensure_legacy(id) do
        {:ok, run_id} when is_binary(run_id) -> ExtractionRuns.perform(id, run_id)
        _ -> :ok
      end
    else
      perform_legacy_extraction(id)
    end

    :ok
  end

  def perform(id, "validate") do
    doc = get!(id)

    if doc.state == "validating" do
      result =
        with :ok <- target(doc),
             {:ok, payload} <-
               if(doc.dry_run["diagnostic"],
                 do: diagnostic_xml(doc),
                 else: XML.import_xml(doc.current_xml, doc.agenda)
               ),
             {:ok, response} <- Client.import(doc, payload, true, config()),
             do: {:ok, Map.put(response, "payload_hash", digest(payload))}

      locked(id, fn current ->
        require_state!(current, ["validating"])

        if doc.dry_run["diagnostic"] do
          {response, accepted, reason} =
            case result do
              {:ok, response} -> {response, true, nil}
              {_, reason, response} -> {response, false, reason}
              {_, reason} -> {%{}, false, reason}
            end

          update!(current,
            state: doc.dry_run["resume_state"],
            dry_run:
              Map.merge(response, %{"diagnostic" => true, "accepted" => accepted, "ok" => false}),
            error: reason || doc.dry_run["original_error"],
            error_stage: doc.dry_run["original_error_stage"]
          )
        else
          case result do
            {:ok, response} ->
              update!(current,
                state: "review",
                dry_run: Map.merge(response, %{"ok" => true, "hash" => digest(doc.current_xml)}),
                error: nil
              )

            {:rejected, reason, response} ->
              update!(current,
                state: "review",
                dry_run: response,
                error_stage: "validation",
                error: reason
              )

            {:uncertain, reason, response} ->
              update!(current,
                state: "review",
                dry_run: response,
                error_stage: "validation",
                error: reason
              )

            {_, reason} ->
              update!(current,
                state: "review",
                dry_run: %{},
                error_stage: "validation",
                error: reason
              )
          end
        end
      end)
    end

    :ok
  end

  def perform(id, "send") do
    # Commit uncertainty BEFORE the network call. A crash or retry can only look up, never POST again.
    case locked(id, fn doc ->
           require_target!(doc)

           case doc.state do
             "sending" ->
               {:first,
                update!(doc,
                  state: "uncertain",
                  error_stage: "import",
                  error: "Probíhá zápis; při přerušení je nutné ověřit výsledek v ABRA"
                )}

             "uncertain" ->
               {:verify, doc}

             _ ->
               :done
           end
         end) do
      {:ok, {:first, doc}} ->
        case Client.find(doc, config()) do
          :not_found -> finish_import(doc, Client.import(doc, doc.sent_xml, false, config()))
          {:ok, remote_id} -> finish_import(doc, {:found, remote_id})
          {:error, reason} -> finish_import(doc, {:uncertain, reason})
        end

      {:ok, {:verify, doc}} ->
        case Client.find(doc, config()) do
          {:ok, remote_id} ->
            finish_import(doc, {:found, remote_id})

          :not_found ->
            finish_import(
              doc,
              {:uncertain,
               "Doklad zatím nebyl nalezen. Ověřte jej ručně v ABRA; nový zápis zůstává blokován."}
            )

          {:error, reason} ->
            finish_import(doc, {:uncertain, reason})
        end

      {:error, reason} ->
        locked(id, fn doc ->
          if doc.state in ["sending", "uncertain"] do
            update!(doc,
              state: if(doc.state == "sending", do: "review", else: "uncertain"),
              dry_run: %{},
              error: reason,
              error_stage: "import"
            )
          else
            doc
          end
        end)

      _ ->
        :ok
    end

    :ok
  end

  defp perform_legacy_extraction(id) do
    doc = get!(id)

    if doc.state in ["uploaded", "processing"] do
      case locked(id, fn current ->
             require_state!(current, ["uploaded", "processing"])
             update!(current, state: "processing")
           end) do
        {:ok, _} ->
          case SourceImages.prepare(
                 doc,
                 Keyword.put(config(), :original_only, Extractor.strategy(doc) == "simple_xml")
               ) do
            {:ok, parts, image_metadata} -> transcribe(id, parts, image_metadata)
            {:error, reason} -> extraction_failed(id, reason, nil)
          end

        _ ->
          :ok
      end
    end

    :ok
  end

  defp transcribe(id, parts, image_metadata) do
    doc = get!(id)

    if doc.state == "processing" do
      case build_extraction(doc) do
        :suggestions ->
          locked(id, fn current ->
            require_state!(current, ["processing"])
            update!(current, state: "review", current_xml: nil, error: nil, error_stage: nil)
          end)

        {:ok, raw, xml} ->
          locked(id, fn current ->
            require_state!(current, ["processing"])

            update!(current,
              state: "review",
              generated_xml: raw,
              current_xml: xml,
              error: nil,
              error_stage: nil
            )
          end)

        {:error, reason, raw} when doc.extraction_attempts >= 2 ->
          extraction_failed(id, reason, raw)

        {:error, reason, raw} ->
          if doc.extraction_attempts >= Extractor.max_attempts(doc) do
            extraction_failed(id, reason, raw)
          else
            reservation =
              locked(id, fn current ->
                require_state!(current, ["processing"])

                if current.extraction_attempts != doc.extraction_attempts,
                  do: Repo.rollback("Vytěžení již rezervoval jiný worker")

                if current.extraction_attempts >= Extractor.max_attempts(current),
                  do: Repo.rollback("Limit volání vytěžení byl vyčerpán")

                metadata =
                  current.extraction_metadata
                  |> Map.put("images", image_metadata)
                  |> Map.put("validation_error", reason)

                update!(current,
                  extraction_attempts: current.extraction_attempts + 1,
                  extraction_metadata: metadata
                )
              end)

            case reservation do
              {:ok, reserved} ->
                feedback =
                  if doc.extracted_data != %{}, do: %{data: doc.extracted_data, error: reason}

                result = Extractor.extract(doc, config(), parts, feedback)

                case persist_transcription_result(reserved, result, raw) do
                  {:ok, _} -> transcribe(id, parts, image_metadata)
                  _ -> :ok
                end

              _ ->
                :ok
            end
          end
      end
    end
  end

  defp persist_transcription_result(reserved, result, previous_xml) do
    locked(reserved.id, fn doc ->
      require_state!(doc, ["processing"])

      if doc.extraction_attempts != reserved.extraction_attempts,
        do: Repo.rollback("Souběžný výsledek vytěžení byl odmítnut")

      {metadata, attrs} =
        case result do
          {:ok_xml, raw, metadata} ->
            {metadata, [generated_xml: raw]}

          {:ok, data, metadata} ->
            {metadata, [extracted_data: data]}

          {:error, reason, metadata} ->
            {metadata,
             [
               state: "failed",
               error_stage: "extraction",
               error: reason,
               generated_xml: previous_xml
             ]}
        end

      call =
        metadata
        |> Map.put("attempt", doc.extraction_attempts)
        |> Map.put("model", config()[:openai_model])
        |> Map.put("prompt_version", Extractor.prompt_version(Extractor.strategy(doc)))

      metadata = Map.update(doc.extraction_metadata, "calls", [call], &(&1 ++ [call]))
      update!(doc, Keyword.put(attrs, :extraction_metadata, metadata))
    end)
  end

  defp build_extraction(%{extracted_data: data} = doc) when data != %{} do
    if Extractor.strategy(doc) == "header_form", do: :suggestions, else: build_extraction_xml(doc)
  end

  defp build_extraction(doc), do: build_extraction_xml(doc)

  defp build_extraction_xml(doc) do
    if Extractor.strategy(doc) == "simple_xml" do
      if is_binary(doc.generated_xml) do
        case XML.normalize(doc.generated_xml, doc.agenda, XML.template_for(doc), doc.external_id) do
          {:ok, xml} -> {:ok, doc.generated_xml, xml}
          {:error, reason} -> {:error, reason, doc.generated_xml}
        end
      else
        {:error, "XML originálu dosud nebylo vytvořeno", nil}
      end
    else
      build_transcription(doc.extracted_data, doc)
    end
  end

  defp build_transcription(data, _doc) when data == %{},
    do: {:error, "Přepis originálu dosud nebyl vytvořen", nil}

  defp build_transcription(data, doc) do
    case Builder.build(data, doc) do
      {:ok, raw} ->
        case XML.normalize(raw, doc.agenda, XML.template_for(doc), doc.external_id) do
          {:ok, xml} -> {:ok, raw, xml}
          {:error, reason} -> {:error, reason, raw}
        end

      error ->
        error
    end
  end

  defp extraction_failed(id, reason, raw) do
    locked(id, fn doc ->
      require_state!(doc, ["processing"])

      update!(doc,
        state: "failed",
        generated_xml: raw,
        current_xml: nil,
        dry_run: %{},
        error_stage: "extraction",
        error: reason
      )
    end)
  end

  def transcription(doc), do: doc.edited_data || doc.extracted_data

  def transcription_hash(doc),
    do:
      digest(
        Jason.encode!([
          transcription(doc),
          doc.current_xml,
          doc.accounting_settings,
          doc.active_extraction_run_id
        ])
      )

  def repair_transcription(id, json, expected_hash) do
    with true <- is_binary(json) and byte_size(json) <= 250_000,
         {:ok, data} <- Jason.decode(json) do
      save_transcription(id, data, expected_hash)
    else
      _ -> {:error, "Přepis nemá platnou JSON strukturu"}
    end
  end

  def save_transcription(id, data, expected_hash) do
    locked(id, fn doc ->
      if Extractor.strategy(doc) == "header_form",
        do: Repo.rollback("Použijte formulář hlavičky a DPH")

      require_state!(doc, ["failed", "review"])

      unless is_nil(doc.sent_xml) and (doc.state == "review" or doc.error_stage == "extraction"),
        do: Repo.rollback("Přepis nelze upravit po zahájení importu")

      if transcription_hash(doc) != expected_hash,
        do: Repo.rollback("Přepis se mezitím změnil; obnovte stránku")

      case CozyCheckout.IncomingDocuments.Transcription.validate(data) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      if byte_size(Jason.encode!(data)) > 250_000, do: Repo.rollback("Přepis přesahuje 250 kB")

      case build_transcription(data, doc) do
        {:ok, _raw, xml} ->
          update!(doc,
            edited_data: data,
            state: "review",
            current_xml: xml,
            dry_run: %{},
            error: nil,
            error_stage: nil
          )

        {:error, reason, raw} ->
          update!(doc,
            edited_data: data,
            state: "failed",
            current_xml: nil,
            generated_xml: raw,
            dry_run: %{},
            error: reason,
            error_stage: "extraction"
          )
      end
    end)
  end

  @doc "Downloads are diagnostic only; no accounting write or approval is performed."
  def diagnostic_xml(%Document{} = doc) do
    cond do
      is_binary(doc.sent_xml) ->
        {:ok, doc.sent_xml}

      is_binary(doc.current_xml) ->
        XML.import_xml(doc.current_xml, doc.agenda)

      Extractor.strategy(doc) == "header_form" ->
        {:error, "Nejprve zkontrolujte a uložte formulář hlavičky a DPH"}

      true ->
        draft =
          if transcription(doc) != %{},
            do: Builder.draft(transcription(doc), doc),
            else: {:ok, doc.generated_xml}

        with {:ok, raw} when is_binary(raw) <- draft,
             {:ok, xml} <-
               XML.restore_accounting(raw, doc.agenda, XML.template_for(doc), doc.external_id),
             {:ok, fields} <- XML.parse(xml, doc.agenda) do
          fields =
            if XML.items(fields) == [],
              do: fields,
              else: Map.reject(fields, fn {key, _} -> XML.amount?(key) end)

          {:ok, XML.render(fields, doc.agenda, doc.external_id)}
        else
          {:error, reason} -> {:error, reason}
          _ -> {:error, "Dosud není dostupný návrh XML"}
        end
    end
  end

  def diagnostic_xml(id), do: id |> get!() |> diagnostic_xml()

  defp finish_import(doc, result) do
    locked(doc.id, fn current ->
      if current.state == "sent" do
        current
      else
        case result do
          {:ok, response} ->
            update!(current,
              state: "sent",
              deferred_at: nil,
              response: response,
              remote_id: response["id"],
              sent_at: DateTime.utc_now(:second),
              error: nil,
              error_stage: nil
            )
            |> CozyCheckout.IncomingDocuments.SourceAttachments.enqueue_locked()

          {:found, remote_id} ->
            update!(current,
              state: "sent",
              deferred_at: nil,
              response: Map.put(current.response, "verified_by_external_id", true),
              remote_id: remote_id,
              sent_at: DateTime.utc_now(:second),
              error: nil,
              error_stage: nil
            )
            |> CozyCheckout.IncomingDocuments.SourceAttachments.enqueue_locked()

          {:rejected, reason, response} ->
            update!(current,
              state: "review",
              response: response,
              dry_run: %{},
              error: reason,
              error_stage: "import"
            )

          {:uncertain, reason, response} ->
            update!(current,
              state: "uncertain",
              response: response,
              error: reason,
              error_stage: "import"
            )

          {:uncertain, reason} ->
            update!(current, state: "uncertain", error: reason, error_stage: "import")
        end
      end
    end)
  end

  def worker_failed(id, operation) do
    locked(id, fn doc ->
      case {operation, doc.state} do
        {"extract", state}
        when state in ["uploaded", "processing"] and is_nil(doc.active_extraction_run_id) ->
          update!(doc,
            state: "failed",
            error_stage: "extraction",
            error: "Vytěžení bylo přerušeno. Zkuste jej znovu."
          )

        {"validate", "validating"} when is_map_key(doc.dry_run, "diagnostic") ->
          update!(doc,
            state: doc.dry_run["resume_state"],
            dry_run: %{},
            error: doc.dry_run["original_error"] || "Diagnostická kontrola byla přerušena",
            error_stage: doc.dry_run["original_error_stage"]
          )

        {"validate", "validating"} ->
          update!(doc,
            state: "review",
            error_stage: "validation",
            error: "Kontrola byla přerušena. Spusťte ji znovu."
          )

        _ ->
          doc
      end
    end)
  end

  defp locked(id, fun) do
    Repo.transaction(fn ->
      doc =
        Repo.one!(
          from d in Document, where: d.id == ^id and is_nil(d.deleted_at), lock: "FOR UPDATE"
        )

      fun.(doc)
    end)
  end

  defp update!(doc, attrs), do: doc |> Ecto.Changeset.change(attrs) |> Repo.update!(log: false)

  defp job!(id, op) do
    case %{document_id: id, operation: op}
         |> IncomingDocumentWorker.new(
           queue: if(op == "extract", do: :incoming_extraction, else: :billing)
         )
         |> Oban.insert() do
      {:ok, %Oban.Job{conflict?: true}} ->
        Repo.rollback("Předchozí operace ještě čeká ve frontě. Zkuste to znovu za chvíli.")

      {:ok, job} ->
        job

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp require_state!(doc, states),
    do:
      if(doc.state not in states,
        do: Repo.rollback("Doklad je uzamčen nebo se jeho stav změnil. Obnovte stránku.")
      )

  defp require_hash!(doc, hash),
    do:
      if(not is_binary(doc.current_xml) or digest(doc.current_xml) != hash,
        do:
          Repo.rollback("Doklad mezitím někdo upravil. Obnovte stránku a zkontrolujte jej znovu.")
      )

  defp require_target!(doc) do
    case target(doc) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp target(doc) do
    cfg = config()

    with :ok <- configured(cfg) do
      if doc.base_url == cfg[:base_url] and doc.company_id == cfg[:company_id],
        do: :ok,
        else:
          {:error,
           "Cílová firma se změnila. Doklad patří do #{doc.company_id}; přenos je blokován."}
    end
  end

  def configured(cfg) do
    if cfg[:enabled] == true and
         Enum.all?([:base_url, :company_id, :username, :password], &(cfg[&1] not in [nil, ""])),
       do: :ok,
       else: {:error, "Přijaté doklady jsou vypnuté nebo chybí připojení ABRA"}
  end
end

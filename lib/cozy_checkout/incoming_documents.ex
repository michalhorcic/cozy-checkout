defmodule CozyCheckout.IncomingDocuments do
  @moduledoc "Admin-reviewed received documents with immutable create-only ABRA delivery."
  import Ecto.Query
  alias CozyCheckout.Repo
  alias CozyCheckout.IncomingDocuments.{Builder, Client, Document, Extractor, SourceImages, XML}
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

  def upload(bytes, filename, agenda, strategy \\ "structured") do
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

        job!(doc.id, "extract")
        %{document: doc, duplicate?: duplicate}
      end)
    else
      false -> {:error, "Vyberte podporovanou agendu a způsob vytěžení"}
      error -> error
    end
  end

  defp content_type(bytes, filename)
       when is_binary(bytes) and byte_size(bytes) > 0 and byte_size(bytes) <= @max_size do
    case {String.downcase(Path.extname(filename)), bytes} do
      {".pdf", <<"%PDF-", _::binary>>} -> {:ok, "application/pdf"}
      {ext, <<0xFF, 0xD8, 0xFF, _::binary>>} when ext in [".jpg", ".jpeg"] -> {:ok, "image/jpeg"}
      {".png", <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>} -> {:ok, "image/png"}
      _ -> {:error, "Podporujeme pouze PDF, JPEG a PNG se správným obsahem"}
    end
  end

  defp content_type(_, _), do: {:error, "Soubor je prázdný nebo větší než 10 MB"}

  def save(id, attrs, expected_hash) do
    locked(id, fn doc ->
      require_state!(doc, ["review"])
      require_hash!(doc, expected_hash)

      case XML.edit(doc.current_xml, attrs, doc.agenda, doc.template_xml, doc.external_id) do
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

      case XML.normalize(xml, doc.agenda, doc.template_xml, doc.external_id) do
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

  def retry_extraction(id, strategy \\ nil) do
    locked(id, fn doc ->
      require_state!(doc, ["failed", "review"])

      if not is_nil(doc.sent_xml) or (doc.state == "failed" and doc.error_stage != "extraction"),
        do: Repo.rollback("Vytěžení nelze opakovat po zahájení importu")

      strategy = strategy || Extractor.strategy(doc)
      unless strategy in Extractor.strategies(), do: Repo.rollback("Neplatný způsob vytěžení")
      job!(id, "extract")

      update!(doc,
        state: "uploaded",
        current_xml: nil,
        generated_xml: nil,
        dry_run: %{},
        extracted_data: %{},
        extraction_metadata: %{"strategy" => strategy},
        extraction_attempts: 0,
        error: nil,
        error_stage: nil
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

  def verify(id) do
    locked(id, fn doc ->
      require_state!(doc, ["uncertain"])
      require_target!(doc)
      job!(id, "send")
      doc
    end)
  end

  def perform(id, "extract") do
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

  def perform(id, "validate") do
    doc = get!(id)

    if doc.state == "validating" do
      result =
        with :ok <- target(doc),
             {:ok, payload} <- XML.import_xml(doc.current_xml, doc.agenda),
             {:ok, response} <- Client.import(doc, payload, true, config()),
             do: {:ok, Map.put(response, "payload_hash", digest(payload))}

      locked(id, fn current ->
        require_state!(current, ["validating"])

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

  defp transcribe(id, parts, image_metadata) do
    doc = get!(id)

    if doc.state == "processing" do
      case build_extraction(doc) do
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

  defp build_extraction(doc) do
    if Extractor.strategy(doc) == "simple_xml" do
      if is_binary(doc.generated_xml) do
        case XML.normalize(doc.generated_xml, doc.agenda, doc.template_xml, doc.external_id) do
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
        case XML.normalize(raw, doc.agenda, doc.template_xml, doc.external_id) do
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

  def repair_transcription(id, json, expected_hash) do
    locked(id, fn doc ->
      require_state!(doc, ["failed"])

      unless doc.error_stage == "extraction" and is_nil(doc.sent_xml),
        do: Repo.rollback("Přepis nelze upravit po zahájení importu")

      if digest(Jason.encode!(doc.extracted_data)) != expected_hash,
        do: Repo.rollback("Přepis se mezitím změnil; obnovte stránku")

      with true <- is_binary(json) and byte_size(json) <= 250_000,
           {:ok, data} <- Jason.decode(json),
           {:ok, _raw, xml} <- build_transcription(data, doc) do
        update!(doc,
          state: "review",
          current_xml: xml,
          dry_run: %{},
          error: nil,
          error_stage: nil
        )
      else
        {:error, reason, _} -> Repo.rollback(reason)
        _ -> Repo.rollback("Přepis nemá platnou JSON strukturu")
      end
    end)
  end

  defp finish_import(doc, result) do
    locked(doc.id, fn current ->
      if current.state == "sent" do
        current
      else
        case result do
          {:ok, response} ->
            update!(current,
              state: "sent",
              response: response,
              remote_id: response["id"],
              sent_at: DateTime.utc_now(:second),
              error: nil,
              error_stage: nil
            )

          {:found, remote_id} ->
            update!(current,
              state: "sent",
              response: Map.put(current.response, "verified_by_external_id", true),
              remote_id: remote_id,
              sent_at: DateTime.utc_now(:second),
              error: nil,
              error_stage: nil
            )

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
        {"extract", state} when state in ["uploaded", "processing"] ->
          update!(doc,
            state: "failed",
            error_stage: "extraction",
            error: "Vytěžení bylo přerušeno. Zkuste jej znovu."
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
    case %{document_id: id, operation: op} |> IncomingDocumentWorker.new() |> Oban.insert() do
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

  defp configured(cfg) do
    if cfg[:enabled] == true and
         Enum.all?([:base_url, :company_id, :username, :password], &(cfg[&1] not in [nil, ""])),
       do: :ok,
       else: {:error, "Přijaté doklady jsou vypnuté nebo chybí připojení ABRA"}
  end
end

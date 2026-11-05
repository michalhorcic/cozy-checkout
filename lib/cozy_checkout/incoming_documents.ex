defmodule CozyCheckout.IncomingDocuments do
  @moduledoc "Admin-reviewed received documents with immutable create-only ABRA delivery."
  import Ecto.Query
  alias CozyCheckout.Repo
  alias CozyCheckout.IncomingDocuments.{Client, Document, Extractor, XML}
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

  def upload(bytes, filename, agenda) do
    cfg = config()

    with :ok <- configured(cfg),
         true <- agenda in XML.agendas(),
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
      false -> {:error, "Vyberte podporovanou agendu"}
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

  def retry_extraction(id) do
    locked(id, fn doc ->
      require_state!(doc, ["failed"])
      if doc.error_stage != "extraction", do: Repo.rollback("Vytěžení nelze opakovat")
      job!(id, "extract")
      update!(doc, state: "uploaded", error: nil, error_stage: nil)
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

  def approve(id, expected_hash, warnings_confirmed \\ false) do
    locked(id, fn doc ->
      require_state!(doc, ["review"])
      require_hash!(doc, expected_hash)
      require_target!(doc)

      unless doc.dry_run["hash"] == expected_hash and doc.dry_run["ok"] == true,
        do: Repo.rollback("Nejprve spusťte kontrolu aktuálního XML v ABRA")

      if doc.dry_run["warnings"] != [] and not warnings_confirmed,
        do: Repo.rollback("Výslovně potvrďte, že jste zkontrolovali upozornění ABRA")

      job!(id, "send")
      update!(doc, state: "sending", sent_xml: doc.current_xml, error: nil, error_stage: nil)
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
      locked(id, fn current ->
        require_state!(current, ["uploaded", "processing"])
        update!(current, state: "processing")
      end)

      result =
        with {:ok, xml} <- Extractor.extract(doc, config()),
             {:ok, normalized} <-
               XML.normalize(xml, doc.agenda, doc.template_xml, doc.external_id),
             do: {:ok, xml, normalized}

      locked(id, fn current ->
        require_state!(current, ["processing"])

        case result do
          {:ok, raw, xml} ->
            update!(current,
              state: "review",
              generated_xml: raw,
              current_xml: xml,
              error: nil,
              error_stage: nil
            )

          {:error, reason} ->
            update!(current, state: "failed", error_stage: "extraction", error: reason)
        end
      end)
    end

    :ok
  end

  def perform(id, "validate") do
    doc = get!(id)

    if doc.state == "validating" do
      result = with :ok <- target(doc), do: Client.import(doc, doc.current_xml, true, config())

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
              response: %{"verified_by_external_id" => true},
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

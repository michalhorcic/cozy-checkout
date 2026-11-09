defmodule CozyCheckout.IncomingDocuments.Batches do
  @moduledoc "Staged, explicitly started batches of independent received documents."
  import Ecto.Query
  alias CozyCheckout.{IncomingDocuments, Repo}

  alias CozyCheckout.IncomingDocuments.{
    Accounting,
    Batch,
    Client,
    Document,
    ExtractionRun,
    ExtractionRuns,
    SupplierProfiles,
    XML
  }

  def limit, do: max(1, IncomingDocuments.config()[:batch_max_files] || 50)

  def categories,
    do: [{"Faktury", "faktura-prijata"}, {"Hotově", "pokladni-pohyb"}, {"Kartou", "zavazek"}]

  def create(attrs) do
    cfg = IncomingDocuments.config()
    agenda = attrs["agenda"]
    name = String.trim(attrs["name"] || "")

    with :ok <- IncomingDocuments.configured(cfg),
         true <- agenda in XML.agendas(),
         true <- String.length(name) <= 150 do
      name =
        if name == "",
          do:
            "#{IncomingDocuments.agenda_label(agenda)} · #{Calendar.strftime(DateTime.utc_now(), "%d. %m. %Y %H:%M UTC")}",
          else: name

      Repo.insert(%Batch{
        name: name,
        max_files: limit(),
        agenda: agenda,
        base_url: cfg[:base_url],
        company_id: cfg[:company_id]
      })
    else
      false -> {:error, "Vyberte kategorii a název do 150 znaků"}
      error -> error
    end
  end

  def get!(id), do: Repo.one!(from b in Batch, where: b.id == ^id and is_nil(b.deleted_at))

  # One grouped query, including persistent completion notices. No large document fields.
  def list(page \\ 0) do
    Repo.all(
      from b in Batch,
        left_join: d in Document,
        on: d.batch_id == b.id and is_nil(d.deleted_at),
        left_join: r in ExtractionRun,
        on: r.id == d.initial_extraction_run_id,
        where: is_nil(b.deleted_at),
        group_by: b.id,
        order_by: [desc: b.inserted_at, desc: b.id],
        limit: 25,
        offset: ^(max(page, 0) * 25),
        select: %{
          batch: b,
          total: count(d.id),
          sent: filter(count(d.id), d.state == "sent"),
          extracted: filter(count(d.id), r.state == "completed"),
          failed: filter(count(d.id), r.state == "failed")
        }
    )
  end

  def documents(id, max_files \\ nil) do
    max_files = max_files || get!(id).max_files

    Repo.all(
      from d in Document,
        left_join: r in ExtractionRun,
        on: r.id == d.initial_extraction_run_id,
        where: d.batch_id == ^id and is_nil(d.deleted_at),
        order_by: d.batch_position,
        limit: ^max_files,
        select: %{
          id: d.id,
          filename: d.filename,
          state: d.state,
          position: d.batch_position,
          deferred_at: d.deferred_at,
          error: d.error,
          initial_state: r.state
        }
    )
  end

  def progress(id) do
    Repo.one(
      from d in Document,
        left_join: r in ExtractionRun,
        on: r.id == d.initial_extraction_run_id,
        where: d.batch_id == ^id and is_nil(d.deleted_at),
        select: %{
          total: count(d.id),
          waiting: filter(count(d.id), r.state == "pending"),
          processing: filter(count(d.id), r.state == "running"),
          extracted: filter(count(d.id), r.state == "completed"),
          failed: filter(count(d.id), r.state == "failed"),
          sent: filter(count(d.id), d.state == "sent"),
          deferred: filter(count(d.id), not is_nil(d.deferred_at))
        }
    )
  end

  def presets(id) do
    batch = get!(id)

    with :ok <- target(batch), {:ok, rows} <- Client.presets(batch, IncomingDocuments.config()) do
      {:ok, Enum.filter(rows, &Accounting.applicable?(&1, batch.agenda))}
    end
  end

  def save_settings(id, preset, include_items) when is_boolean(include_items) do
    batch = get!(id)

    with :ok <- target(batch), {:ok, settings} <- settings(batch, preset) do
      locked(id, fn current ->
        preparing!(current)
        target!(current)
        update!(current, accounting_settings: settings, include_items: include_items)
      end)
    end
  end

  defp settings(_batch, ""), do: {:ok, %{}}

  defp settings(batch, preset) do
    with {:ok, rows} <- Client.presets(batch, IncomingDocuments.config()),
         row when not is_nil(row) <- Enum.find(rows, &(&1["kod"] == preset)),
         do: Accounting.select(row, batch.agenda, ""),
         else: (
           nil -> {:error, "Předpis není v číselníku ABRA"}
           error -> error
         )
  end

  def add_source(id, bytes, filename, opts \\ []) do
    with {:ok, mime} <- IncomingDocuments.content_type(bytes, filename) do
      sha = IncomingDocuments.digest(bytes)

      locked(id, fn batch ->
        preparing!(batch)
        target!(batch)
        # Same-batch retries return the existing item, even at the limit.
        existing =
          Repo.one(
            from d in Document,
              where: d.batch_id == ^id and d.sha256 == ^sha and is_nil(d.deleted_at),
              select: d.id
          )

        cond do
          existing ->
            %{id: existing, duplicate?: true}

          true ->
            duplicate =
              Repo.one(
                from d in Document,
                  where:
                    d.sha256 == ^sha and is_nil(d.deleted_at) and
                      d.company_id == ^batch.company_id,
                  where:
                    fragment(
                      "rtrim(?, '/') = ?",
                      d.base_url,
                      ^SupplierProfiles.base_url(batch.base_url)
                    ),
                  limit: 1,
                  select: %{id: d.id, filename: d.filename, state: d.state}
              )

            if duplicate && !opts[:allow_duplicate], do: Repo.rollback({:duplicate, duplicate})

            count =
              Repo.aggregate(
                from(d in Document, where: d.batch_id == ^id and is_nil(d.deleted_at)),
                :count
              )

            if count >= batch.max_files,
              do: Repo.rollback("Dávka může mít nejvýše #{batch.max_files} souborů")

            position =
              (Repo.one(
                 from d in Document, where: d.batch_id == ^id, select: max(d.batch_position)
               ) || 0) + 1

            doc_id = Ecto.UUID.generate()

            Repo.insert!(
              %Document{
                id: doc_id,
                batch_id: id,
                batch_position: position,
                state: "staged",
                agenda: batch.agenda,
                base_url: batch.base_url,
                company_id: batch.company_id,
                template_xml: XML.template(batch.agenda),
                original: bytes,
                sha256: sha,
                content_type: mime,
                filename: Path.basename(filename),
                external_id: "ext:cozy-incoming:#{doc_id}",
                extraction_metadata: %{"strategy" => "header_form"}
              },
              log: false
            )

            %{id: doc_id, duplicate?: false}
        end
      end)
    end
  end

  def remove_source(id, document_id) do
    locked(id, fn batch ->
      preparing!(batch)

      {count, _} =
        Repo.update_all(
          from(d in Document,
            where:
              d.id == ^document_id and d.batch_id == ^id and d.state == "staged" and
                is_nil(d.deleted_at)
          ),
          set: [deleted_at: now(), updated_at: now()]
        )

      if count != 1, do: Repo.rollback("Soubor již není v připravované dávce")
      :ok
    end)
  end

  def start(id) do
    locked(id, fn batch ->
      target!(batch)

      if batch.started_at do
        batch
      else
        cfg = IncomingDocuments.config()

        unless is_binary(cfg[:openai_model]) and cfg[:openai_model] != "" and
                 cfg[:openai_api_key] not in [nil, ""],
               do: Repo.rollback("Chybí konfigurace OpenAI nebo model")

        docs =
          Repo.all(
            from d in Document,
              where: d.batch_id == ^id and is_nil(d.deleted_at),
              order_by: d.batch_position,
              select:
                struct(d, [
                  :id,
                  :sha256,
                  :base_url,
                  :company_id,
                  :agenda,
                  :state,
                  :accounting_settings,
                  :extraction_metadata,
                  :extracted_data,
                  :edited_data
                ])
          )

        if docs == [], do: Repo.rollback("Prázdnou dávku nelze spustit")

        unless Enum.all?(
                 docs,
                 &(&1.state == "staged" && &1.base_url == batch.base_url &&
                     &1.company_id == batch.company_id)
               ),
               do: Repo.rollback("Složení dávky se změnilo")

        Repo.update_all(from(d in Document, where: d.batch_id == ^id and is_nil(d.deleted_at)),
          set: [accounting_settings: batch.accounting_settings]
        )

        docs = Enum.map(docs, &%{&1 | accounting_settings: batch.accounting_settings})
        ExtractionRuns.start_batch_locked(docs, cfg[:openai_model], batch.include_items)
        update!(batch, started_at: now(), model: cfg[:openai_model])
      end
    end)
  end

  # The first run is immutable as the readiness criterion. Later retries cannot
  # close an already completed batch or change its original extraction counts.
  def refresh(id) do
    locked(id, fn batch ->
      if batch.started_at && is_nil(batch.extraction_finished_at) do
        counts = progress(id)

        if counts.total > 0 && counts.total == counts.extracted + counts.failed,
          do: update!(batch, extraction_finished_at: now()),
          else: batch
      else
        batch
      end
    end)
  end

  def review!(id, document_id) do
    {:ok, batch} = refresh(id)
    if is_nil(batch.extraction_finished_at), do: raise(Ecto.NoResultsError, queryable: Batch)
    # Check membership before fetching the private original.
    unless Repo.exists?(
             from d in Document,
               where: d.id == ^document_id and d.batch_id == ^id and is_nil(d.deleted_at)
           ),
           do: raise(Ecto.NoResultsError, queryable: Document)

    {batch, documents(id, batch.max_files)}
  end

  def defer(id, document_id, deferred \\ true) do
    review!(id, document_id)

    Repo.transaction(fn ->
      doc =
        Repo.one!(
          from d in Document,
            where: d.id == ^document_id and d.batch_id == ^id,
            lock: "FOR UPDATE",
            select: struct(d, [:id, :state, :deferred_at])
        )

      if doc.state == "sent", do: Repo.rollback("Odeslaný doklad nelze odložit")
      update!(doc, deferred_at: if(deferred, do: now(), else: nil))
    end)
  end

  # Only terminal Oban states establish that the job ended. Age alone never
  # authorizes marking an in-flight paid call as failed or sending it again.
  def reconcile do
    jobs =
      Repo.all(
        from j in Oban.Job,
          join: r in ExtractionRun,
          on: fragment("?->>'run_id'", j.args) == type(r.id, :string),
          join: d in Document,
          on: r.document_id == d.id,
          where:
            j.worker == "CozyCheckout.Workers.IncomingDocumentWorker" and
              j.state in ["completed", "discarded", "cancelled"] and
              r.state in ["pending", "running"] and not is_nil(d.batch_id),
          limit: 100,
          select: {d.id, r.id}
      )

    Enum.each(jobs, fn {id, run} -> ExtractionRuns.interrupt(id, run) end)

    # Build the readiness aggregate explicitly to include missing run rows.
    ready =
      from d in Document,
        left_join: r in ExtractionRun,
        on: r.id == d.initial_extraction_run_id,
        where: is_nil(d.deleted_at) and not is_nil(d.batch_id),
        group_by: d.batch_id,
        having: count(d.id) == filter(count(d.id), r.state in ["completed", "failed"]),
        select: d.batch_id

    Repo.update_all(
      from(b in Batch,
        where:
          b.id in subquery(ready) and not is_nil(b.started_at) and
            is_nil(b.extraction_finished_at) and is_nil(b.deleted_at)
      ),
      set: [extraction_finished_at: now(), updated_at: now()]
    )

    :ok
  end

  defp target(batch) do
    cfg = IncomingDocuments.config()

    with :ok <- IncomingDocuments.configured(cfg) do
      if SupplierProfiles.base_url(batch.base_url) == SupplierProfiles.base_url(cfg[:base_url]) &&
           batch.company_id == cfg[:company_id],
         do: :ok,
         else: {:error, "Cílová firma se změnila; dávka je uzamčená"}
    end
  end

  defp target!(batch) do
    case target(batch) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp preparing!(batch), do: if(batch.started_at, do: Repo.rollback("Dávka již byla spuštěna"))
  defp now, do: DateTime.utc_now(:second)
  defp update!(row, attrs), do: row |> Ecto.Changeset.change(attrs) |> Repo.update!(log: false)

  defp locked(id, fun),
    do:
      Repo.transaction(fn ->
        fun.(
          Repo.one!(
            from b in Batch, where: b.id == ^id and is_nil(b.deleted_at), lock: "FOR UPDATE"
          )
        )
      end)
end

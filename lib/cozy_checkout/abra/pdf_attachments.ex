defmodule CozyCheckout.Abra.PdfAttachments do
  @moduledoc "Opt-in PDF delivery. Only reads existing accounting export state."
  import Ecto.Query
  alias CozyCheckout.{Billing, Repo}
  alias CozyCheckout.Abra.{Accommodation, AccommodationExport, PdfClient, PdfTransfer}
  alias CozyCheckout.Billing.Document
  alias CozyCheckout.Workers.AbraPdfWorker

  def enabled?, do: Application.get_env(:cozy_checkout, :abra_pdf, [])[:enabled] == true

  def status(document_id) do
    Repo.one(
      from t in PdfTransfer,
        join: e in assoc(t, :export),
        where: e.document_id == ^document_id
    )
  end

  @doc "Explicitly queue one already synchronized document; also retries a failed attachment."
  def enqueue(document_id) do
    if enabled?() do
      Repo.transaction(fn ->
        export = Repo.one(from e in AccommodationExport, where: e.document_id == ^document_id)
        doc = Repo.get(Document, document_id)

        unless export && doc && export.state == "synced" &&
                 doc.kind in ["advance", "final"] && is_binary(export.remote_id),
               do:
                 Repo.rollback(
                   "PDF vyžaduje úspěšně synchronizovanou zálohovou nebo konečnou fakturu"
                 )

        transfer = %PdfTransfer{export_id: export.id}
        Repo.insert!(transfer, on_conflict: :nothing, conflict_target: [:export_id])

        transfer =
          Repo.one!(from t in PdfTransfer, where: t.export_id == ^export.id, lock: "FOR UPDATE")

        if transfer.state != "uploaded" do
          {:ok, _} = %{transfer_id: transfer.id} |> AbraPdfWorker.new() |> Oban.insert()
          transfer |> Ecto.Changeset.change(state: "queued", error: nil) |> Repo.update!()
        else
          transfer
        end
      end)
    else
      {:error, "Odesílání PDF do ABRA je vypnuté"}
    end
  end

  @doc "Queue a bounded batch of missing attachments whenever PDF delivery is enabled."
  def scan do
    if enabled?() do
      ids =
        Repo.all(
          from e in AccommodationExport,
            join: d in Document,
            on: d.id == e.document_id,
            left_join: t in PdfTransfer,
            on: t.export_id == e.id,
            where:
              e.state == "synced" and
                d.kind in ["advance", "final"] and is_nil(t.id),
            order_by: [asc: e.synced_at, asc: e.id],
            limit: 50,
            select: e.id
        )

      # Batch the new intents and jobs; the scan has no per-document queries.
      now = DateTime.utc_now(:second)

      rows =
        Enum.map(
          ids,
          &%{
            id: Ecto.UUID.generate(),
            export_id: &1,
            state: "queued",
            inserted_at: now,
            updated_at: now
          }
        )

      case Repo.transaction(fn ->
             {_, inserted} =
               Repo.insert_all(PdfTransfer, rows,
                 on_conflict: :nothing,
                 conflict_target: [:export_id],
                 returning: [:id]
               )

             inserted |> Enum.map(&AbraPdfWorker.new(%{transfer_id: &1.id})) |> Oban.insert_all()
           end) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  def deliver(id) do
    if enabled?() do
      transfer = Repo.get!(PdfTransfer, id)
      if transfer.state == "uploaded", do: :ok, else: transfer(transfer)
    else
      {:snooze, 60}
    end
  end

  defp transfer(transfer) do
    export = Repo.get!(AccommodationExport, transfer.export_id)
    cfg = Accommodation.config()

    result =
      with :ok <- validate_target(export, cfg),
           {:ok, doc} <- Billing.ensure_pdf(export.document_id) do
        hash = digest(doc.pdf)
        filename = "#{doc.number}.pdf"
        legacy_filename = "cozy-#{doc.id}-#{hash}.pdf"
        previous_hash = if export.verification["advance_update"], do: transfer.sha256
        filenames = [filename, legacy_filename]

        filenames =
          if is_binary(previous_hash),
            do: Enum.uniq(filenames ++ ["cozy-#{doc.id}-#{previous_hash}.pdf"]),
            else: filenames

        with :ok <-
               ensure_attachment(
                 export.remote_id,
                 filenames,
                 doc.pdf,
                 hash,
                 cfg,
                 previous_hash
               ) do
          transfer
          |> Ecto.Changeset.change(
            state: "uploaded",
            error: nil,
            sha256: hash,
            uploaded_at: DateTime.utc_now(:second)
          )
          |> Repo.update!()

          :ok
        end
      end

    case result do
      :ok ->
        :ok

      {:error, reason} ->
        transfer |> Ecto.Changeset.change(state: "failed", error: reason) |> Repo.update!()
        {:error, reason}
    end
  end

  defp validate_target(export, cfg) do
    cond do
      export.state != "synced" or not is_binary(export.remote_id) ->
        {:error, "Účetní export není dokončen"}

      export.base_url != cfg[:base_url] or export.company_id != cfg[:company_id] ->
        {:error, "Cílová firma ABRA se změnila; přenos PDF pozastaven"}

      cfg[:username] in [nil, ""] or cfg[:password] in [nil, ""] ->
        {:error, "Chybí přístupové údaje do ABRA"}

      true ->
        :ok
    end
  end

  defp ensure_attachment(id, [filename | _] = filenames, bytes, hash, cfg, previous_hash) do
    case PdfClient.find(id, filenames, cfg) do
      :not_found ->
        with :ok <- PdfClient.upload(id, filename, bytes, cfg),
             do: verify_attachment(id, filename, hash, cfg)

      {:ok, [%{"id" => attachment_id}]} when is_binary(previous_hash) ->
        with {:ok, current} <- PdfClient.content(id, attachment_id, cfg) do
          cond do
            digest(current) == hash ->
              :ok

            digest(current) == previous_hash ->
              with :ok <- PdfClient.delete(id, attachment_id, cfg),
                   :ok <- PdfClient.upload(id, filename, bytes, cfg),
                   do: verify_attachment(id, filename, hash, cfg)

            true ->
              {:error, "Obsah PDF přílohy v ABRA nesouhlasí"}
          end
        end

      {:ok, rows} ->
        verify_content(id, rows, hash, cfg)

      error ->
        error
    end
  end

  defp verify_attachment(id, filename, hash, cfg) do
    case PdfClient.find(id, filename, cfg) do
      {:ok, rows} -> verify_content(id, rows, hash, cfg)
      :not_found -> {:error, "ABRA po nahrání nevrátila PDF přílohu"}
      error -> error
    end
  end

  defp verify_content(id, [%{"id" => attachment_id}], hash, cfg) do
    with {:ok, bytes} <- PdfClient.content(id, attachment_id, cfg) do
      if digest(bytes) == hash, do: :ok, else: {:error, "Obsah PDF přílohy v ABRA nesouhlasí"}
    end
  end

  defp verify_content(_, _, _, _), do: {:error, "Nejednoznačná PDF příloha v ABRA"}
  defp digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end

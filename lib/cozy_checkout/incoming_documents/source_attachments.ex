defmodule CozyCheckout.IncomingDocuments.SourceAttachments do
  @moduledoc "Durable delivery of the stored source, independently of the immutable accounting import."
  import Ecto.Query
  alias CozyCheckout.{IncomingDocuments, Repo}
  alias CozyCheckout.Abra.PdfClient
  alias CozyCheckout.IncomingDocuments.{Document, SupplierProfiles}
  alias CozyCheckout.Workers.IncomingDocumentAttachmentWorker

  def enqueue(id), do: locked(id, &enqueue_locked/1)

  # Called under the document lock, in the same transaction as confirmed sent.
  def enqueue_locked(doc) do
    cond do
      is_nil(doc.original) ->
        doc

      doc.state != "sent" or is_nil(doc.remote_id) ->
        Repo.rollback("Nejprve musí být doklad potvrzený v ABRA")

      doc.source_attachment["state"] in ["queued", "processing", "uploaded"] ->
        doc

      doc.content_type not in ["application/pdf", "image/jpeg", "image/png"] ->
        update!(doc, %{
          "state" => "failed",
          "error" => "Podklad nemá podporovaný formát PDF, JPEG nebo PNG"
        })

      true ->
        delivery_id = Ecto.UUID.generate()

        extension =
          case doc.content_type do
            "application/pdf" -> ".pdf"
            "image/jpeg" -> ".jpg"
            "image/png" -> ".png"
          end

        attachment = %{
          "state" => "queued",
          "delivery_id" => delivery_id,
          "filename" => "podklad-#{doc.id}#{extension}",
          "sha256" => doc.sha256,
          "upload_reserved" => false
        }

        case %{document_id: doc.id, delivery_id: delivery_id}
             |> IncomingDocumentAttachmentWorker.new()
             |> Oban.insert() do
          {:ok, %{conflict?: false}} -> update!(doc, attachment)
          _ -> Repo.rollback("Přílohu se nepodařilo zařadit do fronty")
        end
    end
  end

  def deliver(%Oban.Job{
        args: %{"document_id" => id, "delivery_id" => delivery_id},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    case claim(id, delivery_id, attempt, max_attempts || 5) do
      {:ok, :skip} ->
        :ok

      {:ok, {:error, reason}} ->
        {:error, reason}

      {:ok, {doc, token, cfg}} ->
        result = ensure_source(doc, token, cfg)

        case finish(doc.id, delivery_id, token, result) do
          {:ok, _} -> result
          _ -> :ok
        end

      {:error, _} ->
        :ok
    end
  end

  def worker_failed(id, delivery_id, attempt) do
    locked(id, fn doc ->
      attachment = doc.source_attachment

      if attachment["delivery_id"] == delivery_id && attachment["attempt"] in [nil, attempt] &&
           attachment["state"] != "uploaded" do
        update!(
          doc,
          Map.merge(attachment, %{
            "state" => "failed",
            "error" => "Přenos přílohy byl přerušen. Další pokus nejprve ověří přílohy v ABRA.",
            "attempt" => attempt,
            "retry_pending" => attempt < (attachment["max_attempts"] || 5)
          })
        )
      end
    end)
  end

  def reconcile do
    error = %{
      "state" => "failed",
      "retry_pending" => false,
      "error" =>
        "Job přílohy byl ukončen před potvrzením přenosu. Přenos lze zopakovat bez nového účetního dokladu."
    }

    Repo.update_all(
      from(d in Document,
        join: j in Oban.Job,
        on:
          fragment("?->>'delivery_id'", j.args) ==
            fragment("?->>'delivery_id'", d.source_attachment),
        where:
          j.worker == "CozyCheckout.Workers.IncomingDocumentAttachmentWorker" and
            j.state in ["completed", "discarded", "cancelled"],
        where:
          fragment("?->>'state'", d.source_attachment) in ["queued", "processing"] or
            fragment("?->>'retry_pending' = 'true'", d.source_attachment)
      ),
      set: [
        source_attachment:
          dynamic([d], fragment("? || ?", d.source_attachment, type(^error, :map))),
        updated_at: DateTime.utc_now(:second)
      ]
    )

    :ok
  end

  defp claim(id, delivery_id, attempt, max_attempts) do
    locked(id, fn doc ->
      attachment = doc.source_attachment

      cond do
        attachment["delivery_id"] != delivery_id || attachment["state"] == "uploaded" ->
          :skip

        attachment["state"] == "processing" && (attachment["attempt"] || 0) >= attempt ->
          :skip

        true ->
          cfg = IncomingDocuments.config()

          case validate(doc, attachment, cfg) do
            :ok ->
              token = Ecto.UUID.generate()

              attachment =
                Map.merge(attachment, %{
                  "state" => "processing",
                  "attempt" => attempt,
                  "max_attempts" => max_attempts,
                  "token" => token,
                  "error" => nil
                })

              {update!(doc, attachment), token,
               cfg
               |> Keyword.put(:attachment_agenda, doc.agenda)
               |> Keyword.put(:attachment_content_type, doc.content_type)
               |> Keyword.put(:attachment_exhaustive, true)}

            {:error, reason} ->
              update!(
                doc,
                Map.merge(attachment, %{
                  "state" => "failed",
                  "error" => reason,
                  "attempt" => attempt,
                  "max_attempts" => max_attempts,
                  "retry_pending" => attempt < max_attempts
                })
              )

              {:error, reason}
          end
      end
    end)
  end

  defp validate(doc, attachment, cfg) do
    with :ok <- IncomingDocuments.configured(cfg) do
      cond do
        doc.state != "sent" || is_nil(doc.remote_id) ->
          {:error, "Doklad není potvrzený v ABRA"}

        SupplierProfiles.base_url(doc.base_url) != SupplierProfiles.base_url(cfg[:base_url]) ||
            doc.company_id != cfg[:company_id] ->
          {:error, "Cílová firma se změnila; přenos přílohy je blokován"}

        not is_binary(doc.original) || doc.sha256 != attachment["sha256"] ||
            IncomingDocuments.digest(doc.original) != doc.sha256 ->
          {:error, "Uložený podklad se změnil; příloha nebyla odeslána"}

        true ->
          :ok
      end
    end
  end

  defp ensure_source(doc, token, cfg) do
    filename = doc.source_attachment["filename"]

    case PdfClient.find(doc.remote_id, filename, cfg) do
      {:ok, rows} ->
        verify_content(doc, rows, cfg)

      :not_found ->
        # A reserved PUT may have reached ABRA. Automatic retries only reconcile;
        # a new upload permission requires an explicit new delivery intent.
        if doc.source_attachment["upload_reserved"] do
          {:error,
           "Předchozí přenos přílohy není potvrzený. Zkontrolujte přílohy v ABRA a případně spusťte nový pokus tlačítkem."}
        else
          with {:ok, :reserved} <- reserve(doc, token),
               :ok <- PdfClient.upload(doc.remote_id, filename, doc.original, cfg),
               {:ok, rows} <- find_uploaded(doc, filename, cfg) do
            verify_content(doc, rows, cfg)
          else
            {:error, reason} when is_binary(reason) -> {:error, reason}
            _ -> {:error, "Přenos přílohy byl nahrazen novějším pokusem"}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
    |> friendly_error()
  end

  defp reserve(doc, token) do
    locked(doc.id, fn current ->
      unless current.source_attachment["state"] == "processing" &&
               current.source_attachment["token"] == token &&
               current.source_attachment["delivery_id"] == doc.source_attachment["delivery_id"],
             do: Repo.rollback(:stale)

      update!(current, Map.put(current.source_attachment, "upload_reserved", true))
      :reserved
    end)
  end

  defp find_uploaded(doc, filename, cfg) do
    case PdfClient.find(doc.remote_id, filename, cfg) do
      :not_found -> {:error, "ABRA po nahrání nevrátila přílohu"}
      result -> result
    end
  end

  defp verify_content(doc, [%{"id" => id}], cfg) do
    with {:ok, bytes} <- PdfClient.content(doc.remote_id, id, cfg) do
      if IncomingDocuments.digest(bytes) == doc.sha256,
        do: :ok,
        else: {:error, "Obsah přílohy v ABRA nesouhlasí; existující příloha nebyla přepsána"}
    end
  end

  defp verify_content(_, _, _),
    do: {:error, "ABRA vrátila nejednoznačnou přílohu; nic nebylo přepsáno"}

  defp friendly_error({:error, reason}),
    do: {:error, String.replace(reason, "ABRA PDF", "ABRA příloha")}

  defp friendly_error(:ok), do: :ok

  defp finish(id, delivery_id, token, result) do
    locked(id, fn doc ->
      attachment = doc.source_attachment

      unless attachment["delivery_id"] == delivery_id && attachment["token"] == token,
        do: Repo.rollback(:stale)

      attrs =
        case result do
          :ok ->
            %{
              "state" => "uploaded",
              "error" => nil,
              "retry_pending" => false,
              "verified_at" => DateTime.to_iso8601(DateTime.utc_now(:second))
            }

          {:error, reason} ->
            %{
              "state" => "failed",
              "error" => reason,
              "retry_pending" => (attachment["attempt"] || 0) < (attachment["max_attempts"] || 5)
            }
        end

      update!(doc, Map.merge(attachment, attrs))
    end)
  end

  defp update!(doc, attachment),
    do: doc |> Ecto.Changeset.change(source_attachment: attachment) |> Repo.update!(log: false)

  defp locked(id, fun),
    do:
      Repo.transaction(fn ->
        fun.(
          Repo.one!(
            from d in Document, where: d.id == ^id and is_nil(d.deleted_at), lock: "FOR UPDATE"
          )
        )
      end)
end

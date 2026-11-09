defmodule CozyCheckout.Abra.PdfClient do
  @moduledoc "Attachment-only ABRA client. Cannot create or update accounting documents."

  def upload(remote_id, filename, pdf, cfg) do
    path = invoice_path(remote_id, cfg) <> "/prilohy/new/" <> segment(filename)

    case request(:put, path, cfg,
           body: pdf,
           headers: [{"content-type", cfg[:attachment_content_type] || "application/pdf"}]
         ) do
      {:ok, %{status: status}} when status in [200, 201] -> :ok
      other -> error(other)
    end
  end

  def delete(remote_id, attachment_id, cfg) do
    path = invoice_path(remote_id, cfg) <> "/prilohy/" <> segment(attachment_id) <> ".json"

    case request(:delete, path, cfg, []) do
      {:ok, %{status: status}} when status in [200, 204, 404] -> :ok
      other -> error(other)
    end
  end

  # Read every page before deciding an attachment is absent. A lost PUT response
  # must be reconciled before another upload can be attempted.
  def find(remote_id, filenames, cfg), do: find(remote_id, List.wrap(filenames), cfg, 0, [])

  defp find(_remote_id, _filenames, _cfg, offset, _matches) when offset >= 10_000,
    do: {:error, "ABRA PDF: seznam příloh přesáhl bezpečný limit"}

  defp find(remote_id, filenames, cfg, offset, previous_matches) do
    case request(:get, invoice_path(remote_id, cfg) <> "/prilohy.json", cfg,
           params: [detail: "full", limit: 100, start: offset, order: "id"]
         ) do
      {:ok, %{status: 200, body: %{"winstrom" => %{"priloha" => rows}}}} when is_list(rows) ->
        matches =
          previous_matches ++ Enum.filter(rows, &(is_map(&1) and &1["nazSoub"] in filenames))

        cond do
          length(rows) > 100 or
              not Enum.all?(
                rows,
                &(is_map(&1) and is_binary(&1["nazSoub"]) and not is_nil(&1["id"]))
              ) ->
            {:error, "ABRA PDF: neplatný seznam příloh"}

          length(rows) == 100 && (matches == [] || cfg[:attachment_exhaustive] == true) ->
            find(remote_id, filenames, cfg, offset + 100, matches)

          matches != [] ->
            {:ok, matches}

          true ->
            :not_found
        end

      other ->
        error(other)
    end
  end

  def content(remote_id, attachment_id, cfg) do
    path = invoice_path(remote_id, cfg) <> "/prilohy/" <> segment(attachment_id) <> "/content"

    case request(:get, path, cfg, decode_body: false) do
      {:ok, %{status: 200, body: bytes}} when is_binary(bytes) -> {:ok, bytes}
      other -> error(other)
    end
  end

  defp request(method, path, cfg, opts) do
    Req.request(
      Keyword.merge(
        [
          method: method,
          url:
            "#{String.trim_trailing(cfg[:base_url], "/")}/c/#{segment(cfg[:company_id])}/#{path}",
          auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
          retry: false,
          redirect: false,
          receive_timeout: 30_000
        ],
        opts
      )
    )
  end

  defp invoice_path(id, cfg),
    do: (cfg[:attachment_agenda] || "faktura-vydana") <> "/" <> segment(id)

  defp segment(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)

  defp error({:ok, %{status: status}}),
    do: {:error, "ABRA PDF: HTTP #{status} nebo neplatná odpověď"}

  defp error({:error, _}),
    do: {:error, "ABRA PDF: síťová chyba; další pokus nejprve ověří přílohy"}
end

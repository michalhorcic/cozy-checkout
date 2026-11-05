defmodule CozyCheckout.IncomingDocuments.Client do
  @moduledoc "Native JSON import projected from reviewed XML, matching accommodation API requests."

  alias CozyCheckout.IncomingDocuments.{ImportPayload, ResponseDiagnostics}

  def import(doc, xml, dry_run?, cfg) do
    case ImportPayload.from_xml(xml, doc) do
      {:ok, payload} -> request_import(doc, xml, payload, dry_run?, cfg)
      {:error, reason} -> {:rejected, reason, %{"errors" => [reason], "warnings" => []}}
    end
  end

  defp request_import(doc, xml, payload, dry_run?, cfg) do
    case Req.post(url(doc) <> ".json",
           json: payload,
           headers: [{"accept", "application/json"}],
           params: if(dry_run?, do: [{"dry-run", "true"}], else: []),
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           retry: false,
           redirect: false,
           decode_body: false,
           receive_timeout: 30_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, response} ->
        content_type = response |> Req.Response.get_header("content-type") |> Enum.join(", ")

        headers =
          for name <- ~w(content-type location server via retry-after www-authenticate),
              values = Req.Response.get_header(response, name),
              values != [],
              into: %{} do
            value = Enum.join(values, ", ") |> String.slice(0, 1500)
            {name, if(name == "location", do: ResponseDiagnostics.safe_url(value), else: value)}
          end

        metadata = %{
          "request" => %{
            "method" => "POST",
            "url" => ResponseDiagnostics.safe_url(url(doc) <> ".json"),
            "dry_run" => dry_run?,
            "accept" => "application/json",
            "content_type" => "application/json",
            "source_xml_hash" => CozyCheckout.IncomingDocuments.digest(xml),
            "json_payload_hash" => CozyCheckout.IncomingDocuments.digest(Jason.encode!(payload))
          },
          "response_headers" => headers
        }

        parse_response(response.status, response.body, dry_run?, content_type, metadata)

      {:error, _} ->
        {:uncertain, "ABRA není dostupná nebo vypršel časový limit"}
    end
  end

  def presets(doc, cfg), do: presets_page(doc, cfg, 0, [])

  defp presets_page(_doc, _cfg, offset, _rows) when offset >= 2000,
    do: {:error, "Číselník dosáhl limitu 2000 předpisů; načtení nebylo potvrzeno jako úplné"}

  defp presets_page(doc, cfg, offset, rows) do
    endpoint =
      "#{String.trim_trailing(doc.base_url, "/")}/c/#{encode(doc.company_id)}/predpis-zauctovani.json"

    fields =
      "id,kod,nazev,modulFap,modulZav,modulPokV,protiUcetVydej,dphZaklUcet,dphSnizUcet,dphSniz2Ucet"

    case Req.get(endpoint,
           params: [
             detail: "custom:" <> fields,
             relations: "code",
             limit: 200,
             start: offset,
             order: "id"
           ],
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           retry: false,
           redirect: false,
           receive_timeout: 15_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, %{status: 200, body: %{"winstrom" => %{"predpis-zauctovani" => page}}}}
      when is_list(page) and length(page) <= 200 ->
        if Enum.all?(page, &is_map/1) do
          if length(page) < 200,
            do: {:ok, rows ++ page},
            else: presets_page(doc, cfg, offset + 200, rows ++ page)
        else
          {:error, "ABRA vrátila neplatný číselník předpisů"}
        end

      {:ok, %{status: status}} ->
        {:error, "Načtení předpisů ABRA selhalo (HTTP #{status})"}

      _ ->
        {:error, "Číselník předpisů ABRA není dostupný"}
    end
  end

  def find(doc, cfg) do
    id = URI.encode(doc.external_id, &URI.char_unreserved?/1)

    case Req.get(url(doc) <> "/#{id}.json",
           params: [detail: "custom:id"],
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           retry: false,
           redirect: false,
           receive_timeout: 30_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, %{status: 200, body: %{"winstrom" => body}}} when is_map(body) ->
        case body[doc.agenda] do
          [%{"id" => id}] ->
            if valid_id?(id), do: {:ok, to_string(id)}, else: {:error, "ABRA nevrátila platné ID"}

          [] ->
            :not_found

          _ ->
            {:error, "ABRA nevrátila jednoznačný výsledek ověření"}
        end

      {:ok, %{status: 404}} ->
        :not_found

      _ ->
        {:error, "Výsledek v ABRA se nepodařilo ověřit"}
    end
  end

  def url(doc),
    do: "#{String.trim_trailing(doc.base_url, "/")}/c/#{encode(doc.company_id)}/#{doc.agenda}"

  def document_url(doc), do: url(doc) <> "/#{encode(doc.remote_id)}"
  defp encode(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp parse_response(status, raw, dry?, content_type, metadata) do
    parsed =
      if is_binary(raw) do
        case Jason.decode(raw) do
          {:ok, parsed} -> parsed
          _ -> raw
        end
      else
        raw
      end

    response =
      Map.merge(metadata, %{
        "http_status" => status,
        "content_type" => content_type,
        "raw_body" => preview(raw),
        "truncated" => is_binary(raw) and String.valid?(raw) and String.length(raw) > 100_000,
        "warnings" => [],
        "errors" => []
      })

    case parsed do
      %{"winstrom" => body} when is_map(body) ->
        parse_winstrom(status, body, dry?, response)

      _ ->
        format =
          cond do
            is_map(parsed) ->
              "JSON neobsahuje očekávaný objekt winstrom; klíče: " <>
                Enum.join(Map.keys(parsed), ", ")

            is_binary(parsed) and String.trim(parsed) == "" ->
              "prázdné tělo odpovědi"

            is_binary(parsed) and String.starts_with?(String.trim(parsed), "<") ->
              "server vrátil XML nebo HTML místo očekávaného JSON"

            true ->
              "tělo odpovědi není očekávané JSON"
          end

        diagnostic = ResponseDiagnostics.describe(status, raw, metadata["response_headers"])

        {:uncertain, "ABRA HTTP #{status}: #{format}. " <> diagnostic["summary"],
         Map.put(response, "format_diagnostic", diagnostic)}
    end
  end

  defp parse_winstrom(status, body, dry?, response) do
    results = body["results"]
    errors = messages(body, "errors")
    warnings = messages(body, "warnings")
    result = if is_list(results) and length(results) == 1, do: hd(results), else: %{}
    id = if is_map(result), do: result["id"]

    response =
      Map.merge(response, %{
        "body" => body,
        "warnings" => warnings,
        "errors" => errors,
        "preview" => dry_run_preview(result)
      })

    cond do
      status in [200, 201] and body["success"] in [true, "true"] and errors == [] and
        is_map(result) and map_size(result) > 0 and (dry? or valid_id?(id)) ->
        {:ok, Map.put(response, "id", if(id, do: to_string(id)))}

      errors != [] ->
        {:rejected, Enum.join(errors, "; "), response}

      true ->
        details =
          "success=#{inspect(body["success"])}, počet výsledků=#{if is_list(results), do: length(results), else: "chybí"}, id=#{inspect(id)}"

        {:uncertain,
         "ABRA HTTP #{status}: nejednoznačný výsledek importu (#{details}). Rozbalte podrobnosti odpovědi ABRA.",
         response}
    end
  end

  defp dry_run_preview(%{"content" => content}) when is_map(content) do
    for {agenda, records} <- content,
        agenda in ["faktura-prijata", "pokladni-pohyb", "zavazek"],
        record <- List.wrap(records),
        is_map(record),
        do:
          Map.take(
            record,
            ~w(kod typUcOp primUcet protiUcet dphZaklUcet dphSnizUcet dphSniz2Ucet)
          )
  end

  defp dry_run_preview(_), do: []

  defp messages(body, key) do
    entries =
      List.wrap(body[key]) ++
        Enum.flat_map(List.wrap(body["results"]), fn
          result when is_map(result) -> List.wrap(result[key])
          _ -> []
        end)

    Enum.map(entries, fn
      message when is_map(message) ->
        text = message["message"] || message["$"] || "ABRA: #{key}"

        details =
          for {field, label} <- [
                {"for", "pole"},
                {"path", "cesta"},
                {"code", "kód"},
                {"messageCode", "typ chyby"},
                {"value", "hodnota"}
              ],
              Map.has_key?(message, field),
              do: "#{label}: #{display(message[field])}"

        Enum.join([display(text) | details], " · ")

      message when is_binary(message) ->
        message

      _ ->
        "ABRA: #{key}"
    end)
  end

  defp display(value) when is_binary(value), do: value
  defp display(value), do: inspect(value)

  defp preview(raw) when is_binary(raw) do
    if String.valid?(raw),
      do: String.slice(raw, 0, 100_000),
      else: "Binární odpověď (#{byte_size(raw)} bytů)"
  end

  defp preview(raw), do: Jason.encode!(raw, pretty: true) |> String.slice(0, 100_000)

  defp valid_id?(id) when is_integer(id), do: id > 0
  defp valid_id?(id) when is_binary(id), do: Regex.match?(~r/^[1-9]\d*$/, id)
  defp valid_id?(_), do: false
end

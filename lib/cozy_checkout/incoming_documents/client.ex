defmodule CozyCheckout.IncomingDocuments.Client do
  @moduledoc "XML import using the existing ABRA connection conventions, without logging document data."

  def import(doc, xml, dry_run?, cfg) do
    case Req.post(url(doc) <> ".json",
           body: xml,
           headers: [{"content-type", "application/xml"}, {"accept", "application/json"}],
           params: [{"dry-run", to_string(dry_run?)}],
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           retry: false,
           redirect: false,
           receive_timeout: 30_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, %{status: status, body: body}} -> parse_response(status, body, dry_run?)
      {:error, _} -> {:uncertain, "ABRA není dostupná nebo vypršel časový limit"}
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

  defp parse_response(status, %{"winstrom" => body}, dry?) when is_map(body) do
    results = body["results"]
    errors = messages(body, "errors")
    warnings = messages(body, "warnings")
    result = if is_list(results) and length(results) == 1, do: hd(results), else: %{}
    id = if is_map(result), do: result["id"]
    response = %{"http_status" => status, "body" => body, "warnings" => warnings}

    cond do
      status in [200, 201] and body["success"] in [true, "true"] and errors == [] and
        is_map(result) and map_size(result) > 0 and (dry? or valid_id?(id)) ->
        {:ok, Map.put(response, "id", if(id, do: to_string(id)))}

      errors != [] ->
        {:rejected, Enum.join(errors, "; "), response}

      true ->
        {:uncertain, "ABRA vrátila nejednoznačnou odpověď (HTTP #{status})"}
    end
  end

  defp parse_response(status, _, _),
    do: {:uncertain, "ABRA vrátila neplatnou odpověď (HTTP #{status})"}

  defp messages(body, key) do
    entries =
      List.wrap(body[key]) ++
        Enum.flat_map(List.wrap(body["results"]), fn
          result when is_map(result) -> List.wrap(result[key])
          _ -> []
        end)

    Enum.map(entries, fn
      %{"message" => message} when is_binary(message) -> message
      message when is_binary(message) -> message
      _ -> "ABRA: #{key}"
    end)
  end

  defp valid_id?(id) when is_integer(id), do: id > 0
  defp valid_id?(id) when is_binary(id), do: Regex.match?(~r/^[1-9]\d*$/, id)
  defp valid_id?(_), do: false
end

defmodule CozyCheckout.Abra.Client do
  @moduledoc """
  HTTP client for ABRA Flexi REST API using Basic authentication.
  """

  require Logger

  @doc """
  POSTs a new invoice (faktura-vydana) to Abra Flexi.
  Returns {:ok, abra_id} on success or {:error, reason} on failure.
  """
  def create_invoice(payload, cfg \\ config()) do
    url = "#{cfg[:base_url]}/c/#{cfg[:company_id]}/faktura-vydana.json"

    case Req.post(url,
           json: payload,
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           headers: [{"Accept", "application/json"}],
           retry: false
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in [200, 201] ->
        parse_abra_id(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        reason = extract_error(body, status)
        Logger.warning("[Abra] Invoice creation failed: #{reason}")
        {:error, reason}

      {:error, exception} ->
        reason = Exception.message(exception)
        Logger.warning("[Abra] HTTP error: #{reason}")
        {:error, reason}
    end
  end

  @doc "Reads an invoice by stable external identity without changing it."
  def find_invoice(external_id, cfg) do
    id = URI.encode(external_id, &URI.char_unreserved?/1)
    url = "#{cfg[:base_url]}/c/#{cfg[:company_id]}/faktura-vydana/#{id}.json"

    case Req.get(url,
           params: [
             detail:
               "custom:id,kod,varSym,sumCelkem,mena,typDokl,bankovniUcet,ucetni,clenDph,clenKonVykDph"
           ],
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           headers: [{"Accept", "application/json"}],
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: %{"winstrom" => %{"faktura-vydana" => [invoice]}}}}
      when is_map(invoice) ->
        {:ok, invoice}

      {:ok, %Req.Response{status: 200, body: %{"winstrom" => %{"faktura-vydana" => []}}}} ->
        :not_found

      {:ok, %Req.Response{status: 404}} ->
        :not_found

      {:ok, %Req.Response{status: 200}} ->
        {:error, "unexpected_response"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "ABRA lookup HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  @doc "Reads one bank page; no date filter, so late imports are included."
  def bank_page(offset, limit, cfg) do
    url = "#{cfg[:base_url]}/c/#{cfg[:company_id]}/banka.json"

    case Req.get(url,
           params: [detail: "full", limit: limit, start: offset, order: "id"],
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           headers: [{"Accept", "application/json"}],
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: %{"winstrom" => %{"banka" => rows}}}}
      when is_list(rows) ->
        {:ok, rows}

      {:ok, %Req.Response{status: 200}} ->
        {:error, "ABRA vrátila neplatný seznam bankovních pohybů"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "ABRA banka HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp parse_abra_id(%{"winstrom" => %{"results" => [%{} = result | _]}}) do
    case Map.get(result, "errors") do
      [error | _] = errors ->
        reason = error_message(error)
        Logger.warning("[Abra] Invoice import failed: #{inspect(errors)}")
        {:error, reason}

      errors when errors in [nil, []] ->
        case valid_document_id(Map.get(result, "id")) do
          {:ok, id} ->
            {:ok, id}

          :error ->
            Logger.warning("[Abra] Response did not contain a valid document ID")
            {:error, "unexpected_response"}
        end

      _ ->
        Logger.warning("[Abra] Unexpected response errors: #{inspect(result)}")
        {:error, "unexpected_response"}
    end
  end

  defp parse_abra_id(body) do
    Logger.warning("[Abra] Unexpected response body: #{inspect(body)}")
    {:error, "unexpected_response"}
  end

  defp valid_document_id(id) when is_integer(id) and id > 0, do: {:ok, Integer.to_string(id)}

  defp valid_document_id(id) when is_binary(id) do
    if String.trim(id) == "", do: :error, else: {:ok, id}
  end

  defp valid_document_id(_), do: :error

  defp error_message(%{"message" => message}) when is_binary(message) and message != "",
    do: message

  defp error_message(_), do: "import_error"

  defp extract_error(
         %{"winstrom" => %{"results" => [%{"errors" => [%{"message" => msg} | _]} | _]}},
         _
       ),
       do: msg

  defp extract_error(_, status), do: "HTTP #{status}"

  defp config, do: Application.fetch_env!(:cozy_checkout, :abra)
end

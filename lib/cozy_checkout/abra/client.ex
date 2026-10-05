defmodule CozyCheckout.Abra.Client do
  @moduledoc """
  HTTP client for ABRA Flexi REST API using Basic authentication.
  """

  require Logger

  @doc """
  POSTs a new invoice (faktura-vydana) to Abra Flexi.
  Returns {:ok, abra_id} on success or {:error, reason} on failure.
  """
  def create_invoice(payload) do
    cfg = config()
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

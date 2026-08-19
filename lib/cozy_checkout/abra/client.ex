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

  defp parse_abra_id(%{"winstrom" => %{"results" => [%{"id" => id} | _]}}),
    do: {:ok, to_string(id)}

  defp parse_abra_id(body) do
    Logger.warning("[Abra] Unexpected response body: #{inspect(body)}")
    {:error, "unexpected_response"}
  end

  defp extract_error(
         %{"winstrom" => %{"results" => [%{"errors" => [%{"message" => msg} | _]} | _]}},
         _
       ),
       do: msg

  defp extract_error(_, status), do: "HTTP #{status}"

  defp config, do: Application.fetch_env!(:cozy_checkout, :abra)
end

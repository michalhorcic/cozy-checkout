defmodule CozyCheckout.Economics.Config do
  @moduledoc "Explicit reporting connection; never inherits Billing or bar credentials."

  def get, do: Application.get_env(:cozy_checkout, :economics, [])
  def enabled?, do: Keyword.get(get(), :enabled, false)

  def connection do
    cfg = get()
    uri = URI.parse(Keyword.get(cfg, :base_url) || "")

    cond do
      not enabled?() ->
        {:error, :disabled}

      (uri.scheme != "https" or is_nil(uri.host) or uri.userinfo) || uri.query || uri.fragment ->
        {:error, :invalid_connection}

      Enum.any?([:company_id, :username, :password], &blank?(cfg[&1])) ->
        {:error, :invalid_connection}

      true ->
        {:ok, cfg}
    end
  end

  def identity(cfg) do
    {String.trim_trailing(cfg[:base_url], "/"), cfg[:company_id]}
  end

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end

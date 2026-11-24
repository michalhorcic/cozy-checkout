defmodule CozyCheckout.Abra.InvoiceCancellation do
  @moduledoc "Verified, retryable cancellation using the original ABRA identity."
  alias CozyCheckout.Abra.{Client, BankVerification}

  def cancel(export, doc, cfg) do
    with {:ok, remote} <- Client.read_invoice(export.external_id, cfg),
         :ok <- unpaid_original(remote, export, doc) do
      if remote["storno"] in [true, "true"] do
        :ok
      else
        with {:ok, response} <- Client.cancel_invoice(export.external_id, cfg),
             {:ok, confirmed} <- Client.read_invoice(export.external_id, cfg),
             :ok <- unpaid_original(confirmed, export, doc) do
          if confirmed["storno"] in [true, "true"],
            do: :ok,
            else: {:error, unconfirmed_reason(confirmed, response)}
        else
          :not_found -> {:error, "ABRA po stornu nevrátila původní fakturu; opakujte smazání"}
          error -> error
        end
      end
    else
      :not_found -> {:error, "Původní faktura v ABRA chybí; smazání je zastaveno"}
      error -> error
    end
  end

  defp unconfirmed_reason(remote, response) do
    reason = if response.messages == "", do: "ABRA neuvedla důvod", else: response.messages

    "ABRA nepotvrdila storno: po akci storno (HTTP #{response.http_status}) " <>
      "vrátila storno=#{inspect(remote["storno"])}; " <>
      "stav zámku=#{inspect(remote["zamekK"])}. #{reason}. " <>
      "Místní faktura nebyla smazána; zkontrolujte doklad v ABRA a poté opakujte smazání."
  end

  defp unpaid_original(remote, export, doc) do
    cond do
      is_nil(remote["id"]) or remote["kod"] != doc.number or
        remote["varSym"] != doc.variable_symbol or
          (export.remote_id && to_string(remote["id"]) != export.remote_id) ->
        {:error, "Nelze ověřit identitu původní faktury v ABRA"}

      not BankVerification.equal?(remote["juhSum"], Decimal.new(0)) ->
        {:error, "Faktura v ABRA má úhradu nebo ji nelze ověřit; nelze ji smazat"}

      remote["storno"] not in [true, false, "true", "false"] ->
        {:error, "Nelze ověřit stav storna v ABRA"}

      true ->
        :ok
    end
  end
end

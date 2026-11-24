defmodule CozyCheckout.Abra.InvoiceCancellation do
  @moduledoc "Verified, retryable cancellation using the original ABRA identity."
  alias CozyCheckout.Abra.{Client, BankVerification}

  def cancel(export, doc, cfg) do
    with {:ok, remote} <- Client.read_invoice(export.external_id, cfg),
         :ok <- unpaid_original(remote, export, doc) do
      if remote["storno"] in [true, "true"] do
        :ok
      else
        payload = %{
          "winstrom" => %{
            "faktura-vydana" => [
              %{
                "id" => export.external_id,
                "@update" => "ok",
                "@create" => "fail",
                "storno" => true
              }
            ]
          }
        }

        with {:ok, _} <- Client.create_invoice(payload, cfg),
             {:ok, confirmed} <- Client.read_invoice(export.external_id, cfg),
             :ok <- unpaid_original(confirmed, export, doc) do
          if confirmed["storno"] in [true, "true"],
            do: :ok,
            else: {:error, "ABRA nepotvrdila storno; opakujte smazání"}
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

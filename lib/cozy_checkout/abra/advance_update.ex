defmodule CozyCheckout.Abra.AdvanceUpdate do
  @moduledoc "Explicit replacement of an unpaid advance request under its existing identity."
  alias CozyCheckout.Abra.{BankVerification, Client}

  def deliver(export, cfg) do
    [invoice] = export.payload["winstrom"]["faktura-vydana"]

    case Client.advance_invoice_snapshot(export.external_id, cfg) do
      {:ok, snapshot} ->
        with :ok <- editable(export, invoice, snapshot.invoice) do
          if matches?(invoice, snapshot),
            do: {:ok, to_string(snapshot.invoice["id"])},
            else: write_and_verify(export, invoice, cfg)
        end

      :not_found when is_nil(export.remote_id) ->
        # The original creation may have failed before the invoice reached ABRA.
        write_and_verify(export, invoice, cfg)

      :not_found ->
        {:error, "Původní zálohová výzva v ABRA chybí; aktualizace ji znovu nezakládá"}

      error ->
        error
    end
  end

  defp write_and_verify(export, invoice, cfg) do
    with {:ok, _} <- Client.create_invoice(export.payload, cfg),
         {:ok, snapshot} <- Client.advance_invoice_snapshot(export.external_id, cfg),
         :ok <- editable(export, invoice, snapshot.invoice) do
      if matches?(invoice, snapshot),
        do: {:ok, to_string(snapshot.invoice["id"])},
        else: {:error, "ABRA nepotvrdila aktualizovaný rozpis zálohy; opakujte přenos"}
    else
      :not_found -> {:error, "ABRA po aktualizaci nevrátila zálohovou výzvu"}
      error -> error
    end
  end

  defp editable(export, expected, remote) do
    same_identity? =
      Enum.all?(~w(kod varSym typDokl mena bankovniUcet), &(expected[&1] == remote[&1])) and
        not is_nil(remote["id"]) and
        (is_nil(export.remote_id) or to_string(remote["id"]) == export.remote_id)

    cond do
      not same_identity? or remote["ucetni"] not in [false, "false"] ->
        {:error, "Doklad v ABRA není původní zálohová výzva; aktualizace je zastavena"}

      remote["storno"] not in [false, "false"] ->
        {:error, "Stornovanou zálohovou výzvu nelze aktualizovat"}

      not BankVerification.equal?(remote["juhSum"], Decimal.new(0)) ->
        {:error, "Zálohová výzva v ABRA již má úhradu; nelze ji aktualizovat"}

      true ->
        :ok
    end
  end

  defp matches?(invoice, snapshot) do
    remote = snapshot.invoice

    Enum.all?(~w(poznam popis), &(invoice[&1] == remote[&1])) and
      BankVerification.equal?(
        remote["sumCelkem"],
        Enum.reduce(invoice["polozkyFaktury"], Decimal.new(0), fn item, sum ->
          Decimal.add(sum, item["cenaMj"])
        end)
      ) and
      Enum.sort(Enum.map(invoice["polozkyFaktury"], &signature/1)) ==
        Enum.sort(Enum.map(snapshot.items, &signature/1))
  end

  defp signature(item) do
    {Enum.map(~w(nazev typCenyDphK typSzbDphK clenDph clenKonVykDph), &item[&1]),
     Enum.map(~w(mnozMj cenaMj), &BankVerification.amount(item[&1]))}
  end
end

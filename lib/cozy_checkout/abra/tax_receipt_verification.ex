defmodule CozyCheckout.Abra.TaxReceiptVerification do
  @moduledoc "Checks immutable ZDD values and reports field names without exposing customer data."
  alias CozyCheckout.Abra.BankVerification
  alias CozyCheckout.Billing.Money

  def check(invoice, remote) do
    exact =
      ~w(kod varSym typDokl mena bankovniUcet clenDph clenKonVykDph typUcOp primUcet protiUcet dphSnizUcet dphZaklUcet)

    totals =
      ~w(sumOsv sumZklSniz sumDphSniz sumZklSniz2 sumDphSniz2 sumZklZakl sumDphZakl szbDphSniz szbDphZakl)

    dates = ~w(datVyst datSplat duzpPuv datUcto)
    # Older saved payloads used the nonexistent `email` property. Do not rewrite
    # issued documents or require ABRA to echo that unsupported property.
    buyer =
      Enum.filter(
        ~w(nazFirmy ulice mesto psc ic dic kontaktEmail stat),
        &Map.has_key?(invoice, &1)
      )

    expected_total =
      Money.sum(
        Enum.map(
          ~w(sumOsv sumZklSniz sumDphSniz sumZklZakl sumDphZakl),
          &Decimal.new(invoice[&1])
        )
      )

    differences =
      Enum.reject(exact ++ buyer, &(remote[&1] == invoice[&1])) ++
        Enum.reject(totals, &BankVerification.equal?(remote[&1], Decimal.new(invoice[&1]))) ++
        Enum.reject(
          dates,
          &(is_binary(remote[&1]) and String.slice(remote[&1], 0, 10) == invoice[&1])
        ) ++
        Enum.reject(~w(ucetni bezPolozek), &(remote[&1] in [true, "true"])) ++
        if(remote["storno"] in [false, "false"], do: [], else: ["storno"]) ++
        if(BankVerification.equal?(remote["sumCelkem"], expected_total),
          do: [],
          else: ["sumCelkem"]
        ) ++
        if valid_id?(remote["id"]), do: [], else: ["id"]

    if differences == [],
      do: :ok,
      else:
        {:error,
         "ZDD v ABRA neodpovídá místnímu snapshotu; liší se pole: #{Enum.join(differences, ", ")}. Nic se nepřepisuje"}
  end

  defp valid_id?(id), do: (is_integer(id) and id > 0) or (is_binary(id) and id != "")
end

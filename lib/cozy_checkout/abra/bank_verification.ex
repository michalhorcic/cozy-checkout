defmodule CozyCheckout.Abra.BankVerification do
  @moduledoc "Conservative checks of fresh bank data and accounting links. Unknown relationships block writes."

  @payment_types ~w(typVazbyDokl.uhrada typVazbyDokl.uhradaZALOHY)

  def fingerprint(bank) do
    id = if is_integer(bank["id"]) or is_binary(bank["id"]), do: to_string(bank["id"])
    date = if is_binary(bank["datVyst"]), do: String.slice(bank["datVyst"], 0, 10)

    {id, bank["banka"], bank["mena"], bank["typPohybuK"], amount(bank["sumCelkem"]), date,
     bank["varSym"],
     case bank["storno"] do
       value when value in [false, "false"] -> false
       value when value in [true, "true"] -> true
       _ -> :unknown
     end}
  end

  def check(snapshot, expected, source_id, receipt_id \\ nil)

  def check(%{bank: bank, links: links, amounts: amounts}, expected, source_id, receipt_id)
      when is_map(bank) and is_list(links) and is_list(amounts) do
    cond do
      fingerprint(bank) != fingerprint(expected) ->
        {:error, "Bankovní pohyb se změnil; obnovte návrh"}

      bank["mena"] != "code:CZK" or bank["typPohybuK"] != "typPohybu.prijem" ->
        {:error, "Potvrdit lze pouze příjem v CZK"}

      bank["storno"] not in [false, "false"] ->
        {:error, "Pohyb je stornovaný nebo nelze ověřit storno"}

      not is_struct(amount(bank["sumCelkem"]), Decimal) ->
        {:error, "Neplatná částka pohybu"}

      not Decimal.positive?(amount(bank["sumCelkem"])) ->
        {:error, "Neplatná částka příjmu"}

      true ->
        check_links(bank, links, amounts, source_id, receipt_id)
    end
  end

  def check(_, _, _, _), do: {:error, "ABRA nevrátila platný pohyb a úplné vazby"}

  defp check_links(bank, links, amounts, source_id, receipt_id) do
    with {:ok, links} <- active(links), {:ok, amounts} <- active(amounts) do
      expected_amount = amount(bank["sumCelkem"])

      checks =
        Enum.map(links, fn link ->
          target = to_string(link["idDokl"])
          binding = Enum.find(amounts, &(to_string(&1["id"]) == to_string(link["idVazby"])))
          direct? = to_string(link["uroven"]) == "1" and link["modulK"] == "modulUcetni.FAV"

          cond do
            direct? and target == to_string(source_id) and link["typVazbyK"] in @payment_types and
              not is_nil(binding) and binding["typVazbyK"] == link["typVazbyK"] and
                equal?(binding["castka"], expected_amount) ->
              :source

            direct? and not is_nil(receipt_id) and target == to_string(receipt_id) and
              link["typVazbyK"] == "typVazbyDokl.vazbaZDD" and not is_nil(binding) and
                binding["typVazbyK"] == "typVazbyDokl.vazbaZDD" ->
              :receipt

            true ->
              :conflict
          end
        end)

      complete? =
        Enum.all?(amounts, fn binding ->
          Enum.any?(links, &(to_string(&1["idVazby"]) == to_string(binding["id"])))
        end)

      cond do
        :conflict in checks or not complete? or Enum.count(checks, &(&1 == :source)) > 1 or
            Enum.count(checks, &(&1 == :receipt)) > 1 ->
          {:error, "Pohyb má částečné, konfliktní nebo neznámé vazby; vyřešte je ručně"}

        :source not in checks and bank["sparovano"] not in [false, "false"] ->
          {:error, "Volnou částku bankovního pohybu nelze ověřit"}

        true ->
          {:ok, %{source_paired?: :source in checks, receipt_linked?: :receipt in checks}}
      end
    end
  end

  defp active(rows) do
    if Enum.all?(rows, &(is_map(&1) and &1["storno"] in [true, false, "true", "false"])) do
      {:ok, Enum.filter(rows, &(&1["storno"] in [false, "false"]))}
    else
      {:error, "ABRA nevrátila ověřitelný stav vazeb"}
    end
  end

  def amount(value) when is_binary(value) or is_integer(value) or is_float(value) do
    case Decimal.parse(to_string(value)) do
      {number, ""} ->
        if Decimal.nan?(number) or Decimal.inf?(number), do: nil, else: Decimal.normalize(number)

      _ ->
        nil
    end
  end

  def amount(_), do: nil

  def equal?(left, %Decimal{} = right) do
    case amount(left) do
      %Decimal{} = left -> Decimal.equal?(left, right)
      _ -> false
    end
  end

  def equal?(_, _), do: false
end

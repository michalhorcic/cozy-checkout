defmodule CozyCheckout.IncomingDocuments.Accounting do
  @moduledoc "Explicit per-document accounting selection from the connected ABRA company."
  @accounts ~w(protiUcet dphZaklUcet dphSnizUcet dphSniz2Ucet)
  def accounts, do: @accounts

  def applicable?(row, agenda) do
    field =
      case agenda do
        "faktura-prijata" -> "modulFap"
        "pokladni-pohyb" -> "modulPokV"
        "zavazek" -> "modulZav"
      end

    row[field] in [true, "true"]
  end

  def select(row, agenda, internal_code) do
    with true <- applicable?(row, agenda),
         code when is_binary(code) and code != "" <- row["kod"],
         {:ok, internal_code} <- internal_code(internal_code),
         {:ok, accounts} <- accounts(row) do
      {:ok,
       Map.merge(accounts, %{
         "typUcOp" => "code:" <> code,
         "kod" => internal_code,
         "preset_name" => row["nazev"] || code
       })}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Předpis není určený pro zvolenou agendu"}
    end
  end

  def internal_code(value) when is_binary(value) do
    code = value |> String.trim() |> String.upcase()

    if String.length(code) <= 20 and not Regex.match?(~r/[\x00-\x1f]/, code),
      do: {:ok, code},
      else: {:error, "Interní číslo může mít nejvýše 20 znaků, bez řídicích znaků"}
  end

  def internal_code(_), do: {:error, "Neplatné interní číslo"}

  defp accounts(row) do
    Enum.reduce_while(
      [{"protiUcetVydej", "protiUcet"} | Enum.map(tl(@accounts), &{&1, &1})],
      {:ok, %{}},
      fn {from, to}, {:ok, result} ->
        value = row[from]

        cond do
          value in [nil, ""] ->
            {:cont, {:ok, result}}

          is_binary(value) and Regex.match?(~r/^code:[0-9]{1,6}$/, value) ->
            {:cont, {:ok, Map.put(result, to, value)}}

          true ->
            {:halt, {:error, "ABRA nevrátila jednoznačný kód účtu #{from}; výběr nebyl uložen"}}
        end
      end
    )
  end
end

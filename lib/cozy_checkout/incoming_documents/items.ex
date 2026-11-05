defmodule CozyCheckout.IncomingDocuments.Items do
  @moduledoc "Decimal checks for non-stock items, discounts and receipt VAT summaries."

  @groups %{
    "typSzbDph.dphOsv" => {nil, "sumOsv", nil},
    "typSzbDph.dphSniz" => {"szbDphSniz", "sumZklSniz", "sumDphSniz"},
    "typSzbDph.dphZakl" => {"szbDphZakl", "sumZklZakl", "sumDphZakl"}
  }
  @totals ~w(sumOsv sumZklSniz sumZklSniz2 sumZklZakl sumDphSniz sumDphSniz2 sumDphZakl sumCelkem)

  def validate(%{"polozkyDokladu" => [_ | _] = rows} = fields) do
    with {:ok, calculated} <- calculate_rows(rows, fields),
         :ok <- compare_summary(calculated, fields) do
      {:ok, Map.put(fields, "polozkyDokladu", calculated)}
    end
  end

  def validate(fields), do: {:ok, fields}

  defp calculate_rows(rows, fields) do
    Enum.reduce_while(Enum.with_index(rows, 1), {:ok, []}, fn {row, index}, {:ok, acc} ->
      case calculate(row, fields) do
        {:ok, calculated} -> {:cont, {:ok, [calculated | acc]}}
        {:error, reason} -> {:halt, {:error, "Položka #{index} (#{row["nazev"]}): #{reason}"}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp calculate(row, fields) do
    with :ok <- required(row),
         {:ok, quantity} <- number(row["mnozMj"], "mnozMj", 6),
         {:ok, unit} <- number(row["cenaMj"], "cenaMj", 6),
         {:ok, discount} <- number(Map.get(row, "slevaPol", "0"), "slevaPol", 6),
         true <- not Decimal.equal?(quantity, 0),
         true <- Decimal.compare(discount, 0) != :lt and Decimal.compare(discount, 100) != :gt do
      {rate_field, _, _} = @groups[row["typSzbDphK"]]
      rate = if rate_field, do: Decimal.new(fields[rate_field]), else: Decimal.new(0)

      price =
        unit
        |> Decimal.mult(quantity)
        |> Decimal.mult(Decimal.sub(1, Decimal.div(discount, 100)))
        |> Decimal.round(2)

      {net, vat, gross} =
        if row["typCenyDphK"] == "typCeny.sDph" do
          net = price |> Decimal.div(Decimal.add(1, Decimal.div(rate, 100))) |> Decimal.round(2)
          {net, Decimal.sub(price, net), price}
        else
          vat = price |> Decimal.mult(rate) |> Decimal.div(100) |> Decimal.round(2)
          {price, vat, Decimal.add(price, vat)}
        end

      sums = %{
        "sumZkl" => Decimal.to_string(net),
        "sumDph" => Decimal.to_string(vat),
        "sumCelkem" => Decimal.to_string(gross)
      }

      with :ok <- compare_supplied(row, sums),
           :ok <- compare_rate(row["szbDph"], rate) do
        {:ok,
         row
         |> Map.put("slevaPol", Decimal.to_string(discount))
         |> Map.merge(sums)
         |> Map.put("szbDph", Decimal.to_string(rate))
         |> Map.put("typPolozkyK", "typPolozky.obecny")}
      end
    else
      false -> {:error, "mnozMj nesmí být nula a slevaPol musí být v rozmezí 0–100 %"}
      error -> error
    end
  end

  defp required(row) do
    cond do
      row["nazev"] in [nil, ""] ->
        {:error, "chybí nazev"}

      row["nazev"] == "NÁZEV Z ORIGINÁLU" ->
        {:error, "ukázková položka vzoru nebyla nahrazena skutečnou položkou originálu"}

      not Map.has_key?(@groups, row["typSzbDphK"]) ->
        {:error, "typSzbDphK musí označovat osvobození, sníženou nebo základní sazbu ze vzoru"}

      row["typCenyDphK"] not in ["typCeny.sDph", "typCeny.bezDph"] ->
        {:error, "typCenyDphK musí být typCeny.sDph nebo typCeny.bezDph"}

      row["typPolozkyK"] not in [nil, "typPolozky.obecny"] ->
        {:error, "povoleny jsou jen obecné neskladové položky (typPolozky.obecny)"}

      true ->
        :ok
    end
  end

  defp number(value, key, precision) do
    if is_binary(value) and
         Regex.match?(Regex.compile!("^-?\\d{1,12}(\\.\\d{1,#{precision}})?$"), value),
       do: {:ok, Decimal.new(value)},
       else: {:error, "neplatné #{key}=#{inspect(value)}"}
  end

  defp compare_supplied(row, sums) do
    Enum.reduce_while(sums, :ok, fn {key, expected}, :ok ->
      if Map.has_key?(row, key) do
        case number(row[key], key, 2) do
          {:ok, amount} ->
            if Decimal.equal?(amount, Decimal.new(expected)),
              do: {:cont, :ok},
              else:
                {:halt,
                 {:error,
                  "#{key}=#{row[key]}, z ceny, množství, slevy a sazby vychází #{expected}"}}

          error ->
            {:halt, error}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  defp compare_rate(nil, _), do: :ok

  defp compare_rate(value, expected) do
    with {:ok, rate} <- number(value, "szbDph", 6),
         true <- Decimal.equal?(rate, expected) do
      :ok
    else
      _ -> {:error, "szbDph=#{value} neodpovídá zvolené sazbě #{expected}"}
    end
  end

  defp compare_summary(rows, fields) do
    initial = Map.new(@totals, &{&1, Decimal.new(0)})

    totals =
      Enum.reduce(rows, initial, fn row, sums ->
        {_, net_field, vat_field} = @groups[row["typSzbDphK"]]

        sums =
          sums
          |> Map.update!(net_field, &Decimal.add(&1, Decimal.new(row["sumZkl"])))
          |> Map.update!("sumCelkem", &Decimal.add(&1, Decimal.new(row["sumCelkem"])))

        if vat_field,
          do: Map.update!(sums, vat_field, &Decimal.add(&1, Decimal.new(row["sumDph"]))),
          else: sums
      end)

    differences =
      for key <- @totals,
          not Decimal.equal?(totals[key], Decimal.new(fields[key])),
          do: "#{key}: na dokladu #{fields[key]}, z položek #{totals[key]}"

    if differences == [],
      do: :ok,
      else:
        {:error,
         "Součet položek nesouhlasí s rekapitulací DPH — " <>
           Enum.join(differences, "; ") <> ". Rozdíly zaokrouhlení automaticky nerozdělujeme."}
  end
end

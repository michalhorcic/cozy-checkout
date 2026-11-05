defmodule CozyCheckout.IncomingDocuments.FormSuggestions do
  @moduledoc "Deterministic VAT and date suggestions; no accounting decisions or model calls."
  alias CozyCheckout.IncomingDocuments.Transcription

  @groups %{
    "0" => ~w(sumOsv),
    "12" => ~w(sumZklSniz sumDphSniz),
    "21" => ~w(sumZklZakl sumDphZakl)
  }

  def from(data) do
    case Transcription.validate(data) do
      :ok ->
        data = Transcription.canonicalize(data)
        {vat, messages} = vat(data["vat_summary"])

        source_dates = %{
          "datVyst" => date(data["issue_date"]),
          "duzpPuv" => date(data["tax_date"]),
          "datSplat" => date(data["due_date"])
        }

        %{vat: vat, dates: dates(source_dates), messages: messages}

      _ ->
        %{vat: %{}, dates: %{}, messages: []}
    end
  end

  def dates(values) do
    values = Map.new(~w(datVyst duzpPuv datSplat duzpUcto datUcto), &{&1, date(values[&1])})
    issue = values["datVyst"] || values["duzpPuv"]
    tax = values["duzpPuv"] || issue
    claim = if issue && tax, do: Enum.max([issue, tax]), else: issue || tax

    Map.merge(values, %{
      "datVyst" => issue,
      "duzpPuv" => tax,
      "datSplat" => values["datSplat"] || issue,
      "datUcto" => values["datUcto"] || issue,
      "duzpUcto" => values["duzpUcto"] || claim
    })
    |> Map.reject(fn {_, value} -> is_nil(value) end)
  end

  defp date(value) when is_binary(value) do
    value = String.trim(value)

    iso =
      case Regex.run(~r/^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$/, value) do
        [_, day, month, year] ->
          year <>
            "-" <> String.pad_leading(month, 2, "0") <> "-" <> String.pad_leading(day, 2, "0")

        _ ->
          value
      end

    case Date.from_iso8601(iso) do
      {:ok, parsed} -> Date.to_iso8601(parsed)
      _ -> nil
    end
  end

  defp date(_), do: nil

  defp vat(rows) do
    rows
    |> Enum.group_by(&rate(&1["rate"]))
    |> Enum.reduce({%{}, []}, fn {rate, rows}, {fields, messages} ->
      if Map.has_key?(@groups, rate) do
        case sum(rows, rate) do
          {:ok, net, vat} ->
            amounts =
              [net, vat] |> Enum.map(&(Decimal.round(&1, 2) |> Decimal.to_string(:normal)))

            {Map.merge(fields, Map.new(Enum.zip(@groups[rate], amounts))), messages}

          :error ->
            {fields,
             messages ++
               [
                 "Rekapitulace DPH #{rate} % je neúplná nebo nesouhlasí; tuto sazbu doplňte ručně."
               ]}
        end
      else
        {fields,
         messages ++
           ["Sazbu #{inspect(hd(rows)["rate"])} nelze automaticky přiřadit do formuláře."]}
      end
    end)
  end

  defp sum(rows, rate) do
    Enum.reduce_while(rows, {:ok, Decimal.new(0), Decimal.new(0)}, fn row, {:ok, net, vat} ->
      case amounts(row, rate) do
        {:ok, n, v} -> {:cont, {:ok, Decimal.add(net, n), Decimal.add(vat, v)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp amounts(row, rate) do
    net = money(row["net"])
    vat = if rate == "0" and row["vat"] in [nil, ""], do: Decimal.new(0), else: money(row["vat"])
    gross = money(row["gross"])

    {net, vat} =
      cond do
        is_struct(net, Decimal) and is_struct(vat, Decimal) ->
          {net, vat}

        is_nil(row["net"]) and is_struct(gross, Decimal) and is_struct(vat, Decimal) ->
          {Decimal.sub(gross, vat), vat}

        is_nil(row["vat"]) and is_struct(gross, Decimal) and is_struct(net, Decimal) ->
          {net, Decimal.sub(gross, net)}

        true ->
          {nil, nil}
      end

    if is_struct(net, Decimal) and is_struct(vat, Decimal) and
         (rate != "0" or Decimal.equal?(vat, 0)) and
         (is_nil(row["gross"]) or
            (is_struct(gross, Decimal) and Decimal.equal?(Decimal.add(net, vat), gross))),
       do: {:ok, net, vat},
       else: :error
  end

  defp money(value) when is_binary(value) do
    if Regex.match?(~r/^-?\d{1,12}(\.\d{1,2})?$/, value), do: Decimal.new(value)
  end

  defp money(_), do: nil

  defp rate(value) when is_binary(value) do
    value =
      value
      |> String.trim()
      |> String.replace(~r/\s*%$/, "")
      |> String.trim()
      |> String.replace(",", ".")

    if Regex.match?(~r/^\d{1,2}(\.0+)?$/, value),
      do: value |> Decimal.new() |> Decimal.normalize() |> Decimal.to_string(:normal),
      else: nil
  end

  defp rate(_), do: nil
end

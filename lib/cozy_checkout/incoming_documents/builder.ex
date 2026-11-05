defmodule CozyCheckout.IncomingDocuments.Builder do
  @moduledoc "Maps source facts to the stored accounting template; the model never selects ABRA fields."
  alias CozyCheckout.IncomingDocuments.{Transcription, XML}

  @header %{
    "document_number" => "cisDosle",
    "variable_symbol" => "varSym",
    "issue_date" => "datVyst",
    "tax_date" => "duzpPuv",
    "due_date" => "datSplat",
    "total" => "sumCelkem"
  }
  @supplier %{
    "name" => "nazFirmy",
    "ic" => "ic",
    "dic" => "dic",
    "street" => "ulice",
    "city" => "mesto",
    "postal_code" => "psc"
  }
  @groups %{
    "0" => {"sumOsv", nil, "typSzbDph.dphOsv"},
    "12" => {"sumZklSniz", "sumDphSniz", "typSzbDph.dphSniz"},
    "21" => {"sumZklZakl", "sumDphZakl", "typSzbDph.dphZakl"}
  }

  def build(data, doc) do
    with :ok <- Transcription.validate(data),
         :ok <- currency(data["currency"]),
         :ok <- number_label(data["document_number_label"]),
         {:ok, defaults} <- XML.parse(doc.template_xml, doc.agenda),
         {:ok, fields} <- summary(defaults, data["vat_summary"]),
         {:ok, rows} <- rows(data["items"], data["vat_legend"]) do
      fields =
        Enum.reduce(@header, fields, fn {from, to}, acc -> Map.put(acc, to, data[from] || "") end)

      fields =
        Enum.reduce(@supplier, fields, fn {from, to}, acc ->
          Map.put(acc, to, data["supplier"][from] || "")
        end)

      fields =
        fields |> Map.put("cisDosle", document_number(data)) |> Map.put("polozkyDokladu", rows)

      xml = XML.render(fields, doc.agenda, doc.external_id)

      cond do
        data["complete"] != true ->
          {:error, "Přepis originálu není úplný: " <> Enum.join(data["uncertainties"], "; "), xml}

        data["uncertainties"] != [] ->
          {:error, "Přepis vyžaduje kontrolu: " <> Enum.join(data["uncertainties"], "; "), xml}

        true ->
          {:ok, xml}
      end
    else
      {:error, reason} -> {:error, reason, nil}
    end
  end

  defp currency("CZK"), do: :ok
  defp currency(_), do: {:error, "Měna z originálu není potvrzená jako CZK"}
  defp number_label(nil), do: :ok

  defp number_label(label) do
    if Regex.match?(~r/kart|termin[aá]l|autoriz|transakc/i, label),
      do: {:error, "Číslo dokladu bylo převzato z platební nebo věrnostní části (#{label})"},
      else: :ok
  end

  defp document_number(data) do
    number = data["document_number"] || ""
    label = data["document_number_label"]

    if is_binary(label) and String.trim(label) != "" do
      Regex.replace(
        Regex.compile!("^\\s*" <> Regex.escape(String.trim(label)) <> "[:\\s]*", "iu"),
        number,
        ""
      )
    else
      number
    end
  end

  defp rate(value) when is_binary(value) do
    if Regex.match?(~r/^\d{1,2}(\.0{1,6})?$/, value) do
      key = value |> Decimal.new() |> Decimal.normalize() |> Decimal.to_string(:normal)

      if Map.has_key?(@groups, key),
        do: {:ok, key},
        else: {:error, "Nepodporovaná sazba #{value}"}
    else
      {:error, "Nečitelná sazba DPH #{inspect(value)}"}
    end
  end

  defp rate(_), do: {:error, "Chybí sazba DPH z originálu"}

  defp summary(_defaults, []) do
    {:error, "Chybí rekapitulace DPH z originálu"}
  end

  defp summary(defaults, summaries) do
    defaults =
      Enum.reduce(Enum.filter(XML.editable(), &XML.amount?/1), defaults, &Map.put(&2, &1, "0.00"))

    Enum.reduce_while(summaries, {:ok, defaults, []}, fn row, {:ok, fields, seen} ->
      with {:ok, key} <- rate(row["rate"]),
           false <- key in seen,
           :ok <- summary_gross(row, key) do
        {net_key, vat_key, _} = @groups[key]
        fields = Map.put(fields, net_key, row["net"] || if(key == "0", do: row["gross"]) || "")
        fields = if vat_key, do: Map.put(fields, vat_key, row["vat"] || ""), else: fields
        {:cont, {:ok, fields, [key | seen]}}
      else
        true -> {:halt, {:error, "Duplicitní sazba v rekapitulaci DPH"}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, fields, _} -> {:ok, fields}
      error -> error
    end
  end

  defp summary_gross(row, key) do
    values =
      if key == "0",
        do: [row["net"] || row["gross"], row["vat"] || "0.00"],
        else: [row["net"], row["vat"]]

    with {:ok, net} <- money(Enum.at(values, 0)),
         {:ok, vat} <- money(Enum.at(values, 1)),
         true <- key != "0" or Decimal.equal?(vat, 0) do
      if is_nil(row["gross"]) do
        :ok
      else
        with {:ok, gross} <- money(row["gross"]),
             true <- Decimal.equal?(gross, Decimal.add(net, vat)),
             do: :ok,
             else: (_ ->
                      {:error,
                       "Rekapitulace DPH #{key} %: základ a daň nesouhlasí s částkou včetně DPH"})
      end
    else
      _ -> {:error, "Rekapitulace DPH #{key} % nemá čitelné a konzistentní částky"}
    end
  end

  defp money(value) when is_binary(value) do
    if Regex.match?(~r/^-?\d{1,12}(\.\d{1,2})?$/, value),
      do: {:ok, Decimal.new(value)},
      else: {:error, "Neplatná částka"}
  end

  defp money(_), do: {:error, "Chybí částka"}

  defp rows([], _legend), do: {:error, "Chybí jednotlivé položky originálu"}

  defp rows(items, legend) do
    Enum.reduce_while(Enum.with_index(items, 1), {:ok, []}, fn {row, index}, {:ok, acc} ->
      case row(row, legend) do
        {:ok, mapped} -> {:cont, {:ok, [mapped | acc]}}
        {:error, reason} -> {:halt, {:error, "Položka #{index}: #{reason}"}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp row(source, legend) do
    with {:ok, key} <- item_rate(source, legend) do
      {_, _, vat_type} = @groups[key]

      row = %{
        "nazev" => source["name"] || "",
        "mnozMj" => source["quantity"] || "",
        "cenaMj" => source["unit_price"] || "",
        "slevaPol" => source["discount_percent"] || "0",
        "typSzbDphK" => vat_type,
        "typCenyDphK" =>
          case source["price_includes_vat"] do
            true -> "typCeny.sDph"
            false -> "typCeny.bezDph"
            _ -> ""
          end
      }

      row =
        if source["line_total"], do: Map.put(row, "sumCelkem", source["line_total"]), else: row

      {:ok, row}
    end
  end

  defp item_rate(source, legend) do
    matches =
      Enum.filter(
        legend,
        &(&1["marker"] == source["vat_marker"] and source["vat_marker"] not in [nil, ""])
      )

    case matches do
      [entry] ->
        with {:ok, key} <- rate(entry["rate"]),
             true <- is_nil(source["vat_rate"]) or match?({:ok, ^key}, rate(source["vat_rate"])) do
          {:ok, key}
        else
          _ ->
            {:error, "Sazba položky nesouhlasí se značkou #{source["vat_marker"]} a legendou DPH"}
        end

      [] ->
        if source["vat_marker"] in [nil, ""],
          do: rate(source["vat_rate"]),
          else: {:error, "Značka #{source["vat_marker"]} nemá jednoznačnou legendu DPH"}

      _ ->
        {:error, "Duplicitní značka v legendě DPH"}
    end
  end
end

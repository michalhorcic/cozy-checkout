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
    case draft(data, doc) do
      {:ok, raw} ->
        case compose(data, doc, true) do
          {:ok, xml} ->
            case coverage_issues(Transcription.canonicalize(data)) do
              [] -> {:ok, xml}
              issues -> {:error, Enum.map_join(issues, "; ", & &1.message), raw}
            end

          {:error, reason, _} ->
            issues = coverage_issues(Transcription.canonicalize(data))

            prefix =
              if issues == [], do: "", else: Enum.map_join(issues, "; ", & &1.message) <> " "

            {:error, prefix <> reason, raw}
        end

      {:error, reason} ->
        {:error, reason, nil}
    end
  end

  @doc "Well-formed diagnostic XML even when the source amounts need correction. Never authorizes import."
  def draft(data, doc) do
    case compose(data, doc, false) do
      {:ok, xml} -> {:ok, xml}
      {:error, reason, _} -> {:error, reason}
    end
  end

  defp compose(data, doc, strict) do
    with :ok <- Transcription.validate(data),
         data = Transcription.canonicalize(data),
         :ok <- if(strict, do: currency(data["currency"]), else: :ok),
         :ok <- if(strict, do: number_label(data["document_number_label"]), else: :ok),
         {:ok, defaults} <- XML.parse(XML.template_for(doc), doc.agenda),
         {:ok, fields} <- summary(defaults, data["vat_summary"], strict),
         {:ok, rows} <- rows(data["items"], data["vat_legend"], strict) do
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
        strict and data["complete"] != true ->
          {:error, "Přepis originálu není úplný: " <> Enum.join(data["uncertainties"], "; "), xml}

        strict and data["uncertainties"] != [] ->
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

  defp summary(_defaults, [], true) do
    {:error, "Chybí rekapitulace DPH z originálu"}
  end

  defp summary(defaults, summaries, strict) do
    defaults =
      Enum.reduce(Enum.filter(XML.editable(), &XML.amount?/1), defaults, &Map.put(&2, &1, "0.00"))

    Enum.reduce_while(Enum.with_index(summaries), {:ok, defaults, []}, fn {row, index},
                                                                          {:ok, fields, seen} ->
      with {:ok, key} <- rate(row["rate"]),
           false <- key in seen,
           :ok <- if(strict, do: summary_gross(row, key, index), else: :ok) do
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

  @doc "Source coverage is independent of JSON's complete flag and of the VAT summary."
  def source_issues(data) do
    case Transcription.validate(data) do
      :ok ->
        canonical = Transcription.canonicalize(data)
        summary_issues(data) ++ coverage_issues(canonical) ++ item_source_issues(canonical)

      _ ->
        []
    end
  end

  defp coverage_issues(data) do
    totals = Enum.map(data["items"], &money(&1["line_total"]))

    with {:ok, total} <- money(data["total"]),
         true <- Enum.all?(totals, &match?({:ok, _}, &1)),
         false <- Enum.any?(data["items"], &(&1["price_includes_vat"] == false)) do
      sum =
        Enum.reduce(totals, Decimal.new(0), fn {:ok, amount}, acc -> Decimal.add(acc, amount) end)

      if Decimal.equal?(total, sum) do
        []
      else
        [
          %{
            path: "items",
            message:
              "Položky pokrývají #{sum} Kč z celku #{total} Kč (total / sumCelkem); rozdíl #{Decimal.sub(total, sum)} Kč. Rekapitulace DPH není položka. Znovu zkontrolujte účtované služby a všechny strany originálu; chybějící položky nelze domyslet z rekapitulace."
          }
        ]
      end
    else
      _ -> []
    end
  end

  defp item_source_issues(data) do
    Enum.flat_map(Enum.with_index(data["items"]), fn {row, index} ->
      rate =
        case item_rate(row, data["vat_legend"]) do
          {:ok, _} ->
            []

          {:error, reason} ->
            [
              %{
                path: "items.#{index}.vat_rate",
                message: reason <> ". Neurčená sazba neznamená osvobození ani plnění bez DPH."
              }
            ]
        end

      price =
        if is_boolean(row["price_includes_vat"]),
          do: [],
          else: [
            %{
              path: "items.#{index}.price_includes_vat",
              message: "Není určeno, zda je jednotková cena s DPH nebo bez DPH"
            }
          ]

      rate ++ price
    end)
  end

  def summary_issues(data) do
    case Transcription.validate(data) do
      :ok ->
        data = Transcription.canonicalize(data)

        Enum.flat_map(Enum.with_index(data["vat_summary"]), fn {row, index} ->
          case rate(row["rate"]) do
            {:ok, key} -> vat_issues(row, key, index)
            {:error, reason} -> [%{path: "vat_summary.#{index}.rate", message: reason}]
          end
        end)

      _ ->
        []
    end
  end

  defp summary_gross(row, key, index) do
    case vat_issues(row, key, index) do
      [] -> :ok
      issues -> {:error, Enum.map_join(issues, "; ", &(&1.path <> ": " <> &1.message))}
    end
  end

  defp vat_issues(row, key, index) do
    net_value = row["net"] || if(key == "0", do: row["gross"])
    vat_value = row["vat"] || if(key == "0", do: "0")

    issues =
      for {field, value} <- [{"net", net_value}, {"vat", vat_value}],
          match?({:error, _}, money(value)),
          do: %{
            path: "vat_summary.#{index}.#{field}",
            message:
              "Rekapitulace DPH #{key} %: #{if field == "net", do: "základ", else: "DPH"} má nečitelnou nebo chybějící hodnotu #{inspect(value)}"
          }

    if issues != [] do
      issues
    else
      {:ok, net} = money(net_value)
      {:ok, vat} = money(vat_value)

      cond do
        key == "0" and not Decimal.equal?(vat, 0) ->
          [%{path: "vat_summary.#{index}.vat", message: "Sazba 0 % nemůže mít nenulovou DPH"}]

        is_nil(row["gross"]) ->
          []

        true ->
          case money(row["gross"]) do
            {:ok, gross} ->
              if Decimal.equal?(gross, Decimal.add(net, vat)),
                do: [],
                else: [
                  %{
                    path: "vat_summary.#{index}.gross",
                    message:
                      "Základ #{net} + DPH #{vat} = #{Decimal.add(net, vat)}, uvedeno s DPH #{gross}"
                  }
                ]

            _ ->
              [
                %{
                  path: "vat_summary.#{index}.gross",
                  message: "Nečitelná částka s DPH #{inspect(row["gross"])}"
                }
              ]
          end
      end
    end
  end

  defp money(value) when is_binary(value) do
    if Regex.match?(~r/^-?\d{1,12}(\.\d{1,2})?$/, value),
      do: {:ok, Decimal.new(value)},
      else: {:error, "Neplatná částka"}
  end

  defp money(_), do: {:error, "Chybí částka"}

  defp rows([], _legend, true), do: {:error, "Chybí jednotlivé položky originálu"}

  defp rows(items, legend, strict) do
    Enum.reduce_while(Enum.with_index(items, 1), {:ok, []}, fn {row, index}, {:ok, acc} ->
      case row(row, legend, strict) do
        {:ok, mapped} -> {:cont, {:ok, [mapped | acc]}}
        {:error, reason} -> {:halt, {:error, "Položka #{index}: #{reason}"}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp row(source, legend, strict) do
    case item_rate(source, legend) do
      {:ok, key} -> {:ok, map_row(source, elem(@groups[key], 2))}
      error when strict -> error
      _ -> {:ok, map_row(source, "")}
    end
  end

  defp map_row(source, vat_type) do
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

    row
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

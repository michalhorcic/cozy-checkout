defmodule CozyCheckout.IncomingDocuments.HeaderForm do
  @moduledoc "Reviewed, item-free ABRA headers. Extraction supplies suggestions, never accounting choices."
  alias CozyCheckout.IncomingDocuments.{FormSuggestions, Transcription, XML}

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
  @amounts ~w(sumOsv sumZklSniz sumDphSniz sumZklZakl sumDphZakl sumCelkem)

  def fields do
    [
      {"nazFirmy", "Dodavatel *", "text"},
      {"cisDosle", "Číslo původního dokladu *", "text"},
      {"ic", "IČO", "text"},
      {"dic", "DIČ", "text"},
      {"datVyst", "Datum vystavení *", "date"},
      {"duzpPuv", "DUZP (při odpočtu DPH) *", "date"},
      {"duzpUcto", "Datum uplatnění DPH (při odpočtu) *", "date"},
      {"datUcto", "Datum zaúčtování", "date"},
      {"varSym", "Variabilní symbol", "text"},
      {"datSplat", "Splatnost (faktura / závazek) *", "date"},
      {"sumOsv", "Osvobozeno / bez DPH (Kč)", "text"},
      {"sumZklSniz", "Základ 12 % (Kč)", "text"},
      {"sumDphSniz", "DPH 12 % (Kč)", "text"},
      {"sumZklZakl", "Základ 21 % (Kč)", "text"},
      {"sumDphZakl", "DPH 21 % (Kč)", "text"},
      {"sumCelkem", "Celkem včetně DPH (Kč) *", "text"},
      {"ulice", "Ulice", "text"},
      {"mesto", "Město", "text"},
      {"psc", "PSČ", "text"},
      {"buc", "Bankovní účet", "text"},
      {"iban", "IBAN", "text"},
      {"popis", "Popis dokladu", "text"}
    ]
  end

  def vat_groups do
    [{12, "sumZklSniz", "sumDphSniz"}, {21, "sumZklZakl", "sumDphZakl"}]
  end

  def vat_keys, do: Enum.flat_map(vat_groups(), fn {_, base, vat} -> [base, vat] end)

  @doc "Read-only totals from the current form values; nil marks an invalid amount."
  def vat_totals(values) do
    totals =
      Map.new(vat_groups(), fn {rate, base, vat} ->
        {rate, sum_amounts(values, [base, vat])}
      end)

    Map.put(totals, :combined, sum_amounts(values, vat_keys()))
  end

  defp sum_amounts(values, keys) do
    Enum.reduce_while(keys, Decimal.new("0.00"), fn key, total ->
      value = amount(Map.get(values, key) || "")

      if Regex.match?(~r/^-?\d{1,12}(\.\d{1,2})?$/, value),
        do: {:cont, Decimal.add(total, Decimal.new(value))},
        else: {:halt, nil}
    end)
  end

  def keys, do: Enum.map(fields(), &elem(&1, 0)) ++ ["poznam"]

  def defaults, do: Map.new(keys(), &{&1, ""})

  def values(doc) do
    cond do
      is_binary(doc.current_xml) ->
        case XML.parse(doc.current_xml, doc.agenda) do
          {:ok, fields} ->
            values = Map.merge(defaults(), Map.take(fields, keys()))

            notes =
              Enum.map_join(XML.items(fields), "\n", fn row ->
                Enum.map_join(~w(nazev mnozMj cenaMj sumCelkem), " | ", &(row[&1] || ""))
              end)

            if notes == "",
              do: values,
              else:
                Map.update!(
                  values,
                  "poznam",
                  &(&1 <> "\nOrientační přepis původních položek (bez zaúčtování):\n" <> notes)
                )

          _ ->
            defaults()
        end

      is_map(doc.edited_data) and is_map(doc.edited_data["header_form"]) ->
        Map.merge(defaults(), doc.edited_data["header_form"])

      doc.extracted_data != %{} ->
        suggestions(doc.extracted_data)

      true ->
        defaults()
    end
  end

  def suggestions(data) do
    data = Transcription.canonicalize(data)

    values =
      Enum.reduce(@header, defaults(), fn {source, target}, acc ->
        Map.put(acc, target, data[source] || "")
      end)

    values =
      Enum.reduce(@supplier, values, fn {source, target}, acc ->
        Map.put(acc, target, data["supplier"][source] || "")
      end)

    suggestions = FormSuggestions.from(data)

    values =
      values
      |> Map.merge(Map.new(~w(datVyst duzpPuv datSplat), &{&1, ""}))
      |> Map.merge(suggestions.vat)
      |> Map.merge(suggestions.dates)

    notes =
      Enum.map_join(data["items"], "\n", fn row ->
        row["raw_text"] ||
          Enum.join(
            Enum.reject(
              [row["name"], row["quantity"], row["unit_price"], row["line_total"]],
              &is_nil/1
            ),
            " | "
          )
      end)

    Map.put(
      values,
      "poznam",
      if(notes == "", do: "", else: "Orientační přepis položek (bez zaúčtování):\n" <> notes)
    )
  end

  def build(attrs, doc) do
    with true <-
           is_map(attrs) and
             Enum.all?(attrs, fn {key, value} ->
               key in keys() and is_binary(value) and byte_size(value) <= 30_000
             end),
         {:ok, template} <- XML.parse(XML.template_for(doc), doc.agenda),
         values = Map.merge(defaults(), attrs),
         values =
           Enum.reduce(@amounts, values, fn key, acc -> Map.update!(acc, key, &amount/1) end),
         :ok <- required_dates(values, doc.agenda),
         fields =
           template
           |> Map.merge(values)
           |> Map.put("bezPolozek", "true")
           |> Map.put("polozkyDokladu", []),
         xml = XML.render(fields, doc.agenda, doc.external_id),
         {:ok, xml} <- XML.normalize(xml, doc.agenda, XML.template_for(doc), doc.external_id) do
      {:ok, values, xml}
    else
      false -> {:error, "Neplatná pole formuláře"}
      error -> error
    end
  end

  defp amount(value) do
    trimmed = String.trim(value)
    grouped? = Regex.match?(~r/^-?\d{1,3}([ \x{00a0}\x{202f}]+\d{3})+([.,]\d{1,2})?$/u, trimmed)

    compact =
      if grouped?, do: String.replace(trimmed, ~r/[ \x{00a0}\x{202f}]/u, ""), else: trimmed

    if compact == "", do: "0.00", else: String.replace(compact, ",", ".")
  end

  defp required_dates(values, agenda) do
    vat? =
      Enum.any?(~w(sumDphSniz sumDphZakl), fn key ->
        case Decimal.parse(values[key]) do
          {amount, ""} -> not Decimal.equal?(amount, 0)
          _ -> true
        end
      end)

    cond do
      agenda in ["faktura-prijata", "zavazek"] and values["datSplat"] == "" ->
        {:error, "U přijaté faktury a závazku vyplňte splatnost"}

      vat? and (values["duzpPuv"] == "" or values["duzpUcto"] == "") ->
        {:error, "Při uplatnění DPH vyplňte DUZP i datum uplatnění DPH"}

      true ->
        :ok
    end
  end
end

defmodule CozyCheckout.IncomingDocuments.XML do
  @moduledoc "Restricted XML dialect for reviewed document headers and non-stock receipt items."

  @agendas ["faktura-prijata", "pokladni-pohyb", "zavazek"]
  @text ~w(cisDosle varSym datVyst duzpPuv duzpUcto datSplat datUcto popis poznam nazFirmy ic dic ulice mesto psc buc iban)
  @amounts ~w(sumOsv sumZklSniz sumZklSniz2 sumZklZakl sumDphSniz sumDphSniz2 sumDphZakl sumCelkem)
  @fixed ~w(kod typDokl mena stat statDph typUcOp primUcet protiUcet dphZaklUcet dphSnizUcet dphSniz2Ucet clenDph clenKonVykDph stredisko pokladna typPohybuK szbDphSniz szbDphSniz2 szbDphZakl bezPolozek ucetni)
  @item_fields ~w(nazev mnozMj cenaMj typCenyDphK typSzbDphK slevaPol sumZkl sumDph sumCelkem szbDph typPolozkyK)
  @item_editable ~w(nazev mnozMj cenaMj typCenyDphK typSzbDphK slevaPol)
  @rates ~w(szbDphSniz szbDphSniz2 szbDphZakl)
  @dates ~w(datVyst duzpPuv duzpUcto datSplat datUcto)
  @discard ~w(id kod lastUpdate createdDate createdBy updatedBy datUhr stavUhrK zuctovano)

  def agendas, do: @agendas
  def editable, do: @text ++ @amounts
  def fixed, do: @fixed
  def item_editable, do: @item_editable
  def items(fields), do: Map.get(fields, "polozkyDokladu", [])
  def amount?(key), do: key in @amounts
  def date?(key), do: key in @dates

  def template(agenda) when agenda in @agendas do
    :cozy_checkout |> Application.app_dir("priv/incoming_documents/#{agenda}.xml") |> File.read!()
  end

  @doc "Only explicit persisted accounting choices override the original template snapshot."
  def template_for(doc) do
    settings = Map.get(doc, :accounting_settings, %{})

    if settings == %{} do
      doc.template_xml
    else
      {:ok, fields} = parse(doc.template_xml, doc.agenda)

      fields =
        if settings["typUcOp"],
          do: Map.drop(fields, CozyCheckout.IncomingDocuments.Accounting.accounts()),
          else: fields

      fields =
        Map.merge(
          fields,
          Map.take(settings, [
            "typUcOp",
            "kod" | CozyCheckout.IncomingDocuments.Accounting.accounts()
          ])
        )

      fields = if fields["kod"] in [nil, ""], do: Map.delete(fields, "kod"), else: fields
      render(fields, doc.agenda)
    end
  end

  @doc "Parses without creating atoms from names; only one bounded item collection is allowed, without DTD or entities."
  def parse(xml, agenda) when is_binary(xml) and byte_size(xml) <= 250_000 do
    if String.valid?(xml) and
         (String.starts_with?(String.trim_leading(xml), "```") or
            String.ends_with?(String.trim_trailing(xml), "```")) do
      {:error,
       "Výstup obsahuje ohraničení Markdownu (```xml nebo ```), které není součástí XML. Odstraňte tyto řádky; obsah musí začínat <?xml a končit </winstrom>."}
    else
      parse_document(xml, agenda)
    end
  end

  def parse(_, _), do: invalid()

  defp parse_document(xml, agenda) do
    if agenda in @agendas and String.valid?(xml) and not String.contains?(xml, <<0>>) and
         not Regex.match?(~r/<!|<\?/u, strip_declaration(xml)) do
      state = %{
        stack: [],
        fields: %{},
        text: "",
        agenda: agenda,
        done: false,
        item: %{},
        items: [],
        collection: false
      }

      case :xmerl_sax_parser.stream(xml, event_fun: &event/3, event_state: state) do
        {:ok, %{stack: [], fields: fields, done: true}, rest} ->
          if String.trim(to_string(rest)) == "", do: {:ok, fields}, else: invalid()

        _ ->
          invalid()
      end
    else
      invalid()
    end
  catch
    _, _ -> invalid()
  end

  defp strip_declaration(xml),
    do: Regex.replace(~r/\A\s*<\?xml\s+[^?]*\?>/u, xml, "", global: false)

  defp event({:startElement, uri, name, _, attrs}, _, state) do
    key = to_string(name)
    if uri != [], do: throw(:invalid_xml)

    case state.stack do
      [] ->
        if key != "winstrom" or state.done, do: throw(:invalid_xml)
        check_attrs(attrs, ~w(version source))

      ["winstrom"] ->
        if key != state.agenda or state.done, do: throw(:invalid_xml)
        check_attrs(attrs, ~w(create update))

      [agenda, "winstrom"] when agenda == state.agenda ->
        if key not in (@text ++ @amounts ++ @fixed ++ @discard ++ ["polozkyDokladu"]) or
             Map.has_key?(state.fields, key),
           do: throw(:invalid_xml)

        check_attrs(attrs, [])

      ["polozkyDokladu", agenda, "winstrom"] when agenda == state.agenda ->
        if key != agenda <> "-polozka" or length(state.items) >= 202, do: throw(:invalid_xml)
        check_attrs(attrs, [])

      [row, "polozkyDokladu", agenda, "winstrom"] when agenda == state.agenda ->
        if row != agenda <> "-polozka" or key not in (@item_fields ++ @discard) or
             Map.has_key?(state.item, key),
           do: throw(:invalid_xml)

        check_attrs(attrs, [])

      _ ->
        throw(:invalid_xml)
    end

    if key == "polozkyDokladu" and state.collection, do: throw(:invalid_xml)

    %{
      state
      | stack: [key | state.stack],
        text: "",
        collection: state.collection or key == "polozkyDokladu"
    }
  end

  defp event({:endElement, _, name, _}, _, %{stack: [key | rest]} = state) do
    if to_string(name) != key, do: throw(:invalid_xml)

    state =
      cond do
        length(rest) == 4 ->
          %{state | item: Map.put(state.item, key, String.trim(state.text))}

        length(rest) == 3 ->
          %{state | items: [state.item | state.items], item: %{}}

        length(rest) == 2 and key == "polozkyDokladu" ->
          %{state | fields: Map.put(state.fields, key, Enum.reverse(state.items))}

        length(rest) == 2 ->
          %{state | fields: Map.put(state.fields, key, String.trim(state.text))}

        true ->
          state
      end

    %{state | stack: rest, text: "", done: state.done or key == state.agenda}
  end

  defp event({kind, chars}, _, state) when kind in [:characters, :ignorableWhitespace] do
    value = to_string(chars)
    if length(state.stack) not in [3, 5] and String.trim(value) != "", do: throw(:invalid_xml)

    if length(state.stack) == 3 and hd(state.stack) == "polozkyDokladu" and
         String.trim(value) != "",
       do: throw(:invalid_xml)

    %{state | text: state.text <> value}
  end

  defp event({:startDTD, _, _, _}, _, _), do: throw(:invalid_xml)
  defp event({:startPrefixMapping, _, _}, _, _), do: throw(:invalid_xml)
  defp event({:processingInstruction, _, _}, _, _), do: throw(:invalid_xml)
  defp event(_, _, state), do: state

  defp check_attrs(attrs, allowed) do
    Enum.each(attrs, fn {uri, prefix, name, _} ->
      if uri != [] or prefix != [] or to_string(name) not in allowed, do: throw(:invalid_xml)
    end)
  end

  def normalize(xml, agenda, template, external_id) do
    with {:ok, fields} <- parse(xml, agenda),
         {:ok, defaults} <- parse(template, agenda),
         :ok <- validate_fixed(fields, defaults),
         fields =
           defaults
           |> Map.take(editable())
           |> Map.merge(Map.take(fields, editable()))
           |> Map.merge(Map.take(defaults, @fixed))
           |> Map.put("polozkyDokladu", items(fields))
           |> Map.put("bezPolozek", if(items(fields) == [], do: "true", else: "false")),
         :ok <- validate(fields),
         {:ok, fields} <- CozyCheckout.IncomingDocuments.Items.validate(fields) do
      {:ok, render(fields, agenda, external_id)}
    end
  end

  def edit(xml, attrs, agenda, template, external_id) do
    with {:ok, fields} <- parse(xml, agenda),
         true <- Enum.all?(Map.keys(attrs), &(&1 in (editable() ++ ["items"]))),
         {:ok, rows} <- edited_items(items(fields), attrs["items"]),
         merged = Map.merge(fields, Map.drop(attrs, ["items"])) |> Map.put("polozkyDokladu", rows) do
      normalize(render(merged, agenda, external_id), agenda, template, external_id)
    else
      false -> {:error, "Neznámé pole dokladu"}
      error -> error
    end
  end

  defp edited_items(rows, nil), do: {:ok, rows}

  defp edited_items(rows, attrs) when is_map(attrs) do
    expected = rows |> Enum.with_index() |> Enum.map(fn {_, i} -> to_string(i) end) |> Enum.sort()

    if Enum.sort(Map.keys(attrs)) == expected and
         Enum.all?(attrs, fn {_, row} ->
           is_map(row) and Enum.all?(Map.keys(row), &(&1 in @item_editable))
         end) do
      {:ok,
       rows
       |> Enum.with_index()
       |> Enum.map(fn {row, i} ->
         row |> Map.drop(~w(sumZkl sumDph sumCelkem szbDph)) |> Map.merge(attrs[to_string(i)])
       end)}
    else
      {:error, "Neplatná úprava položek"}
    end
  end

  defp edited_items(_, _), do: {:error, "Neplatná úprava položek"}

  @doc "ABRA calculates an itemized header from items; never send its reference totals twice."
  def import_xml(xml, agenda) do
    with {:ok, fields} <- parse(xml, agenda),
         {:ok, adjustments} <- CozyCheckout.IncomingDocuments.Items.adjustments(fields) do
      if items(fields) == [] do
        {:ok, xml}
      else
        fields =
          fields |> Map.drop(@amounts) |> Map.put("polozkyDokladu", items(fields) ++ adjustments)

        {:ok, render(fields, agenda, fields["id"])}
      end
    end
  end

  def rounding_adjustments(xml, agenda) do
    with {:ok, fields} <- parse(xml, agenda),
         do: CozyCheckout.IncomingDocuments.Items.adjustments(fields)
  end

  def extraction_template(template, agenda) do
    {:ok, fields} = parse(template, agenda)

    row = %{
      "nazev" => "NÁZEV Z ORIGINÁLU",
      "mnozMj" => "1",
      "cenaMj" => "0.00",
      "typCenyDphK" => "typCeny.sDph",
      "typSzbDphK" => "typSzbDph.dphZakl",
      "slevaPol" => "0"
    }

    fields |> Map.put("polozkyDokladu", [row]) |> render(agenda)
  end

  def render(fields, agenda, external_id \\ nil) do
    identity = if external_id, do: "<id>#{escape(external_id)}</id>", else: ""

    fields = if items(fields) == [], do: fields, else: Map.put(fields, "bezPolozek", "false")

    body =
      for key <- @fixed ++ editable(),
          Map.has_key?(fields, key),
          do: "<#{key}>#{escape(fields[key])}</#{key}>"

    rows =
      if items(fields) == [] do
        ""
      else
        content =
          for row <- items(fields) do
            values =
              for key <- @item_fields,
                  key != "typPolozkyK",
                  Map.has_key?(row, key),
                  do: "<#{key}>#{escape(row[key])}</#{key}>"

            "<#{agenda}-polozka><typPolozkyK>#{if row["typPolozkyK"] == "typPolozky.ucetni", do: "typPolozky.ucetni", else: "typPolozky.obecny"}</typPolozkyK>#{Enum.join(values)}</#{agenda}-polozka>"
          end

        "<polozkyDokladu>#{Enum.join(content)}</polozkyDokladu>"
      end

    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<winstrom version=\"1.0\"><#{agenda} create=\"ok\" update=\"fail\">#{identity}#{Enum.join(body)}#{rows}</#{agenda}></winstrom>"
  end

  @doc "Lists accounting differences without weakening the template's fixed settings."
  def accounting_differences(xml, agenda, template) do
    with {:ok, fields} <- parse(xml, agenda),
         {:ok, defaults} <- parse(template, agenda) do
      {:ok, fixed_differences(fields, defaults)}
    end
  end

  @doc "Prepares a repair draft; validation and approval are still required before import."
  def restore_accounting(xml, agenda, template, external_id) do
    with {:ok, fields} <- parse(xml, agenda),
         {:ok, defaults} <- parse(template, agenda) do
      fields =
        Map.merge(Map.take(fields, editable() ++ ["polozkyDokladu"]), Map.take(defaults, @fixed))

      {:ok, render(fields, agenda, external_id) |> String.replace("><", ">\n<")}
    end
  end

  defp fixed_differences(fields, defaults) do
    for key <- @fixed -- (@rates ++ ["bezPolozek", "kod"]),
        Map.has_key?(fields, key),
        not equivalent?(key, fields[key], defaults[key]),
        do: %{field: key, expected: defaults[key], actual: fields[key]}
  end

  defp equivalent?(_, actual, expected), do: actual == expected

  defp validate_fixed(fields, defaults) do
    case fixed_differences(fields, defaults) do
      [] ->
        :ok

      differences ->
        details =
          Enum.map_join(differences, "; ", fn diff ->
            "#{diff.field}: vzor #{inspect(diff.expected)}, vráceno #{inspect(diff.actual)}"
          end)

        {:error, "Účetní nastavení se liší od vzoru — " <> details}
    end
  end

  defp validate(fields) do
    missing = Enum.filter(~w(nazFirmy cisDosle datVyst), &(fields[&1] in [nil, ""]))

    dates =
      Enum.filter(
        @dates,
        &(fields[&1] not in [nil, ""] and not match?({:ok, _}, Date.from_iso8601(fields[&1])))
      )

    cond do
      missing != [] ->
        {:error, "Nevyplněná povinná pole: " <> Enum.map_join(missing, ", ", &required_label/1)}

      dates != [] ->
        {:error,
         "Neplatné datum (očekáváno RRRR-MM-DD): " <>
           Enum.map_join(dates, "; ", &"#{&1}=#{inspect(fields[&1])}")}

      true ->
        validate_amounts(fields)
    end
  end

  defp required_label("cisDosle"),
    do: "cisDosle (číslo původního dokladu; u PENNY hledejte EV-č včetně patičky účtenky)"

  defp required_label("nazFirmy"), do: "nazFirmy (dodavatel)"
  defp required_label("datVyst"), do: "datVyst (datum vystavení)"

  defp validate_amounts(fields) do
    case decimals(fields) do
      {:ok, amounts} ->
        total =
          Enum.reduce(@amounts -- ["sumCelkem"], Decimal.new(0), &Decimal.add(amounts[&1], &2))

        cond do
          not Decimal.equal?(total, amounts["sumCelkem"]) ->
            {:error,
             "Nesouhlasí sumCelkem: uvedeno #{amounts["sumCelkem"]} Kč, součet základů, osvobozené částky a DPH je #{total} Kč (rozdíl #{Decimal.sub(amounts["sumCelkem"], total)} Kč)"}

          not Decimal.positive?(amounts["sumCelkem"]) ->
            {:error, "sumCelkem musí být větší než nula"}

          true ->
            :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decimals(fields) do
    Enum.reduce_while(@amounts, {:ok, %{}}, fn key, {:ok, acc} ->
      value = Map.get(fields, key, "0.00")

      if is_binary(value) and Regex.match?(~r/^-?\d{1,12}(\.\d{1,2})?$/, value),
        do: {:cont, {:ok, Map.put(acc, key, Decimal.new(value))}},
        else:
          {:halt,
           {:error,
            "Neplatná částka #{key}=#{inspect(value)}: použijte číslo s tečkou a nejvýše dvěma desetinnými místy"}}
    end)
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp invalid,
    do:
      {:error,
       "Neplatné XML: očekáván jeden doklad vybrané agendy a nejvýše 200 položek v polozkyDokladu, bez vazeb a externích entit"}
end

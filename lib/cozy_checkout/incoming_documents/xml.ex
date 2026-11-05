defmodule CozyCheckout.IncomingDocuments.XML do
  @moduledoc "Restricted flat XML dialect for the three supplied bezPolozek templates."

  @agendas ["faktura-prijata", "pokladni-pohyb", "zavazek"]
  @text ~w(cisDosle varSym datVyst duzpPuv duzpUcto datSplat datUcto popis nazFirmy ic dic ulice mesto psc buc iban)
  @amounts ~w(sumOsv sumZklSniz sumZklSniz2 sumZklZakl sumDphSniz sumDphSniz2 sumDphZakl sumCelkem)
  @fixed ~w(typDokl mena stat statDph typUcOp primUcet protiUcet dphZaklUcet dphSnizUcet dphSniz2Ucet clenDph clenKonVykDph stredisko pokladna typPohybuK szbDphSniz szbDphSniz2 szbDphZakl bezPolozek ucetni)
  @rates ~w(szbDphSniz szbDphSniz2 szbDphZakl)
  @dates ~w(datVyst duzpPuv duzpUcto datSplat datUcto)
  @discard ~w(id kod lastUpdate createdDate createdBy updatedBy datUhr stavUhrK zuctovano)

  def agendas, do: @agendas
  def editable, do: @text ++ @amounts
  def fixed, do: @fixed
  def amount?(key), do: key in @amounts
  def date?(key), do: key in @dates

  def template(agenda) when agenda in @agendas do
    :cozy_checkout |> Application.app_dir("priv/incoming_documents/#{agenda}.xml") |> File.read!()
  end

  @doc "Parses without creating atoms from names; DTD, entities and nested records are forbidden."
  def parse(xml, agenda) when is_binary(xml) and byte_size(xml) <= 100_000 do
    if agenda in @agendas and String.valid?(xml) and
         not Regex.match?(~r/<!|<\?/u, strip_declaration(xml)) do
      state = %{stack: [], fields: %{}, text: "", agenda: agenda, done: false}

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

  def parse(_, _), do: invalid()

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
        if key not in (@text ++ @amounts ++ @fixed ++ @discard) or
             Map.has_key?(state.fields, key),
           do: throw(:invalid_xml)

        check_attrs(attrs, [])

      _ ->
        throw(:invalid_xml)
    end

    %{state | stack: [key | state.stack], text: ""}
  end

  defp event({:endElement, _, name, _}, _, %{stack: [key | rest]} = state) do
    if to_string(name) != key, do: throw(:invalid_xml)

    fields =
      if length(rest) == 2,
        do: Map.put(state.fields, key, String.trim(state.text)),
        else: state.fields

    %{state | stack: rest, fields: fields, text: "", done: state.done or key == state.agenda}
  end

  defp event({kind, chars}, _, state) when kind in [:characters, :ignorableWhitespace] do
    value = to_string(chars)
    if length(state.stack) < 3 and String.trim(value) != "", do: throw(:invalid_xml)
    %{state | text: state.text <> value}
  end

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
           |> Map.merge(Map.take(defaults, @fixed)),
         :ok <- validate(fields) do
      {:ok, render(fields, agenda, external_id)}
    end
  end

  def edit(xml, attrs, agenda, template, external_id) do
    with {:ok, fields} <- parse(xml, agenda),
         true <- Enum.all?(Map.keys(attrs), &(&1 in editable())),
         merged = Map.merge(fields, attrs) do
      normalize(render(merged, agenda, external_id), agenda, template, external_id)
    else
      false -> {:error, "Neznámé pole dokladu"}
      error -> error
    end
  end

  def render(fields, agenda, external_id \\ nil) do
    identity = if external_id, do: "<id>#{escape(external_id)}</id>", else: ""

    body =
      for key <- @fixed ++ editable(),
          Map.has_key?(fields, key),
          do: "<#{key}>#{escape(fields[key])}</#{key}>"

    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<winstrom version=\"1.0\"><#{agenda} create=\"ok\" update=\"fail\">#{identity}#{Enum.join(body)}</#{agenda}></winstrom>"
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
      fields = Map.merge(Map.take(fields, editable()), Map.take(defaults, @fixed))
      {:ok, render(fields, agenda, external_id) |> String.replace("><", ">\n<")}
    end
  end

  defp fixed_differences(fields, defaults) do
    for key <- @fixed,
        Map.has_key?(fields, key),
        not equivalent?(key, fields[key], defaults[key]),
        do: %{field: key, expected: defaults[key], actual: fields[key]}
  end

  defp equivalent?(key, actual, expected) when key in @rates do
    valid_number = fn value ->
      is_binary(value) and Regex.match?(~r/^\d{1,3}(\.\d{1,6})?$/, value)
    end

    valid_number.(actual) and valid_number.(expected) and
      Decimal.equal?(Decimal.new(actual), Decimal.new(expected))
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
        {:error, "Chybí povinná pole: " <> Enum.join(missing, ", ")}

      dates != [] ->
        {:error,
         "Neplatné datum (očekáváno RRRR-MM-DD): " <>
           Enum.map_join(dates, "; ", &"#{&1}=#{inspect(fields[&1])}")}

      true ->
        validate_amounts(fields)
    end
  end

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
       "Neplatné XML: očekáván jeden bezpoložkový doklad vybrané agendy bez vazeb a externích entit"}
end

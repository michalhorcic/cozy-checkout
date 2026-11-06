defmodule CozyCheckout.IncomingDocuments.Transcription do
  @moduledoc "Source-only JSON contract; accounting fields never come from the model."

  def schema do
    text = %{"type" => ["string", "null"]}

    object(%{
      "document_number" => text,
      "document_number_label" => text,
      "variable_symbol" => text,
      "issue_date" => text,
      "tax_date" => text,
      "due_date" => text,
      "currency" => text,
      "total" => text,
      "supplier" => object(Map.new(~w(name ic dic street city postal_code), &{&1, text})),
      "vat_legend" => array(object(%{"marker" => text, "rate" => text})),
      "vat_summary" => array(object(Map.new(~w(rate net vat gross), &{&1, text}))),
      "items" =>
        array(
          object(
            Map.merge(
              Map.new(
                ~w(name quantity unit_price line_total discount_percent vat_marker vat_rate raw_text),
                &{&1, text}
              ),
              %{"price_includes_vat" => %{"type" => ["boolean", "null"]}}
            )
          )
        ),
      "complete" => %{"type" => "boolean"},
      "uncertainties" => array(%{"type" => "string"})
    })
  end

  @doc "Header-only output omits item rows entirely from the model contract."
  def header_schema do
    full = schema()

    %{
      full
      | "properties" => Map.delete(full["properties"], "items"),
        "required" => List.delete(full["required"], "items")
    }
  end

  @doc "Normalizes unambiguous Czech numeric formatting without changing source values."
  def canonicalize(data) do
    data
    |> normalize_money_fields(~w(total), data["currency"])
    |> Map.update!(
      "vat_summary",
      &Enum.map(&1, fn row ->
        row
        |> normalize_fields(~w(rate))
        |> normalize_money_fields(~w(net vat gross), data["currency"])
      end)
    )
    |> Map.update!("vat_legend", &Enum.map(&1, fn row -> normalize_fields(row, ~w(rate)) end))
    |> Map.update!(
      "items",
      &Enum.map(&1, fn row ->
        row
        |> normalize_fields(~w(quantity discount_percent vat_rate))
        |> normalize_money_fields(~w(unit_price line_total), data["currency"])
      end)
    )
  end

  defp normalize_money_fields(map, keys, currency) do
    Enum.reduce(keys, map, fn key, acc ->
      Map.update!(acc, key, fn value ->
        value = if currency == "CZK" and is_binary(value), do: strip_czk(value), else: value
        canonical_number(value)
      end)
    end)
  end

  defp strip_czk(value) do
    value = String.trim(value)

    cond do
      Regex.match?(~r/^(?:Kč|CZK)\s*[-+]?\d/iu, value) ->
        Regex.replace(~r/^(?:Kč|CZK)\s*/iu, value, "")

      Regex.match?(~r/\d\s*(?:Kč|CZK)$/iu, value) ->
        Regex.replace(~r/\s*(?:Kč|CZK)$/iu, value, "")

      true ->
        value
    end
  end

  defp normalize_fields(map, keys) do
    Enum.reduce(keys, map, fn key, acc -> Map.update!(acc, key, &canonical_number/1) end)
  end

  defp canonical_number(value) when is_binary(value) do
    trimmed = String.trim(value)
    grouped? = Regex.match?(~r/^-?\d{1,3}([ \x{00a0}\x{202f}]+\d{3})+([.,]\d{1,12})?$/u, trimmed)

    compact =
      if grouped?, do: String.replace(trimmed, ~r/[ \x{00a0}\x{202f}]/u, ""), else: trimmed

    compact = String.replace(compact, ",", ".")

    cond do
      compact == "" ->
        nil

      Regex.match?(~r/^-?\d{1,12}(\.\d{1,12})?$/, compact) ->
        if Regex.match?(~r/\.\d{2}0+$/, compact),
          do: compact |> Decimal.new() |> Decimal.normalize() |> Decimal.to_string(:normal),
          else: compact

      true ->
        value
    end
  end

  defp canonical_number(value), do: value

  defp object(properties),
    do: %{
      "type" => "object",
      "properties" => properties,
      "required" => Enum.sort(Map.keys(properties)),
      "additionalProperties" => false
    }

  defp array(items), do: %{"type" => "array", "items" => items}

  @doc "Validate locally as well: schema adherence is not proof that the source was read correctly."
  def validate(data, contract \\ schema()) do
    with :ok <- shape(data, contract, "doklad"),
         true <-
           length(data["items"] || []) <= 200 and length(data["vat_summary"]) <= 4 and
             length(data["vat_legend"]) <= 10 do
      :ok
    else
      false -> {:error, "Přepis přesahuje povolený počet položek nebo sazeb"}
      error -> error
    end
  end

  defp shape(nil, %{"type" => types}, _) when is_list(types),
    do: if("null" in types, do: :ok, else: {:error, "Nepovolená prázdná hodnota"})

  defp shape(value, %{"type" => "object", "properties" => props}, path) when is_map(value) do
    if Enum.sort(Map.keys(value)) == Enum.sort(Map.keys(props)) do
      Enum.reduce_while(props, :ok, fn {key, spec}, :ok ->
        case shape(value[key], spec, path <> "." <> key) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      {:error, "#{path}: přepis má chybějící nebo nepovolená pole"}
    end
  end

  defp shape(value, %{"type" => "array", "items" => spec}, path)
       when is_list(value) and length(value) <= 200 do
    Enum.reduce_while(value, :ok, fn item, :ok ->
      case shape(item, spec, path) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp shape(value, %{"type" => "boolean"}, _) when is_boolean(value), do: :ok

  defp shape(value, %{"type" => "string"}, _) when is_binary(value) and byte_size(value) <= 2000,
    do: :ok

  defp shape(value, %{"type" => types}, path) when is_list(types),
    do: shape(value, %{"type" => Enum.find(types, &(&1 != "null"))}, path)

  defp shape(_, _, path), do: {:error, "#{path}: neočekávaný typ nebo příliš dlouhá hodnota"}
end

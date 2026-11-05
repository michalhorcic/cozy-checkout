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

  defp object(properties),
    do: %{
      "type" => "object",
      "properties" => properties,
      "required" => Enum.sort(Map.keys(properties)),
      "additionalProperties" => false
    }

  defp array(items), do: %{"type" => "array", "items" => items}

  @doc "Validate locally as well: schema adherence is not proof that the source was read correctly."
  def validate(data) do
    with :ok <- shape(data, schema(), "doklad"),
         true <-
           length(data["items"]) <= 200 and length(data["vat_summary"]) <= 4 and
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

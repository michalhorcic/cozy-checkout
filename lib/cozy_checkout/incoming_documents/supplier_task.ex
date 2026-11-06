defmodule CozyCheckout.IncomingDocuments.SupplierTask do
  @moduledoc "Sparse source-only corrections from an independent supplier instruction call."
  alias CozyCheckout.IncomingDocuments.Transcription

  @fields ~w(document_number document_number_label variable_symbol issue_date tax_date due_date currency total supplier.name supplier.ic supplier.dic supplier.street supplier.city supplier.postal_code)

  def schema do
    text = %{"type" => ["string", "null"]}

    object(%{
      "fields" => %{
        "type" => "array",
        "items" =>
          object(%{
            "field" => %{"type" => "string", "enum" => @fields},
            "value" => text,
            "source_text" => text
          })
      },
      "vat_summary" =>
        Map.put(Transcription.schema()["properties"]["vat_summary"], "type", ["array", "null"]),
      "uncertainties" => %{"type" => "array", "items" => %{"type" => "string"}}
    })
  end

  defp object(properties),
    do: %{
      "type" => "object",
      "properties" => properties,
      "required" => Enum.sort(Map.keys(properties)),
      "additionalProperties" => false
    }

  def validate(
        %{"fields" => fields, "vat_summary" => vat, "uncertainties" => uncertainties} = data
      )
      when map_size(data) == 3 and is_list(fields) and length(fields) <= 14 and
             is_list(uncertainties) and length(uncertainties) <= 20 do
    valid_fields =
      Enum.all?(fields, fn
        %{"field" => field, "value" => value, "source_text" => source} = row
        when map_size(row) == 3 ->
          field in @fields and text?(value) and text?(source) and
            (is_nil(value) or (is_binary(source) and String.trim(source) != ""))

        _ ->
          false
      end)

    unique_fields = valid_fields and Enum.uniq_by(fields, & &1["field"]) == fields

    if valid_fields and unique_fields and Enum.all?(uncertainties, &(is_binary(&1) and text?(&1))) and
         valid_vat?(vat),
       do: :ok,
       else: {:error, "Neplatná struktura samostatného dodavatelského dotazu"}
  end

  def validate(_), do: {:error, "Neplatná struktura samostatného dodavatelského dotazu"}

  defp text?(nil), do: true
  defp text?(value), do: is_binary(value) and byte_size(value) <= 2000
  defp valid_vat?(nil), do: true

  defp valid_vat?(rows) when is_list(rows) and length(rows) <= 4 do
    Enum.all?(rows, fn
      %{"rate" => _, "net" => _, "vat" => _, "gross" => _} = row when map_size(row) == 4 ->
        Enum.all?(Map.values(row), &text?/1)

      _ ->
        false
    end)
  end

  defp valid_vat?(_), do: false

  @doc "Only explicitly returned permitted fields override the general reading, including explicit nulls."
  def merge(data, result) do
    data =
      Enum.reduce(result["fields"], data, fn row, acc ->
        case String.split(row["field"], ".") do
          ["supplier", key] -> put_in(acc, ["supplier", key], row["value"])
          [key] -> Map.put(acc, key, row["value"])
        end
      end)

    data =
      if is_nil(result["vat_summary"]),
        do: data,
        else: Map.put(data, "vat_summary", result["vat_summary"])

    Map.update!(
      data,
      "uncertainties",
      &(Enum.uniq(result["uncertainties"] ++ &1) |> Enum.take(200))
    )
  end
end

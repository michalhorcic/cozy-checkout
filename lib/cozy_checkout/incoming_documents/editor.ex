defmodule CozyCheckout.IncomingDocuments.Editor do
  @moduledoc "Typed form updates for source transcription drafts. No accounting mapping or model calls."
  @collections ~w(vat_summary vat_legend items)

  def apply(data, attrs) do
    Enum.reduce(data, data, fn {key, previous}, result ->
      value =
        cond do
          key in @collections ->
            Enum.with_index(previous)
            |> Enum.map(fn {row, index} ->
              update_row(row, get_in(attrs, [key, to_string(index)]) || %{})
            end)

          key == "supplier" ->
            update_row(previous, attrs[key] || %{})

          key == "uncertainties" and is_binary(attrs[key]) ->
            String.split(attrs[key], "\n", trim: true)

          Map.has_key?(attrs, key) ->
            cast(key, attrs[key])

          true ->
            previous
        end

      Map.put(result, key, value)
    end)
  end

  defp update_row(row, attrs),
    do:
      Enum.reduce(row, row, fn {key, _}, result ->
        if Map.has_key?(attrs, key), do: Map.put(result, key, cast(key, attrs[key])), else: result
      end)

  defp cast("complete", value), do: value in [true, "true"]
  defp cast("price_includes_vat", "true"), do: true
  defp cast("price_includes_vat", "false"), do: false
  defp cast("price_includes_vat", _), do: nil

  defp cast(_, value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp cast(_, _), do: nil

  def name(path), do: "fields[source]" <> Enum.map_join(path, "", &"[#{&1}]")

  def value(data, path) do
    value =
      Enum.reduce(path, data, fn key, acc ->
        if is_list(acc), do: Enum.at(acc, key), else: Map.get(acc || %{}, key)
      end)

    case value do
      true -> "true"
      false -> "false"
      list when is_list(list) -> Enum.join(list, "\n")
      nil -> ""
      value -> value
    end
  end

  def add(data, collection) when collection in @collections do
    limit =
      case collection do
        "items" -> 200
        "vat_summary" -> 4
        _ -> 10
      end

    if length(data[collection]) < limit do
      properties =
        CozyCheckout.IncomingDocuments.Transcription.schema()["properties"][collection]["items"][
          "properties"
        ]

      Map.update!(data, collection, &(&1 ++ [Map.new(properties, fn {key, _} -> {key, nil} end)]))
    else
      data
    end
  end

  def add(data, _), do: data

  def delete(data, collection, index) when collection in @collections do
    case Integer.parse(index) do
      {i, ""} when i >= 0 -> Map.update!(data, collection, &List.delete_at(&1, i))
      _ -> data
    end
  end

  def delete(data, _, _), do: data
end

defmodule CozyCheckout.IncomingDocuments.ImportPayload do
  @moduledoc "Projects reviewed XML into the native JSON envelope used by the working accommodation API."
  alias CozyCheckout.IncomingDocuments.XML

  def from_xml(xml, doc) do
    with {:ok, fields} <- XML.parse(xml, doc.agenda) do
      record =
        fields
        |> Map.take(XML.fixed() ++ XML.editable())
        |> Map.reject(fn {_key, value} -> value in [nil, ""] end)
        |> Map.merge(%{"@create" => "ok", "@update" => "fail", "id" => doc.external_id})
        |> boolean("bezPolozek")
        |> boolean("ucetni")

      record =
        case XML.items(fields) do
          [] -> record
          rows -> Map.put(record, "polozkyDokladu", rows)
        end

      {:ok, %{"winstrom" => %{doc.agenda => [record]}}}
    end
  end

  defp boolean(record, key) do
    case record[key] do
      "true" -> Map.put(record, key, true)
      "false" -> Map.put(record, key, false)
      _ -> record
    end
  end
end

defmodule CozyCheckout.Economics.AccountMapping do
  @moduledoc "Versioned presentation categories; account kinds still come from ABRA."
  @version 1
  @mapping %{
    "602001" => "Ubytování a stravování",
    "602002" => "Pronájem prostor",
    "604001" => "Bar",
    "648100" => "Další výnosy",
    "501100" => "Potraviny",
    "502001" => "Energie",
    "521001" => "Mzdy",
    "501300" => "Úklid a praní",
    "518400" => "Úklid a praní",
    "518200" => "Účetní a právní služby",
    "511001" => "Opravy",
    "518001" => "Ostatní služby",
    "551001" => "Odpisy"
  }
  def version, do: @version
  def entries, do: Enum.sort(@mapping)
  def category(code), do: Map.get(@mapping, code, "Nezařazeno")
  def sales?(code), do: code in ["602001", "602002", "604001"]
end

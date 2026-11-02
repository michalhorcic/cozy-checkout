defmodule CozyCheckout.Recipes.Pictograms do
  @moduledoc "Small, manually assigned recipe pictogram catalogue."
  @options [
    {"poultry", "Drůbež"},
    {"beef", "Hovězí"},
    {"pork", "Vepřové"},
    {"minced", "Mleté maso"},
    {"soup", "Polévka"},
    {"legumes", "Luštěniny"},
    {"vegetables", "Zelenina"},
    {"pasta", "Těstoviny"},
    {"rice", "Rýže"},
    {"potatoes", "Brambory"},
    {"dumplings", "Knedlíky"},
    {"sweet", "Sladká jídla"},
    {"sauce", "Omáčky"},
    {"wok", "Wok a směsi"},
    {"breakfast", "Snídaňový bufet"}
  ]
  def options, do: @options
  def keys, do: Enum.map(@options, &elem(&1, 0))
  def label(key), do: Enum.find_value(@options, fn {id, label} -> if id == key, do: label end)
end

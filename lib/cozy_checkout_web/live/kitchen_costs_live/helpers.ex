defmodule CozyCheckoutWeb.KitchenCostsLive.Helpers do
  def error(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        token = "%{#{key}}"

        if String.contains?(acc, token),
          do: String.replace(acc, token, to_string(value)),
          else: acc
      end)
    end)
    |> messages()
    |> Enum.join(" · ")
  end

  def error(:possible_duplicate),
    do:
      "Možná duplicita dokladu. Zkontrolujte seznam nákupů a výslovně potvrďte uložení duplicity."

  def error(:already_replaced), do: "Tento nákup už má novější verzi. Otevřete poslední verzi."

  def error(:mapping_changed),
    do: "Slovník se mezitím změnil. Obnovte náhled přiřazení a znovu ho potvrďte."

  def error(:unconfirmed_mapping),
    do: "Potvrďte přiřazení u všech řádků označených jako surovina."

  def error(:invalid_ingredient), do: "Vyberte existující nearchivovanou surovinu."
  def error(v) when is_binary(v), do: v
  def error(_), do: "Údaje se nepodařilo uložit. Zkontrolujte formulář a obnovte podklady."

  defp messages(map) when is_map(map),
    do: Enum.flat_map(map, fn {key, value} -> Enum.map(messages(value), &"#{key}: #{&1}") end)

  defp messages(list) when is_list(list), do: Enum.flat_map(list, &messages/1)
  defp messages(text), do: [text]

  def source("weighted_average"), do: "Vážený průměr za 90 dní"
  def source("older_purchase"), do: "Starší nákup"
  def source("manual_estimate"), do: "Ruční odhad"
  def source(_), do: "Chybí cena"
  def money(nil), do: "Chybí cena"

  def money(value) when is_binary(value),
    do: value |> Decimal.new() |> CozyCheckoutWeb.CurrencyHelper.format_currency()

  def money(value), do: CozyCheckoutWeb.CurrencyHelper.format_currency(value)
  def number(nil), do: "—"

  def number(value),
    do: CozyCheckoutWeb.CurrencyHelper.format_number(value, precision: 4, decimal_separator: ",")
end

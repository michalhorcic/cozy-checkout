defmodule CozyCheckoutWeb.EconomicsLive.Components do
  use CozyCheckoutWeb, :html
  alias CozyCheckoutWeb.CurrencyHelper

  def money(nil), do: "Nedostupné"
  def money(value), do: value |> Decimal.new() |> CurrencyHelper.format_currency()

  def warning("missing_currency"),
    do:
      "U části tuzemských pohybů ABRA neuvádí měnu dokladu. Částky jsou převzaté z tuzemských MD/Dal."

  def warning("unmapped_accounts"),
    do:
      "Některé účty jsou v kategorii Nezařazeno. Jsou zahrnuté v celkových výnosech a nákladech."

  def warning("unposted_documents"),
    do: "Období obsahuje nezaúčtované pohyby. Do účetního výsledku se nezapočítávají."

  def warning("unposted_incomplete"),
    do:
      "Některé nezaúčtované pohyby nemají úplné účty nebo částky. Jejich předběžný součet není dostupný."

  def warning("unsupported_open_items"),
    do:
      "U části salda se změnila hodnota dokladu. Celkové pohledávky a závazky proto nejsou dostupné."

  def warning(_), do: "Data vyžadují kontrolu."

  attr :title, :string, required: true
  attr :value, :any, default: nil
  attr :explanation, :string, required: true
  attr :status, :string, default: "Zaúčtované pohyby ABRA"

  def metric(assigns) do
    ~H"""
    <section class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
      <h2 class="text-sm font-medium text-base-content/70">{@title}</h2>
      <p class="mt-2 text-2xl font-bold tabular-nums">{money(@value)}</p>
      <p class="mt-2 text-sm">{@explanation}</p>
      <p class="mt-3 text-xs text-base-content/60">{@status}</p>
    </section>
    """
  end

  attr :active, :string, default: "overview"

  def navigation(assigns) do
    ~H"""
    <nav class="flex flex-wrap gap-2" aria-label="Ekonomika firmy">
      <.link
        navigate={~p"/admin/economics"}
        class={["btn btn-sm", @active == "overview" && "btn-primary"]}
      >Přehled</.link>
      <.link
        navigate={~p"/admin/economics/settings"}
        class={["btn btn-sm", @active == "settings" && "btn-primary"]}
      >Zdroj a úplnost</.link>
    </nav>
    """
  end

  def error(:disabled), do: "Ekonomika firmy je vypnutá."

  def error(:not_imported),
    do: "Z tohoto zdroje zatím nejsou načtená data. Spusťte první aktualizaci."

  def error(:invalid_connection),
    do: "Připojení k ABŘE není úplné nebo nevyužívá HTTPS. Zkontrolujte konfiguraci Economics."

  def error(:invalid_range),
    do: "Vyberte měsíce dostupné v načteném období a správné pořadí od–do."

  def error(:invalid_confirmation),
    do: "Zvolte ukončený měsíc a uveďte podklad potvrzení alespoň 10 znaky."

  def error(:snapshot_changed),
    do: "Data se mezitím změnila. Obnovte přehled a zkontrolujte nový stav."

  def error(:account_unavailable), do: "Účet nemá v tomto období dostupné pohyby."
  def error(_), do: "Operaci se nepodařilo dokončit. Zkontrolujte stav importu a konfiguraci."

  def run_label(nil), do: "Žádný dokončený import"

  def run_label(%{state: "running"}),
    do: "Probíhá načítání; přehled používá poslední úspěšná data."

  def run_label(%{state: "failed", error: code}),
    do:
      "Poslední import selhal (#{code}). Zobrazují se poslední úspěšná data, pokud jsou dostupná."

  def run_label(%{state: "succeeded", completed_at: at}), do: "Poslední úspěšný import: #{at}"

  def bar_width(value, months) do
    max_value =
      months
      |> Enum.flat_map(&[&1["totals"]["revenue"], &1["totals"]["expense"]])
      |> Enum.map(&(Decimal.new(&1) |> Decimal.abs()))
      |> Enum.max(Decimal)

    if Decimal.equal?(max_value, 0),
      do: 0,
      else:
        value
        |> Decimal.new()
        |> Decimal.abs()
        |> Decimal.div(max_value)
        |> Decimal.mult(100)
        |> Decimal.round(0)
        |> Decimal.to_integer()
  end
end

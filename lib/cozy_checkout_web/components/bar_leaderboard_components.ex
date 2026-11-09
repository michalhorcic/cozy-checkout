defmodule CozyCheckoutWeb.BarLeaderboardComponents do
  use Phoenix.Component

  import CozyCheckoutWeb.AccountStampComponents
  import CozyCheckoutWeb.CurrencyHelper

  alias CozyCheckout.Sales.AccountStamps

  attr :entries, :list, required: true

  def bar_podium(assigns) do
    ~H"""
    <section
      id="bar-podium"
      aria-labelledby="bar-cup-title"
      class="mb-5 rounded-2xl border border-amber-200 bg-linear-to-br from-amber-50 via-white to-secondary-50 p-4 sm:p-5"
    >
      <div class="flex items-start gap-3">
        <span aria-hidden="true" class="text-4xl">🏆</span>
        <div>
          <p class="text-xs font-bold uppercase tracking-widest text-amber-800">Barová síň slávy</p>
          <h2 id="bar-cup-title" class="text-xl font-bold text-primary-500">Pohár štědré ruky</h2>
          <p class="mt-1 text-sm text-primary-400">Malý bar. Velká jména. Kdo právě drží pohár?</p>
        </div>
      </div>

      <div
        :if={@entries == []}
        class="mt-4 rounded-xl border border-dashed border-amber-300 p-4 text-sm text-amber-900"
      >
        Pódium zatím čeká na své hvězdy. První barová položka vás zapojí do hry.
      </div>

      <ol
        :if={@entries != []}
        class="mt-4 grid gap-3 sm:grid-cols-3"
        aria-label="Stupně vítězů podle útraty"
      >
        <li
          :for={entry <- Enum.filter(@entries, &(&1.rank <= 3))}
          data-rank={entry.rank}
          class={["min-w-0 rounded-xl border p-3", medal_style(entry.rank)]}
        >
          <.bar_badge entry={entry} />
          <div class="mt-3 flex items-center gap-3">
            <.account_stamp stamp={AccountStamps.key(entry.order)} class="h-12 w-12" />
            <div class="min-w-0">
              <p class="break-words font-bold text-primary-500">{entry.name}</p>
              <p class="text-lg font-bold tabular-nums text-primary-500">
                {format_currency(entry.total)}
              </p>
            </div>
          </div>
          <p class="mt-2 text-xs font-medium">{motto(entry.rank)}</p>
        </li>
      </ol>

      <details class="mt-3 text-xs text-primary-400">
        <summary class="min-h-11 cursor-pointer py-3 font-semibold">
          Jak se hraje? · {length(@entries)} soutěžících
        </summary>
        <p class="max-w-3xl leading-relaxed">
          Každý host soutěží součtem svých barových účtů za aktuální pobyt, včetně zaplacených.
          Samostatný účet představuje jednoho soutěžícího a soutěží do uzavření.
          Počítá se útrata po slevách, bez spropitného. Servisní a stornované účty nehrají.
          Nulová útrata čeká na start. Při shodě se místo i medaile sdílí.
          Výsledky se načtou při otevření přehledu. V poháru je i káva, limonáda a něco na zub.
        </p>
        <ol :if={@entries != []} class="mt-3 space-y-2" aria-label="Celý barový žebříček">
          <li
            :for={entry <- @entries}
            class="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-white/80 p-2"
          >
            <span class="min-w-0 break-words"><strong>{entry.rank}.</strong> {entry.name}</span>
            <span class="font-semibold tabular-nums">{format_currency(entry.total)}</span>
          </li>
        </ol>
      </details>
    </section>
    """
  end

  attr :entry, :map, default: nil

  def bar_badge(assigns) do
    ~H"""
    <span
      :if={@entry}
      data-bar-rank={@entry.rank}
      class={[
        "inline-flex max-w-full items-center gap-1 rounded-full border px-2 py-1 text-xs font-bold",
        medal_style(@entry.rank)
      ]}
    >
      <span aria-hidden="true">{medal(@entry.rank)}</span>
      <span>{@entry.rank}. · {title(@entry.rank)}</span>
    </span>
    """
  end

  defp medal(1), do: "🥇"
  defp medal(2), do: "🥈"
  defp medal(3), do: "🥉"
  defp medal(_), do: "✨"

  defp title(1), do: "Zlatý mecenáš"
  defp title(2), do: "Stříbrný srdcař"
  defp title(3), do: "Bronzový bohém"
  defp title(_), do: "Barový parťák"

  defp motto(1), do: "Tenhle pohár má svého patrona."
  defp motto(2), do: "Elegance se stříbrným leskem."
  defp motto(3), do: "Na bedně je prostě dobře."

  defp medal_style(1), do: "border-amber-300 bg-amber-100/80 text-amber-900"
  defp medal_style(2), do: "border-slate-300 bg-slate-100/80 text-slate-700"
  defp medal_style(3), do: "border-orange-300 bg-orange-100/80 text-orange-900"
  defp medal_style(_), do: "border-secondary-300 bg-secondary-50 text-primary-400"
end

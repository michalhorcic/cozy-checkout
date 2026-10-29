defmodule CozyCheckoutWeb.EconomicsLive.Charts do
  @moduledoc "Server-rendered HTML/CSS charts, following the existing Economy charts."
  use CozyCheckoutWeb, :html
  import CozyCheckoutWeb.EconomicsLive.Components, only: [money: 1]

  attr :report, :map, required: true

  def monthly(assigns) do
    values =
      for month <- assigns.report.months,
          field <- ["revenue", "expense", "result"],
          do: month["totals"][field]

    assigns =
      assign(assigns,
        maximum: maximum(values),
        confirmed:
          MapSet.new(Enum.filter(assigns.report.confirmations, & &1.confirmed), & &1.month)
      )

    ~H"""
    <section
      id="economics-monthly-chart"
      class="rounded-xl border border-base-300 p-5"
      aria-labelledby="economics-monthly-title"
    >
      <h2 id="economics-monthly-title" class="text-xl font-semibold">
        Měsíční vývoj výnosů, nákladů a výsledku
      </h2>
      <p class="mt-2 text-sm text-base-content/70">
        Zaúčtované částky v Kč. Kliknutím na měsíc otevřete jeho účty. Nepotvrzené měsíce jsou průběžné.
      </p>
      <div class="my-4 flex flex-wrap gap-5 text-sm">
        <span class="flex items-center gap-2"><span class="h-3 w-3 bg-primary-500" aria-hidden="true"></span>Výnosy</span><span class="flex items-center gap-2"><span
          class="h-3 w-3 bg-tertiary-500"
          aria-hidden="true"
        ></span>Náklady</span>
      </div>
      <div class="overflow-x-auto">
        <div style={"min-width: #{max(length(@report.months) * 90, 320)}px"}>
          <p class="text-xs text-base-content/60">
            Horní mez: {money(@maximum)} · shodné měřítko obou grafů
          </p>
          <div
            class="relative grid h-56 gap-3 border-b border-base-300"
            style={"grid-template-columns: repeat(#{length(@report.months)}, minmax(0, 1fr))"}
            role="group"
            aria-label="Výnosy a náklady po měsících v Kč"
          >
            <div
              class="pointer-events-none absolute inset-x-0 top-1/2 border-t border-base-300"
              aria-hidden="true"
            >
              <span class="bg-base-100 text-xs">0 Kč</span>
            </div>
            <.link
              :for={month <- @report.months}
              patch={
                ~p"/admin/economics?#{%{period: @report.period["code"], from: String.slice(month["from"], 0, 7), to: String.slice(month["from"], 0, 7)}}" <> "#economics-accounts"
              }
              class="relative flex h-full justify-center gap-1 rounded focus-visible:outline-2 focus-visible:outline-primary"
              aria-label={"#{String.slice(month["from"], 0, 7)}: výnosy #{money(month["totals"]["revenue"])}, náklady #{money(month["totals"]["expense"])}"}
            >
              <div
                :for={
                  {field, color} <- [{"revenue", "bg-primary-500"}, {"expense", "bg-tertiary-500"}]
                }
                class={["absolute w-1/3 rounded-sm", color]}
                style={column_style(month["totals"][field], @maximum, field)}
                title={money(month["totals"][field])}
                aria-hidden="true"
              >
              </div>
            </.link>
          </div>
          <div
            class="mt-2 grid gap-3 text-center text-xs"
            style={"grid-template-columns: repeat(#{length(@report.months)}, minmax(0, 1fr))"}
          >
            <div :for={month <- @report.months}>
              <span class="font-semibold">{String.slice(month["from"], 0, 7)}</span><span class="mt-1 block text-base-content/60">{if MapSet.member?(
                                                                                                                                        @confirmed,
                                                                                                                                        month[
                                                                                                                                          "from"
                                                                                                                                        ]
                                                                                                                                      ),
                                                                                                                                      do:
                                                                                                                                        "Potvrzeno",
                                                                                                                                      else:
                                                                                                                                        "Nepotvrzeno"}</span>
            </div>
          </div>
          <h3 class="mt-6 text-sm font-semibold">Účetní výsledek · výnosy minus náklady</h3>
          <div
            class="relative mt-2 grid h-40 gap-3"
            style={"grid-template-columns: repeat(#{length(@report.months)}, minmax(0, 1fr))"}
            role="group"
            aria-label="Účetní výsledek po měsících v Kč, záporné hodnoty pod nulovou osou"
          >
            <div
              class="pointer-events-none absolute inset-x-0 top-1/2 border-t border-base-300"
              aria-hidden="true"
            >
              <span class="bg-base-100 text-xs">0 Kč</span>
            </div>
            <div
              :for={month <- @report.months}
              class="relative h-full"
              aria-label={"#{String.slice(month["from"], 0, 7)}: #{money(month["totals"]["result"])}"}
            >
              <div
                class={[
                  "absolute left-1/4 w-1/2 rounded-sm",
                  if(negative?(month["totals"]["result"]),
                    do: "bg-secondary-400",
                    else: "bg-primary-500"
                  )
                ]}
                style={signed_style(month["totals"]["result"], @maximum)}
                title={money(month["totals"]["result"])}
                aria-hidden="true"
              >
              </div>
            </div>
          </div>
          <div
            class="grid gap-3 text-center text-xs tabular-nums"
            style={"grid-template-columns: repeat(#{length(@report.months)}, minmax(0, 1fr))"}
          >
            <span :for={month <- @report.months}>{money(month["totals"]["result"])}</span>
          </div>
          <p class="mt-2 text-xs text-base-content/60">
            Dolní mez: {money(Decimal.negate(Decimal.new(@maximum)) |> Decimal.to_string(:normal))}. Záporný výsledek je pod osou; sám o sobě neznamená úkol k vyřešení.
          </p>
        </div>
      </div>
    </section>
    """
  end

  attr :report, :map, required: true

  def costs(assigns) do
    assigns =
      assign(assigns, :maximum, maximum(Enum.map(assigns.report.cost_categories, & &1.amount)))

    ~H"""
    <section
      id="economics-cost-chart"
      class="rounded-xl border border-base-300 p-5"
      aria-labelledby="economics-cost-title"
    >
      <h2 id="economics-cost-title" class="text-xl font-semibold">Kam směřují náklady</h2>
      <p class="mt-2 text-sm text-base-content/70">
        Kategorie od největšího nákladu. Rozbalením zobrazíte účty a jejich zápisy. Nezařazené účty jsou zahrnuté.
      </p>
      <p :if={@report.cost_categories == []} class="mt-4">V tomto období nejsou nákladové pohyby.</p>
      <div class="mt-4 divide-y divide-base-200">
        <details :for={category <- @report.cost_categories} class="py-3">
          <summary class="cursor-pointer rounded focus-visible:outline-2 focus-visible:outline-primary">
            <span class="inline-flex w-full flex-wrap items-center justify-between gap-2"><span class="font-medium">{category.category}</span><span class="tabular-nums">{money(
              category.amount
            )}</span></span>
            <span
              class="relative mt-2 block h-5 bg-base-200"
              role="img"
              aria-label={"#{category.category}: #{money(category.amount)}"}
            >
              <span class="absolute inset-y-0 left-1/2 border-l border-base-300" aria-hidden="true"></span>
              <span
                class="absolute inset-y-0 bg-primary-500"
                style={"#{if negative?(category.amount), do: "right", else: "left"}: 50%; width: #{scale(category.amount, @maximum)}%"}
                aria-hidden="true"
              ></span>
            </span>
          </summary>
          <ul class="mt-3 space-y-2 pl-4">
            <li :for={account <- category.accounts}>
              <.link
                navigate={
                  ~p"/admin/economics/accounts/#{account.code}?#{%{period: @report.period["code"], from: @report.from, to: @report.to}}"
                }
                class="link link-primary"
              >{account.code} · {account.name} · {money(account.totals["expense"])}</.link>
            </li>
          </ul>
        </details>
      </div>
      <p class="mt-3 text-xs text-base-content/60">
        Střed = 0 Kč, krajní hodnoty ±{money(@maximum)}. Záporné opravy jsou vlevo od nuly.
      </p>
    </section>
    """
  end

  def maximum([]), do: "0"

  def maximum(values),
    do:
      values
      |> Enum.map(&(Decimal.new(&1) |> Decimal.abs()))
      |> Enum.max(Decimal)
      |> Decimal.to_string(:normal)

  def scale(value, maximum) do
    if Decimal.equal?(Decimal.new(maximum), 0),
      do: 0,
      else:
        value
        |> Decimal.new()
        |> Decimal.abs()
        |> Decimal.div(Decimal.new(maximum))
        |> Decimal.mult(48)
        |> Decimal.round(0)
        |> Decimal.to_integer()
  end

  defp negative?(value), do: Decimal.negative?(Decimal.new(value))

  defp signed_style(value, maximum),
    do:
      "#{if negative?(value), do: "top", else: "bottom"}: 50%; height: #{scale(value, maximum)}%"

  defp column_style(value, maximum, field),
    do:
      signed_style(value, maximum) <> "; #{if field == "revenue", do: "left", else: "right"}: 14%"
end

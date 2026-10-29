defmodule CozyCheckoutWeb.EconomicsLive.HomeComponents do
  use CozyCheckoutWeb, :html

  import CozyCheckoutWeb.EconomicsLive.Components,
    only: [money: 1, error: 1, document_identity: 1]

  def issues(nil), do: []
  def issues({:ok, data}), do: data.issues
  def issues({:error, reason}), do: [%{kind: :unavailable, reason: reason}]

  attr :issue, :map, required: true

  def attention_item(assigns) do
    ~H"""
    <li>
      <.link
        navigate={issue_path(@issue)}
        class="flex flex-wrap items-center justify-between gap-3 px-6 py-4 text-sm hover:bg-secondary-50"
        data-economics-issue={@issue.kind}
      >
        <div>
          <p class={[
            "font-semibold",
            if(@issue.kind in [:overdue_receivables, :overdue_payables],
              do: "text-error",
              else: "text-primary-500"
            )
          ]}>
            {issue_title(@issue)}
          </p><p class="mt-1 text-primary-400">
            {issue_detail(@issue)}
          </p>
        </div>
        <span class="font-medium text-tertiary-600">Zkontrolovat →</span>
      </.link>
    </li>
    """
  end

  attr :result, :any, required: true

  def cards(assigns) do
    data =
      case assigns.result do
        {:ok, data} -> data
        _ -> nil
      end

    assigns = assign(assigns, :data, data)

    ~H"""
    <section
      id="dashboard-economics"
      class="mb-7 space-y-3"
      aria-labelledby="dashboard-economics-title"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h2 id="dashboard-economics-title" class="text-lg font-semibold text-primary-500">
          Ekonomika firmy
        </h2><.link
          navigate={~p"/admin/economics"}
          class="text-sm font-semibold text-tertiary-600 hover:underline"
        >Otevřít ekonomiku →</.link>
      </div>
      <p class="text-xs text-primary-400">
        {if @data && @data.saldo,
          do:
            "Saldo k #{@data.saldo.date} · #{if @data.saldo.fresh, do: "dnešní údaje", else: "starší údaje"} · předběžné, čeká na účetní ověření",
          else: "Denní saldo zatím není dostupné. Chybějící hodnoty nejsou nula."}
      </p>
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <.card
          title="Výsledek potvrzeného měsíce"
          amount={@data && @data.result && @data.result.totals["result"]}
          path={result_path(@data)}
        >
          <p :if={@data && @data.result}>
            {String.slice(@data.result.month, 0, 7)} · účetní úplnost potvrzena
          </p>
          <p :if={@data && @data.result}>
            Výnosy {money(@data.result.totals["revenue"])} · náklady {money(
              @data.result.totals["expense"]
            )}
          </p>
          <p :if={!@data || !@data.result}>Zatím žádný potvrzený měsíc.</p>
        </.card>
        <.card
          title="Pohledávky po splatnosti"
          amount={@data && @data.saldo && @data.saldo.receivables.amount}
          path={~p"/admin/economics?saldo=receivables-overdue" <> "#economics-current-saldo"}
        >
          <p :if={@data && @data.saldo && @data.saldo.supported}>
            Počet dokladů: {@data.saldo.receivables.count} · předběžný stav
          </p>
          <p :if={@data && @data.saldo && @data.saldo.receivables.oldest_due}>
            Nejstarší splatnost {@data.saldo.receivables.oldest_due}
          </p>
        </.card>
        <.card
          title="Závazky do 14 dnů"
          amount={@data && @data.saldo && @data.saldo.payables.amount}
          path={~p"/admin/economics?saldo=payables-upcoming" <> "#economics-current-saldo"}
        >
          <p :if={@data && @data.saldo && @data.saldo.supported}>
            Počet dokladů: {@data.saldo.payables.count} · od {@data.saldo.date} do {@data.saldo.horizon}
          </p>
          <p>Již prošlé závazky najdete v upozorněních.</p>
        </.card>
        <.card
          title="Banka · účetní zůstatek"
          amount={@data && @data.bank && @data.bank.amount}
          path={bank_path(@data)}
        >
          <p :if={@data && @data.bank}>K {@data.bank.date}</p><p>
            Shoda s bankovním výpisem není potvrzena.
          </p>
        </.card>
      </div>
    </section>
    """
  end

  attr :saldo, :any, default: nil
  attr :focus, :string, default: "all"

  def current_saldo(assigns) do
    assigns =
      assign(
        assigns,
        :items,
        CozyCheckout.Economics.Attention.filter_items(assigns.saldo, assigns.focus)
      )

    ~H"""
    <section
      id="economics-current-saldo"
      class="rounded-xl border border-base-300 p-5"
      aria-labelledby="economics-current-saldo-title"
    >
      <h2 id="economics-current-saldo-title" class="text-xl font-semibold">
        Denní splatnosti · podklady k řešení
      </h2>
      <p :if={!@saldo} class="mt-3">Denní saldo dosud nebylo načteno. Spusťte aktualizaci z ABRY.</p>
      <div :if={@saldo} class="mt-3 space-y-4">
        <p>
          Stav k {@saldo.date}. Předběžné saldo čeká na účetní ověření; tento stav je oddělený od historického výběru měsíců.
        </p>
        <p :if={!@saldo.fresh} class="alert alert-warning">
          Zobrazený stav není dnešní. Od {@saldo.date} mohly přijít další úhrady. Aktualizujte údaje.
        </p>
        <p :if={!@saldo.supported} class="alert alert-warning">
          Některé částky nelze bezpečně určit. Souhrnné ukazatele nejsou dostupné.
        </p>
        <nav class="flex flex-wrap gap-2" aria-label="Filtr denních splatností">
          <.link
            :for={
              {focus, label} <- [
                {"all", "Všechny položky"},
                {"receivables-overdue", "Pohledávky po splatnosti"},
                {"payables-upcoming", "Závazky do 14 dnů"},
                {"payables-overdue", "Závazky po splatnosti"}
              ]
            }
            patch={~p"/admin/economics?#{%{saldo: focus}}" <> "#economics-current-saldo"}
            class={["btn btn-sm", @focus == focus && "btn-primary"]}
          >{label}</.link>
        </nav>
        <p :if={@focus == "payables-upcoming"} class="text-sm">
          Splatnost od {@saldo.date} do {@saldo.horizon}, včetně obou dnů.
        </p>
        <p :if={@items == []}>Pro tento výběr nejsou otevřené položky.</p>
        <div :if={@items != []} class="overflow-x-auto">
          <table id="economics-daily-items" class="table">
            <thead>
              <tr>
                <th>Druh</th><th>Firma a doklad · popis</th><th>Splatnost</th><th>Zbývalo k datu</th>
              </tr>
            </thead><tbody>
              <tr :for={item <- @items}>
                <td>{if item["kind"] == "receivable", do: "Pohledávka", else: "Závazek"}</td><td>
                  <.document_identity record={item} />
                </td><td>{item["due"] || "Splatnost neznámá"}</td><td>{money(item["amount"])}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="text-xs text-base-content/60">
          Záporné dobropisy zůstávají samostatné a nesnižují nesouvisející dluhy. Chybějící splatnosti nejsou zahrnuté do součtů podle termínu.
        </p>
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :amount, :any, default: nil
  attr :path, :string, required: true
  slot :inner_block

  defp card(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class="block rounded-xl border border-secondary-200 bg-white p-4 transition-colors hover:bg-secondary-50 focus-visible:outline-2 focus-visible:outline-tertiary-500"
    >
      <h3 class="text-sm text-primary-400">{@title}</h3><p class="mt-2 text-2xl font-semibold tabular-nums text-primary-500">
        {money(@amount)}
      </p><div class="mt-2 space-y-1 text-xs text-primary-400">{render_slot(@inner_block)}</div>
    </.link>
    """
  end

  defp bank_path(%{bank: %{period: code, date: date}}),
    do:
      ~p"/admin/economics?#{%{period: code, from: String.slice(date, 0, 7), to: String.slice(date, 0, 7)}}" <>
        "#economics-bank-accounts"

  defp bank_path(_), do: ~p"/admin/economics" <> "#economics-bank-accounts"

  defp result_path(%{result: %{period: code, month: month}}),
    do:
      ~p"/admin/economics?#{%{period: code, from: String.slice(month, 0, 7), to: String.slice(month, 0, 7)}}"

  defp result_path(_), do: ~p"/admin/economics/settings"

  defp issue_path(%{kind: :overdue_receivables}),
    do: ~p"/admin/economics?saldo=receivables-overdue" <> "#economics-current-saldo"

  defp issue_path(%{kind: :upcoming_payables}),
    do: ~p"/admin/economics?saldo=payables-upcoming" <> "#economics-current-saldo"

  defp issue_path(%{kind: :overdue_payables}),
    do: ~p"/admin/economics?saldo=payables-overdue" <> "#economics-current-saldo"

  defp issue_path(%{kind: :changed_months}),
    do: ~p"/admin/economics/settings" <> "#economics-confirmations"

  defp issue_path(_), do: ~p"/admin/economics/settings"

  defp issue_title(%{kind: :overdue_receivables, count: count, amount: amount}),
    do: "Pohledávky po splatnosti (#{count}) · #{money(amount)}"

  defp issue_title(%{kind: :upcoming_payables, count: count, amount: amount}),
    do: "Závazky splatné do 14 dnů (#{count}) · #{money(amount)}"

  defp issue_title(%{kind: :overdue_payables, count: count, amount: amount}),
    do: "Závazky po splatnosti (#{count}) · #{money(amount)}"

  defp issue_title(%{kind: :changed_months, count: count}),
    do: "Změna dříve potvrzených měsíců: #{count}"

  defp issue_title(%{kind: :import_failed}), do: "Poslední aktualizace ekonomiky selhala"
  defp issue_title(%{kind: :stale_saldo}), do: "Saldo není aktuální"
  defp issue_title(%{kind: :missing_saldo}), do: "Denní saldo zatím nebylo načteno"
  defp issue_title(%{kind: :unsupported_saldo}), do: "Částky salda vyžadují kontrolu"

  defp issue_title(%{kind: :unknown_due, count: count}),
    do: "Chybějící splatnost · počet dokladů: #{count}"

  defp issue_title(_), do: "Ekonomická data nejsou dostupná"

  defp issue_detail(%{kind: kind, date: date})
       when kind in [:overdue_receivables, :upcoming_payables, :overdue_payables],
       do: "Podle salda k #{date}. Předběžné údaje, bez započtení nesouvisejících dobropisů."

  defp issue_detail(%{kind: :stale_saldo, date: date}),
    do: "Poslední stav je k #{date}. Spusťte aktualizaci; mezitím mohly přijít úhrady."

  defp issue_detail(%{kind: :changed_months}),
    do: "Po kontrole změn znovu potvrďte účetní úplnost příslušných měsíců."

  defp issue_detail(%{kind: :import_failed}),
    do: "Přehled zachovává poslední úspěšná data. Zkontrolujte import a případně jej zopakujte."

  defp issue_detail(%{kind: :unsupported_saldo}),
    do:
      "Změněná hodnota dokladu brání spolehlivému součtu. Ukazatele se zobrazují jako nedostupné."

  defp issue_detail(%{kind: :unknown_due}),
    do:
      "Tyto položky nejsou zahrnuté do částek podle splatnosti. Zkontrolujte jejich podklady v ABŘE."

  defp issue_detail(%{kind: :unavailable, reason: reason}), do: error(reason)

  defp issue_detail(_),
    do: "Na stránce Zdroj a úplnost spusťte aktualizaci. Úvodní přehled ABRU přímo nevolá."
end

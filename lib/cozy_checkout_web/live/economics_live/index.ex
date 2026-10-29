defmodule CozyCheckoutWeb.EconomicsLive.Index do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Economics
  import CozyCheckoutWeb.EconomicsLive.Components

  @impl true
  def mount(_, _, socket) do
    if Economics.enabled?(),
      do: {:ok, assign(socket, page_title: "Ekonomika firmy")},
      else: {:ok, redirect(socket, to: ~p"/admin")}
  end

  @impl true
  def handle_params(params, _, socket), do: {:noreply, load(socket, params)}

  @impl true
  def handle_event("filter", %{"range" => range}, socket) do
    params = Map.reject(range, fn {_, value} -> value == "" end)

    current =
      socket.assigns.data && socket.assigns.data.snapshot &&
        socket.assigns.data.snapshot.period_code

    params = if params["period"] != current, do: Map.drop(params, ["from", "to"]), else: params
    {:noreply, push_patch(socket, to: ~p"/admin/economics?#{params}")}
  end

  def handle_event("import", _, socket) do
    case Economics.request_sync(socket.assigns.params["period"] || "current") do
      {:ok, _} ->
        {:noreply,
         socket
         |> load(socket.assigns.params)
         |> put_flash(:info, "Aktualizace zařazena. Po dokončení obnovte přehled.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error(reason))}
    end
  end

  def handle_event("reload", _, socket), do: {:noreply, load(socket, socket.assigns.params)}

  defp load(socket, params) do
    result = Economics.overview(params)

    data =
      case result do
        {:ok, data} -> data
        _ -> nil
      end

    report = data && data.report

    range = %{
      "period" => params["period"] || (data && data.snapshot && data.snapshot.period_code) || "",
      "from" => params["from"] || (report && report[:from]) || "",
      "to" => params["to"] || (report && report[:to]) || ""
    }

    assign(socket,
      params: params,
      data: data,
      report: report,
      range: to_form(range, as: :range),
      connection: Economics.connection_info(),
      error:
        case result do
          {:error, reason} -> reason
          _ -> nil
        end
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      content_class="mx-auto w-full max-w-7xl space-y-6"
      main_class="px-4 py-6 sm:px-6 lg:px-8"
    >
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-3xl font-bold">Ekonomika firmy</h1><p class="mt-2 text-base-content/70">
            Výnosy, náklady a účetní výsledek celé firmy z ABRY.
          </p>
        </div>
        <div class="flex gap-2">
          <button
            id="economics-import"
            phx-click="import"
            class="btn btn-primary"
            disabled={!@connection.configured}
          >Aktualizovat z ABRY</button><button phx-click="reload" class="btn btn-outline">Obnovit přehled</button>
        </div>
      </div>
      <.navigation />
      <p class="text-sm text-base-content/70">
        Zdroj: {@connection.host || "nenastaveno"} / {@connection.company || "nenastaveno"}. Pouze čtení účetnictví.
      </p>
      <p :if={@error} id="economics-error" class="alert alert-warning">{error(@error)}</p>
      <p
        :if={@data}
        id="economics-import-state"
        role="status"
        class={["alert", @data.latest_run && @data.latest_run.state == "failed" && "alert-warning"]}
      >
        {run_label(@data.latest_run)}
      </p>
      <.form
        :if={@data && @data.periods != []}
        for={@range}
        id="economics-range"
        phx-submit="filter"
        class="grid gap-4 rounded-xl bg-base-200 p-4 sm:grid-cols-4"
      >
        <.input
          field={@range[:period]}
          type="select"
          label="Hospodářský rok"
          options={Enum.map(@data.periods, &{&1.code, &1.code})}
        />
        <.input field={@range[:from]} type="month" label="Od měsíce" />
        <.input field={@range[:to]} type="month" label="Do měsíce" />
        <button class="btn btn-primary self-end" type="submit">Zobrazit</button>
      </.form>
      <p :if={@data && !@data.snapshot} class="alert alert-warning">
        Pro vybrané období zatím není úspěšný snapshot. Spusťte aktualizaci nebo vyberte již načtený rok.
      </p>
      <p :if={@report && @report[:error]} class="alert alert-warning">{error(@report.error)}</p>
      <div :if={@report && !@report[:error]} id="economics-report" class="space-y-6">
        <div class="rounded-xl border border-base-300 p-4 text-sm space-y-2">
          <p>
            <strong>Období: {hd(@report.months)["from"]} – {List.last(@report.months)["to"]}</strong>
            · Hospodářský rok {@report.period["from"]} – {@report.period["to"]}
          </p>
          <p>
            Data zkontrolována: {@report.checked_at} (UTC). MD/Dal souhlasí s předvahou po jednotlivých účtech.
          </p>
          <p id="economics-completeness">
            Účetní úplnost: {Enum.count(@report.confirmations, & &1.confirmed)} z {length(
              @report.confirmations
            )} vybraných měsíců potvrzeno. Shoda ani čerstvost nenahrazují potvrzení účetní.
          </p>
          <p>
            Účetní výsledek zahrnuje zaúčtované náklady včetně nedaňových a odpisů. Nevyjadřuje příjmy a výdaje peněz. Srovnání před červencem 2026 není dostupné.
          </p>
        </div>
        <p :for={finding <- @report.warnings} class="alert alert-warning">{warning(finding)}</p>
        <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          <.metric
            title="Tržby"
            value={@report.totals["sales"]}
            explanation="Ubytování a stravování, bar a pronájem; rozdělení je v účtech níže."
          />
          <.metric
            title="Další výnosy"
            value={@report.totals["other_revenue"]}
            explanation="Ostatní výnosové účty mimo uvedené tržby."
          />
          <.metric
            title="Náklady"
            value={@report.totals["expense"]}
            explanation="MD minus Dal všech nákladových účtů, včetně odpisů."
          />
          <.metric
            title="Účetní výsledek"
            value={@report.totals["result"]}
            explanation="Veškeré výnosy minus náklady podle zahrnutých účtů; před/po dani dosud nepotvrzeno."
          />
          <.metric
            title="Banka · účetní zůstatek"
            value={@report.ledger_totals["221"]}
            explanation="K poslednímu dni výběru. Počátky a shoda s bankovním výpisem čekají na ověření."
            status="Neověřený stav banky"
          />
          <.metric
            title="Hotovost · účetní zůstatek"
            value={@report.ledger_totals["211"]}
            explanation="Součet účetních analytik. Vztah pokladen a skutečná fyzická hotovost nejsou ověřené."
            status="Neověřený stav hotovosti"
          />
          <.metric
            title="Neuhrazené pohledávky"
            value={@report.open_totals && @report.open_totals["receivable"]["total"]}
            explanation="K poslednímu dni výběru, bez započtení nesouvisejících dobropisů."
            status="Předběžné historické saldo"
          />
          <.metric
            title="Neuhrazené závazky"
            value={@report.open_totals && @report.open_totals["payable"]["total"]}
            explanation="K poslednímu dni výběru, včetně starších otevřených položek."
            status="Předběžné historické saldo"
          />
        </div>
        <section class="rounded-xl border border-base-300 p-5">
          <h2 class="text-xl font-semibold">Měsíční vývoj</h2>
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Měsíc</th><th>Výnosy</th><th>Náklady</th><th>Výsledek</th><th>
                    Nezaúčtované pohyby
                  </th>
                </tr>
              </thead><tbody>
                <tr :for={month <- @report.months}>
                  <td>{String.slice(month["from"], 0, 7)}</td>
                  <td>
                    <span>{money(month["totals"]["revenue"])}</span><div
                      class="mt-1 h-1.5 rounded bg-primary"
                      style={"width: #{bar_width(month["totals"]["revenue"], @report.months)}%"}
                    >
                    </div>
                  </td>
                  <td>
                    <span>{money(month["totals"]["expense"])}</span><div
                      class="mt-1 h-1.5 rounded bg-warning"
                      style={"width: #{bar_width(month["totals"]["expense"], @report.months)}%"}
                    >
                    </div>
                  </td>
                  <td class="font-semibold">{money(month["totals"]["result"])}</td>
                  <td>
                    {month["unposted_count"]}<span
                      :if={month["unposted_count"] > 0}
                      class="block text-xs"
                    >Předběžný výsledek nezaúčtovaných: {money(
                      month["preliminary_totals"] && month["preliminary_totals"]["result"]
                    )}</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
        <section class="rounded-xl border border-base-300 p-5">
          <h2 class="text-xl font-semibold">Výnosy a rozpad nákladů</h2><p class="mt-2 text-sm">
            Mapování kategorií je pracovní návrh. Společné náklady nejsou rozdělené odhadem.
          </p>
          <div class="overflow-x-auto">
            <table id="economics-accounts" class="table">
              <thead>
                <tr>
                  <th>Účet</th><th>Název</th><th>Kategorie</th><th>Výnosy</th><th>Náklady</th>
                </tr>
              </thead><tbody>
                <tr :for={account <- @report.accounts}>
                  <td>
                    <.link
                      navigate={
                        ~p"/admin/economics/accounts/#{account.code}?#{%{period: @data.snapshot.period_code, from: @report.from, to: @report.to}}"
                      }
                      class="link link-primary"
                    >{account.code}</.link>
                  </td>
                  <td>{account.name}</td><td>{account.category}</td><td>
                    {money(account.totals["revenue"])}
                  </td><td>{money(account.totals["expense"])}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
        <section class="rounded-xl border border-base-300 p-5">
          <h2 class="text-xl font-semibold">Banka a hotovost · podkladové účty</h2>
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Účet</th><th>Název</th><th>Počátek posledního měsíce</th><th>Konec výběru</th>
                </tr>
              </thead><tbody>
                <tr :for={balance <- @report.balances}>
                  <td>{balance["account"]}</td><td>{balance["name"]}</td><td>
                    {money(balance["opening"])}
                  </td><td>{money(balance["closing"])}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={@report.balances == []} class="mt-3">
            Bankovní ani pokladní účty nejsou dostupné. Jejich stav nelze pokládat za nulu.
          </p>
        </section>
        <section class="rounded-xl border border-base-300 p-5">
          <h2 class="text-xl font-semibold">Splatnosti a historické saldo</h2>
          <p class="my-3 text-sm">
            Předběžný stav k {List.last(@report.months)["to"]}. Částečné úhrady, dobropisy a převod starších dluhů vyžadují účetní ověření.
          </p>
          <div :if={@report.open_totals} class="grid gap-3 sm:grid-cols-2">
            <p>
              Pohledávky po splatnosti:
              <strong>{money(@report.open_totals["receivable"]["due"])}</strong><br />Oddělené dobropisy: {money(
                @report.open_totals["receivable"]["credits"]
              )}
            </p>
            <p>
              Závazky po splatnosti:
              <strong>{money(@report.open_totals["payable"]["due"])}</strong><br />Oddělené dobropisy: {money(
                @report.open_totals["payable"]["credits"]
              )}
            </p>
          </div>
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Druh</th><th>Reference ABRA</th><th>Splatnost</th><th>Zbývalo k datu</th>
                </tr>
              </thead><tbody>
                <tr
                  :for={item <- Enum.sort_by(@report.open_items, &(&1["due"] || "9999"))}
                  :if={item["amount"] != "0"}
                >
                  <td>{if item["kind"] == "receivable", do: "Pohledávka", else: "Závazek"}</td><td>
                    {item["module"]} / {item["document_id"]}
                  </td><td>{item["due"] || "Splatnost neznámá"}</td><td>{money(item["amount"])}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end

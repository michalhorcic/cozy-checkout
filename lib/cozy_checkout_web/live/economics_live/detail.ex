defmodule CozyCheckoutWeb.EconomicsLive.Detail do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Economics
  import CozyCheckoutWeb.EconomicsLive.Components

  @impl true
  def mount(_, _, socket) do
    if Economics.enabled?(),
      do: {:ok, assign(socket, page_title: "Účetní pohyby")},
      else: {:ok, redirect(socket, to: ~p"/admin")}
  end

  @impl true
  def handle_params(%{"account" => code} = params, _, socket) do
    case Economics.account_detail(params, code) do
      {:ok, detail} ->
        {:noreply,
         assign(socket,
           detail: detail,
           error: nil,
           params: Map.take(params, ["period", "from", "to"])
         )}

      {:error, reason} ->
        {:noreply, assign(socket, detail: nil, error: reason, params: %{})}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      content_class="mx-auto w-full max-w-7xl space-y-6"
      main_class="px-4 py-6 sm:px-6 lg:px-8"
    >
      <.link navigate={~p"/admin/economics?#{@params}"} class="btn btn-sm btn-outline">Zpět na ekonomiku</.link>
      <p :if={@error} class="alert alert-warning">{error(@error)}</p>
      <div :if={@detail} class="space-y-4">
        <h1 class="text-3xl font-bold">{@detail.code} · {@detail.account}</h1>
        <p>
          Zaúčtované pohyby {hd(@detail.report.months)["from"]} – {List.last(@detail.report.months)[
            "to"
          ]}. Zdroj: ABRA, místní snapshot.
        </p>
        <p class="alert">
          Částky MD a Dal jsou účetní zápisy. Účetní úplnost období a skutečné peněžní stavy se potvrzují samostatně.
        </p>
        <div class="overflow-x-auto">
          <table id="economics-movements" class="table">
            <thead>
              <tr>
                <th>Datum účtování</th><th>Modul / doklad</th><th>Zápis ABRA</th><th>MD</th><th>
                  Dal
                </th>
              </tr>
            </thead><tbody>
              <tr :for={row <- Enum.sort_by(@detail.rows, &{&1["date"], &1["journal_id"]})}>
                <td>{row["date"]}</td><td>{row["module"]} / {row["document_id"]}</td><td>
                  {row["journal_id"]}
                </td><td>{money(row["md"])}</td><td>{money(row["dal"])}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

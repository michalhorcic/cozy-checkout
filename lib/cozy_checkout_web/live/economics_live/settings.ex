defmodule CozyCheckoutWeb.EconomicsLive.Settings do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Economics
  import CozyCheckoutWeb.EconomicsLive.Components

  @impl true
  def mount(_, _, socket) do
    if Economics.enabled?(),
      do: {:ok, assign(socket, page_title: "Zdroj a úplnost ekonomiky")},
      else: {:ok, redirect(socket, to: ~p"/admin")}
  end

  @impl true
  def handle_params(params, _, socket), do: {:noreply, load(socket, params)}

  @impl true
  def handle_event("import", %{"import" => params}, socket) do
    case Economics.request_sync(params["period"] || "current") do
      {:ok, _} ->
        {:noreply,
         socket
         |> load(socket.assigns.params)
         |> put_flash(:info, "Import zařazen. Po dokončení obnovte přehled.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error(reason))}
    end
  end

  def handle_event("confirm", %{"confirmation" => attrs}, socket) do
    snapshot_id =
      socket.assigns.data && socket.assigns.data.snapshot && socket.assigns.data.snapshot.id

    if snapshot_id do
      case Economics.confirm_month(snapshot_id, attrs["month"] || "", attrs["evidence"] || "") do
        {:ok, _} ->
          {:noreply,
           socket
           |> load(socket.assigns.params)
           |> put_flash(:info, "Účetní úplnost měsíce potvrzena pro tuto verzi dat.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, error(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Nejprve načtěte účetní data.")}
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

    assign(socket,
      params: params,
      data: data,
      report: data && data.report,
      connection: Economics.connection_info(),
      mapping: Economics.mapping(),
      import_form: to_form(%{"period" => params["period"] || "current"}, as: :import),
      confirmation: to_form(%{"month" => "", "evidence" => ""}, as: :confirmation),
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
      content_class="mx-auto w-full max-w-5xl space-y-6"
      main_class="px-4 py-6 sm:px-6 lg:px-8"
    >
      <h1 class="text-3xl font-bold">Zdroj a úplnost ekonomiky</h1>
      <.navigation active="settings" />
      <section class="rounded-xl border border-base-300 p-5 space-y-3">
        <h2 class="text-xl font-semibold">Zdroj dat ABRA</h2>
        <p>
          Server: <strong>{@connection.host || "nenastaveno"}</strong><br />Firma:
          <strong>{@connection.company || "nenastaveno"}</strong>
        </p>
        <p>
          Připojení: {if @connection.configured, do: "Nastavené", else: "Neúplná konfigurace"}. Přístup je pouze pro čtení.
        </p>
        <p class="text-sm">
          Změna serveru či firmy v konfiguraci oddělí data od předchozího zdroje. Přístupové údaje se v aplikaci nezobrazují.
        </p>
        <.form
          for={@import_form}
          id="economics-import-period"
          phx-submit="import"
          class="flex flex-wrap items-end gap-3"
        >
          <.input
            field={@import_form[:period]}
            label="Kód období v ABŘE (current = aktuální)"
            required
          />
          <button class="btn btn-primary" disabled={!@connection.configured} type="submit">Načíst celé období</button>
          <button class="btn btn-outline" type="button" phx-click="reload">Obnovit přehled</button>
        </.form>
        <p class="text-sm">
          První sledované období začíná 1. 7. 2026. Hranice roku se přebírají z ABRY. Denní načtení probíhá ve 04:00 UTC; výpadek zachová poslední úspěšnou verzi.
        </p>
        <p :if={@error} class="alert alert-warning">{error(@error)}</p>
        <p :if={@data} role="status" class="alert">{run_label(@data.latest_run)}</p>
      </section>
      <section :if={@data && @data.periods != []} class="rounded-xl border border-base-300 p-5">
        <h2 class="text-xl font-semibold">Načtená období</h2>
        <div class="mt-3 flex flex-wrap gap-2">
          <.link
            :for={period <- @data.periods}
            patch={~p"/admin/economics/settings?#{%{period: period.code}}"}
            class="btn btn-sm"
          >{period.code}</.link>
        </div>
      </section>
      <section
        :if={@report && !@report[:error]}
        class="rounded-xl border border-base-300 p-5 space-y-4"
      >
        <h2 class="text-xl font-semibold">Potvrzení účetní úplnosti</h2>
        <p>
          Období {@report.period["from"]} – {@report.period["to"]}. Potvrzujte po dohodě s účetní včetně mezd, odpisů a časového rozlišení. Změna dat měsíce vyžaduje nové potvrzení.
        </p>
        <p class="alert alert-warning">
          Potvrzení úplnosti neověřuje bankovní zůstatek, fyzickou hotovost ani historické saldo a neuzamyká účetnictví v ABŘE.
        </p>
        <table id="economics-confirmations" class="table">
          <thead>
            <tr>
              <th>Měsíc</th><th>Úplnost</th><th>Podklad a čas potvrzení</th>
            </tr>
          </thead><tbody>
            <tr :for={confirmation <- @report.confirmations}>
              <td>{String.slice(confirmation.month, 0, 7)}</td><td>
                {if confirmation.confirmed, do: "Potvrzeno", else: "Neověřeno"}
              </td><td>
                {confirmation.evidence}<span :if={confirmation.confirmed} class="block text-xs">{confirmation.confirmed_at} UTC</span>
              </td>
            </tr>
          </tbody>
        </table>
        <.form for={@confirmation} id="economics-confirm-form" phx-submit="confirm" class="space-y-3">
          <.input
            field={@confirmation[:month]}
            type="select"
            label="Ukončený měsíc"
            prompt="Vyberte měsíc"
            options={
              Enum.filter(
                @report.confirmations,
                &(Date.compare(Date.end_of_month(Date.from_iso8601!(&1.month)), Date.utc_today()) ==
                    :lt)
              )
              |> Enum.map(&{String.slice(&1.month, 0, 7), &1.month})
            }
          />
          <.input
            field={@confirmation[:evidence]}
            type="textarea"
            label="Podklad potvrzení po dohodě s účetní"
            minlength="10"
            maxlength="1000"
            required
          />
          <button class="btn btn-primary" type="submit">Potvrdit úplnost měsíce</button>
        </.form>
      </section>
      <section class="rounded-xl border border-base-300 p-5">
        <h2 class="text-xl font-semibold">Mapování účtů · verze 1</h2>
        <p class="my-3 text-sm">
          Pracovní návrh kategorií čeká na účetní potvrzení. Druh účtu v ABŘE rozhoduje o zahrnutí do výsledku. Další účty zůstávají v kategorii Nezařazeno.
        </p>
        <table class="table">
          <thead>
            <tr>
              <th>Účet</th><th>Kategorie</th>
            </tr>
          </thead><tbody>
            <tr :for={{code, category} <- @mapping}>
              <td>{code}</td><td>{category}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.app>
    """
  end
end

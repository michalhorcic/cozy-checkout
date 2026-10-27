defmodule CozyCheckoutWeb.BillingLive.Seasons do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Billing
  alias CozyCheckout.Billing.Season
  alias CozyCheckoutWeb.BillingLive.Helpers

  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Ceník ubytování",
       month: Date.beginning_of_month(Billing.today()),
       editing: nil,
       form: to_form(Season.changeset(%Season{}, %{}))
     )
     |> refresh()}
  end

  def handle_event("month", %{"month" => month}, socket) do
    case Date.from_iso8601(month <> "-01") do
      {:ok, date} -> {:noreply, socket |> assign(:month, date) |> refresh()}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    season = Billing.get_season!(id)
    {:noreply, assign(socket, editing: id, form: to_form(Season.changeset(season, %{})))}
  end

  def handle_event("cancel", _, socket), do: {:noreply, reset(socket)}
  def handle_event("copy", %{"id" => id}, socket), do: result(Billing.copy_season(id), socket)
  def handle_event("delete", %{"id" => id}, socket), do: result(Billing.delete_season(id), socket)

  def handle_event("save", %{"season" => attrs}, socket),
    do: result(Billing.save_season(attrs, socket.assigns.editing), socket)

  defp result({:ok, _}, socket),
    do: {:noreply, socket |> reset() |> refresh() |> put_flash(:info, "Ceník uložen")}

  defp result({:error, %Ecto.Changeset{} = cs}, socket),
    do: {:noreply, assign(socket, :form, to_form(cs))}

  defp result({:error, error}, socket),
    do: {:noreply, put_flash(socket, :error, Helpers.error(error))}

  defp reset(socket),
    do: assign(socket, editing: nil, form: to_form(Season.changeset(%Season{}, %{})))

  defp refresh(socket) do
    seasons = Billing.list_seasons()
    month = socket.assigns.month
    first = Date.add(month, 1 - Date.day_of_week(month))

    days =
      Date.range(first, Date.add(first, 41))
      |> Enum.map(fn date ->
        season =
          Enum.find(
            seasons,
            &(Date.compare(date, &1.valid_from) != :lt and Date.compare(date, &1.valid_to) != :gt)
          )

        %{date: date, season: season, current: date.month == month.month}
      end)

    assign(socket, seasons: seasons, days: days)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      content_class="mx-auto w-full max-w-7xl space-y-6"
      main_class="px-4 py-6 sm:px-6 lg:px-8 lg:py-8"
    >
      <div class="max-w-6xl mx-auto space-y-6">
        <h1 class="text-3xl font-bold">Ceník ubytování s polopenzí</h1>
        <p>
          Ceny za osobu a noc včetně DPH. Pro celý pobyt se použije datum příjezdu. Změna ceníku nepřecení uložené rezervace.
        </p>
        <form phx-change="month" id="season-month">
          <label for="month">Měsíc</label><input
            class="input ml-3"
            id="month"
            type="month"
            name="month"
            value={Calendar.strftime(@month, "%Y-%m")}
          />
        </form>
        <div class="grid grid-cols-7 gap-1" id="season-calendar">
          <div :for={day <- ~w(Po Út St Čt Pá So Ne)} class="text-center font-bold">{day}</div>
          <div
            :for={day <- @days}
            class={[
              "rounded p-2 min-h-20 text-xs",
              !day.current && "opacity-40",
              if(day.season, do: "bg-emerald-50", else: "bg-amber-100")
            ]}
          >
            <b>{Calendar.strftime(day.date, "%d.%m.")}</b>
            <p>{if day.season, do: day.season.name, else: "Chybí cena"}</p>
            <p :if={day.season}>{format_currency(day.season.adult)}</p>
          </div>
        </div>
        <div class="overflow-x-auto bg-white rounded-xl">
          <table class="table">
            <thead>
              <tr>
                <th>Sezona</th><th>Od–do (včetně)</th><th>Dospělí</th><th>Do 2 let</th><th>
                  Do 12 let
                </th><th>DPH</th><th></th>
              </tr>
            </thead><tbody>
              <tr :for={s <- @seasons}>
                <td>{s.name}</td><td>{s.valid_from} – {s.valid_to}</td><td>
                  {format_currency(s.adult)}
                </td><td>{format_currency(s.infant)}</td><td>{format_currency(s.child)}</td><td>
                  {s.vat_rate}%
                </td><td class="flex gap-2">
                  <button class="btn btn-sm" phx-click="edit" phx-value-id={s.id}>Upravit</button><button
                    class="btn btn-sm"
                    phx-click="copy"
                    phx-value-id={s.id}
                  >Kopie +1 rok</button><button
                    class="btn btn-sm"
                    phx-click="delete"
                    phx-value-id={s.id}
                    data-confirm="Odstranit sezonu? Uložené ceny rezervací zůstanou zachované."
                  >Odstranit</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <.form
          for={@form}
          id="season-form"
          phx-submit="save"
          class="bg-white p-6 rounded-xl grid md:grid-cols-3 gap-4"
        >
          <h2 class="text-xl font-bold md:col-span-3">
            {if @editing, do: "Upravit sezonu", else: "Nová sezona"}
          </h2>
          <.input field={@form[:name]} label="Název" required />
          <.input field={@form[:valid_from]} type="date" label="Platí od" required />
          <.input field={@form[:valid_to]} type="date" label="Platí do (včetně)" required />
          <.input
            :for={
              {key, label} <- [
                {:adult, "Dospělí"},
                {:infant, "Děti do 2 let"},
                {:child, "Děti do 12 let"}
              ]
            }
            field={@form[key]}
            type="number"
            min="0"
            step="0.01"
            label={label}
            required
          />
          <.input
            field={@form[:vat_rate]}
            type="select"
            label="DPH"
            options={[{"12 %", "12"}, {"21 %", "21"}, {"0 %", "0"}]}
          />
          <button class="btn btn-primary">Uložit sezonu</button><button
            type="button"
            class="btn"
            phx-click="cancel"
          >Zrušit úpravy</button>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end

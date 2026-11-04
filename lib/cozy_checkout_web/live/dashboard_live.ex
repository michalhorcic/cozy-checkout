defmodule CozyCheckoutWeb.DashboardLive do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.{Dashboard, Economics}
  alias CozyCheckoutWeb.EconomicsLive.HomeComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_overview(socket)}
  end

  @impl true
  def handle_info(:refresh_overview, socket), do: {:noreply, load_overview(socket)}

  defp load_overview(socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_overview, 60_000)
    economic_overview = if Economics.enabled?(), do: Economics.home_summary()
    overview = Dashboard.overview()

    assign(socket,
      page_title: "Přehled",
      overview: overview,
      booking_issues: Enum.group_by(overview.issues, & &1.booking.id),
      economic_overview: economic_overview,
      economic_issues: HomeComponents.issues(economic_overview)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      main_class="px-4 py-6 sm:px-6 lg:px-8 lg:py-8"
      content_class="mx-auto max-w-7xl"
    >
      <div id="operations-dashboard">
        <header class="mb-7 flex flex-wrap items-end justify-between gap-4">
          <div>
            <p class="mb-1 text-sm text-primary-400">Jindřichův dům · {date(@overview.today)}</p>
            <h1 class="text-3xl font-bold tracking-tight text-primary-500">Přehled provozu</h1>
          </div>
          <.link
            id="new-booking"
            navigate={~p"/admin/bookings/new"}
            class="inline-flex min-h-11 items-center gap-2 rounded-lg bg-primary-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-primary-600"
          >
            <.icon name="hero-plus" class="h-4 w-4" />Nová rezervace
          </.link>
        </header>

        <section
          :if={@overview.issues != [] || @economic_issues != []}
          id="dashboard-attention"
          aria-labelledby="attention-heading"
          class="mb-7 overflow-hidden rounded-2xl border border-warning bg-white shadow-sm"
        >
          <div class="flex items-center gap-3 border-b border-secondary-100 px-6 py-4">
            <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-warning" />
            <h2 id="attention-heading" class="font-semibold text-primary-500">
              Vyžaduje pozornost
              <span class="ml-2 text-sm font-normal text-primary-400">{length(@overview.issues) +
                length(@economic_issues)}</span>
            </h2>
          </div>
          <p class="px-6 pt-3 text-xs text-primary-400">
            Provozní a ekonomické úkoly s odkazy na podklady
          </p>
          <ul class="divide-y divide-secondary-100">
            <HomeComponents.attention_item :for={issue <- @economic_issues} issue={issue} />
            <li :for={issue <- @overview.issues}>
              <.link
                id={"dashboard-issue-#{issue.kind}-#{issue.booking.id}"}
                navigate={issue_path(issue)}
                class="flex flex-wrap items-center justify-between gap-2 px-6 py-4 text-sm hover:bg-secondary-50"
              >
                <div>
                  <span
                    class="font-semibold text-primary-500">{issue.booking.guest.name}</span><span
                    class="ml-2 text-xs text-primary-400">{date(
                    issue.booking.check_in_date
                  )}</span><p class="mt-1 text-primary-400">{issue.reason}</p>
                </div>
                <span class="font-medium text-tertiary-600">{if issue.kind == :details,
                  do: "Doplnit údaje",
                  else: "Zkontrolovat menu"} →</span>
              </.link>
            </li>
          </ul>
        </section>

        <div class="mb-7 grid gap-3 sm:grid-cols-3">
          <.summary
            label="Dnešní příjezdy"
            value={@overview.arrivals}
            detail="rezervací"
            icon="hero-arrow-right-end-on-rectangle"
          />
          <.summary
            label="Dnešní odjezdy"
            value={@overview.departures}
            detail="rezervací"
            icon="hero-arrow-right-start-on-rectangle"
          />
          <.summary
            label="Dnešní obsazenost"
            value={@overview.occupancy}
            detail={"z #{@overview.capacity} osob · dle pobytových položek"}
            icon="hero-user-group"
          />
        </div>

        <div class="mb-7 grid items-start gap-6 xl:grid-cols-[minmax(0,1fr)_20rem]">
          <section
            aria-labelledby="stays-heading"
            class="overflow-hidden rounded-2xl border border-secondary-200 bg-white shadow-sm"
          >
            <div class="flex flex-wrap items-start justify-between gap-3 border-b border-secondary-100 p-5 sm:p-6">
              <div>
                <h2 id="stays-heading" class="text-lg font-semibold text-primary-500">
                  Časová osa skupin
                </h2>
                <p class="mt-1 text-sm text-primary-400">
                  {date(@overview.today)} – {date(@overview.last_date)} · pokoje a připravenost menu
                </p>
              </div>
              <.link
                id="open-calendar"
                navigate={~p"/admin/bookings/calendar"}
                class="inline-flex min-h-11 items-center gap-2 text-sm font-semibold text-tertiary-600 hover:underline"
              >
                <.icon name="hero-calendar-days" class="h-4 w-4" />Kalendář
              </.link>
            </div>
            <div :if={@overview.bookings == []} id="stays-empty" class="px-6 py-12 text-center">
              <.icon name="hero-calendar-days" class="mb-3 h-9 w-9 text-secondary-400" />
              <p class="font-medium text-primary-500">Na následující měsíc tu nejsou žádné pobyty.</p>
              <p class="mt-1 text-sm text-primary-400">Novou rezervaci přidáte tlačítkem nahoře.</p>
            </div>
            <div
              id="dashboard-stays"
              class="overflow-x-auto"
              tabindex="0"
              aria-label="Časová osa skupin, vodorovně posuvná">
              <table :if={@overview.bookings != []} class="w-full border-collapse text-sm">
                <caption class="sr-only">Pobyty podle skupin. Příj. značí příjezd, Odj. odjezd, bod pobyt.</caption>
                <thead>
                  <tr>
                    <th
                      scope="col"
                      class="sticky left-0 z-20 min-w-56 bg-white p-4 text-left text-primary-500">Skupina a příprava</th>
                    <th
                      :for={day <- Date.range(@overview.today, @overview.last_date)}
                      scope="col"
                      class={["min-w-12 border-l border-secondary-100 p-2 text-center text-xs", if(day == @overview.today, do: "bg-tertiary-100 text-tertiary-800", else: "bg-secondary-50 text-primary-400")]}>
                      <span class="block">{Calendar.strftime(day, "%d.%m.")}</span>
                      <span :if={day == @overview.today} class="block">Dnes</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={booking <- @overview.bookings}
                    id={"dashboard-booking-#{booking.id}"}
                    class="border-t border-secondary-200">
                    <th scope="row" class="sticky left-0 z-10 bg-white p-4 text-left font-normal">
                      <.link
                        navigate={~p"/admin/bookings/#{booking.id}"}
                        class="font-semibold text-primary-500 hover:text-tertiary-700 hover:underline">{booking.guest.name}</.link>
                      <p class="mt-1 text-xs text-primary-400">{date(booking.check_in_date)} – {date(booking.check_out_date)}</p>
                      <p class="mt-1 text-xs text-primary-400">{stay_label(booking, @overview.today)} · {CozyCheckout.Bookings.people_count(booking)} osob</p>
                      <p
                        :if={booking.check_in_date == @overview.today}
                        class="mt-1 text-xs font-semibold text-success-dark">Dnes příjezd</p>
                      <p
                        :if={booking.check_out_date == @overview.today}
                        class="mt-1 text-xs font-semibold text-tertiary-800">Dnes odjezd</p>
                      <.link
                        navigate={~p"/admin/bookings/#{booking.id}"}
                        class="mt-2 block text-xs text-tertiary-700 hover:underline">{rooms(booking)}</.link>
                      <.link
                        navigate={~p"/admin/bookings/#{booking.id}/menu"}
                        class={["mt-2 block text-xs hover:underline", if(menu_ready?(booking, Map.get(@booking_issues, booking.id, [])), do: "text-success-dark", else: "text-error")]}>{menu_label(booking, Map.get(@booking_issues, booking.id, []))}</.link>
                      <p :if={booking.short_note} class="mt-2 text-xs text-primary-400">{booking.short_note}</p>
                    </th>
                    <td
                      :for={day <- Date.range(@overview.today, @overview.last_date)}
                      class={["border-l border-secondary-100 p-0 text-center text-xs", if(day == @overview.today, do: "bg-tertiary-50")]}>
                      <.link
                        :if={spans_date?(booking, day)}
                        navigate={~p"/admin/bookings/#{booking.id}"}
                        aria-label={"#{booking.guest.name} · #{date(day)} · #{timeline_label(booking, day)}"}
                        class={["flex min-h-11 items-center justify-center font-medium hover:brightness-95", timeline_color(booking, day)]}>
                        {timeline_label(booking, day)}
                      </.link>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="border-t border-secondary-100 px-6 py-4">
              <.link
                navigate={~p"/admin/bookings"}
                class="text-sm font-medium text-tertiary-600 hover:underline"
              >Všechny rezervace →</.link>
            </div>
          </section>

          <div class="space-y-5">
            <section
              aria-labelledby="food-heading"
              class="rounded-2xl border border-secondary-200 bg-white p-5 shadow-sm sm:p-6"
            >
              <div class="mb-4 flex items-center gap-3">
                <span class="rounded-xl bg-secondary-100 p-2.5"><.icon
                  name="hero-clipboard-document-list"
                  class="h-5 w-5 text-primary-500"
                /></span>
                <div>
                  <h2 id="food-heading" class="font-semibold text-primary-500">Stravování</h2><p class="text-xs text-primary-400">
                    Dnešní porce
                  </p>
                </div>
              </div>
              <dl
                id="today-portions"
                class="mb-4 grid grid-cols-3 gap-2 rounded-xl bg-secondary-50 p-3"
              >
                <div :for={
                  {type, title} <- [
                    {"breakfast", "Snídaně"},
                    {"lunch", "Obědy"},
                    {"dinner", "Večeře"}
                  ]
                }>
                  <dt class="text-xs text-primary-400">{title}</dt><dd
                    id={"dashboard-#{type}"}
                    class="mt-1 text-xl font-semibold text-primary-500"
                  >
                    {@overview.portions[type].total}
                  </dd>
                </div>
              </dl>
              <p
                :if={@overview.portions.incomplete_bookings != []}
                id="portions-incomplete"
                class="mb-4 rounded-lg bg-warning-light px-3 py-2 text-xs text-primary-500"
              >
                Počty jsou neúplné. U některých pobytů chybí údaje o stravování.
              </p>
              <.action
                id="open-meal-planner"
                path={~p"/admin/meal-planner"}
                label="Plán jídel"
                icon="hero-calendar-days"
              />
              <.action
                id="open-kitchen-shopping"
                path={~p"/admin/kitchen-shopping"}
                label="Nákup pro kuchyň"
                icon="hero-shopping-cart"
              />
            </section>
            <section
              aria-labelledby="bar-heading"
              class="rounded-2xl border border-secondary-200 bg-white p-5 shadow-sm sm:p-6"
            >
              <h2 id="bar-heading" class="mb-2 font-semibold text-primary-500">Barový sklad</h2>
              <p class="mb-4 text-sm leading-relaxed text-primary-400">
                Zásoby na baru, doplnění a evidence spotřeby.
              </p>
              <.action
                id="open-bar-stock"
                path={~p"/admin/bar-stock"}
                label="Otevřít barový sklad"
                icon="hero-beaker"
              />
            </section>
            <div class="px-1">
              <.action
                id="open-emails"
                path={~p"/admin/emails"}
                label="Emaily hostům"
                icon="hero-envelope"
              />
              <.action
                id="open-payments"
                path={~p"/admin/payments"}
                label="Proběhlé barové platby"
                icon="hero-banknotes"
              />
            </div>
          </div>
        </div>

        <HomeComponents.cards :if={@economic_overview} result={@economic_overview} />
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :detail, :string, required: true
  attr :icon, :string, required: true

  defp summary(assigns) do
    ~H"""
    <div class="flex items-start gap-4 rounded-xl border border-secondary-200 bg-white p-4 sm:p-5">
      <span class="rounded-lg bg-secondary-50 p-2"><.icon
        name={@icon}
        class="h-5 w-5 text-primary-400"
      /></span>
      <div>
        <p
          class="text-sm text-primary-400">{@label}</p><p
          class="mt-1 text-3xl font-semibold tracking-tight text-primary-500">
          {@value}
        </p><p class="mt-1 text-xs text-primary-400">{@detail}</p>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  defp action(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@path}
      class="mt-2 flex min-h-11 items-center gap-3 rounded-lg px-3 py-3 text-sm font-semibold text-tertiary-700 transition-colors hover:bg-tertiary-50 focus-visible:outline-2 focus-visible:outline-tertiary-500"
    ><.icon name={@icon} class="h-5 w-5 shrink-0" />{@label}<.icon
      name="hero-arrow-right"
      class="ml-auto h-4 w-4 shrink-0"
    /></.link>
    """
  end

  defp date(nil), do: "bez data odjezdu"
  defp date(date), do: Calendar.strftime(date, "%d. %m. %Y")

  defp rooms(booking) do
    numbers = booking.rooms |> Enum.map(& &1.room_number) |> Enum.sort()

    case numbers do
      [] ->
        if booking.room_number in [nil, ""],
          do: "Pokoje zatím nepřiřazeny",
          else: "Pokoje: #{booking.room_number}"

      numbers ->
        "Pokoje: #{Enum.join(numbers, ", ")}"
    end
  end

  defp spans_date?(booking, day) do
    Date.compare(day, booking.check_in_date) != :lt and
      (is_nil(booking.check_out_date) or Date.compare(day, booking.check_out_date) != :gt)
  end

  defp timeline_color(booking, day) do
    cond do
      booking.check_in_date == day -> "rounded-l-lg bg-success-light text-success-dark"
      booking.check_out_date == day -> "rounded-r-lg bg-tertiary-100 text-tertiary-800"
      true -> "bg-secondary-200 text-primary-500"
    end
  end

  defp timeline_label(booking, day) do
    cond do
      booking.check_in_date == day and booking.check_out_date == day -> "↔"
      booking.check_in_date == day -> "Příj."
      booking.check_out_date == day -> "Odj."
      true -> "●"
    end
  end

  defp menu_ready?(%{meal_plan: "none"}, _issues), do: true

  defp menu_ready?(booking, issues) do
    CozyCheckout.Bookings.Booking.meal_details_complete?(booking) and issues == []
  end

  defp menu_label(%{meal_plan: "none"}, _issues), do: "Bez stravování"

  defp menu_label(booking, issues) do
    cond do
      not CozyCheckout.Bookings.Booking.meal_details_complete?(booking) ->
        "Stravování: doplnit údaje"

      not menu_ready?(booking, issues) ->
        "Menu: vyžaduje pozornost"

      true ->
        "Menu připravené"
    end
  end

  defp stay_label(booking, today) do
    if Date.compare(booking.check_in_date, today) == :gt, do: "Nadcházející", else: "Probíhající"
  end

  defp issue_path(%{kind: :details, booking: booking}), do: ~p"/admin/bookings/#{booking.id}/edit"
  defp issue_path(%{booking: booking}), do: ~p"/admin/bookings/#{booking.id}/menu"
end

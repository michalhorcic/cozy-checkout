defmodule CozyCheckoutWeb.BookingLive.TimelineComponent do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Dashboard

  @impl true
  def update(assigns, socket) do
    today = Date.utc_today()
    start_date = Map.get(socket.assigns, :start_date, today)
    socket = assign(socket, id: assigns.id, today: today, start_date: start_date)
    data = if start_date == today, do: Map.get(assigns, :initial_data)
    {:ok, load_timeline(socket, data)}
  end

  @impl true
  def handle_event(event, _params, socket) when event in ["prev_month", "next_month", "today"] do
    start_date =
      case event do
        "prev_month" -> Date.shift(socket.assigns.start_date, month: -1)
        "next_month" -> Dashboard.month_ahead(socket.assigns.start_date)
        "today" -> Date.utc_today()
      end

    {:noreply, socket |> assign(:start_date, start_date) |> load_timeline()}
  end

  defp load_timeline(socket, data \\ nil) do
    start_date = socket.assigns.start_date
    end_date = Dashboard.month_ahead(start_date)
    data = data || Dashboard.timeline(start_date, end_date)

    assign(socket,
      end_date: end_date,
      dates: Enum.to_list(Date.range(start_date, end_date)),
      bookings: data.bookings,
      booking_issues: Enum.group_by(data.issues, & &1.booking.id),
      occupancy: data.occupancy,
      capacity: data.capacity
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id={@id}
      aria-labelledby="stays-heading"
      class="overflow-hidden rounded-2xl border border-secondary-200 bg-white shadow-sm"
    >
      <div class="flex flex-wrap items-start justify-between gap-3 border-b border-secondary-100 p-5 sm:p-6">
        <div>
          <h2 id="stays-heading" class="text-lg font-semibold text-primary-500">
            Časová osa skupin
          </h2>
          <p class="mt-1 text-sm text-primary-400">
            {date(@start_date)} – {date(@end_date)} · pokoje a připravenost menu
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
      <div class="flex flex-wrap items-center gap-2 border-b border-secondary-100 px-5 py-3">
        <button
          type="button"
          phx-click="prev_month"
          phx-target={@myself}
          aria-label="Předchozí měsíc"
          class="min-h-11 rounded-lg px-3 text-sm text-tertiary-700 hover:bg-secondary-50"
        >← Předchozí</button>
        <button
          type="button"
          phx-click="today"
          phx-target={@myself}
          class="min-h-11 rounded-lg px-3 text-sm text-tertiary-700 hover:bg-secondary-50"
        >Dnes</button>
        <button
          type="button"
          phx-click="next_month"
          phx-target={@myself}
          aria-label="Následující měsíc"
          class="min-h-11 rounded-lg px-3 text-sm text-tertiary-700 hover:bg-secondary-50"
        >Následující →</button>
      </div>
      <div :if={@bookings == []} id="stays-empty" class="px-6 py-12 text-center">
        <.icon name="hero-calendar-days" class="mb-3 h-9 w-9 text-secondary-400" />
        <p class="font-medium text-primary-500">Ve zvoleném období tu nejsou žádné pobyty.</p>
        <.link
          navigate={~p"/admin/bookings/new"}
          class="mt-2 inline-block text-sm text-tertiary-700 hover:underline"
        >Přidat rezervaci →</.link>
      </div>
      <div
        id={"#{@id}-scroll"}
        class="overflow-x-auto"
        tabindex="0"
        aria-label="Časová osa skupin, vodorovně posuvná"
      >
        <table :if={@bookings != []} class="w-full border-collapse text-sm">
          <caption class="sr-only">
            Pobyty podle skupin. Příj. značí příjezd, Odj. odjezd, bod pobyt.
          </caption>
          <thead>
            <tr>
              <th
                scope="col"
                class="sticky left-0 z-20 min-w-56 bg-white p-4 text-left text-primary-500"
              >
                Skupina a příprava
              </th>
              <th
                :for={day <- @dates}
                scope="col"
                class={[
                  "min-w-12 border-l border-secondary-100 p-2 text-center text-xs",
                  if(day == @today,
                    do: "bg-tertiary-100 text-tertiary-800",
                    else: "bg-secondary-50 text-primary-400"
                  )
                ]}
              >
                <span class="block">{Calendar.strftime(day, "%d.%m.")}</span>
                <span :if={day == @today} class="block">Dnes</span>
                <span class="mt-1 block font-normal" title="Obsazenost / kapacita">{Map.get(
                  @occupancy,
                  day,
                  0
                )}/{@capacity}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={booking <- @bookings}
              id={"dashboard-booking-#{booking.id}"}
              class="border-t border-secondary-200"
            >
              <th scope="row" class="sticky left-0 z-10 bg-white p-4 text-left font-normal">
                <.link
                  navigate={~p"/admin/bookings/#{booking.id}"}
                  class="font-semibold text-primary-500 hover:text-tertiary-700 hover:underline"
                >{booking.guest.name}</.link>
                <p class="mt-1 text-xs text-primary-400">
                  {date(booking.check_in_date)} – {date(booking.check_out_date)}
                </p>
                <p class="mt-1 text-xs text-primary-400">
                  {stay_label(booking, @today)} · {CozyCheckout.Bookings.people_count(booking)} osob
                </p>
                <p
                  :if={booking.check_in_date == @today}
                  class="mt-1 text-xs font-semibold text-success-dark"
                >
                  Dnes příjezd
                </p>
                <p
                  :if={booking.check_out_date == @today}
                  class="mt-1 text-xs font-semibold text-tertiary-800"
                >
                  Dnes odjezd
                </p>
                <.link
                  navigate={~p"/admin/bookings/#{booking.id}"}
                  class="mt-2 block text-xs text-tertiary-700 hover:underline"
                >{rooms(booking)}</.link>
                <.link
                  navigate={~p"/admin/bookings/#{booking.id}/menu"}
                  class={[
                    "mt-2 block text-xs hover:underline",
                    if(menu_ready?(booking, Map.get(@booking_issues, booking.id, [])),
                      do: "text-success-dark",
                      else: "text-error"
                    )
                  ]}
                >{menu_label(booking, Map.get(@booking_issues, booking.id, []))}</.link>
                <p :if={booking.short_note} class="mt-2 text-xs text-primary-400">
                  {booking.short_note}
                </p>
              </th>
              <td
                :for={day <- @dates}
                class={[
                  "border-l border-secondary-100 p-0 text-center text-xs",
                  if(day == @today, do: "bg-tertiary-50")
                ]}
              >
                <.link
                  :if={spans_date?(booking, day)}
                  navigate={~p"/admin/bookings/#{booking.id}"}
                  aria-label={"#{booking.guest.name} · #{date(day)} · #{timeline_label(booking, day)}"}
                  class={[
                    "flex min-h-11 items-center justify-center font-medium hover:brightness-95",
                    timeline_color(booking, day)
                  ]}
                >
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
end

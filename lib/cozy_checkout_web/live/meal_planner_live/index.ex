defmodule CozyCheckoutWeb.MealPlannerLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Meals
  alias CozyCheckout.Bookings
  alias CozyCheckout.Meals.MenuPlanning
  import CozyCheckoutWeb.MealComponents
  import CozyCheckoutWeb.KitchenComponents, only: [kitchen_header: 1]

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    week_start = Meals.start_of_week(today)

    socket =
      socket
      |> assign(:week_start, week_start)
      |> assign(:dietary_panel_open, true)
      |> assign(:modal_date, nil)
      |> assign(:modal_bookings, [])
      |> load_week_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    context = CozyCheckoutWeb.FoodNavigation.context(params)

    date =
      case Date.from_iso8601(context["from"] || "") do
        {:ok, date} -> date
        _ -> Date.utc_today()
      end

    first = Meals.start_of_week(date)

    socket =
      if first == socket.assigns.week_start,
        do: socket,
        else: socket |> assign(:week_start, first) |> load_week_data()

    context =
      if Map.has_key?(context, "from"),
        do: context,
        else:
          Map.merge(context, %{
            "from" => Date.to_iso8601(first),
            "to" => Date.to_iso8601(Date.add(first, 6))
          })

    {:noreply, assign(socket, :food_context, context)}
  end

  @impl true
  def handle_event("prev_week", _params, socket) do
    first = Date.add(socket.assigns.week_start, -7)

    context =
      Map.merge(socket.assigns.food_context, %{
        "from" => Date.to_iso8601(first),
        "to" => Date.to_iso8601(Date.add(first, 6))
      })

    {:noreply, push_patch(socket, to: CozyCheckoutWeb.FoodNavigation.path(:planner, context))}
  end

  @impl true
  def handle_event("next_week", _params, socket) do
    first = Date.add(socket.assigns.week_start, 7)

    context =
      Map.merge(socket.assigns.food_context, %{
        "from" => Date.to_iso8601(first),
        "to" => Date.to_iso8601(Date.add(first, 6))
      })

    {:noreply, push_patch(socket, to: CozyCheckoutWeb.FoodNavigation.path(:planner, context))}
  end

  @impl true
  def handle_event("today", _params, socket) do
    first = Meals.start_of_week(Date.utc_today())

    context =
      Map.merge(socket.assigns.food_context, %{
        "from" => Date.to_iso8601(first),
        "to" => Date.to_iso8601(Date.add(first, 6))
      })

    {:noreply, push_patch(socket, to: CozyCheckoutWeb.FoodNavigation.path(:planner, context))}
  end

  @impl true
  def handle_event("toggle_dietary_panel", _params, socket) do
    {:noreply, assign(socket, :dietary_panel_open, !socket.assigns.dietary_panel_open)}
  end

  @impl true
  def handle_event("show_guest_bookings", %{"date" => date_string}, socket) do
    date = Date.from_iso8601!(date_string)
    bookings = bookings_for_date(socket.assigns.bookings, date)

    {:noreply, assign(socket, modal_date: date, modal_bookings: bookings)}
  end

  @impl true
  def handle_event("close_bookings_modal", _params, socket) do
    {:noreply, assign(socket, modal_date: nil, modal_bookings: [])}
  end

  defp load_week_data(socket) do
    week_start = socket.assigns.week_start
    week_end = Date.add(week_start, 6)

    portion_counts = Meals.get_portion_counts_for_range(week_start, week_end)
    kitchen = MenuPlanning.kitchen_for_range(week_start, week_end)

    freezer =
      CozyCheckout.Kitchen.Freezer.presentation(kitchen.groups |> Map.values() |> List.flatten())

    # Load guest counts for the week
    occupancy_map = Bookings.get_occupancy_for_range(week_start, week_end)

    # Load dietary restrictions
    dietary_restrictions = Meals.get_dietary_restrictions_for_week(week_start)

    # Load bookings for the week
    bookings = Bookings.list_bookings_for_date_range(week_start, week_end)

    # Generate week days (Sunday to Saturday)
    week_days =
      Date.range(week_start, week_end)
      |> Enum.map(fn date ->
        %{
          date: date,
          guest_count: Map.get(occupancy_map, date, 0),
          portions: Map.fetch!(portion_counts, date),
          group_menus:
            Map.new(["breakfast", "lunch", "dinner"], fn type ->
              {type,
               Enum.map(
                 Map.get(kitchen.groups, {date, type}, []),
                 &Map.put(&1, :freezer_items, Map.get(freezer.by_item, &1.id, []))
               )}
            end)
        }
      end)

    socket
    |> assign(:week_days, week_days)
    |> assign(:menu_issues, kitchen.issues)
    |> assign(
      :incomplete_bookings,
      portion_counts
      |> Map.values()
      |> Enum.flat_map(& &1.incomplete_bookings)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.check_in_date, Date)
    )
    |> assign(:dietary_restrictions, dietary_restrictions)
    |> assign(:bookings, bookings)
    |> assign(:page_title, "Plán jídel · týden od #{Calendar.strftime(week_start, "%d.%m.%Y")}")
  end

  defp day_name(date) do
    Enum.at(~w(Pondělí Úterý Středa Čtvrtek Pátek Sobota Neděle), Date.day_of_week(date) - 1)
  end

  defp format_date(date) do
    Calendar.strftime(date, "%d.%m.")
  end

  defp meal_type_emoji(type) do
    case type do
      "breakfast" -> "🌅"
      "lunch" -> "🌞"
      "dinner" -> "🌙"
      _ -> "🍽️"
    end
  end

  defp meal_type_label(type) do
    case type do
      "breakfast" -> "Snídaně"
      "lunch" -> "Oběd"
      "dinner" -> "Večeře"
      _ -> type
    end
  end

  defp guest_count_class(count) do
    level = Bookings.occupancy_level(count)

    case level do
      :full -> "text-error font-bold"
      :high -> "text-warning font-bold"
      :medium -> "text-warning font-semibold"
      :low -> "text-success font-semibold"
    end
  end

  attr :id, :string, required: true
  attr :day, :map, required: true
  attr :meal_type, :string, required: true

  defp menu_coverage(assigns) do
    assigns = assign(assigns, :uncovered, uncovered_count(assigns.day, assigns.meal_type))

    ~H"""
    <div id={@id}>
      <p :if={@uncovered > 0} class="mb-2 text-xs font-semibold text-warning">
        Chybí menu pro {@uncovered} porcí
      </p>
      <p :if={@day.portions[@meal_type].total == 0} class="text-sm text-primary-400">
        Bez plánované stravy
      </p>
    </div>
    """
  end

  defp uncovered_count(day, type) do
    assigned = day.group_menus[type] |> Enum.map(& &1.counts.total) |> Enum.sum()
    max(day.portions[type].total - assigned, 0)
  end

  defp bookings_for_date(bookings, date) do
    Enum.filter(bookings, fn booking ->
      check_in_ok = Date.compare(date, booking.check_in_date) in [:eq, :gt]

      check_out_ok =
        if booking.check_out_date do
          Date.compare(date, booking.check_out_date) in [:eq, :lt]
        else
          true
        end

      check_in_ok and check_out_ok
    end)
  end
end

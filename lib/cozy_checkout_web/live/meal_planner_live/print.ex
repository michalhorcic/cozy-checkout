defmodule CozyCheckoutWeb.MealPlannerLive.Print do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Meals
  alias CozyCheckout.Bookings

  @impl true
  def mount(%{"week" => week_string}, _session, socket) do
    week_start = Date.from_iso8601!(week_string)
    
    socket =
      socket
      |> assign(:week_start, week_start)
      |> load_week_data()

    {:ok, socket}
  end

  def mount(_params, _session, socket) do
    # Default to current week if no week param provided
    today = Date.utc_today()
    week_start = Meals.start_of_week(today)

    socket =
      socket
      |> assign(:week_start, week_start)
      |> load_week_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  defp load_week_data(socket) do
    week_start = socket.assigns.week_start
    week_end = Date.add(week_start, 6)

    # Load meals for the week
    meals_by_date = Meals.get_meals_for_week(week_start)

    # Load guest counts for the week
    occupancy_map = Bookings.get_occupancy_for_range(week_start, week_end)

    # Load dietary restrictions
    dietary_restrictions = Meals.get_dietary_restrictions_for_week(week_start)

    # Generate week days (Sunday to Saturday)
    week_days =
      Date.range(week_start, week_end)
      |> Enum.map(fn date ->
        %{
          date: date,
          guest_count: Map.get(occupancy_map, date, 0),
          meals: Map.get(meals_by_date, date, []) |> meals_to_map()
        }
      end)

    socket
    |> assign(:week_days, week_days)
    |> assign(:dietary_restrictions, dietary_restrictions)
    |> assign(:generated_date, Date.utc_today())
    |> assign(:page_title, "Weekly Menu - #{Calendar.strftime(week_start, "%B %d, %Y")}")
  end

  defp meals_to_map(meals) do
    Enum.reduce(meals, %{}, fn meal, acc ->
      Map.put(acc, meal.meal_type, meal)
    end)
  end

  defp day_name(date) do
    Calendar.strftime(date, "%A")
  end

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp meal_type_label(type) do
    case type do
      "breakfast" -> "Breakfast"
      "lunch" -> "Lunch"
      "dinner" -> "Dinner"
      _ -> type
    end
  end
end

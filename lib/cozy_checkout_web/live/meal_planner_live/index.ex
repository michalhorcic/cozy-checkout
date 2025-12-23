defmodule CozyCheckoutWeb.MealPlannerLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Meals
  alias CozyCheckout.Bookings

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    week_start = Meals.start_of_week(today)

    socket =
      socket
      |> assign(:week_start, week_start)
      |> assign(:edit_modal_open, false)
      |> assign(:edit_date, nil)
      |> assign(:edit_meal_type, nil)
      |> assign(:edit_menu_text, "")
      |> assign(:edit_dietary_notes, "")
      |> assign(:dietary_panel_open, true)
      |> load_week_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_week", _params, socket) do
    week_start = Date.add(socket.assigns.week_start, -7)

    socket =
      socket
      |> assign(:week_start, week_start)
      |> load_week_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("next_week", _params, socket) do
    week_start = Date.add(socket.assigns.week_start, 7)

    socket =
      socket
      |> assign(:week_start, week_start)
      |> load_week_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("today", _params, socket) do
    today = Date.utc_today()
    week_start = Meals.start_of_week(today)

    socket =
      socket
      |> assign(:week_start, week_start)
      |> load_week_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_dietary_panel", _params, socket) do
    {:noreply, assign(socket, :dietary_panel_open, !socket.assigns.dietary_panel_open)}
  end

  @impl true
  def handle_event("open_edit_modal", %{"date" => date_string, "type" => meal_type}, socket) do
    date = Date.from_iso8601!(date_string)
    meal = Meals.get_meal_by_date_and_type(date, meal_type)

    socket =
      socket
      |> assign(:edit_modal_open, true)
      |> assign(:edit_date, date)
      |> assign(:edit_meal_type, meal_type)
      |> assign(:edit_menu_text, meal && meal.menu_text || "")
      |> assign(:edit_dietary_notes, meal && meal.dietary_notes || "")

    {:noreply, socket}
  end

  @impl true
  def handle_event("noop", _params, socket) do
    # Do nothing - this just prevents clicks from bubbling to the backdrop
    {:noreply, socket}
  end

  @impl true
  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, :edit_modal_open, false)}
  end

  @impl true
  def handle_event("validate_meal", params, socket) do
    # Just update the form values, preserving existing values if not in params
    meal_params = Map.get(params, "meal", %{})

    socket =
      socket
      |> assign(:edit_menu_text, Map.get(meal_params, "menu_text", socket.assigns.edit_menu_text))
      |> assign(:edit_dietary_notes, Map.get(meal_params, "dietary_notes", socket.assigns.edit_dietary_notes))

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_meal", params, socket) do
    meal_params = Map.get(params, "meal", %{})

    attrs = %{
      menu_text: Map.get(meal_params, "menu_text"),
      dietary_notes: Map.get(meal_params, "dietary_notes")
    }

    case Meals.upsert_meal(socket.assigns.edit_date, socket.assigns.edit_meal_type, attrs) do
      {:ok, _meal} ->
        socket =
          socket
          |> assign(:edit_modal_open, false)
          |> put_flash(:info, "Meal saved successfully")
          |> load_week_data()

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save meal")}
    end
  end

  @impl true
  def handle_event("copy_from_yesterday", _params, socket) do
    yesterday = Date.add(socket.assigns.edit_date, -1)
    meal = Meals.get_meal_by_date_and_type(yesterday, socket.assigns.edit_meal_type)

    socket =
      if meal do
        socket
        |> assign(:edit_menu_text, meal.menu_text || "")
        |> assign(:edit_dietary_notes, meal.dietary_notes || "")
      else
        put_flash(socket, :info, "No meal found for yesterday")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("copy_to_week", _params, socket) do
    # Copy current meal to all remaining days of the week
    week_end = Date.add(socket.assigns.week_start, 6)
    current_date = socket.assigns.edit_date
    meal_type = socket.assigns.edit_meal_type

    # Get all dates from current date to end of week
    target_dates =
      Date.range(Date.add(current_date, 1), week_end)
      |> Enum.to_list()

    if target_dates == [] do
      {:noreply, put_flash(socket, :info, "Already at the end of the week")}
    else
      meal = Meals.get_meal_by_date_and_type(current_date, meal_type)

      if meal && meal.menu_text do
        case Meals.copy_meal_to_dates(meal, target_dates) do
          {:ok, count} ->
            socket =
              socket
              |> put_flash(:info, "Meal copied to #{count} days")
              |> load_week_data()

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to copy meal")}
        end
      else
        {:noreply, put_flash(socket, :info, "Please save this meal first")}
      end
    end
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
    |> assign(:page_title, "Meal Planner - Week of #{Calendar.strftime(week_start, "%B %d, %Y")}")
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
    Calendar.strftime(date, "%b %d")
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
      "breakfast" -> "Breakfast"
      "lunch" -> "Lunch"
      "dinner" -> "Dinner"
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

  defp has_dietary_notes?(meal) do
    meal && meal.dietary_notes && meal.dietary_notes != ""
  end

  defp needs_planning?(guest_count, meal) do
    guest_count > 20 && (!meal || !meal.menu_text || meal.menu_text == "")
  end
end

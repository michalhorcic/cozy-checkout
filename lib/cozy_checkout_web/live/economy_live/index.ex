defmodule CozyCheckoutWeb.EconomyLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Bookings

  @impl true
  def mount(_params, _session, socket) do
    # Default to current date + 1 year
    today = Date.utc_today()
    one_year_ahead = Date.add(today, 365)

    # Default to all states selected
    all_states = ["draft", "personal", "generated", "sent", "advance_paid", "paid"]

    socket =
      socket
      |> assign(:page_title, "Economy Management")
      |> assign(:start_date, today)
      |> assign(:end_date, one_year_ahead)
      |> assign(:selected_states, all_states)
      |> assign(:all_states, all_states)
      |> load_economy_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    start_date = parse_date(params["start_date"]) || socket.assigns.start_date
    end_date = parse_date(params["end_date"]) || socket.assigns.end_date

    socket =
      socket
      |> assign(:start_date, start_date)
      |> assign(:end_date, end_date)
      |> load_economy_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_state", %{"state" => state}, socket) do
    selected_states =
      if state in socket.assigns.selected_states do
        List.delete(socket.assigns.selected_states, state)
      else
        [state | socket.assigns.selected_states]
      end

    socket =
      socket
      |> assign(:selected_states, selected_states)
      |> load_economy_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_all_states", _params, socket) do
    socket =
      socket
      |> assign(:selected_states, socket.assigns.all_states)
      |> load_economy_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_all_states", _params, socket) do
    socket =
      socket
      |> assign(:selected_states, [])
      |> load_economy_data()

    {:noreply, socket}
  end

  defp load_economy_data(socket) do
    %{start_date: start_date, end_date: end_date, selected_states: selected_states} =
      socket.assigns

    stats = Bookings.get_economy_stats(start_date, end_date, selected_states)
    monthly_stats = Bookings.get_monthly_stats(start_date, end_date, selected_states)

    socket
    |> assign(:stats, stats)
    |> assign(:monthly_stats, monthly_stats)
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp format_date(date) do
    Calendar.strftime(date, "%d. %m. %Y")
  end

  defp state_label("draft"), do: "Draft"
  defp state_label("personal"), do: "Personal"
  defp state_label("generated"), do: "Generated"
  defp state_label("sent"), do: "Sent"
  defp state_label("advance_paid"), do: "Advance Paid"
  defp state_label("paid"), do: "Paid"
  defp state_label(state), do: String.capitalize(state)

  defp state_badge_class("draft"), do: "bg-secondary-100 text-primary-500"
  defp state_badge_class("personal"), do: "bg-info-light text-info-dark"
  defp state_badge_class("generated"), do: "bg-tertiary-100 text-tertiary-800"
  defp state_badge_class("sent"), do: "bg-warning-light text-warning-dark"
  defp state_badge_class("advance_paid"), do: "bg-orange-100 text-orange-800"
  defp state_badge_class("paid"), do: "bg-success-light text-success-dark"
  defp state_badge_class(_), do: "bg-secondary-100 text-primary-500"

  defp max_value(data, key) do
    data
    |> Enum.map(&Map.get(&1, key))
    |> Enum.map(&Decimal.to_float/1)
    |> Enum.max(fn -> 0 end)
  end

  defp max_booking_count(data) do
    data
    |> Enum.map(& &1.booking_count)
    |> Enum.max(fn -> 0 end)
  end

  defp bar_height(value, max_value) when max_value > 0 do
    percentage = value / max_value * 100
    min(percentage, 100)
  end

  defp bar_height(_value, _max_value), do: 0
end

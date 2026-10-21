defmodule CozyCheckoutWeb.MealComponents do
  use CozyCheckoutWeb, :html

  def meal_plan_options do
    [
      {"Stravování nevyplněno", ""},
      {"Bez stravy", "none"},
      {"Polopenze", "half_board"},
      {"Plná penze", "full_board"}
    ]
  end

  def meal_options, do: [{"Snídaně", "breakfast"}, {"Oběd", "lunch"}, {"Večeře", "dinner"}]

  def meal_plan_label(plan) do
    Enum.find_value(meal_plan_options(), "Stravování nevyplněno", fn {label, value} ->
      if value == plan, do: label
    end)
  end

  def meal_label(meal) do
    Enum.find_value(meal_options(), "—", fn {label, value} -> if value == meal, do: label end)
  end

  attr :id, :string, required: true
  attr :counts, :map, required: true
  attr :incomplete, :boolean, default: false

  def portion_count(assigns) do
    ~H"""
    <div id={@id} class="mb-2 text-sm text-primary-500">
      <span class="font-semibold">{@counts.total} porcí</span>
      <span class="block text-xs text-primary-400">
        {@counts.adults} dospělí · {@counts.children} děti
      </span>
      <span :if={@incomplete} class="block text-xs font-semibold text-warning">
        Neúplný součet
      </span>
    </div>
    """
  end

  attr :bookings, :list, required: true

  def incomplete_catering_notice(assigns) do
    ~H"""
    <aside
      :if={@bookings != []}
      id="incomplete-catering"
      class="mb-6 rounded-lg border border-warning bg-warning-light p-4 text-primary-500"
      aria-label="Neúplné údaje o stravování"
    >
      <p class="font-semibold">Počty porcí nejsou úplné</p>
      <p class="mt-1 text-sm">
        Tyto rezervace nemají úplné údaje o stravování a nejsou zahrnuty do součtů:
      </p>
      <ul class="mt-2 space-y-1">
        <li :for={booking <- @bookings}>
          <.link
            id={"incomplete-catering-#{booking.id}"}
            navigate={~p"/admin/bookings/#{booking.id}/edit"}
            class="text-sm underline hover:text-tertiary-600"
          >
            {booking.guest.name} ({Calendar.strftime(booking.check_in_date, "%d.%m.%Y")} – {if booking.check_out_date,
              do: Calendar.strftime(booking.check_out_date, "%d.%m.%Y"),
              else: "odjezd nevyplněn"})
          </.link>
        </li>
      </ul>
    </aside>
    """
  end
end

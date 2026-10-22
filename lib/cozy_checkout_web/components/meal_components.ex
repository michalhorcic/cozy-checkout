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

  attr :id, :string, required: true
  attr :groups, :list, required: true
  attr :shared_text, :string, default: nil

  def group_menus(assigns) do
    ~H"""
    <div :if={@groups != []} id={@id} class="mt-3 space-y-3 border-t border-secondary-200 pt-3">
      <article
        :for={group <- @groups}
        id={"#{@id}-#{group.id}"}
        class="rounded-lg bg-secondary-50 p-3"
      >
        <.link
          navigate={
            CozyCheckoutWeb.FoodNavigation.with_context(
              ~p"/admin/bookings/#{group.booking.id}/menu",
              %{
                "week" => Date.to_iso8601(group.date),
                "booking" => group.booking.id,
                "origin" => "planner"
              }
            )
          }
          phx-click="noop"
          class="text-sm font-semibold text-tertiary-600 underline"
        >{group.booking.guest.name}</.link>
        <.portion_count id={"#{@id}-portions-#{group.id}"} counts={group.counts} />
        <p class="whitespace-pre-line text-sm text-primary-500">{group.menu_text}</p>
        <p :if={group.supplements} class="mt-1 whitespace-pre-line text-xs text-primary-400">
          {group.supplements}
        </p>
        <.link
          navigate={
            CozyCheckoutWeb.FoodNavigation.with_context(
              ~p"/admin/recipes/menu/booking/#{group.id}",
              %{
                "week" => Date.to_iso8601(group.date),
                "booking" => group.booking.id,
                "origin" => "planner"
              }
            )
          }
          phx-click="noop"
          class="mt-2 inline-block text-xs font-semibold text-tertiary-600 underline"
        >Suroviny pro skupinu</.link>
        <p :if={group.manually_edited} class="mt-1 text-xs font-semibold text-tertiary-600">
          Ruční úprava
        </p>
        <p :if={different_shared_menu?(@shared_text, group)} class="mt-1 text-xs text-warning">
          Odlišné od společného menu
        </p>
      </article>
    </div>
    """
  end

  attr :issues, :list, required: true

  def menu_issues(assigns) do
    ~H"""
    <aside
      :if={@issues != []}
      id="booking-menu-issues"
      class="mb-6 rounded-lg border border-secondary-200 bg-white p-4"
    >
      <p class="font-semibold text-primary-500">Menu skupin vyžaduje doplnění</p>
      <ul class="mt-2 space-y-1">
        <li
          :for={issue <- @issues}
          id={"booking-menu-issue-#{issue.booking.id}"}
          class="text-sm text-primary-400"
        >
          <.link
            navigate={~p"/admin/bookings/#{issue.booking.id}/menu"}
            class="text-tertiary-600 underline"
          >{issue.booking.guest.name}</.link>
          · {issue.reason}
        </li>
      </ul>
    </aside>
    """
  end

  defp different_shared_menu?(text, group) do
    text not in [nil, ""] and
      String.trim(text) !=
        CozyCheckout.Meals.MenuPlanning.menu_text(group.menu_text, group.supplements)
  end
end

defmodule CozyCheckoutWeb.MealPlannerLive.Variants do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Meals.{MenuPlanning, MenuRecipes, MenuVariant}
  import CozyCheckoutWeb.MealComponents
  import CozyCheckoutWeb.KitchenComponents, only: [kitchen_header: 1, field_class: 0]

  @impl true
  def mount(_, _, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _, socket) do
    variant =
      case socket.assigns.live_action do
        :new -> %MenuVariant{items: []}
        :edit -> MenuPlanning.get_variant!(params["id"])
        :index -> nil
      end

    {:noreply,
     socket
     |> assign(
       page_title: "Menu z receptů",
       food_context: CozyCheckoutWeb.FoodNavigation.context(params),
       variant: variant,
       focus_item: params["slot"],
       filters: %{"search" => "", "days" => "", "plan" => "", "state" => ""},
       assignment: nil,
       show_breakfasts: false,
       assignment_search: ""
     )
     |> load_variants()}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket),
    do: {:noreply, socket |> assign(:filters, filters) |> filter_variants()}

  def handle_event("toggle_breakfasts", _, socket),
    do: {:noreply, assign(socket, :show_breakfasts, not socket.assigns.show_breakfasts)}

  def handle_event("delete", %{"id" => id}, socket) do
    case MenuPlanning.get_variant!(id) |> MenuPlanning.delete_variant() do
      {:ok, _} -> {:noreply, load_variants(socket)}
      _ -> {:noreply, put_flash(socket, :error, "Menu se změnilo. Obnovte stránku.")}
    end
  end

  def handle_event("duplicate", %{"id" => id}, socket) do
    case MenuPlanning.get_variant!(id) |> MenuRecipes.duplicate() do
      {:ok, copy} ->
        {:noreply,
         push_patch(socket,
           to:
             CozyCheckoutWeb.FoodNavigation.with_context(
               ~p"/admin/meal-planner/variants/#{copy.id}/edit",
               socket.assigns.food_context
             )
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Menu se nepodařilo duplikovat.")}
    end
  end

  def handle_event("assign", %{"id" => id}, socket) do
    variant = MenuPlanning.get_variant!(id)

    if MenuRecipes.readiness(variant).ready? do
      context = socket.assigns.food_context

      if context["booking"] do
        {:noreply,
         push_navigate(socket,
           to:
             CozyCheckoutWeb.FoodNavigation.with_context(
               "/admin/bookings/#{context["booking"]}/menu",
               Map.put(context, "variant", id)
             )
         )}
      else
        {:noreply,
         assign(socket,
           assignment: variant,
           assignment_search: "",
           assignment_options: MenuPlanning.assignment_bookings(variant)
         )}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Rozpracované menu nelze přiřadit. Otevřete editor a vyřešte nedostatky."
       )}
    end
  end

  def handle_event("assignment_search", %{"search" => query}, socket),
    do: {:noreply, assign(socket, :assignment_search, query)}

  def handle_event("close_assignment", _, socket),
    do: {:noreply, assign(socket, :assignment, nil)}

  def handle_event("import_reference", _, socket) do
    case MenuPlanning.import_reference_variants() do
      {:ok, counts} ->
        {:noreply,
         socket
         |> put_flash(
           :success,
           "Přidáno #{counts.created} menu, přeskočeno #{counts.skipped} existujících. Zkontrolujte nevyřešené položky."
         )
         |> load_variants()}

      _ ->
        {:noreply, put_flash(socket, :error, "Import se neuložil.")}
    end
  end

  @impl true
  def handle_info({:menu_saved, _}, socket),
    do:
      {:noreply,
       socket
       |> put_flash(:success, "Menu uloženo. Sestavy přiřazených pobytů se nezměnily.")
       |> push_patch(
         to: CozyCheckoutWeb.FoodNavigation.path(:variants, socket.assigns.food_context)
       )}

  defp load_variants(socket),
    do: socket |> assign(:all_variants, MenuPlanning.list_variants()) |> filter_variants()

  defp filter_variants(socket) do
    filters = socket.assigns.filters
    query = CozyCheckout.Recipes.normalize(filters["search"] || "")

    variants =
      Enum.filter(socket.assigns.all_variants, fn variant ->
        names =
          Enum.flat_map(variant.items, fn item ->
            [MenuRecipes.display(item).main, MenuRecipes.display(item).supplements]
          end)

        text =
          [variant.name | names]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" ")
          |> CozyCheckout.Recipes.normalize()

        state = MenuRecipes.readiness(variant)

        String.contains?(text, query) and
          (filters["days"] in [nil, ""] or to_string(variant.days) == filters["days"]) and
          (filters["plan"] in [nil, ""] or variant.meal_plan == filters["plan"]) and
          (filters["state"] in [nil, ""] or filters["state"] == state.state)
      end)

    assign(socket, :variants, variants)
  end

  defp sorted_items(variant),
    do:
      Enum.sort_by(
        variant.items,
        &{&1.day_number, CozyCheckout.Meals.SlotSchedule.rank(&1.meal_type)}
      )

  defp assignment_matches(options, query),
    do:
      Enum.filter(
        options,
        &String.contains?(
          CozyCheckout.Recipes.normalize(&1.name),
          CozyCheckout.Recipes.normalize(query)
        )
      )
end

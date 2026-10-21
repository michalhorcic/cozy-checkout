defmodule CozyCheckoutWeb.RecipeLive.Links do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Recipes
  alias CozyCheckout.Recipes.{Links, Consumption}
  import CozyCheckoutWeb.KitchenComponents
  @impl true
  def mount(%{"kind" => kind, "item_id" => id}, _, socket) when kind in ["variant", "booking"] do
    item = Links.load!(kind, id)
    settings = Recipes.settings()

    factor =
      if item.meal_type == "breakfast",
        do: settings.breakfast_child_factor,
        else: settings.hot_child_factor

    base =
      if kind == "booking",
        do: Consumption.for_booking_item(id),
        else: {:ok, %{adults: 10, children: 0, factor: factor}}

    {adults, children, blocked} =
      case base do
        {:ok, b} ->
          {b.adults, b.children, nil}

        {:error, _} ->
          {0, 0,
           "Menu už neodpovídá rezervaci nebo je pobyt zrušený. Nejdřív znovu zkontrolujte menu rezervace."}
      end

    back =
      if kind == "variant",
        do: ~p"/admin/meal-planner/variants/#{item.menu_variant_id}/edit",
        else: ~p"/admin/bookings/#{item.booking_menu.booking_id}/menu"

    {:ok,
     socket
     |> assign(:page_title, "Recepty k jídlu")
     |> assign(:kind, kind)
     |> assign(:item, item)
     |> assign(:version, Links.version(item))
     |> assign(:main_id, item.recipe_id)
     |> assign(:extra_ids, Links.supplement_ids(item))
     |> assign(:back, back)
     |> assign(:search, "")
     |> assign(:blocked, blocked)
     |> assign(:factor, factor)
     |> assign(:adults, adults)
     |> assign(:children, children)
     |> assign(:calculator_error, nil)
     |> assign(
       :calculator,
       to_form(%{"adults" => to_string(adults), "children" => to_string(children)},
         as: :calculator
       )
     )
     |> load_results()}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket),
    do: {:noreply, socket |> assign(:search, search) |> load_results()}

  def handle_event("select_main", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:main_id, id)
     |> assign(:extra_ids, Enum.reject(socket.assigns.extra_ids, &(&1 == id)))
     |> load_results()}
  end

  def handle_event("add_extra", %{"id" => id}, socket) do
    ids =
      if id == socket.assigns.main_id,
        do: socket.assigns.extra_ids,
        else: Enum.uniq(socket.assigns.extra_ids ++ [id])

    {:noreply, socket |> assign(:extra_ids, ids) |> load_results()}
  end

  def handle_event("remove_main", _, socket),
    do: {:noreply, socket |> assign(:main_id, nil) |> load_results()}

  def handle_event("remove_extra", %{"id" => id}, socket),
    do:
      {:noreply,
       socket
       |> assign(:extra_ids, Enum.reject(socket.assigns.extra_ids, &(&1 == id)))
       |> load_results()}

  def handle_event("calculate", %{"calculator" => p}, socket) do
    with {a, ""} when a >= 0 <- Integer.parse(p["adults"]),
         {c, ""} when c >= 0 <- Integer.parse(p["children"]) do
      {:noreply,
       socket
       |> assign(:adults, a)
       |> assign(:children, c)
       |> assign(:calculator, to_form(p, as: :calculator))
       |> assign(:calculator_error, nil)
       |> load_results()}
    else
      _ -> {:noreply, assign(socket, :calculator_error, "Zadejte celé nezáporné počty osob.")}
    end
  end

  def handle_event("save", _, socket) do
    case Links.save(
           socket.assigns.kind,
           socket.assigns.item.id,
           socket.assigns.main_id,
           socket.assigns.extra_ids,
           socket.assigns.version
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:success, "Recepty přiřazeny. Text menu zůstal zachován.")
         |> push_navigate(to: socket.assigns.back)}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Podklady se změnily nebo recept není dostupný. Obnovte stránku a zkontrolujte výběr."
         )}
    end
  end

  defp load_results(socket) do
    selected =
      Enum.reject([socket.assigns.main_id | socket.assigns.extra_ids], &is_nil/1)
      |> Enum.map(&Recipes.get_recipe!/1)

    main = Enum.find(selected, &(&1.id == socket.assigns.main_id))
    extras = Enum.reject(selected, &(&1.id == socket.assigns.main_id))

    result =
      Consumption.calculate(
        selected,
        socket.assigns.adults,
        socket.assigns.children,
        socket.assigns.factor
      )

    missing =
      String.split(socket.assigns.item.supplements || "", "\n", trim: true)
      |> Enum.map(&Links.label_name/1)
      |> Enum.reject(&(&1 in Enum.map(extras, fn r -> r.name end)))

    issues = if is_nil(main), do: ["Vyberte recept k hlavnímu chodu nebo bufetu"], else: []

    result = %{
      result
      | issues: result.issues ++ issues ++ Enum.map(missing, &("Doplněk bez receptu: " <> &1))
    }

    rows = Recipes.list_recipes(socket.assigns.search)

    socket
    |> assign(:main, main)
    |> assign(:extras, extras)
    |> assign(:result, result)
    |> assign(
      :links_changed?,
      socket.assigns.main_id != socket.assigns.item.recipe_id ||
        socket.assigns.extra_ids != Links.supplement_ids(socket.assigns.item)
    )
    |> assign(:result_count, length(rows))
    |> stream(:choices, rows, reset: true)
  end
end

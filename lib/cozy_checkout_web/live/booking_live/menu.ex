defmodule CozyCheckoutWeb.BookingLive.Menu do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Bookings
  alias CozyCheckout.Meals.{MenuPlanning, PortionCounts}
  import CozyCheckoutWeb.MealComponents

  import CozyCheckoutWeb.KitchenComponents,
    only: [menu_recipe_links: 1, kitchen_header: 1, freezer_notice: 1, searchable_picker: 1]

  @impl true
  def mount(%{"booking_id" => id} = params, _, socket) do
    {:ok,
     socket
     |> assign(:request_context, CozyCheckoutWeb.FoodNavigation.context(params))
     |> assign(:booking_id, id)
     |> assign(:page_title, "Menu rezervace")
     |> load_state()
     |> open_requested_item(params)}
  end

  @impl true
  def handle_event("toggle_breakfasts", _, socket) do
    show = not socket.assigns.show_breakfasts
    preview_rows = if socket.assigns.preview, do: socket.assigns.preview.rows, else: []

    {:noreply,
     socket
     |> assign(:show_breakfasts, show)
     |> stream(:menu_items, visible_rows(socket.assigns.menu_rows, show), reset: true)
     |> stream(:preview_rows, visible_rows(preview_rows, show), reset: true)}
  end

  def handle_event("select_variant", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.variants, &(&1.id == id)) do
      {:noreply,
       socket
       |> assign(
         selected_variant: id,
         variant_query: nil,
         variant_open: false,
         preview: nil,
         selection_form: to_form(%{"variant_id" => id}, as: :selection)
       )
       |> stream(:preview_rows, [], reset: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("search_variants", %{"variant_search" => %{"0" => query}}, socket),
    do: {:noreply, assign(socket, variant_query: query, variant_open: true)}

  def handle_event("open_variant_search", _, socket),
    do: {:noreply, assign(socket, :variant_open, true)}

  def handle_event("close_variant_search", _, socket),
    do: {:noreply, assign(socket, :variant_open, false)}

  def handle_event("preview", %{"selection" => %{"variant_id" => id}}, socket) do
    case Enum.any?(socket.assigns.variants, &(&1.id == id)) &&
           MenuPlanning.preview(socket.assigns.booking_id, id) do
      {:ok, preview} ->
        {:noreply,
         socket
         |> assign(:selected_variant, id)
         |> assign(:preview, preview)
         |> stream(:preview_rows, visible_rows(preview.rows, socket.assigns.show_breakfasts),
           reset: true
         )}

      _ ->
        {:noreply,
         socket
         |> load_state()
         |> put_flash(:error, "Vyberte dostupnou variantu menu. Seznam byl obnoven.")}
    end
  end

  def handle_event("apply", _, %{assigns: %{preview: nil}} = socket), do: {:noreply, socket}

  def handle_event("apply", _, socket) do
    preview = socket.assigns.preview

    case MenuPlanning.apply_variant(socket.assigns.booking_id, preview.variant.id, preview.token) do
      {:ok, _menu} ->
        {:noreply,
         socket
         |> load_state()
         |> put_flash(:success, "Menu přiřazeno. Ruční úpravy i společné menu byly zachovány.")}

      {:error, :stale_preview} ->
        {:noreply,
         socket
         |> load_state()
         |> put_flash(
           :error,
           "Podklady se od náhledu změnily. Vytvořte nový náhled; nic se neuložilo."
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> load_state()
         |> put_flash(
           :error,
           "Menu nelze použít. Znovu vytvořte náhled a vyřešte zobrazené chyby."
         )}
    end
  end

  def handle_event("edit_item", %{"id" => id}, socket) do
    item = find_item(socket, id)

    if item do
      {:noreply,
       socket
       |> assign(:edit_item, item)
       |> assign(:edit_version, MenuPlanning.item_version(item))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_item", _, socket), do: {:noreply, assign(socket, :edit_item, nil)}

  def handle_event("allow_replacement", %{"id" => id}, socket) do
    item = find_item(socket, id)

    result =
      if item,
        do:
          MenuPlanning.allow_item_replacement(
            socket.assigns.booking_id,
            id,
            MenuPlanning.item_version(item)
          ),
        else: {:error, :stale_item}

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_state()
         |> put_flash(
           :success,
           "Přepsání povoleno. Sestava se změní až po náhledu a použití varianty."
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> load_state()
         |> put_flash(:error, "Jídlo se mezitím změnilo. Zkontrolujte aktuální stav.")}
    end
  end

  @impl true
  def handle_info({:menu_saved, _}, socket),
    do:
      {:noreply,
       socket
       |> load_state()
       |> put_flash(:success, "Podání uloženo a chráněno před přepsáním šablonou.")}

  defp find_item(socket, id) do
    if socket.assigns.menu, do: Enum.find(socket.assigns.menu.items, &(&1.id == id))
  end

  defp open_requested_item(socket, params) do
    requested = params["edit_item"]
    item = if socket.assigns.menu, do: Enum.find(socket.assigns.menu.items, &(&1.id == requested))

    if item,
      do: assign(socket, edit_item: item, edit_version: MenuPlanning.item_version(item)),
      else: socket
  end

  defp visible_rows(rows, show?),
    do: Enum.reject(rows, &(&1.meal_type == "breakfast" and not show?))

  defp load_state(socket) do
    socket = assign_new(socket, :show_breakfasts, fn -> false end)
    booking = Bookings.get_booking!(socket.assigns.booking_id)
    menu = MenuPlanning.get_booking_menu(booking.id)
    variants = MenuPlanning.list_variants()

    rows =
      if menu do
        first = menu.items |> Enum.map(& &1.date) |> Enum.min(Date)
        last = menu.items |> Enum.map(& &1.date) |> Enum.max(Date)
        counts = PortionCounts.for_range([booking], first, last)
        Enum.map(menu.items, &Map.put(&1, :counts, counts[&1.date][&1.meal_type]))
      else
        []
      end

    requested = socket.assigns.request_context["variant"]

    selected =
      if requested && Enum.any?(variants, &(&1.id == requested)),
        do: requested,
        else:
          if(menu && Enum.any?(variants, &(&1.id == menu.menu_variant_id)),
            do: menu.menu_variant_id,
            else: ""
          )

    socket
    |> assign(
      :food_context,
      CozyCheckoutWeb.FoodNavigation.for_booking(booking)
      |> Map.merge(socket.assigns.request_context)
      |> Map.put("booking", booking.id)
    )
    |> assign(
      :freezer,
      CozyCheckout.Kitchen.Freezer.presentation(
        if MenuPlanning.stale?(menu, booking) || booking.status == "cancelled" ||
             booking.deleted_at, do: [], else: rows
      )
    )
    |> assign(:booking, booking)
    |> assign(:menu, menu)
    |> assign(:variants, variants)
    |> assign(:stale_menu, MenuPlanning.stale?(menu, booking))
    |> assign(:selected_variant, selected)
    |> assign(:variant_query, nil)
    |> assign(:variant_open, false)
    |> assign(
      :variant_options,
      Enum.map(variants, fn v ->
        %{
          id: v.id,
          name: v.name,
          hint: "#{v.days} dnů · #{CozyCheckout.Meals.MenuRecipes.readiness(v).label}"
        }
      end)
    )
    |> assign(:preview, nil)
    |> assign(:edit_item, nil)
    |> assign(:selection_form, to_form(%{"variant_id" => selected}, as: :selection))
    |> assign(:menu_rows, rows)
    |> stream(:menu_items, visible_rows(rows, socket.assigns.show_breakfasts), reset: true)
    |> stream(:preview_rows, [], reset: true)
  end
end

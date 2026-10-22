defmodule CozyCheckoutWeb.BookingLive.Menu do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Bookings
  alias CozyCheckout.Meals.{MenuPlanning, BookingMenuItem, PortionCounts}
  import CozyCheckoutWeb.MealComponents
  import CozyCheckoutWeb.KitchenComponents, only: [menu_recipe_links: 1, kitchen_header: 1]

  @impl true
  def mount(%{"booking_id" => id} = params, _, socket) do
    {:ok,
     socket
     |> assign(:request_context, CozyCheckoutWeb.FoodNavigation.context(params))
     |> assign(:booking_id, id)
     |> assign(:page_title, "Menu rezervace")
     |> load_state()}
  end

  @impl true
  def handle_event("select_variant", %{"selection" => %{"variant_id" => id}}, socket) do
    {:noreply,
     socket
     |> assign(:selected_variant, id)
     |> assign(:preview, nil)
     |> stream(:preview_rows, [], reset: true)}
  end

  def handle_event("preview", %{"selection" => %{"variant_id" => id}}, socket) do
    case Enum.any?(socket.assigns.variants, &(&1.id == id)) &&
           MenuPlanning.preview(socket.assigns.booking_id, id) do
      {:ok, preview} ->
        {:noreply,
         socket
         |> assign(:selected_variant, id)
         |> assign(:preview, preview)
         |> stream(:preview_rows, preview.rows, reset: true)}

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
    item = Enum.find(socket.assigns.menu.items, &(&1.id == id))

    if item do
      {:noreply,
       socket
       |> assign(:edit_item, item)
       |> assign(:edit_version, MenuPlanning.item_version(item))
       |> assign(:edit_form, to_form(BookingMenuItem.changeset(item, %{})))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_item", _, socket), do: {:noreply, assign(socket, :edit_item, nil)}

  def handle_event("save_item", %{"booking_menu_item" => attrs}, socket) do
    case MenuPlanning.update_booking_item(
           socket.assigns.booking_id,
           socket.assigns.edit_item.id,
           attrs,
           socket.assigns.edit_version
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_state()
         |> put_flash(:success, "Ruční úprava uložena a chráněna před přepsáním variantou.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :edit_form, to_form(cs))}

      {:error, _} ->
        {:noreply,
         socket
         |> load_state()
         |> put_flash(:error, "Jídlo mezitím změnil někdo jiný. Otevřete ho znovu.")}
    end
  end

  def handle_event("allow_replacement", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.menu.items, &(&1.id == id))

    case MenuPlanning.allow_item_replacement(
           socket.assigns.booking_id,
           id,
           MenuPlanning.item_version(item)
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_state()
         |> put_flash(
           :success,
           "Přepsání povoleno. Text se změní až po náhledu a použití varianty."
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> load_state()
         |> put_flash(:error, "Jídlo se mezitím změnilo. Zkontrolujte aktuální stav.")}
    end
  end

  defp load_state(socket) do
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

    selected =
      if menu && Enum.any?(variants, &(&1.id == menu.menu_variant_id)),
        do: menu.menu_variant_id,
        else: ""

    socket
    |> assign(
      :food_context,
      CozyCheckoutWeb.FoodNavigation.for_booking(booking)
      |> Map.merge(socket.assigns.request_context)
      |> Map.put("booking", booking.id)
    )
    |> assign(:booking, booking)
    |> assign(:menu, menu)
    |> assign(:variants, variants)
    |> assign(:stale_menu, MenuPlanning.stale?(menu, booking))
    |> assign(:selected_variant, selected)
    |> assign(:preview, nil)
    |> assign(:edit_item, nil)
    |> assign(:selection_form, to_form(%{"variant_id" => selected}, as: :selection))
    |> stream(:menu_items, rows, reset: true)
    |> stream(:preview_rows, [], reset: true)
  end
end

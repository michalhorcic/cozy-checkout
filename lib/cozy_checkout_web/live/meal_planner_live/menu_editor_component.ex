defmodule CozyCheckoutWeb.MealPlannerLive.MenuEditorComponent do
  use CozyCheckoutWeb, :live_component
  alias CozyCheckout.{Recipes, Meals.MenuRecipes}
  alias CozyCheckout.Meals.MenuVariant
  import CozyCheckoutWeb.MealComponents
  import CozyCheckoutWeb.KitchenComponents, only: [field_class: 0]

  @impl true
  def update(assigns, socket) do
    identity = {assigns.mode, assigns.record.id}

    if socket.assigns[:identity] == identity do
      {:ok, assign(socket, assigns)}
    else
      record = assigns.record

      draft =
        if assigns.mode == :variant,
          do: MenuRecipes.variant_params(record),
          else: %{"items" => [MenuRecipes.item_params(record)]}

      draft =
        if assigns.mode == :variant and draft["items"] == [], do: rebuild(draft), else: draft

      ids = Enum.flat_map(draft["items"], &selected_ids/1)
      catalog = Recipes.get_recipes(ids) |> Map.new(&{&1.id, &1})
      active = Enum.find_index(draft["items"], &(&1["id"] == assigns[:focus_item])) || 0

      {:ok,
       socket
       |> assign(assigns)
       |> assign(
         identity: identity,
         draft: draft,
         initial: draft,
         history: [],
         active: active,
         role: "main",
         pending: nil,
         error: nil,
         search: "",
         catalog: catalog,
         details: nil,
         transfer_day: "1",
         transfer_type: "dinner",
         library_open: false
       )
       |> load_choices()}
    end
  end

  @impl true
  def handle_event("validate", %{"editor" => params}, socket) do
    {:noreply, apply_inputs(socket, params)}
  end

  def handle_event("activate", %{"index" => index, "role" => role}, socket)
      when role in ["main", "extra"] do
    case index_of(socket, index) do
      nil -> {:noreply, socket}
      index -> {:noreply, assign(socket, active: index, role: role, library_open: true)}
    end
  end

  def handle_event("search", %{"recipe_search" => search}, socket),
    do: {:noreply, socket |> assign(:search, search) |> load_choices()}

  def handle_event("more", _, socket),
    do:
      {:noreply,
       if(socket.assigns.more?, do: load_choices(socket, socket.assigns.offset), else: socket)}

  def handle_event("select_recipe", %{"id" => id}, socket),
    do: select_recipe(socket, socket.assigns.active, socket.assigns.role, id)

  def handle_event("drop_recipe", %{"id" => id, "index" => index, "role" => role}, socket)
      when role in ["main", "extra"] do
    select_recipe(socket, index_of(socket, index), role, id)
  end

  def handle_event("remove_recipe", %{"index" => index, "id" => id}, socket) do
    update_slot(socket, index, fn item ->
      if item["recipe_id"] == id,
        do: Map.put(item, "recipe_id", nil),
        else:
          Map.update!(item, "supplement_recipe_ids", &Enum.reject(&1, fn old -> old == id end))
    end)
  end

  def handle_event("reorder", %{"index" => index, "id" => id, "direction" => direction}, socket) do
    update_slot(socket, index, fn item ->
      ids = item["supplement_recipe_ids"]
      pos = Enum.find_index(ids, &(&1 == id))
      new = if pos, do: pos + if(direction == "up", do: -1, else: 1)

      if new && new >= 0 && new < length(ids),
        do:
          Map.put(
            item,
            "supplement_recipe_ids",
            ids |> List.delete_at(pos) |> List.insert_at(new, id)
          ),
        else: item
    end)
  end

  def handle_event("details", %{"id" => id}, socket) do
    if match?({:ok, _}, Ecto.UUID.cast(id)) do
      case Recipes.get_recipes([id]) do
        [recipe] -> {:noreply, assign(socket, :details, recipe)}
        _ -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_library", _, socket),
    do: {:noreply, assign(socket, :library_open, false)}

  def handle_event("close_details", _, socket), do: {:noreply, assign(socket, :details, nil)}

  def handle_event("build", _, socket) do
    settings =
      MenuVariant.settings_changeset(
        socket.assigns.record,
        Map.drop(socket.assigns.draft, ["items"])
      )

    if settings.valid? do
      draft = rebuild(socket.assigns.draft)
      kept = MapSet.new(draft["items"], &coordinate/1)

      removed =
        Enum.filter(
          socket.assigns.draft["items"],
          &(filled?(&1) and not MapSet.member?(kept, coordinate(&1)))
        )

      propose(socket, draft, removed)
    else
      {:noreply, assign(socket, :error, "Opravte název, délku, penzi a hranice rozpisu.")}
    end
  end

  def handle_event(event, _, socket)
      when event in ["copy_service", "move_service", "copy_day", "breakfasts"] do
    source = Enum.at(socket.assigns.draft["items"], socket.assigns.active)
    day = parse_day(socket.assigns.transfer_day)

    target_index =
      Enum.find_index(
        socket.assigns.draft["items"],
        &(to_string(&1["day_number"]) == to_string(day) and
            &1["meal_type"] == socket.assigns.transfer_type)
      )

    cond do
      is_nil(source) ->
        {:noreply, socket}

      not truthy?(source["reviewed"]) ->
        {:noreply, assign(socket, :error, "Nejdřív zkontrolujte původní text aktivního podání.")}

      event in ["copy_service", "move_service"] and
          (is_nil(target_index) or target_index == socket.assigns.active) ->
        {:noreply, assign(socket, :error, "Vyberte jiné podání dostupné v rozpisu.")}

      event == "copy_day" and
          (is_nil(day) or to_string(day) == to_string(source["day_number"]) or
             not Enum.any?(
               socket.assigns.draft["items"],
               &(to_string(&1["day_number"]) == to_string(day))
             )) ->
        {:noreply, assign(socket, :error, "Vyberte jiný cílový den.")}

      event == "breakfasts" and
          (source["meal_type"] != "breakfast" or is_nil(source["recipe_id"])) ->
        {:noreply, assign(socket, :error, "Aktivujte snídani a vyberte recept bufetu.")}

      true ->
        originals = socket.assigns.draft["items"]

        sources =
          Enum.filter(
            originals,
            &(to_string(&1["day_number"]) == to_string(source["day_number"]))
          )

        if event == "copy_day" and Enum.any?(sources, &(not truthy?(&1["reviewed"]))) do
          {:noreply,
           assign(socket, :error, "Nejdřív zkontrolujte všechna podání zdrojového dne.")}
        else
          items =
            Enum.with_index(originals)
            |> Enum.map(fn {target, index} ->
              cond do
                event in ["copy_service", "move_service"] and index == target_index ->
                  copy_content(source, target)

                event == "move_service" and index == socket.assigns.active ->
                  Map.merge(target, %{
                    "recipe_id" => nil,
                    "supplement_recipe_ids" => [],
                    "note" => nil,
                    "reviewed" => true
                  })

                event == "copy_day" and to_string(target["day_number"]) == to_string(day) ->
                  case Enum.find(sources, &(&1["meal_type"] == target["meal_type"])) do
                    nil -> target
                    from -> copy_content(from, target)
                  end

                event == "breakfasts" and target["meal_type"] == "breakfast" ->
                  Map.merge(target, %{
                    "recipe_id" => source["recipe_id"],
                    "supplement_recipe_ids" =>
                      Enum.reject(target["supplement_recipe_ids"], &(&1 == source["recipe_id"]))
                  })

                true ->
                  target
              end
            end)

          changed =
            Enum.zip(originals, items)
            |> Enum.filter(fn {a, b} -> a != b and filled?(a) end)
            |> Enum.map(&elem(&1, 0))

          propose(socket, Map.put(socket.assigns.draft, "items", items), changed)
        end
    end
  end

  def handle_event("confirm", _, socket) do
    if socket.assigns.pending,
      do: {:noreply, socket |> change(socket.assigns.pending.draft) |> assign(:pending, nil)},
      else: {:noreply, socket}
  end

  def handle_event("cancel_pending", _, socket), do: {:noreply, assign(socket, :pending, nil)}

  def handle_event("undo", _, socket) do
    case socket.assigns.history do
      [previous | rest] ->
        {:noreply,
         assign(socket,
           draft: previous,
           history: rest,
           pending: nil,
           error: nil,
           active: min(socket.assigns.active, length(previous["items"]) - 1)
         )}

      [] ->
        {:noreply, socket}
    end
  end

  def handle_event("save", params, socket) do
    socket = if params["editor"], do: apply_inputs(socket, params["editor"]), else: socket

    result =
      if socket.assigns.mode == :variant do
        MenuRecipes.save_variant(socket.assigns.record, socket.assigns.draft)
      else
        MenuRecipes.save_booking_item(
          socket.assigns.booking_id,
          socket.assigns.record.id,
          hd(socket.assigns.draft["items"]),
          socket.assigns.version
        )
      end

    case result do
      {:ok, saved} ->
        send(self(), {:menu_saved, saved})

        {:noreply,
         socket |> assign(:initial, socket.assigns.draft) |> push_event("menu-editor-saved", %{})}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         assign(
           socket,
           :error,
           "Menu se neuložilo. Zkontrolujte název, délku, penzi a hranice jídel. Po změně nastavení aktualizujte rozpis."
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  def handle_event(_, _, socket),
    do: {:noreply, assign(socket, :error, "Neplatná operace v editoru menu.")}

  defp impact_result(pending, item, catalog) do
    case Enum.find(pending.draft["items"], &(coordinate(&1) == coordinate(item))) do
      nil ->
        "Podání odstranit"

      result ->
        case selected_ids(result) do
          [] -> "Prázdné podání"
          ids -> Enum.map_join(ids, ", ", &recipe_name(catalog, &1))
        end
    end
  end

  defp apply_inputs(socket, params) do
    items =
      Enum.with_index(socket.assigns.draft["items"])
      |> Enum.map(fn {item, index} ->
        inputs = get_in(params, ["items", to_string(index)]) || %{}

        Map.merge(
          item,
          Map.take(inputs, ~w(note reviewed))
          |> Map.new(fn {key, value} ->
            {key, if(key == "reviewed", do: truthy?(value), else: value)}
          end)
        )
      end)

    draft =
      Map.merge(
        socket.assigns.draft,
        Map.take(params, ~w(name days meal_plan first_meal last_meal))
      )
      |> Map.put("items", items)

    socket
    |> assign(
      transfer_day: params["transfer_day"] || socket.assigns.transfer_day,
      transfer_type: params["transfer_type"] || socket.assigns.transfer_type
    )
    |> change(draft)
  end

  defp select_recipe(socket, index, role, id) do
    if is_nil(index) or not match?({:ok, _}, Ecto.UUID.cast(id)) do
      {:noreply, assign(socket, :error, "Neplatný výběr receptu.")}
    else
      item = Enum.at(socket.assigns.draft["items"], index)

      case Recipes.get_recipes([id]) do
        [recipe] ->
          if recipe.archived_at && id not in selected_ids(item) do
            {:noreply, assign(socket, :error, "Archivovaný recept nelze nově vybrat.")}
          else
            socket =
              assign(socket,
                catalog: Map.put(socket.assigns.catalog, id, recipe),
                library_open: false
              )

            update_slot(socket, to_string(index), fn row ->
              if role == "main",
                do:
                  Map.merge(row, %{
                    "recipe_id" => id,
                    "supplement_recipe_ids" =>
                      Enum.reject(row["supplement_recipe_ids"], &(&1 == id))
                  }),
                else:
                  if(id in selected_ids(row),
                    do: row,
                    else: Map.update!(row, "supplement_recipe_ids", &(&1 ++ [id]))
                  )
            end)
          end

        _ ->
          {:noreply, assign(socket, :error, "Recept není dostupný.")}
      end
    end
  end

  defp update_slot(socket, index, fun) do
    case index_of(socket, index) do
      nil ->
        {:noreply, socket}

      index ->
        {:noreply,
         change(
           socket,
           Map.update!(socket.assigns.draft, "items", &List.update_at(&1, index, fun))
         )}
    end
  end

  defp change(socket, draft) do
    if draft == socket.assigns.draft,
      do: socket,
      else:
        assign(socket,
          draft: draft,
          history: Enum.take([socket.assigns.draft | socket.assigns.history], 20),
          active: min(socket.assigns.active, max(length(draft["items"]) - 1, 0)),
          error: nil
        )
  end

  defp propose(socket, draft, []), do: {:noreply, change(socket, draft)}

  defp propose(socket, draft, affected),
    do: {:noreply, assign(socket, :pending, %{draft: draft, affected: affected})}

  defp load_choices(socket, offset \\ 0) do
    page = Recipes.search_recipes(socket.assigns.search, offset)
    choices = if offset == 0, do: page.recipes, else: socket.assigns.choices ++ page.recipes

    assign(socket,
      choices: Enum.uniq_by(choices, & &1.id),
      more?: page.more?,
      offset: page.next_offset
    )
  end

  defp rebuild(draft) do
    settings =
      MenuVariant.settings_changeset(%MenuVariant{}, draft) |> Ecto.Changeset.apply_changes()

    items =
      Enum.map(MenuVariant.slots(settings), fn {day, type} ->
        Enum.find(draft["items"], &(coordinate(&1) == {to_string(day), type})) ||
          %{
            "day_number" => day,
            "meal_type" => type,
            "recipe_id" => nil,
            "supplement_recipe_ids" => [],
            "note" => "",
            "reviewed" => true
          }
      end)

    Map.put(draft, "items", items)
  end

  defp copy_content(source, target),
    do: Map.merge(target, Map.take(source, ~w(recipe_id supplement_recipe_ids note reviewed)))

  defp coordinate(item), do: {to_string(item["day_number"]), item["meal_type"]}

  defp selected_ids(item),
    do: Enum.reject([item["recipe_id"] | item["supplement_recipe_ids"]], &(&1 in [nil, ""]))

  defp filled?(item),
    do: selected_ids(item) != [] or item["note"] not in [nil, ""] or not truthy?(item["reviewed"])

  defp truthy?(value), do: value in [true, "true"]

  defp parse_day(value) do
    case Integer.parse(to_string(value)) do
      {day, ""} when day in 1..366 -> day
      _ -> nil
    end
  end

  defp index_of(socket, value) do
    case Integer.parse(to_string(value)) do
      {index, ""} when index >= 0 -> if index < length(socket.assigns.draft["items"]), do: index
      _ -> nil
    end
  end

  defp recipe_name(catalog, id),
    do: if(catalog[id], do: catalog[id].name, else: "Chybí hlavní recept")

  defp legacy_source(assigns, item) do
    originals = if assigns.mode == :variant, do: assigns.record.items, else: [assigns.record]
    Enum.find(originals, &(&1.id == item["id"]))
  end

  defp error_message(reason) when reason in [:stale_variant, :stale_item],
    do:
      "Menu mezitím změnil někdo jiný nebo se změnil pobyt. Nic se neuložilo; otevřete editor znovu."

  defp error_message(:duplicate_recipe), do: "Jeden recept nesmí být v podání dvakrát."

  defp error_message(_),
    do: "Menu se neuložilo. Některý recept nebo podání není dostupné. Zkontrolujte výběr."
end

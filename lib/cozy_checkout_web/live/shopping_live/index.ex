defmodule CozyCheckoutWeb.ShoppingLive.Index do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.{Recipes, Repo}
  alias CozyCheckout.Kitchen.ShoppingList
  alias CozyCheckout.Recipes.Recipe
  import CozyCheckoutWeb.KitchenComponents

  @impl true
  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:category, "")
     |> assign(:mode, "")
     |> assign(:edit_ingredient, nil)
     |> assign(:range_error, nil)}
  end

  @impl true
  def handle_params(params, _, socket) do
    {first, last} = default_weekend()
    first = params["from"] || Date.to_iso8601(first)
    last = params["to"] || Date.to_iso8601(last)
    booking_id = params["booking"] || ""

    socket =
      socket
      |> assign(:page_title, "Nákup pro kuchyň")
      |> assign(
        :range_form,
        to_form(%{"from" => first, "to" => last, "booking" => booking_id}, as: :range)
      )
      |> assign(:expanded, MapSet.new())
      |> assign(:edit_ingredient, nil)

    case load(first, last, booking_id) do
      {:ok, result} ->
        {:noreply, assign_result(socket, result, booking_id)}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:range_error, error_message(error))
         |> assign(:result, nil)
         |> assign(:booking_options, [{"Všechny skupiny", ""}])
         |> assign(:visible_count, 0)
         |> stream(:rows, [], reset: true)}
    end
  end

  @impl true
  def handle_event("apply_range", %{"range" => p}, socket) do
    case load(p["from"], p["to"], p["booking"]) do
      {:ok, _} ->
        {:noreply, push_patch(socket, to: shopping_path(socket.assigns.live_action, p))}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:range_error, error_message(error))
         |> assign(:range_form, to_form(p, as: :range))
         |> assign(:result, nil)}
    end
  end

  def handle_event("filter", %{"filter" => p}, socket) do
    {:noreply,
     socket
     |> assign(:search, p["search"] || "")
     |> assign(:category, p["category"] || "")
     |> assign(:mode, p["mode"] || "")
     |> filter_rows()}
  end

  def handle_event("toggle_sources", %{"id" => id}, socket) do
    row = Enum.find(socket.assigns.result.rows, &(&1.id == id))

    if row && MapSet.member?(socket.assigns.visible_ids, id) do
      expanded =
        if MapSet.member?(socket.assigns.expanded, id),
          do: MapSet.delete(socket.assigns.expanded, id),
          else: MapSet.put(socket.assigns.expanded, id)

      row =
        row
        |> Map.put(:expanded, MapSet.member?(expanded, id))
        |> Map.put(:category_start, MapSet.member?(socket.assigns.category_starts, id))

      {:noreply, socket |> assign(:expanded, expanded) |> stream_insert(:rows, row)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh", _, socket) do
    p = socket.assigns.range_form.params

    case load(p["from"], p["to"], p["booking"]) do
      {:ok, result} ->
        {:noreply, assign_result(socket, result, p["booking"])}

      {:error, error} ->
        {:noreply, socket |> assign(:range_error, error_message(error)) |> assign(:result, nil)}
    end
  end

  def handle_event("edit_purchase", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.result.rows, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      row ->
        ingredient = Recipes.get_ingredient!(row.id)

        {:noreply,
         socket
         |> assign(:edit_ingredient, ingredient)
         |> assign(
           :purchase_form,
           to_form(CozyCheckout.Recipes.Ingredient.changeset(ingredient, %{}))
         )}
    end
  end

  def handle_event("close_purchase", _, socket),
    do: {:noreply, assign(socket, :edit_ingredient, nil)}

  def handle_event("save_purchase", %{"ingredient" => attrs}, socket) do
    case Recipes.update_ingredient(
           socket.assigns.edit_ingredient,
           Map.take(attrs, ["purchase_mode", "package_size"])
         ) do
      {:ok, _} ->
        p = socket.assigns.range_form.params

        case load(p["from"], p["to"], p["booking"]) do
          {:ok, result} ->
            {:noreply,
             socket |> assign(:edit_ingredient, nil) |> assign_result(result, p["booking"])}

          {:error, error} ->
            {:noreply,
             socket
             |> assign(:edit_ingredient, nil)
             |> assign(:range_error, error_message(error))
             |> assign(:result, nil)}
        end

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :purchase_form, to_form(cs))}

      _ ->
        {:noreply, put_flash(socket, :error, "Nastavení se mezitím změnilo. Otevřete ho znovu.")}
    end
  end

  defp assign_result(socket, result, booking_id) do
    options = [
      {"Všechny skupiny", ""}
      | Enum.map(result.booking_options, fn b ->
          {"#{b.guest.name} · #{ShoppingList.date_label(b.check_in_date)}", b.id}
        end)
    ]

    socket
    |> assign(:result, result)
    |> assign(:range_error, nil)
    |> assign(:booking_id, booking_id || "")
    |> assign(:booking_options, options)
    |> assign(:categories, result.rows |> Enum.map(& &1.ingredient.category) |> Enum.uniq())
    |> assign(:signatures, Map.new(result.rows, &{&1.id, &1.fingerprint}) |> Jason.encode!())
    |> assign(:checklist_scope, "#{result.start_date}:#{result.end_date}:#{booking_id}")
    |> assign(:buffet_recipe, Repo.get_by(Recipe, source_key: "kitchen:breakfast-buffet:v1"))
    |> filter_rows()
  end

  defp filter_rows(socket) do
    rows =
      Enum.filter(socket.assigns.result.rows, fn row ->
        String.contains?(
          Recipes.normalize(row.ingredient.name),
          Recipes.normalize(socket.assigns.search)
        ) and
          (socket.assigns.category == "" or row.ingredient.category == socket.assigns.category) and
          (socket.assigns.mode == "" or row.ingredient.purchase_mode == socket.assigns.mode)
      end)

    {rows, _} =
      Enum.map_reduce(rows, nil, fn row, previous ->
        {Map.put(row, :category_start, row.ingredient.category != previous),
         row.ingredient.category}
      end)

    rows = Enum.map(rows, &Map.put(&1, :expanded, MapSet.member?(socket.assigns.expanded, &1.id)))

    socket
    |> assign(:visible_ids, MapSet.new(rows, & &1.id))
    |> assign(:category_starts, rows |> Enum.filter(& &1.category_start) |> MapSet.new(& &1.id))
    |> assign(:visible_count, length(rows))
    |> assign(
      :filter_form,
      to_form(
        %{
          "search" => socket.assigns.search,
          "category" => socket.assigns.category,
          "mode" => socket.assigns.mode
        },
        as: :filter
      )
    )
    |> stream(:rows, rows, reset: true)
  end

  defp load(first, last, booking_id) do
    with {:ok, first} <- Date.from_iso8601(first || ""),
         {:ok, last} <- Date.from_iso8601(last || "") do
      ShoppingList.generate(first, last, booking_id)
    else
      _ -> {:error, :invalid_range}
    end
  end

  defp shopping_path(action, p) do
    if action == :print,
      do:
        ~p"/admin/kitchen-shopping/print?#{%{from: p["from"], to: p["to"], booking: p["booking"] || ""}}",
      else:
        ~p"/admin/kitchen-shopping?#{%{from: p["from"], to: p["to"], booking: p["booking"] || ""}}"
  end

  defp default_weekend do
    today = Date.utc_today()
    monday = Date.add(today, 1 - Date.day_of_week(today))
    {Date.add(monday, 4), Date.add(monday, 6)}
  end

  defp error_message(:booking_unavailable),
    do: "Vybraná rezervace v období není dostupná. Vyberte jinou skupinu nebo všechny skupiny."

  defp error_message(_),
    do: "Zvolte platné období: od prvního do posledního dne, nejvýše 366 dnů."

  defp quantity(value, unit), do: Recipes.format_quantity(value, unit)

  defp number(value),
    do: value |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")

  defp recipe_path(source) do
    ~p"/admin/recipes/#{source.recipe.id}?#{%{adults: source.adults, children: source.children, percent: Decimal.to_string(Decimal.mult(source.factor, 100), :normal)}}"
  end
end

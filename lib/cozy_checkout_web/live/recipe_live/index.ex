defmodule CozyCheckoutWeb.RecipeLive.Index do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Recipes
  alias CozyCheckout.Recipes.{Recipe, RecipeLine, Ingredient}
  import CozyCheckoutWeb.KitchenComponents

  @impl true
  def mount(_, _, socket),
    do:
      {:ok,
       socket
       |> assign(:search, "")
       |> assign(:quick_ingredient_open, false)}

  @impl true
  def handle_params(params, _, socket) do
    socket = assign(socket, :food_context, CozyCheckoutWeb.FoodNavigation.context(params))

    recipe =
      case socket.assigns.live_action do
        :new -> %Recipe{lines: [%RecipeLine{}]}
        :edit -> Recipes.get_recipe!(params["id"])
        _ -> nil
      end

    socket =
      assign(
        socket,
        :editor_back,
        if(recipe && recipe.id,
          do: CozyCheckoutWeb.FoodNavigation.with_context("/admin/recipes/#{recipe.id}", params),
          else: CozyCheckoutWeb.FoodNavigation.path(:recipes, params)
        )
      )

    all = Recipes.list_recipes(socket.assigns.search)

    {:noreply,
     socket
     |> assign(:page_title, "Recepty")
     |> assign(:recipe, recipe)
     |> assign(:form, if(recipe, do: to_form(Recipe.changeset(recipe, %{}))))
     |> assign(:ingredients, Recipes.list_ingredients("", true))
     |> assign(:ingredient_queries, %{})
     |> assign(:active_ingredient, nil)
     |> assign(:result_count, length(all))
     |> stream(:recipes, all, reset: true)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    recipes = Recipes.list_recipes(search)

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:result_count, length(recipes))
     |> stream(:recipes, recipes, reset: true)}
  end

  def handle_event("validate", %{"recipe" => attrs}, socket),
    do:
      {:noreply,
       assign(
         socket,
         :form,
         to_form(
           Recipe.changeset(socket.assigns.recipe, Map.put_new(attrs, "lines", %{})),
           action: :validate
         )
       )}

  def handle_event("open_ingredient_search", %{"index" => index}, socket),
    do: {:noreply, assign(socket, :active_ingredient, index)}

  def handle_event("close_ingredient_search", _, socket),
    do: {:noreply, assign(socket, :active_ingredient, nil)}

  def handle_event(
        "search_ingredients",
        %{"ingredient_search" => queries, "_target" => ["ingredient_search", index]},
        socket
      ) do
    params = line_params(socket)

    case params["lines"][index] do
      nil ->
        {:noreply, socket}

      line ->
        # A typed name must be selected before saving; never keep a previous ID
        # behind a different search query.
        lines = Map.put(params["lines"], index, Map.put(line, "ingredient_id", ""))

        {:noreply,
         socket
         |> assign(
           :ingredient_queries,
           Map.put(socket.assigns.ingredient_queries, index, queries[index])
         )
         |> assign(:active_ingredient, index)
         |> assign(
           :form,
           to_form(Recipe.changeset(socket.assigns.recipe, Map.put(params, "lines", lines)))
         )}
    end
  end

  def handle_event("select_ingredient", %{"index" => index, "id" => id}, socket) do
    params = line_params(socket)
    ingredient = Enum.find(socket.assigns.ingredients, &(&1.id == id && is_nil(&1.archived_at)))

    case {params["lines"][index], ingredient} do
      {line, ingredient} when not is_nil(line) and not is_nil(ingredient) ->
        unit =
          if Recipes.compatible?(line["unit"], ingredient.base_unit),
            do: line["unit"],
            else: ingredient.base_unit

        line = Map.merge(line, %{"ingredient_id" => ingredient.id, "unit" => unit})
        lines = Map.put(params["lines"], index, line)

        {:noreply,
         socket
         |> assign(:ingredient_queries, Map.delete(socket.assigns.ingredient_queries, index))
         |> assign(:active_ingredient, nil)
         |> assign(
           :form,
           to_form(Recipe.changeset(socket.assigns.recipe, Map.put(params, "lines", lines)))
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("add_line", _, socket) do
    params = line_params(socket)
    lines = Map.put(params["lines"], to_string(map_size(params["lines"])), %{})

    {:noreply,
     socket
     |> assign(:ingredient_queries, %{})
     |> assign(:active_ingredient, nil)
     |> assign(
       :form,
       to_form(Recipe.changeset(socket.assigns.recipe, Map.put(params, "lines", lines)))
     )}
  end

  def handle_event("remove_line", %{"index" => index}, socket) do
    params = line_params(socket)
    socket = assign(socket, ingredient_queries: %{}, active_ingredient: nil)

    {:noreply,
     assign(
       socket,
       :form,
       to_form(
         Recipe.changeset(
           socket.assigns.recipe,
           Map.put(params, "lines", Map.delete(params["lines"], index))
         )
       )
     )}
  end

  def handle_event("save", %{"recipe" => attrs}, socket) do
    # A form without nested fields means the last line was removed. Keep the
    # empty association explicit so Ecto validates it instead of restoring it.
    attrs = Map.put_new(attrs, "lines", %{})

    result =
      if socket.assigns.recipe.id,
        do: Recipes.update_recipe(socket.assigns.recipe, attrs),
        else: Recipes.create_recipe(attrs)

    case result do
      {:ok, recipe} ->
        {:noreply,
         socket
         |> put_flash(:success, "Recept uložen")
         |> push_navigate(
           to:
             CozyCheckoutWeb.FoodNavigation.with_context(
               ~p"/admin/recipes/#{recipe.id}",
               socket.assigns.food_context
             )
         )}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(cs))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Recept se mezitím změnil. Otevřete ho znovu.")}
    end
  end

  def handle_event("new_ingredient", _, socket) do
    {:noreply,
     socket
     |> assign(:quick_ingredient_open, true)
     |> assign(:quick_ingredient_form, to_form(Ingredient.changeset(%Ingredient{}, %{})))}
  end

  def handle_event("close_ingredient", _, socket),
    do: {:noreply, assign(socket, :quick_ingredient_open, false)}

  def handle_event("save_ingredient", %{"ingredient" => attrs}, socket) do
    case Recipes.create_ingredient(attrs) do
      {:ok, ingredient} ->
        params = line_params(socket)

        {index, line} =
          Enum.find(params["lines"], fn {_, l} -> l["ingredient_id"] in [nil, ""] end) ||
            {to_string(map_size(params["lines"])), %{}}

        line =
          Map.merge(line, %{"ingredient_id" => ingredient.id, "unit" => ingredient.base_unit})

        params = Map.put(params, "lines", Map.put(params["lines"], index, line))

        {:noreply,
         socket
         |> assign(:quick_ingredient_open, false)
         |> assign(:ingredient_queries, %{})
         |> assign(:active_ingredient, nil)
         |> assign(:ingredients, Recipes.list_ingredients("", true))
         |> assign(:form, to_form(Recipe.changeset(socket.assigns.recipe, params)))}

      {:error, cs} ->
        {:noreply, assign(socket, :quick_ingredient_form, to_form(cs))}
    end
  end

  defp line_params(socket) do
    lines =
      Ecto.Changeset.get_field(socket.assigns.form.source, :lines, [])
      |> Enum.with_index()
      |> Map.new(fn {line, index} ->
        {to_string(index),
         Map.new(
           [:id, :ingredient_id, :quantity, :unit, :notes, :position],
           &{to_string(&1), Map.get(line, &1)}
         )}
      end)

    Map.put(socket.assigns.form.params || %{}, "lines", lines)
  end
end

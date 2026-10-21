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
       |> assign(:settings_open, false)
       |> assign(:settings_error, nil)
       |> assign(:quick_ingredient_open, false)}

  @impl true
  def handle_params(params, _, socket) do
    recipe =
      case socket.assigns.live_action do
        :new -> %Recipe{lines: [%RecipeLine{}]}
        :edit -> Recipes.get_recipe!(params["id"])
        _ -> nil
      end

    all = Recipes.list_recipes(socket.assigns.search)

    {:noreply,
     socket
     |> assign(:page_title, "Recepty")
     |> assign(:recipe, recipe)
     |> assign(:form, if(recipe, do: to_form(Recipe.changeset(recipe, %{}))))
     |> assign(:ingredients, Recipes.list_ingredients("", true))
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

  def handle_event("add_line", _, socket) do
    params = line_params(socket)
    lines = Map.put(params["lines"], to_string(map_size(params["lines"])), %{})

    {:noreply,
     assign(
       socket,
       :form,
       to_form(Recipe.changeset(socket.assigns.recipe, Map.put(params, "lines", lines)))
     )}
  end

  def handle_event("remove_line", %{"index" => index}, socket) do
    params = line_params(socket)

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
         |> put_flash(:info, "Recept uložen")
         |> push_navigate(to: ~p"/admin/recipes/#{recipe.id}")}

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
         |> assign(:ingredients, Recipes.list_ingredients("", true))
         |> assign(:form, to_form(Recipe.changeset(socket.assigns.recipe, params)))}

      {:error, cs} ->
        {:noreply, assign(socket, :quick_ingredient_form, to_form(cs))}
    end
  end

  def handle_event("settings", _, socket) do
    s = Recipes.settings()

    {:noreply,
     socket
     |> assign(:settings_open, true)
     |> assign(:settings, s)
     |> assign(:settings_error, nil)
     |> assign(
       :settings_form,
       to_form(
         %{
           "hot" => Decimal.to_string(Decimal.mult(s.hot_child_factor, 100), :normal),
           "breakfast" => Decimal.to_string(Decimal.mult(s.breakfast_child_factor, 100), :normal)
         },
         as: :portions
       )
     )}
  end

  def handle_event("close_settings", _, socket),
    do: {:noreply, assign(socket, :settings_open, false)}

  def handle_event("save_settings", %{"portions" => p}, socket) do
    with {hot, ""} <- Decimal.parse(String.replace(p["hot"], ",", ".")),
         {breakfast, ""} <- Decimal.parse(String.replace(p["breakfast"], ",", ".")),
         {:ok, _} <-
           Recipes.update_settings(socket.assigns.settings, %{
             hot_child_factor: Decimal.div(hot, 100),
             breakfast_child_factor: Decimal.div(breakfast, 100)
           }) do
      {:noreply,
       socket
       |> assign(:settings_open, false)
       |> put_flash(:info, "Velikost dětských porcí uložena")}
    else
      _ ->
        {:noreply,
         assign(
           socket,
           :settings_error,
           "Zadejte hodnoty od 0 do 100 %. Při souběžné změně nastavení znovu otevřete."
         )}
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

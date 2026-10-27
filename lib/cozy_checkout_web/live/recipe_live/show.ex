defmodule CozyCheckoutWeb.RecipeLive.Show do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Recipes
  alias CozyCheckout.Recipes.Consumption
  import CozyCheckoutWeb.KitchenComponents
  @impl true
  def mount(_, _, socket), do: {:ok, socket}
  @impl true
  def handle_params(%{"id" => id} = params, _, socket) do
    socket = assign(socket, :food_context, CozyCheckoutWeb.FoodNavigation.context(params))
    recipe = Recipes.get_recipe!(id)
    factor = Recipes.settings().hot_child_factor

    defaults = %{
      "adults" => to_string(max(Decimal.to_integer(recipe.base_servings), 1)),
      "children" => "0",
      "percent" => Decimal.to_string(Decimal.mult(factor, 100), :normal)
    }

    values = Map.merge(defaults, Map.take(params, ["adults", "children", "percent"]))

    {values, adults, children, factor} =
      case parse_calculator(values) do
        {:ok, a, c, f} -> {values, a, c, f}
        _ -> {defaults, String.to_integer(defaults["adults"]), 0, factor}
      end

    {:noreply,
     socket
     |> assign(:back, CozyCheckoutWeb.FoodNavigation.back_path(params, "/admin/recipes"))
     |> assign(:back_label, CozyCheckoutWeb.FoodNavigation.back_label(params, "Zpět na recepty"))
     |> assign(:page_title, recipe.name)
     |> assign(:recipe, recipe)
     |> assign_costs(recipe)
     |> assign(:error, nil)
     |> assign(
       :calculator,
       to_form(
         values,
         as: :calculator
       )
     )
     |> assign(:result, Consumption.calculate([recipe], adults, children, factor))}
  end

  defp assign_costs(socket, recipe) do
    settings = Recipes.settings()
    today = Date.utc_today()

    assign(socket, :portion_costs, [
      {"Teplé jídlo",
       CozyCheckout.KitchenCosts.recipe_cost(recipe, today, settings.hot_child_factor)},
      {"Snídaně",
       CozyCheckout.KitchenCosts.recipe_cost(recipe, today, settings.breakfast_child_factor)}
    ])
  end

  @impl true
  def handle_event("calculate", %{"calculator" => params}, socket) do
    with {:ok, adults, children, factor} <- parse_calculator(params) do
      {:noreply,
       socket
       |> assign(:error, nil)
       |> assign(:calculator, to_form(params, as: :calculator))
       |> assign(
         :result,
         Consumption.calculate(
           [socket.assigns.recipe],
           adults,
           children,
           factor
         )
       )}
    else
      _ ->
        {:noreply,
         assign(
           socket,
           :error,
           "Zadejte celé nezáporné počty osob a velikost dětské porce od 0 do 100 %."
         )}
    end
  end

  defp parse_calculator(params) do
    with {adults, ""} when adults >= 0 <- Integer.parse(params["adults"] || ""),
         {children, ""} when children >= 0 <- Integer.parse(params["children"] || ""),
         {percent, ""} <- Decimal.parse(String.replace(params["percent"] || "", ",", ".")),
         true <- Decimal.compare(percent, 0) != :lt and Decimal.compare(percent, 100) != :gt do
      {:ok, adults, children, Decimal.div(percent, 100)}
    else
      _ -> :error
    end
  end
end

defmodule CozyCheckoutWeb.RecipeLive.Show do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Recipes
  alias CozyCheckout.Recipes.Consumption
  import CozyCheckoutWeb.KitchenComponents
  @impl true
  def mount(_, _, socket), do: {:ok, socket}
  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    recipe = Recipes.get_recipe!(id)
    factor = Recipes.settings().hot_child_factor
    adults = max(Decimal.to_integer(recipe.base_servings), 1)

    {:noreply,
     socket
     |> assign(:page_title, recipe.name)
     |> assign(:recipe, recipe)
     |> assign(:error, nil)
     |> assign(
       :calculator,
       to_form(
         %{
           "adults" => to_string(adults),
           "children" => "0",
           "percent" => Decimal.to_string(Decimal.mult(factor, 100), :normal)
         },
         as: :calculator
       )
     )
     |> assign(:result, Consumption.calculate([recipe], adults, 0, factor))}
  end

  @impl true
  def handle_event("calculate", %{"calculator" => params}, socket) do
    with {adults, ""} when adults >= 0 <- Integer.parse(params["adults"]),
         {children, ""} when children >= 0 <- Integer.parse(params["children"]),
         {percent, ""} <- Decimal.parse(String.replace(params["percent"], ",", ".")),
         true <- Decimal.compare(percent, 0) != :lt and Decimal.compare(percent, 100) != :gt do
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
           Decimal.div(percent, 100)
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
end

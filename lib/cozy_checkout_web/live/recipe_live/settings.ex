defmodule CozyCheckoutWeb.RecipeLive.Settings do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Recipes
  import CozyCheckoutWeb.KitchenComponents

  def mount(_, _, socket) do
    settings = Recipes.settings()

    {:ok,
     socket
     |> assign(:settings, settings)
     |> assign(:error, nil)
     |> assign(:page_title, "Nastavení porcí")
     |> assign(
       :form,
       to_form(
         %{
           "hot" => percent(settings.hot_child_factor),
           "breakfast" => percent(settings.breakfast_child_factor)
         },
         as: :portions
       )
     )}
  end

  def handle_params(params, _, socket),
    do: {:noreply, assign(socket, :food_context, CozyCheckoutWeb.FoodNavigation.context(params))}

  def handle_event("save", %{"portions" => params}, socket) do
    with {hot, ""} <- Decimal.parse(String.replace(params["hot"] || "", ",", ".")),
         {breakfast, ""} <- Decimal.parse(String.replace(params["breakfast"] || "", ",", ".")),
         {:ok, settings} <-
           Recipes.update_settings(socket.assigns.settings, %{
             hot_child_factor: Decimal.div(hot, 100),
             breakfast_child_factor: Decimal.div(breakfast, 100)
           }) do
      {:noreply,
       socket
       |> assign(:settings, settings)
       |> assign(:error, nil)
       |> assign(:form, to_form(params, as: :portions))
       |> put_flash(:success, "Velikost dětských porcí uložena")}
    else
      {:error, :stale} ->
        {:noreply,
         assign(
           socket,
           :error,
           "Nastavení mezitím změnil někdo jiný. Obnovte stránku a zkontrolujte hodnoty."
         )}

      _ ->
        {:noreply,
         socket
         |> assign(:form, to_form(params, as: :portions))
         |> assign(:error, "Zadejte hodnoty od 0 do 100 %.")}
    end
  end

  defp percent(value),
    do: value |> Decimal.mult(100) |> Decimal.normalize() |> Decimal.to_string(:normal)
end

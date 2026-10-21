defmodule CozyCheckoutWeb.RecipeLive.Ingredients do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Recipes
  alias CozyCheckout.Recipes.Ingredient
  import CozyCheckoutWeb.KitchenComponents
  @impl true
  def mount(_, _, socket), do: {:ok, assign(socket, :search, "")}
  @impl true
  def handle_params(params, _, socket) do
    ingredient =
      case socket.assigns.live_action do
        :new -> %Ingredient{}
        :edit -> Recipes.get_ingredient!(params["id"])
        _ -> nil
      end

    rows = Recipes.list_ingredients(socket.assigns.search)

    {:noreply,
     socket
     |> assign(:page_title, "Suroviny")
     |> assign(:ingredient, ingredient)
     |> assign(:form, if(ingredient, do: to_form(Ingredient.changeset(ingredient, %{}))))
     |> assign(:result_count, length(rows))
     |> stream(:ingredients, rows, reset: true)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    rows = Recipes.list_ingredients(search)

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:result_count, length(rows))
     |> stream(:ingredients, rows, reset: true)}
  end

  def handle_event("validate", %{"ingredient" => attrs}, socket),
    do:
      {:noreply,
       assign(
         socket,
         :form,
         to_form(Ingredient.changeset(socket.assigns.ingredient, attrs), action: :validate)
       )}

  def handle_event("save", %{"ingredient" => attrs}, socket) do
    result =
      if socket.assigns.ingredient.id,
        do: Recipes.update_ingredient(socket.assigns.ingredient, attrs),
        else: Recipes.create_ingredient(attrs)

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:success, "Surovina uložena")
         |> push_patch(to: ~p"/admin/ingredients")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(cs))}

      _ ->
        {:noreply, put_flash(socket, :error, "Surovina se mezitím změnila. Znovu ji otevřete.")}
    end
  end
end

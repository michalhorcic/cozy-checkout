defmodule CozyCheckoutWeb.FreezerLive.Index do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.{Recipes}
  alias CozyCheckout.Kitchen.{Freezer, FreezerItem}
  import CozyCheckoutWeb.KitchenComponents

  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(
       search: "",
       archived: false,
       editing: nil,
       removing: nil,
       ingredients: Recipes.list_ingredients("", true),
       recipes: Recipes.list_recipes("", true)
     )
     |> reload()}
  end

  def handle_params(params, _, socket),
    do: {:noreply, assign(socket, :food_context, CozyCheckoutWeb.FoodNavigation.context(params))}

  def handle_event("filter", %{"filter" => p}, socket) do
    {:noreply,
     socket |> assign(search: p["search"], archived: p["archived"] == "true") |> reload()}
  end

  def handle_event("new", _, socket),
    do: {:noreply, edit(socket, %FreezerItem{frozen_on: Freezer.today()})}

  def handle_event("edit", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.items, &(&1.id == id)) do
      nil -> {:noreply, socket}
      item -> {:noreply, edit(socket, item)}
    end
  end

  def handle_event("close", _, socket),
    do: {:noreply, assign(socket, editing: nil, removing: nil)}

  def handle_event("validate", %{"freezer_item" => attrs}, socket) do
    attrs =
      case attrs["link"] do
        "ingredient:" <> id -> Map.merge(attrs, %{"ingredient_id" => id, "recipe_id" => ""})
        "recipe:" <> id -> Map.merge(attrs, %{"recipe_id" => id, "ingredient_id" => ""})
        _ -> Map.merge(attrs, %{"ingredient_id" => "", "recipe_id" => ""})
      end

    selected =
      Enum.find(
        socket.assigns.ingredients ++ socket.assigns.recipes,
        &(&1.id in [attrs["ingredient_id"], attrs["recipe_id"]])
      )

    previous = socket.assigns.form.params["link"] || link_value(socket.assigns.editing)

    attrs =
      if selected && attrs["link"] != previous,
        do: Map.put(attrs, "name", selected.name),
        else: attrs

    {:noreply,
     assign(
       socket,
       :form,
       to_form(
         FreezerItem.changeset(socket.assigns.editing, attrs)
         |> Map.put(:action, :validate)
       )
     )}
  end

  def handle_event("save", %{"freezer_item" => attrs}, socket) do
    attrs =
      case attrs["link"] do
        "ingredient:" <> id -> Map.merge(attrs, %{"ingredient_id" => id, "recipe_id" => ""})
        "recipe:" <> id -> Map.merge(attrs, %{"recipe_id" => id, "ingredient_id" => ""})
        _ -> Map.merge(attrs, %{"ingredient_id" => "", "recipe_id" => ""})
      end

    item = socket.assigns.editing
    result = if item.id, do: Freezer.update_item(item, attrs), else: Freezer.create_item(attrs)

    case result do
      {:error, %Ecto.Changeset{} = cs} -> {:noreply, assign(socket, :form, to_form(cs))}
      result -> finish(socket, result)
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    {:noreply, assign(socket, :removing, Enum.find(socket.assigns.items, &(&1.id == id)))}
  end

  def handle_event("take", %{"amount" => amount}, socket),
    do: finish(socket, Freezer.remove(socket.assigns.removing, amount))

  def handle_event("all", _, socket),
    do: finish(socket, Freezer.remove(socket.assigns.removing, :all))

  def handle_event("archive", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.items, &(&1.id == id)) do
      nil -> {:noreply, socket}
      item -> finish(socket, Freezer.archive_item(item))
    end
  end

  defp finish(socket, {:ok, _}),
    do:
      {:noreply,
       socket
       |> assign(editing: nil, removing: nil)
       |> reload()
       |> put_flash(:success, "Evidence mrazáku uložena.")}

  defp finish(socket, {:error, :invalid_amount}),
    do:
      {:noreply,
       put_flash(socket, :error, "Zadejte kladné množství nejvýše do dostupného zůstatku.")}

  defp finish(socket, _),
    do:
      {:noreply,
       socket
       |> assign(editing: nil, removing: nil)
       |> reload()
       |> put_flash(:error, "Položka se mezitím změnila. Přehled byl obnoven; otevřete ji znovu.")}

  defp edit(socket, item),
    do: assign(socket, editing: item, form: to_form(FreezerItem.changeset(item, %{})))

  defp reload(socket),
    do:
      assign(socket,
        items: Freezer.list_items(socket.assigns.search, socket.assigns.archived),
        page_title: "Mrazák"
      )

  defp link_value(%{ingredient_id: id}) when not is_nil(id), do: "ingredient:" <> id
  defp link_value(%{recipe_id: id}) when not is_nil(id), do: "recipe:" <> id
  defp link_value(_), do: ""

  defp options(socket_items, current, prefix) do
    socket_items
    |> Enum.filter(&(is_nil(&1.archived_at) || link_value(current) == prefix <> &1.id))
    |> Enum.map(&{&1.name <> if(&1.archived_at, do: " (archivováno)", else: ""), prefix <> &1.id})
  end
end

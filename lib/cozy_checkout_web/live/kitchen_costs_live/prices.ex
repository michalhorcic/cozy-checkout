defmodule CozyCheckoutWeb.KitchenCostsLive.Prices do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.{KitchenCosts, Recipes}
  import CozyCheckoutWeb.KitchenCostsLive.Helpers

  @impl true
  def mount(_, _, socket),
    do:
      {:ok,
       socket
       |> assign(:page_title, "Ceny surovin")
       |> assign(:food_context, %{})
       |> assign(:error, nil)
       |> assign(:search, "")}

  @impl true
  def handle_params(params, _, socket), do: {:noreply, load(socket, params["ingredient"])}
  @impl true
  def handle_event("search", %{"search" => search}, socket),
    do: {:noreply, assign(socket, :search, search)}

  def handle_event("manual_price", %{"price" => attrs}, socket) do
    case KitchenCosts.create_manual_price(
           Map.put(attrs, "ingredient_id", socket.assigns.selected.id)
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load(socket.assigns.selected.id)
         |> put_flash(:success, "Datovaný ruční odhad uložen.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, error(reason))
         |> assign(:manual_form, to_form(attrs, as: :price))}
    end
  end

  defp load(socket, id) do
    rows =
      Enum.map(
        Recipes.list_ingredients("", true),
        &%{ingredient: &1, price: KitchenCosts.price_for(&1.id, Date.utc_today())}
      )

    selected = Enum.find_value(rows, fn row -> if row.ingredient.id == id, do: row.ingredient end)

    socket
    |> assign(:rows, rows)
    |> assign(:selected, selected)
    |> assign(:history, if(selected, do: KitchenCosts.price_history(selected.id), else: []))
    |> assign(:error, nil)
    |> assign(
      :manual_form,
      to_form(
        %{"valid_from" => Date.to_iso8601(Date.utc_today()), "unit_price" => "", "note" => ""},
        as: :price
      )
    )
  end

  defp filtered(rows, search),
    do:
      Enum.filter(
        rows,
        &String.contains?(Recipes.normalize(&1.ingredient.name), Recipes.normalize(search))
      )

  defp unit_price(line), do: Decimal.div(line.line_total, line.base_quantity)

  defp trend(history, index) do
    case Enum.at(history, index + 1) do
      nil ->
        "První nákup"

      older ->
        money(Decimal.sub(unit_price(Enum.at(history, index)), unit_price(older))) <>
          " proti předchozímu nákupu"
    end
  end
end

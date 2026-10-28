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
       |> assign(:search, "")
       |> assign(:category, "")
       |> assign(:rows, nil)
       |> assign(:prices_date, nil)}

  @impl true
  def handle_params(params, _, socket) do
    date = Date.utc_today()
    socket = if socket.assigns.prices_date == date, do: socket, else: load_overview(socket, date)
    category = params["category"] || socket.assigns.category

    {:noreply,
     socket
     |> assign(:search, params["search"] || socket.assigns.search)
     |> assign(:category, if(category in socket.assigns.categories, do: category, else: ""))
     |> load_detail(params["ingredient"])}
  end

  @impl true
  def handle_event("search", %{"search" => search} = params, socket),
    do:
      {:noreply, socket |> assign(:search, search) |> assign(:category, params["category"] || "")}

  def handle_event("manual_price", %{"price" => attrs}, socket) do
    case KitchenCosts.create_manual_price(
           Map.put(attrs, "ingredient_id", socket.assigns.selected.id)
         ) do
      {:ok, _} ->
        ingredient = socket.assigns.selected
        date = Date.utc_today()

        socket =
          if socket.assigns.prices_date == date do
            prices = KitchenCosts.price_summaries([ingredient], date)

            rows =
              Enum.map(socket.assigns.rows, fn row ->
                if row.ingredient.id == ingredient.id,
                  do: %{row | price: prices[ingredient.id]},
                  else: row
              end)

            assign(socket, :rows, rows)
          else
            load_overview(socket, date)
          end

        {:noreply,
         socket
         |> assign(:error, nil)
         |> reset_manual_form()
         |> put_flash(:success, "Datovaný ruční odhad uložen.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, error(reason))
         |> assign(:manual_form, to_form(attrs, as: :price))}
    end
  end

  defp load_overview(socket, date) do
    ingredients = Recipes.list_ingredients("", true)
    prices = KitchenCosts.price_summaries(ingredients, date)

    socket
    |> assign(:rows, Enum.map(ingredients, &%{ingredient: &1, price: prices[&1.id]}))
    |> assign(:prices_date, date)
    |> assign(
      :categories,
      ingredients |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort_by(&Recipes.normalize/1)
    )
  end

  defp load_detail(socket, id) do
    selected =
      Enum.find_value(socket.assigns.rows, fn row ->
        if row.ingredient.id == id, do: row.ingredient
      end)

    socket
    |> assign(:selected, selected)
    |> assign(:history, if(selected, do: KitchenCosts.price_history(selected.id), else: []))
    |> assign(:error, nil)
    |> reset_manual_form()
  end

  defp reset_manual_form(socket) do
    assign(
      socket,
      :manual_form,
      to_form(
        %{"valid_from" => Date.to_iso8601(Date.utc_today()), "unit_price" => "", "note" => ""},
        as: :price
      )
    )
  end

  defp filtered(rows, search, category),
    do:
      Enum.filter(
        rows,
        &(String.contains?(Recipes.normalize(&1.ingredient.name), Recipes.normalize(search)) and
            (category == "" or &1.ingredient.category == category))
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

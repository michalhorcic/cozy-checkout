defmodule CozyCheckoutWeb.RecipeLive.Links do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Recipes.{Links, Consumption}
  import CozyCheckoutWeb.KitchenComponents

  @impl true
  def mount(%{"kind" => kind, "item_id" => id} = params, _, socket)
      when kind in ["variant", "booking"] do
    item = Links.load!(kind, id)
    context = CozyCheckoutWeb.FoodNavigation.context(params)

    socket =
      assign(socket,
        food_context: context,
        page_title: "Spotřeba podání",
        food_section: if(context["origin"] == "shopping", do: :shopping, else: :planner),
        redirecting: kind == "variant"
      )

    if kind == "variant" do
      path =
        CozyCheckoutWeb.FoodNavigation.with_context(
          "/admin/meal-planner/variants/#{item.menu_variant_id}/edit?slot=#{item.id}",
          context
        )

      {:ok, push_navigate(socket, to: path)}
    else
      {result, error} =
        case Consumption.for_booking_item(id) do
          {:ok, result} ->
            {result, nil}

          {:error, _} ->
            {nil,
             "Pobyt je zrušený nebo menu neodpovídá aktuálnímu rozpisu či počtům porcí. Zkontrolujte menu pobytu."}
        end

      path =
        CozyCheckoutWeb.FoodNavigation.with_context(
          "/admin/bookings/#{item.booking_menu.booking_id}/menu?edit_item=#{item.id}",
          context
        )

      {:ok,
       assign(socket,
         item: item,
         result: result,
         error: error,
         back_label: CozyCheckoutWeb.FoodNavigation.back_label(params),
         edit_path: path,
         back:
           CozyCheckoutWeb.FoodNavigation.back_path(
             params,
             "/admin/bookings/#{item.booking_menu.booking_id}/menu"
           )
       )}
    end
  end
end

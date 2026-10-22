defmodule CozyCheckoutWeb.FoodNavigation do
  @moduledoc "Shared food navigation and a bounded, URL-based planning context."
  @paths %{
    planner: "/admin/meal-planner",
    shopping: "/admin/kitchen-shopping",
    variants: "/admin/meal-planner/variants",
    recipes: "/admin/recipes",
    ingredients: "/admin/ingredients",
    templates: "/admin/meal-planner/templates",
    settings: "/admin/meal-planner/portion-settings"
  }

  def context(params) do
    range =
      with {:ok, first} <- parse_date(params["from"]),
           {:ok, last} <- parse_date(params["to"]),
           true <- Date.diff(last, first) in 0..365 do
        %{"from" => Date.to_iso8601(first), "to" => Date.to_iso8601(last)}
      else
        _ -> %{}
      end

    range =
      if range == %{} do
        case parse_date(params["week"]) do
          {:ok, date} ->
            first = CozyCheckout.Meals.start_of_week(date)
            %{"from" => Date.to_iso8601(first), "to" => Date.to_iso8601(Date.add(first, 6))}

          _ ->
            %{}
        end
      else
        range
      end

    range
    |> put_uuid("booking", params["booking"])
    |> put_uuid("variant", params["variant"])
    |> then(fn ctx ->
      if params["origin"] in ["shopping", "planner", "booking", "variant"],
        do: Map.put(ctx, "origin", params["origin"]),
        else: ctx
    end)
  end

  def path(section, params \\ %{}),
    do:
      with_context(Map.fetch!(@paths, section), Map.drop(context(params), ["origin", "variant"]))

  def with_context(path, params) do
    uri = URI.parse(path)
    query = Map.merge(URI.decode_query(uri.query || ""), context(params))
    URI.to_string(%{uri | query: if(query == %{}, do: nil, else: URI.encode_query(query))})
  end

  def back_path(params, default) do
    ctx = context(params)

    case ctx["origin"] do
      "shopping" ->
        path(:shopping, ctx)

      "planner" ->
        path(:planner, ctx)

      "booking" when is_map_key(ctx, "booking") ->
        with_context("/admin/bookings/#{ctx["booking"]}/menu", ctx)

      "variant" when is_map_key(ctx, "variant") ->
        with_context("/admin/meal-planner/variants/#{ctx["variant"]}/edit", ctx)

      _ ->
        with_context(default, ctx)
    end
  end

  def back_label(params, default \\ "Zpět") do
    case context(params)["origin"] do
      "shopping" -> "Zpět na nákup"
      "planner" -> "Zpět na plán jídel"
      "booking" -> "Zpět k menu rezervace"
      "variant" -> "Zpět k variantě menu"
      _ -> default
    end
  end

  def for_booking(booking) do
    context(%{
      "from" => Date.to_iso8601(booking.check_in_date),
      "to" => if(booking.check_out_date, do: Date.to_iso8601(booking.check_out_date), else: ""),
      "booking" => booking.id,
      "origin" => "booking"
    })
  end

  defp parse_date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp parse_date(_), do: {:error, :invalid_format}

  defp put_uuid(ctx, key, value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> Map.put(ctx, key, id)
      _ -> ctx
    end
  end
end

defmodule CozyCheckout.Kitchen.ShoppingList do
  @moduledoc "Read-only kitchen shopping calculation, with a recipe/group trail for every quantity."
  import Ecto.Query
  alias CozyCheckout.{Repo, Recipes}
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Meals.{BookingMenu, MenuPlanning, PortionCounts, SlotSchedule}
  alias CozyCheckout.Recipes.{Consumption, Links}

  def generate(start_date, end_date, booking_id \\ nil) do
    with :ok <- validate_range(start_date, end_date),
         :ok <- validate_id(booking_id) do
      bookings = bookings(start_date, end_date)

      selected =
        if booking_id in [nil, ""],
          do: bookings,
          else: Enum.filter(bookings, &(&1.id == booking_id))

      if booking_id not in [nil, ""] and selected == [] do
        {:error, :booking_unavailable}
      else
        {:ok, build(selected, bookings, start_date, end_date)}
      end
    end
  end

  def validate_range(%Date{} = first, %Date{} = last) do
    if Date.diff(last, first) in 0..365, do: :ok, else: {:error, :invalid_range}
  end

  def validate_range(_, _), do: {:error, :invalid_range}

  defp validate_id(id) when id in [nil, ""], do: :ok

  defp validate_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> :ok
      _ -> {:error, :booking_unavailable}
    end
  end

  defp bookings(first, last) do
    Repo.all(
      from b in Booking,
        where: is_nil(b.deleted_at) and b.status != "cancelled",
        where: is_nil(b.meal_plan) or b.meal_plan != "none",
        where:
          b.check_in_date <= ^last and (is_nil(b.check_out_date) or b.check_out_date >= ^first),
        order_by: [asc: b.check_in_date, asc: b.id],
        preload: :guest
    )
  end

  defp build(bookings, options, first, last) do
    ids = Enum.map(bookings, & &1.id)

    menus =
      Repo.all(
        from m in BookingMenu,
          where: m.booking_id in ^ids,
          preload: [
            items: [
              recipe: [lines: :ingredient],
              recipe_supplements: [recipe: [lines: :ingredient]]
            ]
          ]
      )
      |> Map.new(&{&1.booking_id, &1})

    settings = Recipes.settings()

    initial = %{
      totals: %{},
      issues: [],
      services: 0,
      covered_services: 0,
      portions: 0,
      buffet?: false
    }

    result =
      Enum.reduce(bookings, initial, fn booking, acc ->
        if Booking.meal_details_complete?(booking) do
          services =
            PortionCounts.for_range([booking], first, last)
            |> Enum.flat_map(fn {date, types} ->
              for type <- ~w(breakfast lunch dinner),
                  types[type].total > 0,
                  do: %{date: date, type: type, counts: types[type]}
            end)
            |> Enum.sort_by(&{Date.to_gregorian_days(&1.date), SlotSchedule.rank(&1.type)})

          acc = %{
            acc
            | services: acc.services + length(services),
              portions: acc.portions + Enum.reduce(services, 0, &(&1.counts.total + &2))
          }

          menu = menus[booking.id]

          cond do
            services == [] ->
              acc

            is_nil(menu) ->
              add_issue(acc, booking, nil, "Rezervace nemá přiřazené menu")

            MenuPlanning.stale?(menu, booking) ->
              add_issue(acc, booking, nil, "Menu po změně pobytu vyžaduje novou kontrolu")

            true ->
              items = Map.new(menu.items, &{{&1.date, &1.meal_type}, &1})

              Enum.reduce(services, acc, fn service, acc ->
                case items[{service.date, service.type}] do
                  nil ->
                    add_issue(
                      acc,
                      booking,
                      nil,
                      "V menu chybí #{label(service.type)} #{date_label(service.date)}"
                    )

                  item ->
                    add_service(acc, booking, service, item, settings)
                end
              end)
          end
        else
          add_issue(acc, booking, nil, "Doplňte stravování a počty dospělých/dětí")
        end
      end)

    rows =
      result.totals
      |> Map.values()
      |> Enum.map(&purchase/1)
      |> Enum.sort_by(
        &{Recipes.normalize(&1.ingredient.category), Recipes.normalize(&1.ingredient.name)}
      )
      |> Enum.map(&Map.put(&1, :fingerprint, fingerprint(&1)))

    purchase_issues =
      for row <- rows,
          row.purchase_issue,
          do: %{
            id: "ingredient-#{row.id}",
            booking: nil,
            item: nil,
            ingredient: row.ingredient,
            message: row.purchase_issue
          }

    %{
      rows: rows,
      issues: Enum.reverse(result.issues) ++ purchase_issues,
      services: result.services,
      covered_services: result.covered_services,
      portions: result.portions,
      groups: length(bookings),
      booking_options: options,
      buffet?: result.buffet?,
      start_date: first,
      end_date: last
    }
  end

  defp add_service(acc, booking, service, item, settings) do
    recipes =
      Enum.reject([item.recipe | Enum.map(item.recipe_supplements, & &1.recipe)], &is_nil/1)
      |> Enum.uniq_by(& &1.id)

    names = Enum.map(recipes, & &1.name)

    missing =
      String.split(item.supplements || "", "\n", trim: true)
      |> Enum.map(&Links.label_name/1)
      |> Enum.reject(&(&1 in names))

    issues =
      if(is_nil(item.recipe), do: ["Chybí hlavní recept nebo norma bufetu"], else: []) ++
        Enum.map(missing, &("Doplněk bez receptu: " <> &1))

    factor =
      if service.type == "breakfast",
        do: settings.breakfast_child_factor,
        else: settings.hot_child_factor

    {acc, issues} =
      Enum.reduce(recipes, {acc, issues}, fn recipe, {acc, issues} ->
        consumption =
          Consumption.calculate([recipe], service.counts.adults, service.counts.children, factor)

        acc = %{acc | buffet?: acc.buffet? or recipe.source_key == "kitchen:breakfast-buffet:v1"}

        totals =
          Enum.reduce(consumption.quantities, acc.totals, fn row, totals ->
            if Decimal.compare(row.quantity, 0) == :gt do
              source = %{
                recipe: recipe,
                booking: booking,
                item: item,
                date: service.date,
                meal_type: service.type,
                adults: service.counts.adults,
                children: service.counts.children,
                effective: consumption.effective,
                factor: factor,
                quantity: row.quantity
              }

              row = Map.put(row, :sources, [source])

              Map.update(totals, row.id, row, fn previous ->
                %{
                  previous
                  | quantity: Decimal.add(previous.quantity, row.quantity),
                    sources: previous.sources ++ [source]
                }
              end)
            else
              totals
            end
          end)

        {%{acc | totals: totals}, issues ++ consumption.issues}
      end)

    acc = if issues == [], do: %{acc | covered_services: acc.covered_services + 1}, else: acc
    Enum.reduce(Enum.uniq(issues), acc, &add_issue(&2, booking, item, &1))
  end

  defp add_issue(acc, booking, item, message) do
    issue = %{
      id: "issue-#{length(acc.issues)}",
      booking: booking,
      item: item,
      ingredient: nil,
      message: message
    }

    %{acc | issues: [issue | acc.issues]}
  end

  # The sheet rounds the aggregate ratio to 10 decimals before rounding packages up.
  # Ongoing purchases stay visible at consumption quantity, separately from bulk buying.
  def purchase(row) do
    ingredient = row.ingredient

    {quantity, packages, issue} =
      cond do
        ingredient.purchase_mode not in ["Sezona", "Průběžně"] ->
          {nil, nil, "Zvolte způsob nákupu"}

        ingredient.package_size && Decimal.compare(ingredient.package_size, 0) != :gt ->
          {nil, nil, "Opravte velikost balení"}

        ingredient.purchase_mode == "Sezona" and not is_nil(ingredient.package_size) ->
          packages =
            row.quantity
            |> Decimal.div(ingredient.package_size)
            |> Decimal.round(10)
            |> Decimal.round(0, :ceiling)

          {Decimal.mult(packages, ingredient.package_size), packages, nil}

        row.unit == "ks" ->
          {Decimal.round(row.quantity, 0, :ceiling), nil, nil}

        true ->
          {row.quantity, nil, nil}
      end

    Map.merge(row, %{buy_quantity: quantity, packages: packages, purchase_issue: issue})
  end

  def fingerprint(row) do
    payload =
      {row.id, row.ingredient.name, row.unit, Decimal.to_string(Decimal.normalize(row.quantity)),
       row.buy_quantity, row.ingredient.purchase_mode, row.ingredient.package_size,
       Enum.map(
         row.sources,
         &{&1.recipe.id, &1.recipe.name, &1.booking.id, &1.date, &1.meal_type, &1.quantity,
          &1.adults, &1.children, &1.factor}
       )
       |> Enum.sort()}

    :crypto.hash(:sha256, :erlang.term_to_binary(payload)) |> Base.url_encode64(padding: false)
  end

  def label("breakfast"), do: "Snídaně"
  def label("lunch"), do: "Oběd"
  def label("dinner"), do: "Večeře"
  def date_label(date), do: Calendar.strftime(date, "%d. %m. %Y")
end

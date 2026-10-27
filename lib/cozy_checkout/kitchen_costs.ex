defmodule CozyCheckout.KitchenCosts do
  @moduledoc """
  Confirmed kitchen purchases and calculated ingredient costs, including VAT.

  This context accepts reviewed purchase data, not untrusted receipt JSON. Import
  preview and mapping confirmation belong before `confirm_purchase/2`. Quantities
  are explicit totals; optional packaging must agree with them. Prices are never
  rounded here. No stock or accounting documents are created.
  """
  import Ecto.Query
  import Ecto.Changeset
  alias CozyCheckout.{Repo, Recipes}
  alias CozyCheckout.Recipes.Ingredient
  alias CozyCheckout.KitchenCosts.{ManualPrice, Purchase, PurchaseLine, Mapping}

  @doc """
  Atomically stores a reviewed purchase. Repeated import IDs return the original.
  `:replaces_id` creates a replacement without changing the original purchase;
  `:allow_duplicate` acknowledges a possible duplicate identified by receipt data.
  These options must originate from an explicit confirmation, never receipt JSON.
  """
  def confirm_purchase(attrs, opts \\ []) do
    cs = Purchase.changeset(%Purchase{}, attrs)

    if cs.valid? do
      Repo.transaction(fn ->
        import_id = get_field(cs, :import_id)
        if import_id, do: lock_key("kitchen-import:" <> import_id)
        existing = if import_id, do: Repo.get_by(Purchase, import_id: import_id)

        if existing do
          Repo.preload(existing, :lines)
        else
          replaces_id = Keyword.get(opts, :replaces_id)
          if replaces_id, do: lock_replaced_purchase!(replaces_id)
          check_duplicate!(cs, replaces_id, opts)
          cs = snapshot_lines(cs)

          saved =
            cs
            |> put_change(:confirmed_at, DateTime.truncate(DateTime.utc_now(), :second))
            |> put_change(:replaces_id, replaces_id)
            |> Repo.insert()
            |> unwrap!()

          Enum.each(Keyword.get(opts, :mapping_updates, []), fn update ->
            case set_mapping(
                   update.merchant,
                   update.source_name,
                   update.ingredient_id,
                   update.expected_version
                 ) do
              {:ok, _} -> :ok
              {:error, error} -> Repo.rollback(error)
            end
          end)

          saved
        end
      end)
    else
      {:error, cs}
    end
  end

  def normalize_purchase_name(text) when is_binary(text),
    do:
      text
      |> String.normalize(:nfc)
      |> String.downcase()
      |> String.trim()
      |> String.replace(~r/\s+/u, " ")

  def normalize_purchase_name(_), do: ""

  def list_mappings do
    Repo.all(
      from m in Mapping,
        where: is_nil(m.archived_at),
        order_by: [m.merchant_key, m.source_key],
        preload: :ingredient
    )
  end

  def mapping_for(merchant, name) do
    Repo.get_by(Mapping,
      merchant_key: normalize_purchase_name(merchant),
      source_key: normalize_purchase_name(name),
      archived_at: nil
    )
  end

  def mapping_versions(attrs) do
    Map.new(review_lines(attrs["lines"] || []), fn line ->
      mapping = mapping_for(attrs["merchant"], line["source_name"])

      {{normalize_purchase_name(attrs["merchant"]), normalize_purchase_name(line["source_name"])},
       mapping && mapping.lock_version}
    end)
  end

  @doc "Explicit dictionary edit; expected_version is nil for a previously unknown name."
  def set_mapping(merchant, source_name, ingredient_id, expected_version) do
    key = {normalize_purchase_name(merchant), normalize_purchase_name(source_name)}

    Repo.transaction(fn ->
      if not match?({:ok, _}, Ecto.UUID.cast(ingredient_id)),
        do: Repo.rollback(:invalid_ingredient)

      lock_key("kitchen-mapping:" <> Jason.encode!(Tuple.to_list(key)))
      current = mapping_for(merchant, source_name)

      if (current && current.lock_version) != expected_version,
        do: Repo.rollback(:mapping_changed)

      ingredient = lock_ingredient(ingredient_id)

      if is_nil(ingredient) or not is_nil(ingredient.archived_at),
        do: Repo.rollback(:invalid_ingredient)

      cs =
        Mapping.changeset(current || %Mapping{}, %{
          merchant_key: elem(key, 0),
          source_key: elem(key, 1),
          source_name: source_name,
          ingredient_id: ingredient_id
        })

      cs = if current, do: optimistic_lock(cs, :lock_version), else: cs
      cs |> Repo.insert_or_update() |> unwrap!()
    end)
  end

  @doc "Confirmation boundary for the admin form. Dictionary writes require a separate opt-in."
  def confirm_reviewed_purchase(attrs, opts \\ []) do
    lines = review_lines(attrs["lines"] || [])
    versions = Keyword.get(opts, :mapping_versions, %{})

    confirmed? =
      Enum.all?(lines, fn line ->
        line["classification"] != "ingredient" or
          (line["ingredient_id"] not in [nil, ""] and
             line["confirmed_ingredient_id"] == line["ingredient_id"])
      end)

    if confirmed? do
      updates =
        for line <- lines, line["classification"] == "ingredient", line["remember"] == "true" do
          key =
            {normalize_purchase_name(attrs["merchant"]),
             normalize_purchase_name(line["source_name"])}

          %{
            merchant: attrs["merchant"],
            source_name: line["source_name"],
            ingredient_id: line["ingredient_id"],
            expected_version: Map.get(versions, key, :not_reviewed)
          }
        end

      grouped =
        Enum.group_by(
          updates,
          &{normalize_purchase_name(&1.merchant), normalize_purchase_name(&1.source_name)}
        )

      if Enum.any?(grouped, fn {_, entries} ->
           length(Enum.uniq_by(entries, & &1.ingredient_id)) > 1
         end) do
        {:error, "Stejný nákupní název nelze současně zapamatovat pro dvě suroviny"}
      else
        updates =
          grouped |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(fn {_, entries} -> hd(entries) end)

        confirm_purchase(
          Map.put(attrs, "lines", lines),
          Keyword.put(opts, :mapping_updates, updates)
        )
      end
    else
      {:error, :unconfirmed_mapping}
    end
  end

  def review_lines(lines) when is_list(lines), do: lines

  def review_lines(lines) when is_map(lines),
    do: lines |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end) |> Enum.map(&elem(&1, 1))

  def price_history(ingredient_id) do
    Repo.all(
      from l in PurchaseLine,
        join: p in subquery(current_purchases()),
        on: p.id == l.purchase_id,
        where: l.ingredient_id == ^ingredient_id,
        order_by: [desc: p.purchased_on, asc: l.line_number],
        preload: :purchase
    )
  end

  def recipe_cost(recipe, date, factor) do
    adult =
      recipe |> then(&Recipes.Consumption.calculate([&1], 1, 0, factor)) |> cost_consumption(date)

    child =
      recipe |> then(&Recipes.Consumption.calculate([&1], 0, 1, factor)) |> cost_consumption(date)

    %{adult: adult, child: child}
  end

  def get_purchase!(id), do: Purchase |> Repo.get!(id) |> Repo.preload(:lines)

  @doc "Includes original versions, ordered by purchase date. No purchase deletion API."
  def list_purchases do
    Repo.all(
      from p in Purchase, order_by: [desc: p.purchased_on, desc: p.inserted_at], preload: :lines
    )
  end

  def list_unassigned_lines do
    Repo.all(
      from l in PurchaseLine,
        join: p in subquery(current_purchases()),
        on: p.id == l.purchase_id,
        where: l.classification == "unassigned",
        order_by: [desc: p.purchased_on, asc: l.line_number],
        preload: :purchase
    )
  end

  @doc "Adds a dated estimate per base unit. Purchase prices always take precedence."
  def create_manual_price(attrs) do
    cs = ManualPrice.changeset(%ManualPrice{}, attrs)

    if cs.valid? do
      Repo.transaction(fn ->
        ingredient = lock_ingredient(get_field(cs, :ingredient_id))

        cs =
          if ingredient && is_nil(ingredient.archived_at),
            do: put_change(cs, :base_unit, ingredient.base_unit),
            else: add_error(cs, :ingredient_id, "Vyberte existující nearchivovanou surovinu")

        cs |> Repo.insert() |> unwrap!()
      end)
    else
      {:error, cs}
    end
  end

  @doc "90 inclusive calendar days; falls back to latest earlier purchase day, then dated estimate."
  def price_for(ingredient_id, %Date{} = date) do
    ingredient = Recipes.get_ingredient!(ingredient_id)
    first = Date.add(date, -89)
    query = price_lines(ingredient_id, date)
    window = Repo.all(from [l, p] in query, where: p.purchased_on >= ^first)

    case window do
      [] -> older_or_manual(query, ingredient, date)
      lines -> purchase_price(lines, "weighted_average", [])
    end
  end

  @doc "Adds costs to Recipes.Consumption output; missing prices keep the known subtotal incomplete."
  def cost_consumption(consumption, %Date{} = date) do
    rows =
      Enum.map(consumption.quantities, fn row ->
        zero? = Decimal.equal?(row.quantity, 0)

        price =
          if zero?,
            do: %{
              unit_price: nil,
              unit: row.unit,
              source: "not_required",
              lines: [],
              warnings: []
            },
            else: price_for(row.id, date)

        cost =
          cond do
            zero? -> Decimal.new(0)
            price.unit_price -> Decimal.mult(row.quantity, price.unit_price)
            true -> nil
          end

        Map.merge(row, %{price: price, cost: cost})
      end)

    known_total =
      Enum.reduce(rows, Decimal.new(0), fn row, acc -> Decimal.add(acc, row.cost || 0) end)

    issues = consumption.issues ++ Enum.flat_map(rows, & &1.price.warnings)

    Map.merge(consumption, %{
      quantities: rows,
      known_total: known_total,
      complete?: consumption.issues == [] and Enum.all?(rows, &(not is_nil(&1.cost))),
      issues: Enum.uniq(issues)
    })
  end

  defp current_purchases do
    from p in Purchase,
      left_join: replacement in Purchase,
      on: replacement.replaces_id == p.id,
      where: is_nil(replacement.id)
  end

  defp price_lines(ingredient_id, date) do
    from l in PurchaseLine,
      join: p in subquery(current_purchases()),
      on: p.id == l.purchase_id,
      where: l.ingredient_id == ^ingredient_id and p.purchased_on <= ^date,
      order_by: [asc: p.purchased_on, asc: l.id],
      select: %{
        line_id: l.id,
        purchase_id: p.id,
        purchased_on: p.purchased_on,
        quantity: l.base_quantity,
        total: l.line_total,
        unit: l.base_unit
      }
  end

  defp older_or_manual(query, ingredient, date) do
    latest =
      query
      |> exclude(:select)
      |> exclude(:order_by)
      |> select([l, p], max(p.purchased_on))
      |> Repo.one()

    if latest do
      lines = Repo.all(from [l, p] in query, where: p.purchased_on == ^latest)

      purchase_price(lines, "older_purchase", [
        "Cena #{ingredient.name} pochází z nákupu staršího než 90 dní"
      ])
    else
      manual =
        Repo.one(
          from m in ManualPrice,
            where:
              m.ingredient_id == ^ingredient.id and m.valid_from <= ^date and
                is_nil(m.archived_at),
            order_by: [desc: m.valid_from],
            limit: 1
        )

      if manual do
        %{
          unit_price: manual.unit_price,
          unit: manual.base_unit,
          source: "manual_estimate",
          valid_from: manual.valid_from,
          manual_price_id: manual.id,
          lines: [],
          warnings: ["Ruční odhad ceny: #{ingredient.name}"]
        }
      else
        %{
          unit_price: nil,
          unit: ingredient.base_unit,
          source: "missing",
          lines: [],
          warnings: ["Chybí cena: #{ingredient.name}"]
        }
      end
    end
  end

  defp purchase_price(lines, source, warnings) do
    quantity = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.quantity, &2))
    total = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.total, &2))

    %{
      unit_price: Decimal.div(total, quantity),
      unit: hd(lines).unit,
      source: source,
      quantity: quantity,
      total: total,
      lines: lines,
      warnings: warnings
    }
  end

  defp snapshot_lines(cs) do
    ids =
      get_field(cs, :lines)
      |> Enum.map(& &1.ingredient_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    ingredients =
      Repo.all(from i in Ingredient, where: i.id in ^ids, order_by: i.id, lock: "FOR SHARE")
      |> Map.new(&{&1.id, &1})

    lines =
      Enum.map(get_change(cs, :lines), fn line ->
        if get_field(line, :classification) == "ingredient" do
          ingredient = ingredients[get_field(line, :ingredient_id)]

          cond do
            is_nil(ingredient) or not is_nil(ingredient.archived_at) ->
              add_error(line, :ingredient_id, "Vyberte existující nearchivovanou surovinu")

            not Recipes.compatible?(get_field(line, :unit), ingredient.base_unit) ->
              add_error(line, :unit, "Jednotka neodpovídá surovině")

            true ->
              {:ok, quantity} =
                Recipes.to_base(
                  get_field(line, :quantity),
                  get_field(line, :unit),
                  ingredient.base_unit
                )

              line
              |> put_change(:base_quantity, quantity)
              |> put_change(:base_unit, ingredient.base_unit)
              |> put_change(:ingredient_name, ingredient.name)
          end
        else
          line
        end
      end)

    put_assoc(cs, :lines, lines)
  end

  defp lock_replaced_purchase!(id) do
    purchase = Repo.one(from p in Purchase, where: p.id == ^id, lock: "FOR UPDATE")

    cond do
      is_nil(purchase) ->
        Repo.rollback(:purchase_not_found)

      Repo.exists?(from p in Purchase, where: p.replaces_id == ^id) ->
        Repo.rollback(:already_replaced)

      true ->
        purchase
    end
  end

  defp check_duplicate!(cs, replaces_id, opts) do
    merchant = get_field(cs, :merchant) |> String.trim() |> String.downcase()
    date = get_field(cs, :purchased_on)
    number = get_field(cs, :document_number)
    total = get_field(cs, :total_paid)

    key =
      Jason.encode!([
        merchant,
        Date.to_iso8601(date),
        number,
        Decimal.to_string(Decimal.normalize(total), :normal)
      ])

    lock_key("kitchen-receipt:" <> key)

    query =
      from p in subquery(current_purchases()),
        where:
          fragment("lower(btrim(?))", p.merchant) == ^merchant and p.purchased_on == ^date and
            p.total_paid == ^total

    query =
      if number,
        do: where(query, [p], p.document_number == ^number),
        else: where(query, [p], is_nil(p.document_number))

    query = if replaces_id, do: where(query, [p], p.id != ^replaces_id), else: query

    if not Keyword.get(opts, :allow_duplicate, false) and Repo.exists?(query),
      do: Repo.rollback(:possible_duplicate)
  end

  defp lock_ingredient(id),
    do: Repo.one(from i in Ingredient, where: i.id == ^id, lock: "FOR SHARE")

  defp lock_key(key),
    do: Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])

  defp unwrap!({:ok, result}), do: result
  defp unwrap!({:error, cs}), do: Repo.rollback(cs)
end

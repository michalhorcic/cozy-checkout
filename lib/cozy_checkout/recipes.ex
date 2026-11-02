defmodule CozyCheckout.Recipes do
  @moduledoc "Kitchen catalogue. Decimal quantities and compatible units throughout."
  import Ecto.Query
  import Ecto.Changeset
  alias CozyCheckout.Repo
  alias CozyCheckout.Recipes.{Recipe, RecipeLine, Ingredient, Settings}

  def normalize(text),
    do: text |> String.downcase() |> String.normalize(:nfd) |> String.replace(~r/\p{Mn}/u, "")

  def list_recipes(search \\ "", archived \\ false) do
    query = from r in Recipe, order_by: r.name, preload: [lines: :ingredient]
    query = if archived, do: query, else: where(query, [r], is_nil(r.archived_at))
    query |> matching_recipe_names(search) |> Repo.all()
  end

  @recipe_page_size 30

  @doc "A bounded catalogue page without ingredients; case and accent insensitive."
  def search_recipes(search, offset \\ 0)
      when is_binary(search) and is_integer(offset) and offset >= 0 do
    query =
      from r in Recipe,
        where: is_nil(r.archived_at),
        order_by: [asc: r.name, asc: r.id],
        offset: ^offset,
        limit: ^(@recipe_page_size + 1),
        select: struct(r, [:id, :name, :base_servings, :archived_at, :pictogram])

    rows = query |> matching_recipe_names(search) |> Repo.all()

    %{
      recipes: Enum.take(rows, @recipe_page_size),
      more?: length(rows) > @recipe_page_size,
      next_offset: offset + @recipe_page_size
    }
  end

  defp matching_recipe_names(query, search) do
    term = normalize(String.trim(search))

    if term == "" do
      query
    else
      where(
        query,
        [r],
        fragment(
          "strpos(regexp_replace(normalize(lower(?), NFD), '[\u0300-\u036f]', '', 'g'), ?) > 0",
          r.name,
          ^term
        )
      )
    end
  end

  @doc "Load selected recipes, including archived ones, in selection order with a fixed query count."
  def get_recipes([]), do: []

  def get_recipes(ids) do
    ids =
      ids
      |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1)))
      |> Enum.uniq()

    recipes =
      Repo.all(
        from r in Recipe,
          where: r.id in ^ids,
          preload: [lines: ^from(l in RecipeLine, order_by: l.position, preload: :ingredient)]
      )
      |> Map.new(&{&1.id, &1})

    Enum.flat_map(ids, fn id -> if recipes[id], do: [recipes[id]], else: [] end)
  end

  def breakfast_buffet_id do
    Repo.one(
      from r in Recipe,
        where: r.source_key == "kitchen:breakfast-buffet:v1" and is_nil(r.archived_at),
        select: r.id
    )
  end

  def get_recipe!(id),
    do:
      Recipe
      |> Repo.get!(id)
      |> Repo.preload(lines: from(l in RecipeLine, order_by: l.position, preload: :ingredient))

  def list_ingredients(search \\ "", archived \\ false) do
    query = from i in Ingredient, order_by: i.name
    query = if archived, do: query, else: where(query, [i], is_nil(i.archived_at))

    Repo.all(query)
    |> Enum.filter(&String.contains?(normalize(&1.name <> " " <> &1.category), normalize(search)))
  end

  def get_ingredient!(id), do: Repo.get!(Ingredient, id)

  def search_ingredients(ingredients, query) do
    words = query |> normalize() |> String.split()

    Enum.filter(ingredients, fn ingredient ->
      text =
        normalize(Enum.join([ingredient.name, ingredient.category, ingredient.notes || ""], " "))

      Enum.all?(words, &String.contains?(text, &1))
    end)
  end

  def create_ingredient(attrs), do: %Ingredient{} |> Ingredient.changeset(attrs) |> Repo.insert()

  def update_ingredient(ingredient, attrs) do
    Repo.transaction(fn ->
      current = Repo.one!(from i in Ingredient, where: i.id == ^ingredient.id, lock: "FOR UPDATE")
      if current.lock_version != ingredient.lock_version, do: Repo.rollback(:stale)
      cs = Ingredient.changeset(current, attrs)

      cs =
        if get_change(cs, :base_unit) &&
             ingredient_unit_used?(ingredient.id),
           do:
             add_error(
               cs,
               :base_unit,
               "Jednotku používané suroviny nelze změnit. Založte jinou surovinu."
             ),
           else: cs

      case cs |> optimistic_lock(:lock_version) |> Repo.update() do
        {:ok, result} -> result
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  defp ingredient_unit_used?(id) do
    Repo.exists?(from f in CozyCheckout.Kitchen.FreezerItem, where: f.ingredient_id == ^id) or
      Repo.exists?(from l in RecipeLine, where: l.ingredient_id == ^id) or
      Repo.exists?(
        from l in CozyCheckout.KitchenCosts.PurchaseLine, where: l.ingredient_id == ^id
      ) or
      Repo.exists?(from p in CozyCheckout.KitchenCosts.ManualPrice, where: p.ingredient_id == ^id)
  end

  def archive_ingredient(i),
    do:
      i
      |> change(archived_at: DateTime.truncate(DateTime.utc_now(), :second))
      |> optimistic_lock(:lock_version)
      |> Repo.update()

  def create_recipe(attrs), do: save_recipe(%Recipe{lines: []}, attrs)
  def update_recipe(recipe, attrs), do: save_recipe(recipe, attrs)

  def archive_recipe(r),
    do:
      r
      |> change(archived_at: DateTime.truncate(DateTime.utc_now(), :second))
      |> optimistic_lock(:lock_version)
      |> Repo.update()

  defp save_recipe(recipe, attrs) do
    Repo.transaction(fn ->
      cs = Recipe.changeset(recipe, attrs)
      ids = get_field(cs, :lines, []) |> Enum.map(& &1.ingredient_id) |> Enum.reject(&is_nil/1)

      ingredients =
        Repo.all(from i in Ingredient, where: i.id in ^ids, lock: "FOR SHARE")
        |> Map.new(&{&1.id, &1})

      # Validate during a fresh cast. Re-putting an association after cast_assoc/3
      # reprocesses :replace actions and crashes when a persisted line is removed.
      cs = Recipe.changeset(recipe, attrs, &validate_ingredient_line(&1, ingredients))

      cs = if recipe.id, do: optimistic_lock(cs, :lock_version), else: cs

      case Repo.insert_or_update(cs) do
        {:ok, saved} -> get_recipe!(saved.id)
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  defp validate_ingredient_line(line, ingredients) do
    ingredient = ingredients[get_field(line, :ingredient_id)]

    cond do
      is_nil(ingredient) ->
        add_error(line, :ingredient_id, "Vyberte existující surovinu")

      ingredient.archived_at &&
          (is_nil(line.data.id) or line.data.ingredient_id != ingredient.id) ->
        add_error(line, :ingredient_id, "Surovina je archivovaná")

      not compatible?(get_field(line, :unit), ingredient.base_unit) ->
        add_error(line, :unit, "Jednotka neodpovídá surovině (#{ingredient.base_unit})")

      true ->
        line
    end
  end

  def compatible?(unit, base),
    do: {unit, base} in [{"kg", "kg"}, {"g", "kg"}, {"l", "l"}, {"ml", "l"}, {"ks", "ks"}]

  def to_base(q, unit, base) do
    cond do
      unit == base -> {:ok, q}
      {unit, base} in [{"g", "kg"}, {"ml", "l"}] -> {:ok, Decimal.div(q, 1000)}
      true -> {:error, :incompatible_unit}
    end
  end

  def settings, do: Repo.get!(Settings, 1)

  def update_settings(s, attrs) do
    s |> Settings.changeset(attrs) |> optimistic_lock(:lock_version) |> Repo.update()
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  def source_url(%{source_reference: value}) when is_binary(value) do
    uri = URI.parse(value)
    if uri.scheme in ["http", "https"] and uri.host not in [nil, ""], do: value
  end

  def source_url(_), do: nil

  def format_quantity(value, unit) do
    {v, u} =
      if unit in ["kg", "l"] and Decimal.compare(value, 1) == :lt and
           Decimal.compare(value, 0) == :gt,
         do: {Decimal.mult(value, 1000), if(unit == "kg", do: "g", else: "ml")},
         else: {value, unit}

    text =
      v
      |> Decimal.round(3)
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)
      |> String.replace(".", ",")

    if text == "0" and Decimal.compare(v, 0) == :gt, do: "< 0,001 #{u}", else: text <> " " <> u
  end
end

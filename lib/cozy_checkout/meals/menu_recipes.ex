defmodule CozyCheckout.Meals.MenuRecipes do
  @moduledoc "Recipe-only menu editing, readiness and shared live display. Legacy wording is review evidence."
  import Ecto.Query
  alias Ecto.Changeset, as: CS
  alias CozyCheckout.Repo
  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Meals.{MenuVariant, BookingMenuItem, MenuPlanning}
  alias CozyCheckout.Recipes.{Recipe, Links, VariantSupplement, BookingSupplement}

  def display(item) do
    main = if item.recipe, do: item.recipe.name, else: if(legacy?(item), do: item.menu_text)
    extras = item.recipe_supplements |> Enum.sort_by(& &1.position) |> Enum.map(& &1.recipe.name)

    %{
      main: main,
      supplements: if(extras == [], do: nil, else: Enum.join(extras, "\n")),
      note: item.note,
      legacy?: legacy?(item),
      original: if(legacy?(item), do: MenuPlanning.menu_text(item.menu_text, item.supplements))
    }
  end

  def legacy?(item),
    do:
      is_nil(item.recipe_links_reviewed_at) and
        (not blank?(item.menu_text) or not blank?(item.supplements))

  def issues(item, assigning? \\ false) do
    recipes =
      [item.recipe | Enum.map(item.recipe_supplements, & &1.recipe)] |> Enum.reject(&is_nil/1)

    if(is_nil(item.recipe_id), do: ["Chybí hlavní recept nebo norma bufetu"], else: []) ++
      if(legacy?(item),
        do: [
          "Původní text a doplňky čekají na kontrolu: #{MenuPlanning.menu_text(item.menu_text, item.supplements)}"
        ],
        else: []
      ) ++
      if assigning?,
        do: for(r <- recipes, r.archived_at, do: "Archivovaný recept: #{r.name}"),
        else: []
  end

  def readiness(variant) do
    missing = Enum.count(variant.items, &is_nil(&1.recipe_id))
    issues = Enum.flat_map(variant.items, &issues(&1, true))
    valid? = MenuVariant.changeset(variant, %{}).valid?
    ready? = issues == [] and valid? and is_nil(variant.deleted_at)

    needs_review? =
      Enum.any?(variant.items, fn item ->
        legacy?(item) or
          Enum.any?(
            [item.recipe | Enum.map(item.recipe_supplements, & &1.recipe)]
            |> Enum.reject(&is_nil/1),
            &(&1.archived_at != nil)
          )
      end)

    state =
      cond do
        ready? -> "ready"
        needs_review? -> "review"
        missing > 0 -> "draft"
        true -> "review"
      end

    label =
      case state do
        "ready" -> "Připravené"
        "review" -> "K dořešení"
        "draft" -> "Chybí #{missing} podání"
      end

    %{ready?: ready?, missing: missing, label: label, issues: issues, state: state}
  end

  def item_params(item) do
    %{
      "id" => item.id,
      "day_number" => item.day_number,
      "meal_type" => item.meal_type,
      "recipe_id" => item.recipe_id,
      "supplement_recipe_ids" =>
        Enum.map(Enum.sort_by(item.recipe_supplements, & &1.position), & &1.recipe_id),
      "note" => item.note || "",
      "reviewed" => not legacy?(item)
    }
  end

  def variant_params(variant) do
    Map.new(
      [:name, :days, :meal_plan, :first_meal, :last_meal],
      &{to_string(&1), Map.get(variant, &1)}
    )
    |> Map.put("days", to_string(variant.days))
    |> Map.put("items", Enum.map(variant.items, &item_params/1))
  end

  def save_variant(variant, attrs) do
    Repo.transaction(fn ->
      current =
        if variant.id do
          locked =
            Repo.one!(
              from v in MenuVariant,
                where: v.id == ^variant.id and is_nil(v.deleted_at),
                lock: "FOR UPDATE"
            )

          if locked.lock_version != variant.lock_version, do: Repo.rollback(:stale_variant)
          Links.preload_variant(locked)
        else
          %MenuVariant{items: []}
        end

      attrs = sanitize_variant(attrs)
      old_by_id = Map.new(current.items, &{&1.id, &1})
      provided_ids = attrs["items"] |> Enum.map(& &1["id"]) |> Enum.reject(&(&1 in [nil, ""]))

      if length(provided_ids) != length(Enum.uniq(provided_ids)) or
           Enum.any?(provided_ids, &(not Map.has_key?(old_by_id, &1))),
         do: Repo.rollback(:invalid_item)

      cs =
        MenuVariant.changeset(current, attrs, fn item, params ->
          item |> CozyCheckout.Meals.MenuVariantItem.changeset(params) |> review_changeset()
        end)

      if not cs.valid?, do: Repo.rollback(cs)
      children = CS.get_change(cs, :items, [])
      validate_ownership!(children, old_by_id)
      validate_recipes!(children, old_by_id)
      cs = if current.id, do: CS.optimistic_lock(cs, :lock_version), else: cs

      saved =
        case Repo.insert_or_update(cs) do
          {:ok, saved} -> saved
          {:error, cs} -> Repo.rollback(cs)
        end

      Enum.each(saved.items, fn item ->
        replace_supplements("variant", item.id, item.supplement_recipe_ids)
      end)

      MenuPlanning.get_variant!(saved.id)
    end)
  rescue
    Ecto.StaleEntryError -> {:error, :stale_variant}
    Ecto.NoResultsError -> {:error, :stale_variant}
    Ecto.CastError -> {:error, :invalid_recipe}
  end

  def save_booking_item(booking_id, item_id, attrs, expected) do
    Repo.transaction(fn ->
      booking =
        Repo.one!(
          from b in Booking,
            where: b.id == ^booking_id and is_nil(b.deleted_at),
            lock: "FOR UPDATE"
        )

      item = Links.load!("booking", item_id)

      if item.booking_menu.booking_id != booking_id or Links.version(item) != expected,
        do: Repo.rollback(:stale_item)

      if MenuPlanning.stale?(item.booking_menu, booking) or booking.status == "cancelled" or
           not Booking.meal_schedule_complete?(booking),
         do: Repo.rollback(:stale_item)

      cs = BookingMenuItem.changeset(item, sanitize_item(attrs))
      if not cs.valid?, do: Repo.rollback(cs)
      validate_recipes!([cs], %{item.id => item})
      cs = cs |> review_changeset() |> CS.put_change(:manually_edited, true)
      saved = Repo.update!(cs)
      replace_supplements("booking", item.id, CS.get_field(cs, :supplement_recipe_ids))
      Links.load!("booking", saved.id)
    end)
  rescue
    Ecto.NoResultsError -> {:error, :stale_item}
    Ecto.CastError -> {:error, :invalid_recipe}
  end

  def duplicate(variant) do
    Repo.transaction(fn ->
      current =
        Repo.one!(
          from v in MenuVariant,
            where: v.id == ^variant.id and is_nil(v.deleted_at),
            lock: "FOR UPDATE"
        )
        |> Links.preload_variant()

      attrs = variant_params(current)
      items = Enum.map(attrs["items"], &Map.drop(&1, ["id"]))
      attrs = %{attrs | "name" => copy_name(current.name), "items" => items}
      copy = %MenuVariant{items: []} |> MenuVariant.changeset(attrs) |> Repo.insert!()

      Enum.zip(copy.items, current.items)
      |> Enum.each(fn {item, source} ->
        item
        |> CS.change(
          menu_text: source.menu_text,
          supplements: source.supplements,
          recipe_links_reviewed_at: source.recipe_links_reviewed_at
        )
        |> Repo.update!()

        replace_supplements("variant", item.id, item_params(source)["supplement_recipe_ids"])
      end)

      MenuPlanning.get_variant!(copy.id)
    end)
  end

  defp copy_name(name) do
    candidate = String.slice(name, 0, 160) <> " – kopie #{System.unique_integer([:positive])}"

    if Repo.exists?(from v in MenuVariant, where: v.name == ^candidate and is_nil(v.deleted_at)),
      do: copy_name(name),
      else: candidate
  end

  defp sanitize_variant(attrs) do
    attrs = stringify(attrs)

    Map.take(attrs, ~w(name days meal_plan first_meal last_meal))
    |> Map.put("items", attrs |> Map.get("items", []) |> rows() |> Enum.map(&sanitize_item/1))
  end

  defp sanitize_item(attrs) do
    attrs = stringify(attrs)

    Map.take(attrs, ~w(id day_number meal_type recipe_id supplement_recipe_ids note reviewed))
    |> Map.update("supplement_recipe_ids", [], fn ids ->
      if is_list(ids), do: Enum.reject(ids, &(&1 == "")), else: ids
    end)
  end

  defp rows(map) when is_map(map),
    do:
      map
      |> Enum.sort_by(fn {key, _} ->
        case Integer.parse(to_string(key)) do
          {number, ""} -> number
          _ -> 0
        end
      end)
      |> Enum.map(&elem(&1, 1))

  defp rows(list) when is_list(list), do: list
  defp rows(_), do: []
  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp validate_ownership!(children, old_by_id) do
    Enum.each(children, fn cs ->
      if cs.data.id && not Map.has_key?(old_by_id, cs.data.id), do: Repo.rollback(:invalid_item)

      if cs.data.id && cs.action not in [:delete, :replace] do
        old = old_by_id[cs.data.id]

        if {CS.get_field(cs, :day_number), CS.get_field(cs, :meal_type)} !=
             {old.day_number, old.meal_type},
           do: Repo.rollback(:invalid_item)
      end
    end)
  end

  defp validate_recipes!(children, old_by_id) do
    children = Enum.reject(children, &(&1.action in [:delete, :replace]))

    ids =
      Enum.flat_map(children, fn cs ->
        [CS.get_field(cs, :recipe_id) | CS.get_field(cs, :supplement_recipe_ids, [])]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if Enum.any?(ids, &(not match?({:ok, _}, Ecto.UUID.cast(&1)))),
      do: Repo.rollback(:invalid_recipe)

    recipes =
      Repo.all(from r in Recipe, where: r.id in ^ids, lock: "FOR SHARE") |> Map.new(&{&1.id, &1})

    Enum.each(children, fn cs ->
      selected =
        [CS.get_field(cs, :recipe_id) | CS.get_field(cs, :supplement_recipe_ids, [])]
        |> Enum.reject(&is_nil/1)

      if length(selected) != length(Enum.uniq(selected)), do: Repo.rollback(:duplicate_recipe)
      old = old_by_id[cs.data.id]
      retained = if old, do: [old.recipe_id | Links.supplement_ids(old)], else: []

      Enum.each(selected, fn id ->
        recipe = recipes[id]

        if is_nil(recipe) or (recipe.archived_at && id not in retained),
          do: Repo.rollback(:unavailable_recipe)
      end)
    end)
  end

  defp review_changeset(cs) do
    if CS.get_field(cs, :reviewed) do
      CS.put_change(
        cs,
        :recipe_links_reviewed_at,
        CS.get_field(cs, :recipe_links_reviewed_at) ||
          DateTime.truncate(DateTime.utc_now(), :second)
      )
    else
      cs
    end
  end

  def replace_supplements(kind, id, ids) do
    {schema, field} =
      if kind == "variant",
        do: {VariantSupplement, :menu_variant_item_id},
        else: {BookingSupplement, :booking_menu_item_id}

    Repo.delete_all(from l in schema, where: field(l, ^field) == ^id)

    Enum.each(Enum.with_index(ids), fn {recipe_id, position} ->
      schema
      |> struct(%{field => id, :recipe_id => recipe_id, :position => position})
      |> Repo.insert!()
    end)
  end

  defp blank?(text), do: text in [nil, ""] or String.trim(text) == ""
end

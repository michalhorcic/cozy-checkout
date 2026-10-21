defmodule CozyCheckout.Recipes.Links do
  @moduledoc "Structured main/dish links. Text remains editable and booking snapshots keep their own links."
  import Ecto.Query
  alias Ecto.Changeset
  alias CozyCheckout.Repo
  alias CozyCheckout.Recipes.{Recipe, VariantSupplement, BookingSupplement}
  alias CozyCheckout.Meals.{MenuVariant, MenuVariantItem, BookingMenuItem}
  alias CozyCheckout.Bookings.Booking

  def preload(item), do: Repo.preload(item, [:recipe, recipe_supplements: :recipe])

  def preload_variant(variant) do
    variant
    |> Repo.preload(items: [:recipe, recipe_supplements: :recipe])
    |> order_variant()
  end

  defp order_variant(variant) do
    %{
      variant
      | items:
          Enum.sort_by(
            variant.items,
            &{&1.day_number, CozyCheckout.Meals.SlotSchedule.rank(&1.meal_type)}
          )
    }
  end

  def supplement_ids(item) do
    item = preload(item)

    item.recipe_supplements
    |> Enum.sort_by(&{&1.position, &1.recipe_id})
    |> Enum.map(& &1.recipe_id)
  end

  def version(item) do
    :crypto.hash(
      :sha256,
      :erlang.term_to_binary(
        {Map.take(item, [:id, :updated_at, :menu_text, :supplements, :manually_edited, :recipe_id]),
         supplement_ids(item)}
      )
    )
    |> Base.url_encode64(padding: false)
  end

  def label_name(text),
    do: text |> String.replace(~r/^Polévka k (obědu|večeři):\s*/u, "") |> String.trim()

  def infer_variant(variant) do
    recipes =
      Repo.all(from r in Recipe, where: is_nil(r.archived_at), select: {r.name, r.id})
      |> Map.new()

    Enum.each(variant.items, fn item ->
      main = recipes[item.menu_text]
      if main, do: item |> Changeset.change(recipe_id: main) |> Repo.update!()
      names = String.split(item.supplements || "", "\n", trim: true)

      for {name, index} <- Enum.with_index(names),
          id = recipes[label_name(name)],
          not is_nil(id),
          id != main do
        %VariantSupplement{menu_variant_item_id: item.id, recipe_id: id, position: index}
        |> Repo.insert!(on_conflict: :nothing)
      end
    end)

    Repo.preload(variant, [items: [:recipe, recipe_supplements: :recipe]], force: true)
    |> order_variant()
  end

  # Changed menu wording must never silently keep quantities for a different dish.
  def clear_text_changes(before, saved, kind) do
    saved =
      if before.menu_text != saved.menu_text,
        do: saved |> Changeset.change(recipe_id: nil) |> Repo.update!(),
        else: saved

    if before.supplements != saved.supplements do
      if kind == "variant",
        do:
          Repo.delete_all(from l in VariantSupplement, where: l.menu_variant_item_id == ^saved.id),
        else:
          Repo.delete_all(from l in BookingSupplement, where: l.booking_menu_item_id == ^saved.id)
    end

    saved
  end

  def copy(source, target) do
    source = preload(source)
    target |> Changeset.change(recipe_id: source.recipe_id) |> Repo.update!()
    Repo.delete_all(from l in BookingSupplement, where: l.booking_menu_item_id == ^target.id)

    for link <- source.recipe_supplements do
      Repo.insert!(%BookingSupplement{
        booking_menu_item_id: target.id,
        recipe_id: link.recipe_id,
        position: link.position
      })
    end

    target
  end

  def load!("variant", id) do
    item = MenuVariantItem |> Repo.get!(id) |> Repo.preload(:menu_variant) |> preload()
    if item.menu_variant.deleted_at, do: raise(Ecto.NoResultsError, queryable: MenuVariantItem)
    item
  end

  def load!("booking", id) do
    item =
      BookingMenuItem
      |> Repo.get!(id)
      |> Repo.preload(booking_menu: [booking: :guest])
      |> preload()

    if item.booking_menu.booking.deleted_at,
      do: raise(Ecto.NoResultsError, queryable: BookingMenuItem)

    item
  end

  def save(kind, id, main_id, extras, expected) when kind in ["variant", "booking"] do
    main_id = if main_id in [nil, ""], do: nil, else: main_id
    extras = Enum.uniq(extras) |> Enum.reject(&(&1 in [nil, "", main_id]))

    Repo.transaction(fn ->
      original = load!(kind, id)

      if kind == "variant" do
        Repo.one!(
          from v in MenuVariant, where: v.id == ^original.menu_variant_id, lock: "FOR UPDATE"
        )
      else
        Repo.one!(
          from b in Booking, where: b.id == ^original.booking_menu.booking_id, lock: "FOR UPDATE"
        )
      end

      item = load!(kind, id)
      if version(item) != expected, do: Repo.rollback(:stale)

      if kind == "booking" do
        booking = item.booking_menu.booking

        if CozyCheckout.Meals.MenuPlanning.stale?(item.booking_menu, booking) or
             not Booking.meal_details_complete?(booking) or booking.status == "cancelled",
           do: Repo.rollback(:stale_booking)
      end

      ids = Enum.reject([main_id | extras], &is_nil/1)

      retained = Enum.reject([item.recipe_id | supplement_ids(item)], &is_nil/1)

      available =
        Repo.all(
          from r in Recipe,
            where: r.id in ^ids and (is_nil(r.archived_at) or r.id in ^retained),
            select: r.id
        )

      if Enum.sort(ids) != Enum.sort(available), do: Repo.rollback(:unavailable_recipe)

      changes =
        if kind == "booking",
          do: %{recipe_id: main_id, manually_edited: true},
          else: %{recipe_id: main_id}

      item |> Changeset.change(changes) |> Repo.update!()

      if kind == "variant" do
        Repo.delete_all(from l in VariantSupplement, where: l.menu_variant_item_id == ^item.id)

        for {recipe_id, index} <- Enum.with_index(extras),
            do:
              Repo.insert!(%VariantSupplement{
                menu_variant_item_id: item.id,
                recipe_id: recipe_id,
                position: index
              })

        item.menu_variant
        |> Changeset.change()
        |> Changeset.optimistic_lock(:lock_version)
        |> Repo.update!()
      else
        Repo.delete_all(from l in BookingSupplement, where: l.booking_menu_item_id == ^item.id)

        for {recipe_id, index} <- Enum.with_index(extras),
            do:
              Repo.insert!(%BookingSupplement{
                booking_menu_item_id: item.id,
                recipe_id: recipe_id,
                position: index
              })
      end

      load!(kind, id)
    end)
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
    Ecto.NoResultsError -> {:error, :stale}
  end
end

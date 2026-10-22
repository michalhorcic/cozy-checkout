defmodule CozyCheckout.Meals.MenuPlanning do
  @moduledoc "Stay variants and reviewed, independent booking menus. Shared daily meals are never overwritten."
  import Ecto.Query
  alias Ecto.Changeset
  alias CozyCheckout.{Repo, Meals}
  alias CozyCheckout.Bookings.Booking

  alias CozyCheckout.Meals.{
    MenuVariant,
    BookingMenu,
    BookingMenuItem,
    PortionCounts,
    SlotSchedule
  }

  def list_variants do
    Repo.all(from v in MenuVariant, where: is_nil(v.deleted_at), order_by: v.name)
  end

  @doc "Menu choices matching the actual inclusive stay and service boundaries."
  def suitable_variants(booking, variants) do
    if Booking.meal_schedule_complete?(booking) and booking.status != "cancelled" do
      Enum.filter(variants, fn variant ->
        is_nil(variant.deleted_at) and
          variant.days == Date.diff(booking.check_out_date, booking.check_in_date) + 1 and
          variant.meal_plan == booking.meal_plan and
          variant.first_meal == booking.first_meal and variant.last_meal == booking.last_meal
      end)
    else
      []
    end
  end

  def booking_menu_summaries(booking_ids) do
    Repo.all(from m in BookingMenu, where: m.booking_id in ^booking_ids)
    |> Map.new(&{&1.booking_id, &1})
  end

  @doc "Immediate selection; application still rechecks compatibility and preserves manual edits."
  def assign_variant(booking_id, variant_id) do
    with {:ok, preview} <- preview(booking_id, variant_id) do
      apply_variant(booking_id, variant_id, preview.token)
    end
  end

  def get_variant!(id) do
    MenuVariant
    |> where([v], is_nil(v.deleted_at))
    |> Repo.get!(id)
    |> CozyCheckout.Recipes.Links.preload_variant()
  end

  def create_variant(attrs) do
    Repo.transaction(fn ->
      case %MenuVariant{items: []} |> MenuVariant.changeset(attrs) |> Repo.insert() do
        {:ok, variant} -> CozyCheckout.Recipes.Links.infer_variant(variant)
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  def update_variant(variant, attrs) do
    Repo.transaction(fn ->
      case variant
           |> MenuVariant.changeset(attrs)
           |> Changeset.optimistic_lock(:lock_version)
           |> Repo.update() do
        {:ok, saved} ->
          previous = Map.new(variant.items, &{&1.id, &1})

          for item <- saved.items,
              before = previous[item.id],
              not is_nil(before),
              do: CozyCheckout.Recipes.Links.clear_text_changes(before, item, "variant")

          get_variant!(saved.id)

        {:error, cs} ->
          Repo.rollback(cs)
      end
    end)
  rescue
    Ecto.StaleEntryError -> {:error, :stale_variant}
  end

  def delete_variant(variant) do
    variant
    |> Changeset.change(deleted_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Changeset.optimistic_lock(:lock_version)
    |> Repo.update()
  rescue
    Ecto.StaleEntryError -> {:error, :stale_variant}
  end

  @doc "Regenerates the editor's slots, preserving text at matching day/type coordinates. Does not write."
  def variant_form(variant, attrs \\ %{}) do
    attrs = stringify(attrs)
    settings = MenuVariant.settings_changeset(variant, attrs) |> Changeset.apply_changes()

    existing =
      case Map.get(attrs, "items") do
        nil -> Enum.map(variant.items, &item_params/1)
        map when is_map(map) -> Map.values(map)
        list -> list
      end

    items =
      Enum.map(MenuVariant.slots(settings), fn {day, type} ->
        Enum.find(existing, fn row ->
          to_string(row["day_number"]) == to_string(day) and row["meal_type"] == type
        end) ||
          %{
            "day_number" => day,
            "meal_type" => type,
            "menu_text" => if(type == "breakfast", do: "Snídaňový bufet", else: "")
          }
      end)

    MenuVariant.changeset(variant, Map.put(attrs, "items", items))
  end

  defp stringify(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

  defp item_params(item),
    do:
      Map.new(
        [:id, :day_number, :meal_type, :menu_text, :supplements],
        &{to_string(&1), Map.get(item, &1)}
      )

  @doc "Explicit, idempotent import of the reviewed Drive snapshot. Never overwrites existing names."
  def import_reference_variants do
    path = Application.app_dir(:cozy_checkout, "priv/menu_variants/drive_reference.json")
    %{"variants" => variants} = path |> File.read!() |> Jason.decode!()

    Repo.transaction(fn ->
      Enum.reduce(variants, %{created: 0, skipped: 0}, fn attrs, counts ->
        if Repo.exists?(from v in MenuVariant, where: v.name == ^attrs["name"]) do
          %{counts | skipped: counts.skipped + 1}
        else
          case create_variant(attrs) do
            {:ok, _} -> %{counts | created: counts.created + 1}
            {:error, cs} -> Repo.rollback(cs)
          end
        end
      end)
    end)
  end

  def get_booking_menu(booking_id) do
    case Repo.get_by(BookingMenu, booking_id: booking_id) do
      nil ->
        nil

      menu ->
        menu
        |> Repo.preload(items: [:recipe, recipe_supplements: :recipe])
        |> Map.update!(:items, &sort_items/1)
    end
  end

  def booking_signature(booking) do
    Map.new([:check_in_date, :check_out_date, :meal_plan, :first_meal, :last_meal], fn field ->
      value = Map.fetch!(booking, field)
      {to_string(field), if(is_struct(value, Date), do: Date.to_iso8601(value), else: value)}
    end)
  end

  def stale?(nil, _booking), do: false
  def stale?(menu, booking), do: menu.booking_signature != booking_signature(booking)

  def preview(booking_id, variant_id) do
    booking = get_booking!(booking_id)

    case Repo.one(from v in MenuVariant, where: v.id == ^variant_id and is_nil(v.deleted_at)) do
      nil ->
        {:error, :variant_unavailable}

      variant ->
        {:ok, build_preview(booking, CozyCheckout.Recipes.Links.preload_variant(variant))}
    end
  end

  @doc "Rechecks the reviewed version under locks, then applies only to this booking."
  def apply_variant(booking_id, variant_id, token) when is_binary(token) do
    Repo.transaction(fn ->
      booking = get_booking!(booking_id, "FOR UPDATE")

      variant =
        Repo.one(
          from v in MenuVariant,
            where: v.id == ^variant_id and is_nil(v.deleted_at),
            lock: "FOR UPDATE"
        )

      if is_nil(variant), do: Repo.rollback(:variant_unavailable)
      variant = CozyCheckout.Recipes.Links.preload_variant(variant)
      preview = build_preview(booking, variant)

      cond do
        preview.token != token -> Repo.rollback(:stale_preview)
        preview.errors != [] -> Repo.rollback({:invalid_menu, preview.errors})
        true -> persist_preview(preview)
      end
    end)
  end

  defp build_preview(booking, variant) do
    menu = get_booking_menu(booking.id)
    errors = compatibility_errors(booking, variant)

    shared =
      if booking.check_out_date do
        Meals.get_meals_for_date_range(booking.check_in_date, booking.check_out_date)
        |> Map.new(&{{&1.date, &1.meal_type}, &1})
      else
        %{}
      end

    other_items =
      if booking.check_out_date,
        do: group_items(booking.check_in_date, booking.check_out_date),
        else: []

    existing = if menu, do: Map.new(menu.items, &{{&1.date, &1.meal_type}, &1}), else: %{}

    rows =
      if Booking.meal_schedule_complete?(booking) do
        portions =
          PortionCounts.for_range([booking], booking.check_in_date, booking.check_out_date)

        variant.items
        |> Enum.sort_by(&{&1.day_number, SlotSchedule.rank(&1.meal_type)})
        |> Enum.map(fn source ->
          date = Date.add(booking.check_in_date, source.day_number - 1)
          old = existing[{date, source.meal_type}]
          preserve = old && old.manually_edited
          text = if preserve, do: old.menu_text, else: source.menu_text
          supplements = if preserve, do: old.supplements, else: source.supplements
          common = shared[{date, source.meal_type}]

          other =
            Enum.filter(other_items, fn item ->
              item.booking.id != booking.id and item.date == date and
                item.meal_type == source.meal_type and
                menu_text(item.menu_text, item.supplements) != menu_text(text, supplements)
            end)

          %{
            id: "#{date}-#{source.meal_type}",
            date: date,
            day_number: source.day_number,
            meal_type: source.meal_type,
            menu_text: text,
            supplements: supplements,
            source_text: source.menu_text,
            source_supplements: source.supplements,
            source_item: source,
            existing: old,
            preserve: preserve == true,
            counts:
              get_in(portions, [date, source.meal_type]) || %{adults: 0, children: 0, total: 0},
            shared_conflict:
              common && not blank?(common.menu_text) &&
                String.trim(common.menu_text) != menu_text(text, supplements),
            shared_text: if(common, do: common.menu_text),
            other_groups: Enum.map(other, & &1.booking.guest.name) |> Enum.sort()
          }
        end)
      else
        []
      end

    keys = MapSet.new(rows, &{&1.date, &1.meal_type})

    orphans =
      if menu,
        do:
          Enum.filter(
            menu.items,
            &(&1.manually_edited and not MapSet.member?(keys, {&1.date, &1.meal_type}))
          ),
        else: []

    errors =
      if orphans != [],
        do:
          errors ++
            [
              "Ruční úpravy mimo nový rozpis by zanikly. Nejdřív u nich výslovně povolte přepsání."
            ],
        else: errors

    token =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({
          Map.take(booking, [:id, :updated_at, :status, :meal_adults, :meal_children]),
          booking_signature(booking),
          variant.id,
          variant.lock_version,
          variant.items |> Enum.map(&item_params/1) |> Enum.sort(),
          if(menu, do: {menu.id, menu.booking_signature, menu.source_revision, menu.items}),
          rows,
          errors
        })
      )
      |> Base.url_encode64(padding: false)

    %{booking: booking, variant: variant, menu: menu, rows: rows, errors: errors, token: token}
  end

  defp compatibility_errors(booking, variant) do
    errors = []

    errors =
      if booking.status == "cancelled",
        do: errors ++ ["Zrušené rezervaci nelze přiřadit menu."],
        else: errors

    errors =
      if not Booking.meal_schedule_complete?(booking),
        do: errors ++ ["Nejdřív doplňte stravování a termín rezervace."],
        else: errors

    if Booking.meal_schedule_complete?(booking) do
      checks = [
        {Date.diff(booking.check_out_date, booking.check_in_date) + 1 == variant.days,
         "Nesouhlasí počet dnů pobytu a varianty."},
        {booking.meal_plan == variant.meal_plan, "Nesouhlasí režim stravování."},
        {booking.first_meal == variant.first_meal, "Nesouhlasí první jídlo."},
        {booking.last_meal == variant.last_meal, "Nesouhlasí poslední jídlo."},
        {MenuVariant.changeset(variant, %{}).valid?, "Varianta nemá úplný rozpis jídel."}
      ]

      errors ++ for {false, message} <- checks, do: message
    else
      errors
    end
  end

  defp persist_preview(preview) do
    %{booking: booking, variant: variant} = preview

    menu =
      (preview.menu || %BookingMenu{booking_id: booking.id})
      |> BookingMenu.changeset(%{
        menu_variant_id: variant.id,
        variant_name: variant.name,
        source_revision: variant.lock_version,
        booking_signature: booking_signature(booking)
      })
      |> Repo.insert_or_update!()

    desired = MapSet.new(preview.rows, &{&1.date, &1.meal_type})

    if preview.menu do
      Enum.each(preview.menu.items, fn item ->
        if not MapSet.member?(desired, {item.date, item.meal_type}), do: Repo.delete!(item)
      end)
    end

    Enum.each(preview.rows, fn row ->
      if row.preserve do
        row.existing |> Changeset.change(day_number: row.day_number) |> Repo.update!()
      else
        item =
          row.existing ||
            %BookingMenuItem{
              booking_menu_id: menu.id,
              date: row.date,
              day_number: row.day_number,
              meal_type: row.meal_type
            }

        item
        |> BookingMenuItem.changeset(%{
          menu_text: row.source_text,
          supplements: row.source_supplements
        })
        |> Changeset.put_change(:day_number, row.day_number)
        |> Repo.insert_or_update!()
        |> then(&CozyCheckout.Recipes.Links.copy(row.source_item, &1))
      end
    end)

    get_booking_menu(booking.id)
  end

  def update_booking_item(booking_id, item_id, attrs, expected_updated_at) do
    Repo.transaction(fn ->
      get_booking!(booking_id, "FOR UPDATE")
      item = get_scoped_item(booking_id, item_id)
      if is_nil(item) or item_version(item) != expected_updated_at, do: Repo.rollback(:stale_item)

      cs =
        item |> BookingMenuItem.changeset(attrs) |> Changeset.put_change(:manually_edited, true)

      case Repo.update(cs) do
        {:ok, updated} -> CozyCheckout.Recipes.Links.clear_text_changes(item, updated, "booking")
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  def allow_item_replacement(booking_id, item_id, expected_updated_at) do
    Repo.transaction(fn ->
      get_booking!(booking_id, "FOR UPDATE")
      item = get_scoped_item(booking_id, item_id)
      if is_nil(item) or item_version(item) != expected_updated_at, do: Repo.rollback(:stale_item)
      item |> Changeset.change(manually_edited: false) |> Repo.update!()
    end)
  end

  # Content is included because UTC timestamps have second precision.
  def item_version(item), do: CozyCheckout.Recipes.Links.version(item)

  defp get_scoped_item(booking_id, item_id) do
    Repo.one(
      from i in BookingMenuItem,
        join: m in assoc(i, :booking_menu),
        where: m.booking_id == ^booking_id and i.id == ^item_id
    )
  end

  defp get_booking!(id, lock \\ nil) do
    query = from(b in Booking, where: b.id == ^id and is_nil(b.deleted_at))
    query = if lock, do: lock(query, "FOR UPDATE"), else: query
    query |> Repo.one!() |> Repo.preload(:guest)
  end

  @doc "Group-specific menus with live portions, plus missing/stale-menu warnings."
  def kitchen_for_range(start_date, end_date) do
    bookings =
      Repo.all(
        from b in Booking,
          where: is_nil(b.deleted_at) and b.status != "cancelled",
          where:
            b.check_in_date <= ^end_date and
              (is_nil(b.check_out_date) or b.check_out_date >= ^start_date),
          preload: [:guest]
      )

    items = group_items(start_date, end_date)

    menus =
      Repo.all(from m in BookingMenu, where: m.booking_id in ^Enum.map(bookings, & &1.id))
      |> Map.new(&{&1.booking_id, &1})

    issues =
      bookings
      |> Enum.filter(&Booking.meal_details_complete?/1)
      |> Enum.flat_map(fn booking ->
        case menus[booking.id] do
          nil ->
            [%{booking: booking, reason: "Menu ještě není přiřazené"}]

          menu ->
            if stale?(menu, booking),
              do: [
                %{
                  booking: booking,
                  reason: "Termín nebo stravování se změnilo; znovu použijte variantu"
                }
              ],
              else: []
        end
      end)

    groups =
      Enum.reduce(items, %{}, fn item, acc ->
        counts = %{
          adults: item.booking.meal_adults,
          children: item.booking.meal_children,
          total: item.booking.meal_adults + item.booking.meal_children
        }

        entry = Map.put(item, :counts, counts)
        Map.update(acc, {item.date, item.meal_type}, [entry], &(&1 ++ [entry]))
      end)

    %{groups: groups, issues: Enum.sort_by(issues, & &1.booking.check_in_date, Date)}
  end

  defp group_items(start_date, end_date) do
    Repo.all(
      from i in BookingMenuItem,
        join: m in assoc(i, :booking_menu),
        join: b in assoc(m, :booking),
        where: i.date >= ^start_date and i.date <= ^end_date,
        where: is_nil(b.deleted_at) and b.status != "cancelled",
        preload: [booking_menu: {m, booking: {b, :guest}}]
    )
    |> Enum.filter(fn item ->
      booking = item.booking_menu.booking
      Booking.meal_details_complete?(booking) and not stale?(item.booking_menu, booking)
    end)
    |> Enum.map(fn item ->
      %{
        id: item.id,
        date: item.date,
        meal_type: item.meal_type,
        menu_text: item.menu_text,
        supplements: item.supplements,
        manually_edited: item.manually_edited,
        booking: item.booking_menu.booking,
        variant_name: item.booking_menu.variant_name
      }
    end)
    |> Enum.sort_by(
      &{Date.to_gregorian_days(&1.date), SlotSchedule.rank(&1.meal_type), &1.booking.guest.name,
       &1.booking.id}
    )
  end

  def menu_text(main, supplements),
    do:
      [main, supplements] |> Enum.reject(&blank?/1) |> Enum.map(&String.trim/1) |> Enum.join("\n")

  defp blank?(text), do: is_nil(text) or String.trim(text) == ""

  defp sort_items(items),
    do: Enum.sort_by(items, &{Date.to_gregorian_days(&1.date), SlotSchedule.rank(&1.meal_type)})
end

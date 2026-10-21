defmodule CozyCheckout.Meals.BookingMenusTest do
  use CozyCheckout.DataCase, async: true
  import CozyCheckout.MenuFixtures
  alias CozyCheckout.{Bookings, Meals, Repo}
  alias CozyCheckout.Meals.{MenuPlanning, BookingMenuItem}

  test "preview is read-only, includes dates and live portions, and applies an independent snapshot" do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    assert {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
    assert preview.errors == []
    assert length(preview.rows) == 5

    assert Enum.map(preview.rows, & &1.date) == [
             ~D[2027-01-08],
             ~D[2027-01-09],
             ~D[2027-01-09],
             ~D[2027-01-09],
             ~D[2027-01-10]
           ]

    assert Enum.all?(preview.rows, &(&1.counts == %{adults: 10, children: 5, total: 15}))
    assert MenuPlanning.get_booking_menu(booking.id) == nil
    assert {:ok, menu} = MenuPlanning.apply_variant(booking.id, variant.id, preview.token)
    assert length(menu.items) == 5
    assert Meals.get_meals_for_date_range(~D[2027-01-08], ~D[2027-01-10]) == []
  end

  test "mismatched length, board and meal boundaries prevent all writes" do
    booking = menu_booking_fixture()

    for overrides <- [
          %{days: 4},
          %{meal_plan: "half_board"},
          %{first_meal: "lunch"},
          %{last_meal: "lunch"}
        ] do
      variant = variant_fixture(overrides)
      {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
      assert preview.errors != []

      assert {:error, {:invalid_menu, _}} =
               MenuPlanning.apply_variant(booking.id, variant.id, preview.token)

      assert MenuPlanning.get_booking_menu(booking.id) == nil
    end

    for overrides <- [%{meal_plan: nil}, %{meal_plan: "none"}, %{status: "cancelled"}] do
      other = menu_booking_fixture(overrides)
      variant = variant_fixture()
      {:ok, preview} = MenuPlanning.preview(other.id, variant.id)
      assert preview.errors != []

      assert {:error, {:invalid_menu, _}} =
               MenuPlanning.apply_variant(other.id, variant.id, preview.token)
    end
  end

  test "different group menus coexist and conflicts with shared menu are visible without changing it" do
    first = menu_booking_fixture()
    second = menu_booking_fixture(%{meal_adults: 2, meal_children: 0})
    a = variant_fixture(%{name: "Skupina A"})
    b = variant_fixture(%{name: "Skupina B"})

    {:ok, shared} =
      Meals.upsert_meal(~D[2027-01-09], "lunch", %{
        menu_text: "Společný guláš",
        dietary_notes: "Bez lepku"
      })

    assign_variant(first, a)
    {:ok, preview} = MenuPlanning.preview(second.id, b.id)
    lunch = Enum.find(preview.rows, &(&1.meal_type == "lunch"))
    assert lunch.shared_conflict
    assert lunch.shared_text == "Společný guláš"
    assert length(lunch.other_groups) == 1
    assert {:ok, _} = MenuPlanning.apply_variant(second.id, b.id, preview.token)

    groups =
      MenuPlanning.kitchen_for_range(~D[2027-01-09], ~D[2027-01-09]).groups[
        {~D[2027-01-09], "lunch"}
      ]

    assert length(groups) == 2
    assert groups |> Enum.map(& &1.counts.total) |> Enum.sort() == [2, 15]
    assert Repo.get!(CozyCheckout.Meals.Meal, shared.id).menu_text == "Společný guláš"
    assert Repo.get!(CozyCheckout.Meals.Meal, shared.id).dietary_notes == "Bez lepku"
  end

  test "reapplying is idempotent and preserves manual meals and supplements when changing variant" do
    booking = menu_booking_fixture()
    original = variant_fixture()
    menu = assign_variant(booking, original)
    item = hd(menu.items)

    assert {:ok, edited} =
             MenuPlanning.update_booking_item(
               booking.id,
               item.id,
               %{menu_text: "Dietní večeře", supplements: "Bezlepková příloha"},
               MenuPlanning.item_version(item)
             )

    other = variant_fixture()
    {:ok, preview} = MenuPlanning.preview(booking.id, other.id)
    row = hd(preview.rows)
    assert row.preserve
    assert row.menu_text == "Dietní večeře"
    assert row.supplements == "Bezlepková příloha"
    {:ok, applied} = MenuPlanning.apply_variant(booking.id, other.id, preview.token)
    assert hd(applied.items).id == edited.id
    assert hd(applied.items).manually_edited
    ids = Enum.map(applied.items, & &1.id)
    {:ok, again} = MenuPlanning.preview(booking.id, other.id)
    {:ok, repeated} = MenuPlanning.apply_variant(booking.id, other.id, again.token)
    assert Enum.map(repeated.items, & &1.id) == ids
  end

  test "date changes mark snapshots stale and orphaned manual edits block replacement until explicitly released" do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    menu = assign_variant(booking, variant)
    item = hd(menu.items)

    {:ok, edited} =
      MenuPlanning.update_booking_item(
        booking.id,
        item.id,
        %{menu_text: "Ruční menu"},
        MenuPlanning.item_version(item)
      )

    {:ok, changed} =
      Bookings.update_booking(booking, %{
        check_in_date: ~D[2027-01-15],
        check_out_date: ~D[2027-01-17]
      })

    assert MenuPlanning.stale?(menu, changed)
    kitchen = MenuPlanning.kitchen_for_range(~D[2027-01-15], ~D[2027-01-17])
    assert kitchen.groups == %{}
    assert [%{booking: %{id: id}}] = kitchen.issues
    assert id == booking.id
    {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
    assert Enum.any?(preview.errors, &String.contains?(&1, "Ruční úpravy"))

    assert {:error, {:invalid_menu, _}} =
             MenuPlanning.apply_variant(booking.id, variant.id, preview.token)

    assert Repo.get!(BookingMenuItem, edited.id).menu_text == "Ruční menu"

    {:ok, _} =
      MenuPlanning.allow_item_replacement(
        booking.id,
        edited.id,
        MenuPlanning.item_version(edited)
      )

    {:ok, fresh} = MenuPlanning.preview(booking.id, variant.id)
    assert fresh.errors == []
    {:ok, menu} = MenuPlanning.apply_variant(booking.id, variant.id, fresh.token)
    assert hd(menu.items).date == ~D[2027-01-15]
    refute MenuPlanning.stale?(menu, changed)
    refute Repo.get(BookingMenuItem, edited.id)
  end

  test "changes to bookings, shared text or the variant after preview reject stale approval" do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
    {:ok, booking} = Bookings.update_booking(booking, %{meal_children: 6})

    assert {:error, :stale_preview} =
             MenuPlanning.apply_variant(booking.id, variant.id, preview.token)

    {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
    {:ok, _} = Meals.upsert_meal(~D[2027-01-09], "lunch", %{menu_text: "Změněné společné menu"})

    assert {:error, :stale_preview} =
             MenuPlanning.apply_variant(booking.id, variant.id, preview.token)

    {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
    {:ok, _} = MenuPlanning.update_variant(variant, %{name: "Změněná šablona"})

    assert {:error, :stale_preview} =
             MenuPlanning.apply_variant(booking.id, variant.id, preview.token)

    assert MenuPlanning.get_booking_menu(booking.id) == nil
  end

  test "manual edit after preview is never silently overwritten" do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    menu = assign_variant(booking, variant)
    {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
    item = hd(menu.items)

    {:ok, _} =
      MenuPlanning.update_booking_item(
        booking.id,
        item.id,
        %{menu_text: "Pozdní úprava"},
        MenuPlanning.item_version(item)
      )

    assert {:error, :stale_preview} =
             MenuPlanning.apply_variant(booking.id, variant.id, preview.token)

    assert hd(MenuPlanning.get_booking_menu(booking.id).items).menu_text == "Pozdní úprava"
  end

  test "counts remain live while later variant edits do not mutate assigned text" do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    menu = assign_variant(booking, variant)
    {:ok, _} = Bookings.update_booking(booking, %{meal_adults: 20, meal_children: 2})
    {:ok, _} = MenuPlanning.update_variant(variant, %{name: "Novější varianta"})

    [group] =
      MenuPlanning.kitchen_for_range(~D[2027-01-10], ~D[2027-01-10]).groups[
        {~D[2027-01-10], "breakfast"}
      ]

    assert group.counts == %{adults: 20, children: 2, total: 22}
    assert group.menu_text == List.last(menu.items).menu_text
    assert group.variant_name == variant.name
  end

  test "archiving a variant keeps historical snapshots but prevents new application" do
    booking = menu_booking_fixture(%{status: "completed"})
    variant = variant_fixture()
    assign_variant(booking, variant)
    {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
    {:ok, _} = MenuPlanning.delete_variant(variant)
    assert {:error, :variant_unavailable} = MenuPlanning.preview(booking.id, variant.id)

    assert {:error, :variant_unavailable} =
             MenuPlanning.apply_variant(booking.id, variant.id, preview.token)

    assert Map.has_key?(
             MenuPlanning.kitchen_for_range(~D[2027-01-10], ~D[2027-01-10]).groups,
             {~D[2027-01-10], "breakfast"}
           )
  end

  test "missing menus are flagged, cancelled and deleted stays are excluded, completed history remains" do
    missing = menu_booking_fixture()
    cancelled = menu_booking_fixture()
    deleted = menu_booking_fixture()
    completed = menu_booking_fixture(%{status: "completed"})
    variant = variant_fixture()
    for booking <- [cancelled, deleted, completed], do: assign_variant(booking, variant)
    {:ok, _} = Bookings.update_booking(cancelled, %{status: "cancelled"})
    {:ok, _} = Bookings.delete_booking(deleted)
    kitchen = MenuPlanning.kitchen_for_range(~D[2027-01-10], ~D[2027-01-10])
    assert [%{booking: %{id: id}}] = kitchen.issues
    assert id == missing.id
    assert [%{booking: %{id: id}}] = kitchen.groups[{~D[2027-01-10], "breakfast"}]
    assert id == completed.id
  end

  test "two editors cannot overwrite the same item even within the same timestamp second" do
    booking = menu_booking_fixture()
    menu = assign_variant(booking, variant_fixture())
    item = hd(menu.items)
    version = MenuPlanning.item_version(item)

    assert {:ok, edited} =
             MenuPlanning.update_booking_item(
               booking.id,
               item.id,
               %{menu_text: "První editor"},
               version
             )

    assert {:error, :stale_item} =
             MenuPlanning.update_booking_item(
               booking.id,
               item.id,
               %{menu_text: "Druhý editor"},
               version
             )

    assert {:error, :stale_item} =
             MenuPlanning.allow_item_replacement(booking.id, item.id, version)

    assert Repo.get!(BookingMenuItem, edited.id).menu_text == "První editor"
  end

  test "overlapping manual meals keep their text and acquire the new relative day" do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    menu = assign_variant(booking, variant)
    item = Enum.find(menu.items, &(&1.date == ~D[2027-01-09] and &1.meal_type == "dinner"))

    {:ok, _} =
      MenuPlanning.update_booking_item(
        booking.id,
        item.id,
        %{menu_text: "Zachovaná večeře"},
        MenuPlanning.item_version(item)
      )

    {:ok, _} =
      Bookings.update_booking(booking, %{
        check_in_date: ~D[2027-01-09],
        check_out_date: ~D[2027-01-11]
      })

    {:ok, preview} = MenuPlanning.preview(booking.id, variant.id)
    assert preview.errors == []
    {:ok, updated} = MenuPlanning.apply_variant(booking.id, variant.id, preview.token)
    kept = Enum.find(updated.items, &(&1.id == item.id))
    assert kept.day_number == 1
    assert kept.menu_text == "Zachovaná večeře"
  end

  test "an item removed by another application reports a stale edit rather than crashing" do
    booking = menu_booking_fixture()
    variant = variant_fixture()
    menu = assign_variant(booking, variant)
    item = hd(menu.items)

    {:ok, _} =
      Bookings.update_booking(booking, %{
        check_in_date: ~D[2027-01-15],
        check_out_date: ~D[2027-01-17]
      })

    assign_variant(booking, variant)

    assert {:error, :stale_item} =
             MenuPlanning.update_booking_item(
               booking.id,
               item.id,
               %{menu_text: "Starý editor"},
               MenuPlanning.item_version(item)
             )
  end
end

defmodule CozyCheckout.Meals.PortionCountsTest do
  use ExUnit.Case, async: true

  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Meals.PortionCounts

  defp booking(overrides \\ %{}) do
    struct!(
      Booking,
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          check_in_date: ~D[2027-01-08],
          check_out_date: ~D[2027-01-10],
          meal_plan: "full_board",
          meal_adults: 10,
          meal_children: 5,
          first_meal: "dinner",
          last_meal: "breakfast"
        },
        overrides
      )
    )
  end

  defp totals(day), do: Enum.map(["breakfast", "lunch", "dinner"], &day[&1].total)

  test "Friday dinner to Sunday breakfast gives 2 breakfasts, 1 lunch and 2 dinners" do
    counts = PortionCounts.for_range([booking()], ~D[2027-01-07], ~D[2027-01-11])
    assert totals(counts[~D[2027-01-07]]) == [0, 0, 0]
    assert totals(counts[~D[2027-01-08]]) == [0, 0, 15]
    assert totals(counts[~D[2027-01-09]]) == [15, 15, 15]
    assert totals(counts[~D[2027-01-10]]) == [15, 0, 0]
    assert totals(counts[~D[2027-01-11]]) == [0, 0, 0]
    assert counts[~D[2027-01-09]]["lunch"] == %{adults: 10, children: 5, total: 15}
  end

  test "half board excludes every lunch" do
    counts =
      PortionCounts.for_range(
        [booking(%{meal_plan: "half_board"})],
        ~D[2027-01-08],
        ~D[2027-01-10]
      )

    assert totals(counts[~D[2027-01-08]]) == [0, 0, 15]
    assert totals(counts[~D[2027-01-09]]) == [15, 0, 15]
    assert totals(counts[~D[2027-01-10]]) == [15, 0, 0]
  end

  test "all arrival and departure boundaries are inclusive" do
    for {first, expected} <- [
          {"breakfast", [15, 15, 15]},
          {"lunch", [0, 15, 15]},
          {"dinner", [0, 0, 15]}
        ] do
      counts =
        PortionCounts.for_range([booking(%{first_meal: first})], ~D[2027-01-08], ~D[2027-01-10])

      assert totals(counts[~D[2027-01-08]]) == expected
    end

    for {last, expected} <- [
          {"breakfast", [15, 0, 0]},
          {"lunch", [15, 15, 0]},
          {"dinner", [15, 15, 15]}
        ] do
      counts =
        PortionCounts.for_range([booking(%{last_meal: last})], ~D[2027-01-08], ~D[2027-01-10])

      assert totals(counts[~D[2027-01-10]]) == expected
    end
  end

  test "same-day stay counts a single meal or ordered subset" do
    for {first, last, expected} <- [
          {"lunch", "lunch", [0, 15, 0]},
          {"breakfast", "lunch", [15, 15, 0]},
          {"lunch", "dinner", [0, 15, 15]}
        ] do
      stay = booking(%{check_out_date: ~D[2027-01-08], first_meal: first, last_meal: last})

      assert totals(
               PortionCounts.for_range([stay], ~D[2027-01-08], ~D[2027-01-08])[~D[2027-01-08]]
             ) == expected
    end
  end

  test "adds overlapping groups while preserving the adult/child split" do
    groups = [booking(), booking(%{meal_plan: "half_board", meal_adults: 2, meal_children: 0})]
    day = PortionCounts.for_range(groups, ~D[2027-01-09], ~D[2027-01-09])[~D[2027-01-09]]
    assert day["breakfast"] == %{adults: 12, children: 5, total: 17}
    assert day["lunch"] == %{adults: 10, children: 5, total: 15}
  end

  test "week boundary includes the preceding stay's Sunday departure breakfast" do
    counts = PortionCounts.for_range([booking()], ~D[2027-01-10], ~D[2027-01-16])
    assert map_size(counts) == 7
    assert totals(counts[~D[2027-01-10]]) == [15, 0, 0]
    assert totals(counts[~D[2027-01-11]]) == [0, 0, 0]
  end

  test "missing instructions produce warnings alongside known totals, never invented zeros" do
    unknown = booking(%{meal_plan: nil, check_out_date: nil})
    missing_count = booking(%{meal_children: nil})
    invalid_count = booking(%{meal_adults: -1})
    invalid_order = booking(%{check_out_date: ~D[2027-01-08]})
    stays = [booking(), unknown, missing_count, invalid_count, invalid_order]
    day = PortionCounts.for_range(stays, ~D[2027-01-08], ~D[2027-01-08])[~D[2027-01-08]]
    assert day["dinner"].total == 15
    assert day.incomplete_bookings == [unknown, missing_count, invalid_count, invalid_order]
  end

  test "cancelled and deleted stays contribute neither counts nor warnings; completed stays do" do
    stays = [
      booking(%{status: "cancelled"}),
      booking(%{deleted_at: ~U[2027-01-01 00:00:00Z]}),
      booking(%{meal_plan: "none"}),
      booking(%{meal_plan: nil, status: "cancelled"}),
      booking(%{status: "completed"})
    ]

    day = PortionCounts.for_range(stays, ~D[2027-01-09], ~D[2027-01-09])[~D[2027-01-09]]
    assert totals(day) == [15, 15, 15]
    assert day.incomplete_bookings == []
  end
end

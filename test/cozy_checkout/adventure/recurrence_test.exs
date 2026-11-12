defmodule CozyCheckout.Adventure.RecurrenceTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.Adventure.{Recurrence, TaskTemplate}

  test "daily recurrence uses local dates across DST and year boundaries" do
    for day <- [~D[2026-03-29], ~D[2026-10-25], ~D[2026-12-31]] do
      t = %TaskTemplate{starts_on: day, cadence: "daily"}
      assert Recurrence.next(t, Date.add(day, 1)) == Date.add(day, 1)
      assert Recurrence.latest(t, day) == day
      assert Recurrence.latest(t, Date.add(day, -1)) == nil
    end
  end

  test "weekly recurrence supports multiple weekdays without ISO year drift" do
    t = %TaskTemplate{starts_on: ~D[2026-12-28], cadence: "weekly", weekdays: [1, 4]}
    assert Recurrence.next(t, ~D[2026-12-29]) == ~D[2026-12-31]
    assert Recurrence.next(t, ~D[2027-01-01]) == ~D[2027-01-04]
    assert Recurrence.latest(t, ~D[2027-01-03]) == ~D[2026-12-31]
    assert Recurrence.period(t, ~D[2027-01-04]) == "date:2027-01-04"

    assert Recurrence.period(%{t | legacy_code: "prepare_stay"}, ~D[2027-01-04]) ==
             "week:2027-01-04"
  end
end

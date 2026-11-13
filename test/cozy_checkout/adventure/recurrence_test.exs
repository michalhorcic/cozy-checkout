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

  test "monthly uses the original day after February and finds neighboring occurrences" do
    t = %TaskTemplate{starts_on: ~D[2027-01-31], cadence: "monthly"}
    assert Recurrence.next(t, ~D[2026-12-01]) == ~D[2027-01-31]
    assert Recurrence.latest(t, ~D[2027-01-30]) == nil
    assert Recurrence.next(t, ~D[2027-02-01]) == ~D[2027-02-28]
    assert Recurrence.latest(t, ~D[2027-02-27]) == ~D[2027-01-31]
    assert Recurrence.latest(t, ~D[2027-02-28]) == ~D[2027-02-28]
    assert Recurrence.next(t, ~D[2027-03-01]) == ~D[2027-03-31]
    assert Recurrence.latest(t, ~D[2027-03-30]) == ~D[2027-02-28]
    assert Recurrence.next(t, ~D[2028-02-01]) == ~D[2028-02-29]
    assert Recurrence.next(t, ~D[2028-03-01]) == ~D[2028-03-31]
  end

  test "semiannual stays six calendar months apart without completion drift" do
    t = %TaskTemplate{starts_on: ~D[2026-11-13], cadence: "semiannual"}
    assert Recurrence.next(t, ~D[2026-11-20]) == ~D[2027-05-13]
    assert Recurrence.latest(t, ~D[2027-05-12]) == ~D[2026-11-13]
    assert Recurrence.next(t, ~D[2027-05-14]) == ~D[2027-11-13]
    t = %{t | starts_on: ~D[2027-08-31]}
    assert Recurrence.next(t, ~D[2027-09-01]) == ~D[2028-02-29]
    assert Recurrence.next(t, ~D[2028-03-01]) == ~D[2028-08-31]
  end

  test "yearly leap anniversaries recover the 29th and handle nonleap centuries" do
    t = %TaskTemplate{starts_on: ~D[2096-02-29], cadence: "yearly"}
    assert Recurrence.next(t, ~D[2097-01-01]) == ~D[2097-02-28]
    assert Recurrence.latest(t, ~D[2100-02-27]) == ~D[2099-02-28]
    assert Recurrence.next(t, ~D[2100-01-01]) == ~D[2100-02-28]
    assert Recurrence.next(t, ~D[2104-01-01]) == ~D[2104-02-29]
  end

  test "calendar bounds work over long gaps without generating intermediate copies" do
    for cadence <- ~w(monthly semiannual yearly),
        days <- [-100, -1, 0, 1, 28, 29, 30, 365, 10000] do
      t = %TaskTemplate{starts_on: ~D[2024-01-31], cadence: cadence}
      day = Date.add(t.starts_on, days)
      next = Recurrence.next(t, day)
      assert Date.compare(next, day) != :lt
      assert Date.compare(next, t.starts_on) != :lt

      if days < 0 do
        assert Recurrence.latest(t, day) == nil
      else
        latest = Recurrence.latest(t, day)
        assert Date.compare(latest, day) != :gt
        assert Date.compare(Recurrence.next(t, Date.add(latest, 1)), day) == :gt
        assert Recurrence.period(t, latest) == "date:" <> Date.to_iso8601(latest)
      end
    end
  end
end

defmodule CozyCheckout.Adventure.StaysTest do
  use CozyCheckout.DataCase, async: false
  import CozyCheckout.AdventureFixtures
  alias CozyCheckout.Adventure.Sources.Stays
  alias CozyCheckout.{QueryRecorder, Repo}

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
    {:ok, campaign: fixed_campaign(adventure_profile())}
  end

  test "one read separates realized nights and future reservations without duplicating rooms", %{
    campaign: c
  } do
    booking = adventure_booking()

    for number <- ["A", "B"] do
      room = Repo.insert!(%CozyCheckout.Rooms.Room{room_number: number, capacity: 5})
      Repo.insert!(%CozyCheckout.Bookings.BookingRoom{booking_id: booking.id, room_id: room.id})
    end

    adventure_booking(%{
      status: "active",
      check_in_date: ~D[2026-10-04],
      check_out_date: ~D[2026-10-08],
      adults: 3
    })

    adventure_booking(%{
      status: "upcoming",
      check_in_date: ~D[2026-10-07],
      check_out_date: ~D[2026-10-09],
      adults: 4
    })

    adventure_booking(%{status: "cancelled", adults: 50})
    adventure_booking(%{deleted_at: ~U[2026-10-05 12:00:00Z], adults: 50})

    {snapshot, queries} =
      QueryRecorder.record(fn -> Stays.snapshot(c, ~U[2026-10-06 12:00:00Z]) end)

    assert length(queries) == 1
    assert snapshot["completed_stays"] == 1
    assert snapshot["eligible_completed_stays"] == 1
    assert snapshot["realized_bednights"] == 10
    assert snapshot["reserved_bednights"] == 14
    assert snapshot["occupancy_percent"] == "20.00"
    assert snapshot["completeness"] == "complete"
    assert snapshot["as_of"] == "2026-10-06T12:00:00Z"
    assert snapshot["source"] == "bookings"
    refute inspect(snapshot) =~ "Soukromé"
    refute inspect(snapshot) =~ "@example.test"
  end

  test "overlap clips nights to the campaign and includes infants according to calendar counts",
       %{campaign: c} do
    adventure_booking(%{
      check_in_date: ~D[2026-09-28],
      check_out_date: ~D[2026-10-02],
      adults: 1,
      infants: 1
    })

    adventure_booking(%{
      check_in_date: ~D[2026-10-06],
      check_out_date: ~D[2026-10-08],
      status: "upcoming",
      adults: 3
    })

    snapshot = Stays.snapshot(c, ~U[2026-10-06 12:00:00Z])
    assert snapshot["realized_bednights"] == 2
    assert snapshot["reserved_bednights"] == 6
    assert snapshot["completed_stays"] == 1
  end

  test "activation day is excluded from automatic milestone eligibility", %{campaign: c} do
    c = %{c | activated_at: ~U[2026-10-03 12:00:00Z]}
    adventure_booking()
    snapshot = Stays.snapshot(c, ~U[2026-10-06 12:00:00Z])
    assert snapshot["completed_stays"] == 1
    assert snapshot["eligible_completed_stays"] == 0
  end

  test "missing departure and stale statuses mark partial data instead of a verified zero", %{
    campaign: c
  } do
    adventure_booking(%{check_out_date: nil})
    adventure_booking(%{status: "upcoming"})
    snapshot = Stays.snapshot(c, ~U[2026-10-06 12:00:00Z])
    assert snapshot["uncertain_stays"] == 2
    assert snapshot["completeness"] == "partial"
  end

  test "future empty period has known zero counts but unavailable occupancy", %{campaign: c} do
    snapshot = Stays.snapshot(c, ~U[2026-09-30 12:00:00Z])
    assert snapshot["completed_stays"] == 0
    assert snapshot["reserved_bednights"] == 0
    assert snapshot["closed_nights"] == 0
    assert snapshot["occupancy_percent"] == nil
    assert snapshot["occupancy_status"] == "unavailable"
    assert snapshot["completeness"] == "complete"
  end

  test "closure freezes the cutoff while as_of honestly records the current read", %{campaign: c} do
    adventure_booking(%{check_out_date: ~D[2026-10-08]})

    snapshot =
      Stays.snapshot(%{c | closed_at: ~U[2026-10-06 12:00:00Z]}, ~U[2026-10-09 12:00:00Z])

    assert snapshot["cutoff_on"] == "2026-10-06"
    assert snapshot["as_of"] == "2026-10-09T12:00:00Z"
    assert snapshot["eligible_completed_stays"] == 0
  end

  test "closed nights follow Prague midnight and over-capacity results are partial", %{
    campaign: c
  } do
    adventure_booking(%{
      check_in_date: ~D[2026-10-01],
      check_out_date: ~D[2026-10-05],
      adults: 100
    })

    before_midnight = Stays.snapshot(c, ~U[2026-10-05 21:59:59Z])
    after_midnight = Stays.snapshot(c, ~U[2026-10-05 22:00:00Z])
    assert before_midnight["cutoff_on"] == "2026-10-05"
    assert after_midnight["cutoff_on"] == "2026-10-06"
    assert after_midnight["closed_nights"] == 5
    assert after_midnight["completeness"] == "partial"
  end
end

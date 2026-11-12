defmodule CozyCheckout.Adventure.OperationTest do
  use CozyCheckout.DataCase, async: false
  import CozyCheckout.AdventureFixtures
  import CozyCheckout.MenuFixtures
  alias CozyCheckout.{Dashboard, Repo}
  alias CozyCheckout.Adventure.Sources.Operation

  setup do
    previous = Application.get_env(:cozy_checkout, :adventure_enabled, false)
    Application.put_env(:cozy_checkout, :adventure_enabled, true)
    on_exit(fn -> Application.put_env(:cozy_checkout, :adventure_enabled, previous) end)
  end

  test "Prague day follows winter, summer and both UTC DST boundaries without SQL" do
    assert Operation.today(~U[2026-01-01 23:30:00Z]) == ~D[2026-01-02]
    assert Operation.today(~U[2026-07-01 22:30:00Z]) == ~D[2026-07-02]
    assert Operation.today(~U[2026-03-28 22:30:00Z]) == ~D[2026-03-28]
    assert Operation.today(~U[2026-03-29 22:30:00Z]) == ~D[2026-03-30]
    assert Operation.today(~U[2026-10-24 22:30:00Z]) == ~D[2026-10-25]
    assert Operation.today(~U[2026-10-25 22:30:00Z]) == ~D[2026-10-25]
  end

  test "projection retains calendar semantics, known portions, dated issues and no guest payload" do
    today = ~D[2027-01-08]
    arriving = menu_booking_fixture(%{adults: 4})

    leaving =
      menu_booking_fixture(%{
        adults: 7,
        check_in_date: Date.add(today, -2),
        check_out_date: today
      })

    unknown = menu_booking_fixture(%{meal_plan: nil})
    menu_booking_fixture(%{status: "cancelled"})
    menu_booking_fixture(%{status: "completed"})
    overview = Dashboard.overview(today)
    now = ~U[2027-01-08 10:00:00Z]
    snapshot = Operation.project(overview, now)
    assert snapshot.arrivals == overview.arrivals
    assert snapshot.departures == 1
    assert snapshot.occupancy == overview.occupancy
    assert snapshot.portions["breakfast"].total == 15
    # Preserve the kitchen source's inclusion of completed, non-cancelled stays.
    assert snapshot.portions["dinner"].total == 30
    assert snapshot.portions == Map.take(overview.portions, ["breakfast", "lunch", "dinner"])
    assert snapshot.incomplete == 1

    assert %{
             booking_id: unknown.id,
             on: today,
             kind: :details,
             reason: "Doplnit údaje o stravování"
           } in snapshot.issues

    assert Enum.any?(snapshot.issues, &(&1.booking_id == arriving.id and &1.kind == :menu))
    assert Enum.any?(snapshot.issues, &(&1.booking_id == leaving.id))
    refute inspect(snapshot) =~ "Skupina"
    refute Map.has_key?(snapshot, :bookings)
    refute Map.has_key?(snapshot.portions, :incomplete_bookings)
    refute Operation.stale?(snapshot, DateTime.add(now, 899))
    assert Operation.stale?(snapshot, DateTime.add(now, 900))
    assert Operation.stale?(snapshot, ~U[2027-01-08 23:00:00Z])
  end

  test "shared source is read only and bounded by 15 SELECTs for small and many populated stays" do
    today = Operation.today()
    variant = variant_fixture()
    room = Repo.insert!(%CozyCheckout.Rooms.Room{room_number: "4A", capacity: 4})
    booking = menu_booking_fixture(%{check_in_date: today, check_out_date: Date.add(today, 2)})
    Repo.insert!(%CozyCheckout.Bookings.BookingRoom{booking_id: booking.id, room_id: room.id})
    assign_variant(booking, variant)
    small = queries(fn -> assert {:ok, _} = Operation.load() end)

    for _ <- 1..20 do
      booking = menu_booking_fixture(%{check_in_date: today, check_out_date: Date.add(today, 2)})
      Repo.insert!(%CozyCheckout.Bookings.BookingRoom{booking_id: booking.id, room_id: room.id})
      assign_variant(booking, variant)
    end

    many = queries(fn -> assert {:ok, _} = Operation.load() end)
    assert length(small) > 0
    assert length(small) <= 15
    assert length(many) == length(small)
    assert Enum.all?(small ++ many, &String.starts_with?(&1, "SELECT"))
  end

  test "disabled source performs no SQL, including clock lookups" do
    adventure_booking()
    Application.put_env(:cozy_checkout, :adventure_enabled, false)
    assert queries(fn -> assert {:error, :disabled} = Operation.load() end) == []
  end

  defp queries(fun) do
    table = :ets.new(:operation_queries, [:public, :ordered_set])
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:cozy_checkout, :repo, :query],
        &__MODULE__.record_query/4,
        table
      )

    try do
      fun.()
      :ets.tab2list(table) |> Enum.map(&elem(&1, 1))
    after
      :telemetry.detach(handler)
      :ets.delete(table)
    end
  end

  def record_query(_, _, metadata, table) do
    :ets.insert(table, {System.unique_integer([:monotonic]), metadata.query})
  end
end

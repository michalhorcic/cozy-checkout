defmodule CozyCheckout.BarLeaderboardTest do
  use CozyCheckout.DataCase, async: true

  import CozyCheckout.SalesFixtures
  import CozyCheckout.MenuFixtures, only: [menu_booking_fixture: 1]

  alias CozyCheckout.{Repo, Sales}

  test "combines a guest's paid and open accounts for the current stay, excluding tips" do
    booking = active_booking()

    first = account("125.50", booking, %{"tips_amount" => "25", "status" => "paid"})
    second = account("49.50", booking)
    other = account("130", nil)

    assert [winner, runner_up] = Sales.bar_leaderboard()
    assert winner.rank == 1
    assert winner.key == {:guest, booking.id, booking.guest_id}
    assert winner.name == Repo.preload(booking, :guest).guest.name
    assert Enum.sort(winner.order_ids) == Enum.sort([first.id, second.id])
    assert_amount(winner.total, "150")
    assert runner_up.order_ids == [other.id]
  end

  test "ranks using Decimal and shares medals without rearranging the account list" do
    first = account("99.99", nil, %{"name" => "A"})
    second = account("100.00", nil, %{"name" => "B"})
    third = account("100.0", nil, %{"name" => "C"})
    fourth = account("9", nil, %{"name" => "D"})
    original_ids = Enum.map(Sales.list_open_orders(), & &1.id)

    entries = Sales.bar_leaderboard()
    assert Enum.map(entries, & &1.rank) == [1, 1, 3, 4]
    assert Enum.map(entries, & &1.order_ids) == [[second.id], [third.id], [first.id], [fourth.id]]
    assert Enum.map(Sales.list_open_orders(), & &1.id) == original_ids
  end

  test "excludes service, cancelled, deleted, zero and closed standalone accounts" do
    account("0", nil)
    account("300", nil, %{"is_service_order" => true})
    account("300", nil, %{"status" => "cancelled"})
    account("300", nil, %{"status" => "paid"})
    deleted = account("300", nil)
    Repo.update!(Ecto.Changeset.change(deleted, deleted_at: DateTime.utc_now(:second)))

    active = account("20", nil, %{"status" => "partially_paid"})
    assert [%{order_ids: [id]}] = Sales.bar_leaderboard()
    assert id == active.id
  end

  test "excludes past, future, completed and deleted stays" do
    for attrs <- [
          %{
            check_in_date: Date.add(Date.utc_today(), -3),
            check_out_date: Date.add(Date.utc_today(), -1)
          },
          %{
            check_in_date: Date.add(Date.utc_today(), 1),
            check_out_date: Date.add(Date.utc_today(), 2)
          },
          %{status: "completed"}
        ] do
      account("100", active_booking(attrs))
    end

    deleted = active_booking()
    account("100", deleted)
    Repo.update!(Ecto.Changeset.change(deleted, deleted_at: DateTime.utc_now(:second)))
    assert Sales.bar_leaderboard() == []
  end

  test "different guests on the same booking compete separately" do
    booking = active_booking()
    {:ok, guest} = CozyCheckout.Guests.create_guest(%{name: "Second guest"})
    account("100", booking)
    second = account("200", booking, %{"guest_id" => guest.id})

    assert [winner, _] = Sales.bar_leaderboard()
    assert winner.order_ids == [second.id]
    assert winner.name == guest.name
    assert_amount(winner.total, "200")
  end

  defp active_booking(attrs \\ %{}) do
    menu_booking_fixture(
      Map.merge(
        %{
          status: "active",
          check_in_date: Date.utc_today(),
          check_out_date: Date.utc_today(),
          first_meal: "breakfast",
          last_meal: "dinner"
        },
        attrs
      )
    )
  end

  defp account(total, booking, attrs \\ %{}) do
    refs =
      if booking, do: %{"guest_id" => booking.guest_id, "booking_id" => booking.id}, else: %{}

    order = order_fixture(Map.merge(refs, attrs))
    order |> Ecto.Changeset.change(total_amount: Decimal.new(total)) |> Repo.update!()
  end
end

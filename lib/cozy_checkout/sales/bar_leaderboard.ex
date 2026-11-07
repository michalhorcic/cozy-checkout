defmodule CozyCheckout.Sales.BarLeaderboard do
  @moduledoc "Ranks personal bar spending without changing the source account order."

  alias CozyCheckout.Sales

  def rank(orders) do
    orders
    |> Enum.group_by(&participant_key/1)
    |> Enum.map(fn {key, accounts} ->
      representative = Enum.min_by(accounts, & &1.id)

      total =
        Enum.reduce(accounts, Decimal.new(0), fn order, total ->
          spending = Decimal.sub(order.total_amount, order.tips_amount || Decimal.new(0))
          Decimal.add(total, Decimal.max(spending, Decimal.new(0)))
        end)

      %{
        key: key,
        name: participant_name(representative),
        order: representative,
        order_ids: Enum.map(accounts, & &1.id),
        total: total
      }
    end)
    |> Enum.filter(&Decimal.positive?(&1.total))
    |> Enum.sort(fn a, b ->
      case Decimal.compare(a.total, b.total) do
        :eq -> {a.name, a.key} <= {b.name, b.key}
        :gt -> true
        :lt -> false
      end
    end)
    |> Enum.with_index(1)
    |> Enum.map_reduce(nil, fn {entry, position}, previous ->
      rank =
        if previous && Decimal.equal?(entry.total, previous.total),
          do: previous.rank,
          else: position

      ranked = Map.put(entry, :rank, rank)
      {ranked, ranked}
    end)
    |> elem(0)
  end

  defp participant_key(%{booking_id: booking_id, guest_id: guest_id})
       when not is_nil(booking_id) and not is_nil(guest_id),
       do: {:guest, booking_id, guest_id}

  defp participant_key(order), do: {:order, order.id}

  defp participant_name(%{booking_id: booking_id, guest: %{name: name}})
       when not is_nil(booking_id),
       do: name

  defp participant_name(order), do: Sales.get_order_display_name(order)
end

defmodule CozyCheckout.Rooms do
  @moduledoc """
  The Rooms context.
  """

  import Ecto.Query, warn: false
  alias CozyCheckout.Repo

  alias CozyCheckout.Rooms.Room

  @doc """
  Returns the list of rooms.
  """
  def list_rooms do
    Room
    |> where([r], is_nil(r.deleted_at))
    |> order_by([r], r.room_number)
    |> Repo.all()
  end

  @doc """
  Gets a single room.
  """
  def get_room!(id) do
    Room
    |> where([r], is_nil(r.deleted_at))
    |> Repo.get!(id)
  end

  @doc """
  Creates a room.
  """
  def create_room(attrs \\ %{}) do
    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a room.
  """
  def update_room(%Room{} = room, attrs) do
    room
    |> Room.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a room (soft delete).
  """
  def delete_room(%Room{} = room) do
    room
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking room changes.
  """
  def change_room(%Room{} = room, attrs \\ %{}) do
    Room.changeset(room, attrs)
  end

  @doc """
  Checks if a room is available for the given date range, excluding a specific booking.
  Returns true if the room is available, false if it's already booked.
  """
  def room_available?(room_id, check_in_date, check_out_date, exclude_booking_id \\ nil) do
    # Build base query
    query =
      from br in CozyCheckout.Bookings.BookingRoom,
        join: b in assoc(br, :booking),
        where: br.room_id == ^room_id,
        where: is_nil(b.deleted_at),
        where: b.status in ["upcoming", "active"]

    # Add date overlap check - handle nil check_out_date
    query =
      if check_out_date do
        # If check_out_date is provided, check for overlap
        from [br, b] in query,
          where:
            b.check_in_date < ^check_out_date and
              (is_nil(b.check_out_date) or b.check_out_date > ^check_in_date)
      else
        # If no check_out_date (open-ended booking), check if check_in conflicts
        from [br, b] in query,
          where: is_nil(b.check_out_date) or b.check_out_date > ^check_in_date
      end

    # Exclude specific booking if provided
    query =
      if exclude_booking_id do
        where(query, [br, b], b.id != ^exclude_booking_id)
      else
        query
      end

    Repo.aggregate(query, :count) == 0
  end

  @doc """
  Gets rooms that are booked for a specific booking.
  """
  def get_booking_rooms(booking_id) do
    from(r in Room,
      join: br in assoc(r, :booking_rooms),
      where: br.booking_id == ^booking_id,
      where: is_nil(r.deleted_at),
      order_by: r.room_number
    )
    |> Repo.all()
  end
end

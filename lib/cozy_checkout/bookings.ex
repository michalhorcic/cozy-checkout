defmodule CozyCheckout.Bookings do
  @moduledoc """
  The Bookings context.
  """

  import Ecto.Query, warn: false
  alias CozyCheckout.Repo

  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Bookings.BookingGuest

  @doc """
  Returns the list of bookings.
  """
  def list_bookings do
    Booking
    |> where([b], is_nil(b.deleted_at))
    |> preload(:guest)
    |> order_by([b], desc: b.check_in_date)
    |> Repo.all()
  end

  @doc """
  Returns the list of active bookings (currently checked in).
  """
  def list_active_bookings do
    today = Date.utc_today()

    Booking
    |> where([b], is_nil(b.deleted_at))
    |> where([b], b.status == "active")
    |> where([b], b.check_in_date <= ^today)
    |> where([b], is_nil(b.check_out_date) or b.check_out_date >= ^today)
    |> preload(:guest)
    |> order_by([b], [b.check_in_date, b.room_number])
    |> Repo.all()
  end

  @doc """
  Returns the list of bookings for a specific guest.
  """
  def list_bookings_for_guest(guest_id) do
    Booking
    |> where([b], is_nil(b.deleted_at))
    |> where([b], b.guest_id == ^guest_id)
    |> order_by([b], desc: b.check_in_date)
    |> Repo.all()
  end

  @doc """
  Gets a single booking.
  """
  def get_booking!(id) do
    Booking
    |> where([b], is_nil(b.deleted_at))
    |> preload([:guest, :orders])
    |> Repo.get!(id)
  end

  @doc """
  Creates a booking.
  Automatically creates a booking_guest record for the primary guest.
  """
  def create_booking(attrs \\ %{}) do
    Repo.transaction(fn ->
      case %Booking{}
           |> Booking.changeset(attrs)
           |> Repo.insert() do
        {:ok, booking} ->
          # Create primary booking_guest record
          %BookingGuest{}
          |> BookingGuest.changeset(%{
            booking_id: booking.id,
            guest_id: booking.guest_id,
            is_primary: true
          })
          |> Repo.insert!()

          booking

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates a booking.
  """
  def update_booking(%Booking{} = booking, attrs) do
    booking
    |> Booking.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a booking (soft delete).
  """
  def delete_booking(%Booking{} = booking) do
    booking
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking booking changes.
  """
  def change_booking(%Booking{} = booking, attrs \\ %{}) do
    Booking.changeset(booking, attrs)
  end

  @doc """
  Updates booking status based on check-in/check-out dates.
  Should be called periodically or when dates change.
  """
  def update_booking_status(%Booking{} = booking) do
    today = Date.utc_today()

    new_status =
      cond do
        booking.status == "cancelled" ->
          "cancelled"

        Date.compare(booking.check_in_date, today) == :gt ->
          "upcoming"

        booking.check_out_date && Date.compare(booking.check_out_date, today) == :lt ->
          "completed"

        true ->
          "active"
      end

    if new_status != booking.status do
      booking
      |> Ecto.Changeset.change(status: new_status)
      |> Repo.update()
    else
      {:ok, booking}
    end
  end

  @doc """
  Returns bookings for a specific month.
  Useful for calendar views.
  """
  def list_bookings_for_month(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)

    Booking
    |> where([b], is_nil(b.deleted_at))
    |> where(
      [b],
      (b.check_in_date >= ^start_date and b.check_in_date <= ^end_date) or
        (b.check_out_date >= ^start_date and b.check_out_date <= ^end_date) or
        (b.check_in_date < ^start_date and
           (is_nil(b.check_out_date) or b.check_out_date > ^end_date))
    )
    |> preload(:guest)
    |> order_by([b], [b.check_in_date, b.guest_id])
    |> Repo.all()
  end

  @doc """
  Returns bookings for a specific date range.
  """
  def list_bookings_for_date_range(start_date, end_date) do
    Booking
    |> where([b], is_nil(b.deleted_at))
    |> where(
      [b],
      (b.check_in_date >= ^start_date and b.check_in_date <= ^end_date) or
        (b.check_out_date >= ^start_date and b.check_out_date <= ^end_date) or
        (b.check_in_date < ^start_date and
           (is_nil(b.check_out_date) or b.check_out_date > ^end_date))
    )
    |> preload(:guest)
    |> order_by([b], [b.check_in_date, b.guest_id])
    |> Repo.all()
  end

  # Booking Guests Management

  @doc """
  Lists all guests for a booking (including primary).
  """
  def list_booking_guests(booking_id) do
    BookingGuest
    |> where([bg], bg.booking_id == ^booking_id)
    |> preload(:guest)
    |> order_by([bg], [desc: bg.is_primary, asc: bg.inserted_at])
    |> Repo.all()
  end

  @doc """
  Adds a guest to a booking.
  """
  def add_guest_to_booking(booking_id, guest_id) do
    %BookingGuest{}
    |> BookingGuest.changeset(%{
      booking_id: booking_id,
      guest_id: guest_id,
      is_primary: false
    })
    |> Repo.insert()
  end

  @doc """
  Removes a non-primary guest from a booking.
  Cannot remove the primary guest.
  """
  def remove_guest_from_booking(booking_guest_id) do
    booking_guest = Repo.get!(BookingGuest, booking_guest_id)

    if booking_guest.is_primary do
      {:error, :cannot_remove_primary_guest}
    else
      Repo.delete(booking_guest)
    end
  end

  @doc """
  Gets a single booking guest.
  """
  def get_booking_guest!(id) do
    BookingGuest
    |> preload(:guest)
    |> Repo.get!(id)
  end
end

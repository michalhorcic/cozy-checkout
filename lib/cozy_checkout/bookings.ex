defmodule CozyCheckout.Bookings do
  @moduledoc """
  The Bookings context.
  """

  import Ecto.Query, warn: false
  alias CozyCheckout.Repo

  alias CozyCheckout.Bookings.Booking
  alias CozyCheckout.Bookings.BookingGuest
  alias CozyCheckout.Bookings.BookingRoom
  alias CozyCheckout.Bookings.BookingInvoice
  alias CozyCheckout.Bookings.BookingInvoiceItem
  alias CozyCheckout.Rooms

  @cottage_capacity 45

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
  Gets a booking guest.
  """
  def get_booking_guest!(id) do
    BookingGuest
    |> preload(:guest)
    |> Repo.get!(id)
  end

  # Booking Rooms Management

  @doc """
  Lists all rooms for a booking.
  """
  def list_booking_rooms(booking_id) do
    Rooms.get_booking_rooms(booking_id)
  end

  @doc """
  Adds a room to a booking with validation to prevent double-booking.
  """
  def add_room_to_booking(booking_id, room_id) do
    booking = get_booking!(booking_id)

    # Check if room is available for this booking's dates
    check_out_date = booking.check_out_date || Date.add(booking.check_in_date, 365)

    if Rooms.room_available?(room_id, booking.check_in_date, check_out_date, booking_id) do
      %BookingRoom{}
      |> BookingRoom.changeset(%{
        booking_id: booking_id,
        room_id: room_id
      })
      |> Repo.insert()
    else
      {:error, :room_not_available}
    end
  end

  @doc """
  Removes a room from a booking.
  """
  def remove_room_from_booking(booking_id, room_id) do
    case Repo.get_by(BookingRoom, booking_id: booking_id, room_id: room_id) do
      nil -> {:error, :not_found}
      booking_room -> Repo.delete(booking_room)
    end
  end

  @doc """
  Sets rooms for a booking (replaces existing rooms).
  Validates that all rooms are available for the booking dates.
  """
  def set_booking_rooms(booking_id, room_ids) do
    booking = get_booking!(booking_id)
    check_out_date = booking.check_out_date || Date.add(booking.check_in_date, 365)

    # Validate all rooms are available
    unavailable_rooms =
      Enum.reject(room_ids, fn room_id ->
        Rooms.room_available?(room_id, booking.check_in_date, check_out_date, booking_id)
      end)

    if Enum.empty?(unavailable_rooms) do
      Repo.transaction(fn ->
        # Remove existing room associations
        from(br in BookingRoom, where: br.booking_id == ^booking_id)
        |> Repo.delete_all()

        # Add new room associations
        Enum.each(room_ids, fn room_id ->
          %BookingRoom{}
          |> BookingRoom.changeset(%{
            booking_id: booking_id,
            room_id: room_id
          })
          |> Repo.insert!()
        end)

        :ok
      end)
    else
      {:error, {:rooms_not_available, unavailable_rooms}}
    end
  end

  # Booking Invoice Management

  @doc """
  Gets the invoice for a booking with preloaded items.
  """
  def get_invoice_by_booking_id(booking_id) do
    items_query = from(i in BookingInvoiceItem, order_by: i.position)

    BookingInvoice
    |> where([i], i.booking_id == ^booking_id)
    |> preload(items: ^items_query)
    |> Repo.one()
  end

  @doc """
  Gets a booking invoice by ID with preloaded items.
  """
  def get_booking_invoice!(id) do
    items_query = from(i in BookingInvoiceItem, order_by: i.position)

    BookingInvoice
    |> preload(items: ^items_query)
    |> Repo.get!(id)
  end

  @doc """
  Creates a default invoice for a booking with default line items.
  """
  def create_default_invoice(%Booking{} = booking) do
    Repo.transaction(fn ->
      # Create invoice header
      invoice = %BookingInvoice{}
        |> BookingInvoice.changeset(%{booking_id: booking.id})
        |> Repo.insert!()

      # Create default line items
      default_items = [
        %{name: "Dospělí", quantity: 2, price_per_night: Decimal.new("980.00"), vat_rate: Decimal.new("0"), position: 1, booking_invoice_id: invoice.id, item_type: "person"},
        %{name: "Děti do 2 let", quantity: 0, price_per_night: Decimal.new("210.00"), vat_rate: Decimal.new("0"), position: 2, booking_invoice_id: invoice.id, item_type: "person"},
        %{name: "Děti do 12 let", quantity: 0, price_per_night: Decimal.new("880.00"), vat_rate: Decimal.new("0"), position: 3, booking_invoice_id: invoice.id, item_type: "person"}
      ]

      Enum.each(default_items, fn item_attrs ->
        %BookingInvoiceItem{}
        |> BookingInvoiceItem.changeset(item_attrs)
        |> Repo.insert!()
      end)

      # Reload with items
      get_booking_invoice!(invoice.id)
    end)
  end

  @doc """
  Updates a booking invoice header.
  """
  def update_booking_invoice(%BookingInvoice{} = invoice, attrs) do
    invoice
    |> BookingInvoice.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a booking invoice and all its items.
  """
  def delete_booking_invoice(%BookingInvoice{} = invoice) do
    Repo.delete(invoice)
  end

  @doc """
  Creates a new invoice item.
  """
  def create_invoice_item(invoice_id, attrs) do
    attrs = Map.put(attrs, "booking_invoice_id", invoice_id)

    %BookingInvoiceItem{}
    |> BookingInvoiceItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an invoice item.
  """
  def update_invoice_item(%BookingInvoiceItem{} = item, attrs) do
    item
    |> BookingInvoiceItem.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an invoice item.
  """
  def delete_invoice_item(%BookingInvoiceItem{} = item) do
    Repo.delete(item)
  end

  @doc """
  Gets an invoice item by ID.
  """
  def get_invoice_item!(id) do
    Repo.get!(BookingInvoiceItem, id)
  end

  @doc """
  Recalculates and updates the cached totals for all invoice items and the invoice header.
  """
  def recalculate_invoice_totals(%BookingInvoice{} = invoice) do
    Repo.transaction(fn ->
      booking = get_booking!(invoice.booking_id)
      nights = BookingInvoice.calculate_nights(booking)

      # Reload invoice with items
      invoice = get_booking_invoice!(invoice.id)

      # Recalculate each item
      updated_items = Enum.map(invoice.items, fn item ->
        totals = BookingInvoiceItem.calculate_totals(item, nights)

        {:ok, updated_item} = item
          |> BookingInvoiceItem.changeset(totals)
          |> Repo.update()

        updated_item
      end)

      # Calculate invoice totals from items
      invoice_subtotal = updated_items
        |> Enum.map(& &1.subtotal)
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

      invoice_vat_amount = updated_items
        |> Enum.map(& &1.vat_amount)
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

      invoice_total = updated_items
        |> Enum.map(& &1.total)
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

      # Update invoice header with totals
      {:ok, updated_invoice} = invoice
        |> BookingInvoice.changeset(%{
          subtotal: invoice_subtotal,
          vat_amount: invoice_vat_amount,
          total_price: invoice_total
        })
        |> Repo.update()

      # Reload with updated items
      get_booking_invoice!(updated_invoice.id)
    end)
  end

  @doc """
  Generates an invoice number and marks the invoice as generated.
  Format: INV-YYYYMMDD-NNNN (e.g., INV-20251022-0001)
  """
  def generate_invoice_number(%BookingInvoice{} = invoice) do
    today = Date.utc_today()
    date_prefix = "INV-#{Date.to_iso8601(today, :basic)}"

    # Find the highest invoice number for today
    last_invoice =
      from(i in BookingInvoice,
        where: fragment("? LIKE ?", i.invoice_number, ^"#{date_prefix}%"),
        order_by: [desc: i.invoice_number],
        limit: 1
      )
      |> Repo.one()

    next_number = case last_invoice do
      nil -> 1
      %{invoice_number: number} ->
        # Extract NNNN part and increment
        number
        |> String.split("-")
        |> List.last()
        |> String.to_integer()
        |> Kernel.+(1)
    end

    invoice_number = "#{date_prefix}-#{String.pad_leading(Integer.to_string(next_number), 4, "0")}"

    # Recalculate totals before generating
    {:ok, invoice} = recalculate_invoice_totals(invoice)

    invoice
    |> BookingInvoice.changeset(%{
      invoice_number: invoice_number,
      invoice_generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking invoice changes.
  """
  def change_booking_invoice(%BookingInvoice{} = invoice, attrs \\ %{}) do
    BookingInvoice.changeset(invoice, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking invoice item changes.
  """
  def change_invoice_item(%BookingInvoiceItem{} = item, attrs \\ %{}) do
    BookingInvoiceItem.changeset(item, attrs)
  end

  # Occupancy Tracking

  @doc """
  Returns the cottage capacity limit.
  """
  def cottage_capacity, do: @cottage_capacity

  @doc """
  Returns the total number of people booked for a specific date.
  Only counts invoice items with item_type == "person".
  """
  def get_occupancy_for_date(date) do
    from(b in Booking,
      join: bi in BookingInvoice, on: bi.booking_id == b.id,
      join: bii in BookingInvoiceItem, on: bii.booking_invoice_id == bi.id,
      where: b.status in ["upcoming", "active"],
      where: b.check_in_date <= ^date,
      where: is_nil(b.check_out_date) or b.check_out_date > ^date,
      where: bii.item_type == "person",
      select: sum(bii.quantity)
    )
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  @doc """
  Returns daily occupancy for a date range (for calendar view).
  Returns a map: %{~D[2025-10-22] => 12, ~D[2025-10-23] => 15, ...}
  Only counts invoice items with item_type == "person".
  """
  def get_occupancy_for_range(start_date, end_date) do
    # Get all bookings that overlap with the date range
    bookings =
      from(b in Booking,
        join: bi in BookingInvoice, on: bi.booking_id == b.id,
        join: bii in BookingInvoiceItem, on: bii.booking_invoice_id == bi.id,
        where: b.status in ["upcoming", "active"],
        where: b.check_in_date <= ^end_date,
        where: is_nil(b.check_out_date) or b.check_out_date > ^start_date,
        where: bii.item_type == "person",
        select: %{
          check_in: b.check_in_date,
          check_out: b.check_out_date,
          quantity: bii.quantity
        }
      )
      |> Repo.all()

    # Calculate occupancy for each day
    Date.range(start_date, end_date)
    |> Enum.map(fn date ->
      count =
        bookings
        |> Enum.filter(fn b ->
          Date.compare(b.check_in, date) != :gt and
            (is_nil(b.check_out) or Date.compare(b.check_out, date) == :gt)
        end)
        |> Enum.map(& &1.quantity)
        |> Enum.sum()

      {date, count}
    end)
    |> Map.new()
  end

  @doc """
  Returns the occupancy level for display purposes.
  Returns: :low (0-29), :medium (30-39), :high (40-44), :full (45+)
  """
  def occupancy_level(count) do
    cond do
      count >= @cottage_capacity -> :full
      count >= 40 -> :high
      count >= 30 -> :medium
      true -> :low
    end
  end
end

defmodule CozyCheckoutWeb.PosLive.OrderSelection do
  use CozyCheckoutWeb, :live_view

  import Ecto.Query

  alias CozyCheckout.{Sales, Bookings, Repo}

  @impl true
  def mount(%{"booking_id" => booking_id}, _session, socket) do
    booking = Bookings.get_booking!(booking_id)

    orders =
      CozyCheckout.Sales.Order
      |> where([o], o.booking_id == ^booking_id)
      |> where([o], is_nil(o.deleted_at))
      |> where([o], o.status in ["open", "partially_paid"])
      |> preload([:guest, booking: :guest, order_items: [], payments: []])
      |> order_by([o], desc: o.inserted_at)
      |> Repo.all()

    # Get all booking guests to show count
    all_booking_guests = Bookings.list_booking_guests(booking_id)

    {:ok,
     socket
     |> assign(:page_title, "Select Order")
     |> assign(:booking, booking)
     |> assign(:orders, orders)
     |> assign(:show_guest_modal, false)
     |> assign(:booking_guests, [])
     |> assign(:total_guests, length(all_booking_guests))}
  end

  @impl true
  def handle_event("select_order", %{"order-id" => order_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/pos/orders/#{order_id}")}
  end

  @impl true
  def handle_event("back", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/pos")}
  end

  @impl true
  def handle_event("create_new", _params, socket) do
    booking = socket.assigns.booking
    existing_orders = socket.assigns.orders

    # Get all guests for this booking
    all_booking_guests = Bookings.list_booking_guests(booking.id)

    # Get guest IDs that already have orders
    existing_guest_ids =
      existing_orders
      |> Enum.map(& &1.guest_id)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    # Filter out guests who already have orders
    available_guests =
      Enum.reject(all_booking_guests, fn bg ->
        MapSet.member?(existing_guest_ids, bg.guest_id)
      end)

    case available_guests do
      [] ->
        # All guests already have orders
        {:noreply,
         socket
         |> put_flash(:error, "All guests already have orders. Select an existing order or add more guests to the booking.")
         |> assign(:show_guest_modal, false)}

      [single_guest] ->
        # Only one guest available - auto-create order
        {:ok, order} = Sales.create_booking_order_for_guest(booking.id, single_guest.guest_id)
        {:noreply, push_navigate(socket, to: ~p"/pos/orders/#{order.id}")}

      multiple_guests when length(multiple_guests) > 1 ->
        # Multiple guests available - show selection modal
        {:noreply,
         socket
         |> assign(:show_guest_modal, true)
         |> assign(:booking_guests, multiple_guests)}
    end
  end

  @impl true
  def handle_event("hide_guest_modal", _params, socket) do
    {:noreply, assign(socket, show_guest_modal: false)}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    # This event handler prevents the modal from closing when clicking inside
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_guest", %{"guest-id" => guest_id}, socket) do
    booking = socket.assigns.booking

    {:ok, order} = Sales.create_booking_order_for_guest(booking.id, guest_id)

    # Reload orders to show the new one
    orders =
      CozyCheckout.Sales.Order
      |> where([o], o.booking_id == ^booking.id)
      |> where([o], is_nil(o.deleted_at))
      |> where([o], o.status in ["open", "partially_paid"])
      |> preload([:guest, booking: :guest, order_items: [], payments: []])
      |> order_by([o], desc: o.inserted_at)
      |> Repo.all()

    {:noreply,
     socket
     |> assign(:show_guest_modal, false)
     |> assign(:orders, orders)
     |> put_flash(:info, "Order created for #{order.guest.name}")
     |> push_navigate(to: ~p"/pos/orders/#{order.id}")}
  end
end

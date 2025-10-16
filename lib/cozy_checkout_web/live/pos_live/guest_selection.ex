defmodule CozyCheckoutWeb.PosLive.GuestSelection do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:page_title, "Select Booking")
       |> load_bookings()}
    else
      {:ok, assign(socket, page_title: "Select Booking", bookings: [])}
    end
  end

  @impl true
  def handle_event("select_booking", %{"booking-id" => booking_id}, socket) do
    case Sales.get_or_create_booking_order(booking_id) do
      {:ok, order} ->
        {:noreply, push_navigate(socket, to: ~p"/pos/orders/#{order.id}")}

      {:multiple, _orders} ->
        {:noreply, push_navigate(socket, to: ~p"/pos/bookings/#{booking_id}/orders")}
    end
  end

  defp load_bookings(socket) do
    bookings = Sales.list_active_bookings_with_orders()
    assign(socket, :bookings, bookings)
  end
end

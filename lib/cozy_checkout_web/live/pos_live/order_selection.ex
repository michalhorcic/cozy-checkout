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
      |> preload([booking: :guest, order_items: [], payments: []])
      |> order_by([o], desc: o.inserted_at)
      |> Repo.all()

    {:ok,
     socket
     |> assign(:page_title, "Select Order")
     |> assign(:booking, booking)
     |> assign(:orders, orders)}
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

    {:ok, order} =
      Sales.create_order(%{
        "booking_id" => booking.id,
        "guest_id" => booking.guest_id,
        "status" => "open"
      })

    {:noreply, push_navigate(socket, to: ~p"/pos/orders/#{order.id}")}
  end
end

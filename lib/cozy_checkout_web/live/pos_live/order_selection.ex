defmodule CozyCheckoutWeb.PosLive.OrderSelection do
  use CozyCheckoutWeb, :live_view

  import Ecto.Query

  alias CozyCheckout.{Sales, Guests, Repo}

  @impl true
  def mount(%{"guest_id" => guest_id}, _session, socket) do
    guest = Guests.get_guest!(guest_id)

    orders =
      CozyCheckout.Sales.Order
      |> where([o], o.guest_id == ^guest_id)
      |> where([o], is_nil(o.deleted_at))
      |> where([o], o.status in ["open", "partially_paid"])
      |> preload([:guest, :order_items, :payments])
      |> order_by([o], desc: o.inserted_at)
      |> Repo.all()

    {:ok,
     socket
     |> assign(:page_title, "Select Order")
     |> assign(:guest, guest)
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
    {:ok, order} = Sales.create_order(%{"guest_id" => socket.assigns.guest.id, "status" => "open"})
    {:noreply, push_navigate(socket, to: ~p"/pos/orders/#{order.id}")}
  end
end

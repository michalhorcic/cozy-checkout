defmodule CozyCheckoutWeb.PosLive.GuestSelection do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:page_title, "Select Guest")
       |> load_guests()}
    else
      {:ok, assign(socket, page_title: "Select Guest", guests: [])}
    end
  end

  @impl true
  def handle_event("select_guest", %{"guest-id" => guest_id}, socket) do
    case Sales.get_or_create_guest_order(guest_id) do
      {:ok, order} ->
        {:noreply, push_navigate(socket, to: ~p"/pos/orders/#{order.id}")}

      {:multiple, _orders} ->
        {:noreply, push_navigate(socket, to: ~p"/pos/guests/#{guest_id}/orders")}
    end
  end

  defp load_guests(socket) do
    guests = Sales.list_active_guests_with_orders()
    assign(socket, :guests, guests)
  end
end

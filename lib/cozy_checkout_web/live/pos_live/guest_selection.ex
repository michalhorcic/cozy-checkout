defmodule CozyCheckoutWeb.PosLive.GuestSelection do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Sales

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:page_title, "Select Booking")
       |> assign(:show_quick_order_modal, false)
       |> assign(:quick_order_name, "")
       |> assign(:service_mode, false)
       |> load_bookings()
       |> load_standalone_orders()}
    else
      {:ok,
       assign(socket,
         page_title: "Select Booking",
         bookings: [],
         standalone_orders: [],
         show_quick_order_modal: false,
         quick_order_name: "",
         service_mode: false
       )}
    end
  end

  @impl true
  def handle_event("select_booking", %{"booking-id" => booking_id}, socket) do
    service_mode = socket.assigns.service_mode

    case Sales.get_or_create_booking_order(booking_id, service_mode) do
      {:ok, order} ->
        # Single guest, single order - go directly to order
        {:noreply, push_navigate(socket, to: ~p"/pos/orders/#{order.id}")}

      {:needs_guest_selection, _guests} ->
        # Multiple guests but no orders - go to order selection to show guest modal
        {:noreply,
         push_navigate(socket,
           to: ~p"/pos/bookings/#{booking_id}/orders?service_mode=#{service_mode}"
         )}

      {:multiple, _orders} ->
        # Multiple orders exist - go to order selection
        {:noreply,
         push_navigate(socket,
           to: ~p"/pos/bookings/#{booking_id}/orders?service_mode=#{service_mode}"
         )}
    end
  end

  @impl true
  def handle_event("select_order", %{"order-id" => order_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/pos/orders/#{order_id}")}
  end

  @impl true
  def handle_event("show_quick_order_modal", _params, socket) do
    {:noreply, assign(socket, show_quick_order_modal: true, quick_order_name: "")}
  end

  @impl true
  def handle_event("hide_quick_order_modal", _params, socket) do
    {:noreply, assign(socket, show_quick_order_modal: false)}
  end

  @impl true
  def handle_event("update_quick_order_name", params, socket) do
    # Handle both %{"value" => name} and other param formats from phx-keyup
    name = params["value"] || ""
    {:noreply, assign(socket, quick_order_name: name)}
  end

  @impl true
  def handle_event("create_quick_order", _params, socket) do
    order_name = String.trim(socket.assigns.quick_order_name)
    service_mode = socket.assigns.service_mode

    if order_name == "" do
      {:noreply, put_flash(socket, :error, "Order name cannot be empty")}
    else
      case Sales.create_standalone_order(%{
             "name" => order_name,
             "status" => "open",
             "is_service_order" => service_mode
           }) do
        {:ok, order} ->
          {:noreply,
           socket
           |> put_flash(:info, "Order created successfully")
           |> push_navigate(to: ~p"/pos/orders/#{order.id}")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to create order")}
      end
    end
  end

  @impl true
  def handle_event("toggle_service_mode", _params, socket) do
    new_mode = !socket.assigns.service_mode

    {:noreply,
     socket
     |> assign(:service_mode, new_mode)
     |> load_standalone_orders()}
  end

  defp load_bookings(socket) do
    bookings = Sales.list_active_bookings_with_orders()
    assign(socket, :bookings, bookings)
  end

  defp load_standalone_orders(socket) do
    import Ecto.Query
    alias CozyCheckout.Repo
    alias CozyCheckout.Sales.Order

    service_mode = socket.assigns[:service_mode] || false

    standalone_orders =
      Order
      |> where([o], is_nil(o.booking_id))
      |> where([o], is_nil(o.deleted_at))
      |> where([o], o.status in ["open", "partially_paid"])
      |> where([o], o.is_service_order == ^service_mode)
      |> order_by([o], asc: o.name)
      |> Repo.all()

    assign(socket, :standalone_orders, standalone_orders)
  end
end

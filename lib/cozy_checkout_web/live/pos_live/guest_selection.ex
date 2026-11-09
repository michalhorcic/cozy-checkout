defmodule CozyCheckoutWeb.PosLive.GuestSelection do
  use CozyCheckoutWeb, :live_view

  import CozyCheckoutWeb.BarLeaderboardComponents

  alias CozyCheckout.Sales
  alias CozyCheckout.Sales.AccountStamps

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:page_title, "Samoobslužný bar")
       |> assign(:show_quick_order_modal, false)
       |> assign(:quick_order_name, "")
       |> assign(:quick_order_stamp, nil)
       |> assign(:service_mode, false)
       |> load_orders()}
    else
      {:ok,
       assign(socket,
         page_title: "Samoobslužný bar",
         orders: [],
         leaderboard: [],
         bar_badges: %{},
         show_quick_order_modal: false,
         quick_order_name: "",
         quick_order_stamp: nil,
         service_mode: false
       )}
    end
  end

  @impl true
  def handle_event("select_order", %{"order-id" => order_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/pos/orders/#{order_id}")}
  end

  @impl true
  def handle_event("show_quick_order_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_quick_order_modal: true,
       quick_order_name: "",
       quick_order_stamp: Sales.suggest_account_stamp()
     )}
  end

  @impl true
  def handle_event("select_account_stamp", %{"account_stamp" => stamp}, socket) do
    if stamp in AccountStamps.keys() do
      {:noreply, assign(socket, :quick_order_stamp, stamp)}
    else
      {:noreply, socket}
    end
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
      {:noreply, put_flash(socket, :error, "Vyplňte název účtu.")}
    else
      case Sales.create_standalone_order(%{
             "name" => order_name,
             "account_stamp" => socket.assigns.quick_order_stamp,
             "status" => "open",
             "is_service_order" => service_mode
           }) do
        {:ok, order} ->
          {:noreply,
           socket
           |> put_flash(:info, "Účet byl založen.")
           |> push_navigate(to: ~p"/pos/orders/#{order.id}")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Účet se nepodařilo založit.")}
      end
    end
  end

  @impl true
  def handle_event("toggle_service_mode", _params, socket) do
    new_mode = !socket.assigns.service_mode

    {:noreply,
     socket
     |> assign(:service_mode, new_mode)
     |> load_orders()}
  end

  defp load_orders(socket) do
    leaderboard = if socket.assigns.service_mode, do: [], else: Sales.bar_leaderboard()

    badges =
      for entry <- leaderboard, order_id <- entry.order_ids, into: %{}, do: {order_id, entry}

    assign(socket,
      orders: Sales.list_open_orders(socket.assigns.service_mode),
      leaderboard: leaderboard,
      bar_badges: badges
    )
  end
end

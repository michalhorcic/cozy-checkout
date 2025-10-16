defmodule CozyCheckoutWeb.PohodaExportLive.Index do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Pohoda
  alias CozyCheckout.Sales

  import CozyCheckoutWeb.CurrencyHelper

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    first_day_of_month = Date.beginning_of_month(today)

    {:ok,
     socket
     |> assign(:page_title, "POHODA Export")
     |> assign(:date_from, first_day_of_month)
     |> assign(:date_to, today)
     |> assign(:orders, [])
     |> assign(:selected_orders, MapSet.new())
     |> load_orders()}
  end

  @impl true
  def handle_event("load_orders", %{"date_from" => from, "date_to" => to}, socket) do
    with {:ok, date_from} <- Date.from_iso8601(from),
         {:ok, date_to} <- Date.from_iso8601(to) do
      {:noreply,
       socket
       |> assign(:date_from, date_from)
       |> assign(:date_to, date_to)
       |> assign(:selected_orders, MapSet.new())
       |> load_orders()}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid date format")}
    end
  end

  def handle_event("toggle_order", %{"order-id" => order_id}, socket) do
    selected = socket.assigns.selected_orders

    new_selected =
      if MapSet.member?(selected, order_id) do
        MapSet.delete(selected, order_id)
      else
        MapSet.put(selected, order_id)
      end

    {:noreply, assign(socket, :selected_orders, new_selected)}
  end

  def handle_event("select_all", _params, socket) do
    all_order_ids = Enum.map(socket.assigns.orders, & &1.id)
    {:noreply, assign(socket, :selected_orders, MapSet.new(all_order_ids))}
  end

  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, :selected_orders, MapSet.new())}
  end

  def handle_event("export", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_orders)

    if Enum.empty?(selected_ids) do
      {:noreply, put_flash(socket, :error, "Please select at least one order to export")}
    else
      xml_content = Pohoda.export_orders(selected_ids)
      filename = "pohoda_export_#{Date.to_iso8601(Date.utc_today())}.xml"

      {:noreply,
       socket
       |> put_flash(:info, "Export generated successfully")
       |> push_event("download", %{content: xml_content, filename: filename})}
    end
  end

  defp load_orders(socket) do
    date_from = DateTime.new!(socket.assigns.date_from, ~T[00:00:00])
    date_to = DateTime.new!(socket.assigns.date_to, ~T[23:59:59])

    orders = Sales.list_paid_orders_by_date(date_from, date_to)
    assign(socket, :orders, orders)
  end
end

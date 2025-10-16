defmodule CozyCheckoutWeb.PosLive.OrderManagement do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.{Sales, Catalog}

  @impl true
  def mount(%{"id" => order_id}, _session, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:order_id, order_id)
       |> assign(:selected_category_id, nil)
       |> assign(:show_unit_modal, false)
       |> assign(:selected_product, nil)
       |> load_order()
       |> load_products()
       |> assign(:show_success, false)}
    else
      {:ok,
       socket
       |> assign(:order_id, order_id)
       |> assign(:selected_category_id, nil)
       |> assign(:show_unit_modal, false)
       |> assign(:selected_product, nil)
       |> assign(:order, nil)
       |> assign(:categories, [])
       |> assign(:products, [])
       |> assign(:popular_products, [])
       |> assign(:show_success, false)}
    end
  end

  @impl true
  def handle_event("select_category", %{"category-id" => "all"}, socket) do
    {:noreply, assign(socket, :selected_category_id, nil)}
  end

  @impl true
  def handle_event("select_category", %{"category-id" => category_id}, socket) do
    {:noreply, assign(socket, :selected_category_id, category_id)}
  end

  @impl true
  def handle_event("add_product", %{"product-id" => product_id}, socket) do
    product = Enum.find(socket.assigns.products, &(&1.id == product_id)) ||
              Enum.find(socket.assigns.popular_products, &(&1.id == product_id))

    if product && product.unit do
      # Show modal for unit amount selection
      {:noreply,
       socket
       |> assign(:show_unit_modal, true)
       |> assign(:selected_product, product)}
    else
      # Add directly without unit amount
      add_item_to_order(socket, product_id, nil)
    end
  end

  @impl true
  def handle_event("confirm_unit_amount", %{"unit_amount" => unit_amount}, socket) do
    product_id = socket.assigns.selected_product.id

    socket =
      socket
      |> assign(:show_unit_modal, false)
      |> assign(:selected_product, nil)

    add_item_to_order(socket, product_id, unit_amount)
  end

  @impl true
  def handle_event("cancel_unit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_unit_modal, false)
     |> assign(:selected_product, nil)}
  end

  @impl true
  def handle_event("delete_item", %{"item_id" => item_id}, socket) do
    order_item = Enum.find(socket.assigns.order.order_items, &(&1.id == item_id))

    if order_item do
      {:ok, _} = Sales.delete_order_item(order_item)
      {:ok, _order} = Sales.recalculate_order_total(socket.assigns.order)

      {:noreply, load_order(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("back_to_guests", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/pos")}
  end

  @impl true
  def handle_event("hide_success", _params, socket) do
    {:noreply, assign(socket, :show_success, false)}
  end

  defp add_item_to_order(socket, product_id, unit_amount) do
    attrs = %{
      "order_id" => socket.assigns.order_id,
      "product_id" => product_id,
      "quantity" => "1",
      "unit_amount" => unit_amount
    }

    case Sales.create_order_item(attrs) do
      {:ok, _order_item} ->
        {:ok, _order} = Sales.recalculate_order_total(socket.assigns.order)

        {:noreply,
         socket
         |> load_order()
         |> assign(:show_success, true)
         |> push_event("item-added", %{})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add item")}
    end
  end

  defp load_order(socket) do
    order = Sales.get_order!(socket.assigns.order_id)
    page_title = "Order: #{order.guest.name}"

    socket
    |> assign(:order, order)
    |> assign(:page_title, page_title)
  end

  defp load_products(socket) do
    categories = Catalog.list_categories()
    all_products = Catalog.list_products()
    popular_products = Sales.get_popular_products(20)

    socket
    |> assign(:categories, categories)
    |> assign(:products, all_products)
    |> assign(:popular_products, popular_products)
  end

  defp filter_products(products, nil), do: products

  defp filter_products(products, category_id) do
    Enum.filter(products, fn product ->
      product.category_id == category_id
    end)
  end

  defp parse_default_amounts(nil), do: []
  defp parse_default_amounts(""), do: []

  defp parse_default_amounts(amounts_str) when is_binary(amounts_str) do
    case Jason.decode(amounts_str) do
      {:ok, amounts} when is_list(amounts) -> amounts
      _ -> []
    end
  end

  defp parse_default_amounts(_), do: []
end

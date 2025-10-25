defmodule CozyCheckoutWeb.PosLive.OrderManagement do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.{Sales, Catalog}
  alias CozyCheckout.Payments.QrCode
  alias CozyCheckoutWeb.OrderItemGrouper

  @impl true
  def mount(%{"id" => order_id}, _session, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:order_id, order_id)
       |> assign(:selected_category_id, nil)
       |> assign(:show_unit_modal, false)
       |> assign(:selected_product, nil)
       |> assign(:show_payment_modal, false)
       |> assign(:payment_method, nil)
       |> assign(:payment_qr_svg, nil)
       |> assign(:payment_invoice_number, nil)
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
       |> assign(:show_payment_modal, false)
       |> assign(:payment_method, nil)
       |> assign(:payment_qr_svg, nil)
       |> assign(:payment_invoice_number, nil)
       |> assign(:order, nil)
       |> assign(:grouped_items, [])
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
    product =
      Enum.find(socket.assigns.products, &(&1.id == product_id)) ||
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
  def handle_event("quick_add_unit_amount", %{"unit_amount" => unit_amount}, socket) do
    product_id = socket.assigns.selected_product.id

    socket =
      socket
      |> assign(:show_unit_modal, false)
      |> assign(:selected_product, nil)

    add_item_to_order(socket, product_id, unit_amount)
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
  def handle_event("delete_item", params, socket) do
    item_id = params["item-id"] || params["item_id"]
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
  def handle_event("expand_group", params, socket) do
    product_id = params["product-id"] || params["product_id"]
    unit_amount_str = params["unit-amount"] || params["unit_amount"] || params["value"]

    unit_amount = parse_unit_amount(unit_amount_str)

    grouped_items =
      OrderItemGrouper.expand_group(socket.assigns.grouped_items, product_id, unit_amount)

    {:noreply, assign(socket, :grouped_items, grouped_items)}
  end

  @impl true
  def handle_event("collapse_group", params, socket) do
    product_id = params["product-id"] || params["product_id"]
    unit_amount_str = params["unit-amount"] || params["unit_amount"] || params["value"]

    unit_amount = parse_unit_amount(unit_amount_str)

    grouped_items =
      OrderItemGrouper.collapse_group(socket.assigns.grouped_items, product_id, unit_amount)

    {:noreply, assign(socket, :grouped_items, grouped_items)}
  end

  @impl true
  def handle_event("back_to_guests", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/pos")}
  end

  @impl true
  def handle_event("hide_success", _params, socket) do
    {:noreply, assign(socket, :show_success, false)}
  end

  @impl true
  def handle_event("open_payment_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_payment_modal, true)
     |> assign(:payment_method, nil)
     |> assign(:payment_qr_svg, nil)
     |> assign(:payment_invoice_number, nil)}
  end

  @impl true
  def handle_event("close_payment_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_payment_modal, false)
     |> assign(:payment_method, nil)
     |> assign(:payment_qr_svg, nil)
     |> assign(:payment_invoice_number, nil)}
  end

  @impl true
  def handle_event("select_payment_method", %{"method" => "cash"}, socket) do
    # Create payment directly for cash
    attrs = %{
      "order_id" => socket.assigns.order_id,
      "amount" => Decimal.to_string(socket.assigns.order.total_amount),
      "payment_method" => "cash",
      "payment_date" => Date.utc_today()
    }

    case Sales.create_payment(attrs) do
      {:ok, payment} ->
        {:noreply,
         socket
         |> assign(:show_payment_modal, false)
         |> load_order()
         |> put_flash(:info, "Payment recorded successfully. Invoice: #{payment.invoice_number}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create payment")}
    end
  end

  @impl true
  def handle_event("select_payment_method", %{"method" => "qr_code"}, socket) do
    # Create payment and generate QR code
    attrs = %{
      "order_id" => socket.assigns.order_id,
      "amount" => Decimal.to_string(socket.assigns.order.total_amount),
      "payment_method" => "qr_code",
      "payment_date" => Date.utc_today()
    }

    case Sales.create_payment(attrs) do
      {:ok, payment} ->
        # Generate QR code SVG
        bank_account = Application.get_env(:cozy_checkout, :bank_account, "123456789/0100")

        qr_svg =
          QrCode.generate_qr_svg(%{
            account_number: bank_account,
            amount: payment.amount,
            currency: "CZK",
            variable_symbol: payment.invoice_number,
            message: "Order #{socket.assigns.order.order_number}"
          })

        {:noreply,
         socket
         |> assign(:payment_method, "qr_code")
         |> assign(:payment_qr_svg, qr_svg)
         |> assign(:payment_invoice_number, payment.invoice_number)
         |> load_order()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create payment")}
    end
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

    page_title =
      cond do
        # Standalone order (no booking)
        is_nil(order.booking_id) -> "Order: #{order.name}"
        # Regular order with booking
        order.booking && order.booking.guest -> "Order: #{order.booking.guest.name}"
        # Fallback
        true -> "Order: #{order.name || "Unknown"}"
      end

    grouped_items = OrderItemGrouper.group_order_items(order.order_items)

    socket
    |> assign(:order, order)
    |> assign(:grouped_items, grouped_items)
    |> assign(:page_title, page_title)
  end

  defp load_products(socket) do
    categories = Catalog.list_categories()
    all_products = Catalog.list_products()
    popular_products = Sales.get_popular_products(20)

    # Enrich products with pricing information
    products_with_prices = enrich_products_with_prices(all_products)
    popular_with_prices = enrich_products_with_prices(popular_products)

    socket
    |> assign(:categories, categories)
    |> assign(:products, products_with_prices)
    |> assign(:popular_products, popular_with_prices)
  end

  defp enrich_products_with_prices(products) do
    Enum.map(products, fn product ->
      pricelist = Catalog.get_active_pricelist_for_product(product.id)

      pricing_info = if pricelist do
        cond do
          pricelist.price_tiers && pricelist.price_tiers != [] ->
            %{type: :tiers, tiers: pricelist.price_tiers}
          pricelist.price ->
            %{type: :single, price: pricelist.price}
          true ->
            %{type: :none}
        end
      else
        %{type: :none}
      end

      Map.put(product, :pricing_info, pricing_info)
    end)
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

  defp parse_unit_amount(""), do: nil
  defp parse_unit_amount(nil), do: nil

  defp parse_unit_amount(unit_amount_str) when is_binary(unit_amount_str) do
    case Decimal.parse(unit_amount_str) do
      {amount, _} -> amount
      :error -> nil
    end
  end

  defp parse_unit_amount(_), do: nil

  defp get_price_for_amount(product, amount) do
    if product.pricing_info && product.pricing_info.type == :tiers do
      tier = Enum.find(product.pricing_info.tiers, fn tier ->
        tier_amount = tier["unit_amount"] || tier[:unit_amount]
        tier_amount == amount
      end)

      if tier do
        price = tier["price"] || tier[:price]
        if is_struct(price, Decimal), do: price, else: Decimal.new(to_string(price))
      else
        nil
      end
    else
      product.pricing_info && product.pricing_info.type == :single && product.pricing_info.price
    end
  end
end

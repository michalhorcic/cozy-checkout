defmodule CozyCheckoutWeb.PricelistLive.Management do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Catalog
  alias CozyCheckout.Catalog.Pricelist

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Price Management")
      |> assign(:current_scope, :admin)
      |> assign(:show_add_modal, false)
      |> assign(:selected_product, nil)
      |> assign(:form, nil)
      |> load_pricing_issues()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_add_price_modal", %{"product_id" => product_id}, socket) do
    product = Catalog.get_product!(product_id)

    changeset =
      %Pricelist{
        product_id: product.id,
        valid_from: Date.utc_today(),
        valid_to: Date.add(Date.utc_today(), 365),
        vat_rate: Decimal.new("0"),
        active: true
      }
      |> Catalog.change_pricelist()

    socket =
      socket
      |> assign(:show_add_modal, true)
      |> assign(:selected_product, product)
      |> assign(:form, to_form(changeset))

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_modal, false)
     |> assign(:selected_product, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("save_pricelist", %{"pricelist" => pricelist_params}, socket) do
    product = socket.assigns.selected_product

    # Parse the default_unit_amounts from JSON string
    default_unit_amounts =
      case Jason.decode(product.default_unit_amounts || "[]") do
        {:ok, amounts} when is_list(amounts) -> amounts
        _ -> []
      end

    # Prepare price_tiers based on product configuration
    {attrs, has_errors} =
      if default_unit_amounts != [] do
        price_tiers =
          Enum.map(default_unit_amounts, fn amount ->
            price_key = "price_#{amount}"
            price_value = Map.get(pricelist_params, price_key, "")

            # Convert string to number
            price_number =
              case Float.parse(price_value) do
                {num, _} -> num
                :error -> nil
              end

            %{
              "unit_amount" => amount,
              "price" => price_number
            }
          end)

        # Check if all prices are provided (allow 0 but not empty/nil)
        has_errors = Enum.any?(price_tiers, fn tier -> is_nil(tier["price"]) end)

        # Remove the individual price_X keys and add price_tiers
        attrs =
          pricelist_params
          |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "price_") end)
          |> Map.new()
          |> Map.put("product_id", product.id)
          |> Map.put("price_tiers", price_tiers)

        {attrs, has_errors}
      else
        # Single price product
        attrs =
          pricelist_params
          |> Map.put("product_id", product.id)

        has_errors = !Map.has_key?(pricelist_params, "price") || pricelist_params["price"] == ""
        {attrs, has_errors}
      end

    if has_errors do
      {:noreply,
       socket
       |> put_flash(:error, "Please provide all required prices")
       |> assign(:form, to_form(Catalog.change_pricelist(%Pricelist{}, attrs)))}
    else
      case Catalog.create_pricelist(attrs) do
        {:ok, _pricelist} ->
          socket =
            socket
            |> put_flash(:info, "Price added successfully")
            |> assign(:show_add_modal, false)
            |> assign(:selected_product, nil)
            |> assign(:form, nil)
            |> load_pricing_issues()

          {:noreply, socket}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to save: #{inspect(changeset.errors)}")
           |> assign(:form, to_form(changeset))}
      end
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_pricing_issues(socket)}
  end

  defp load_pricing_issues(socket) do
    issues = Catalog.get_products_with_pricing_issues()

    socket
    |> assign(:no_prices_count, length(issues.no_prices))
    |> assign(:expired_prices_count, length(issues.expired_prices))
    |> assign(:incomplete_tiers_count, length(issues.incomplete_tiers))
    |> assign(:products_no_prices, issues.no_prices)
    |> assign(:products_expired_prices, issues.expired_prices)
    |> assign(:products_incomplete_tiers, issues.incomplete_tiers)
  end

  defp get_missing_tiers(product) do
    # Parse the default_unit_amounts from JSON string
    required_amounts =
      case Jason.decode(product.default_unit_amounts || "[]") do
        {:ok, amounts} when is_list(amounts) -> amounts
        _ -> []
      end

    case product.pricelists do
      [] ->
        required_amounts

      pricelists ->
        # Get all configured amounts from all pricelists
        all_configured_amounts =
          Enum.flat_map(pricelists, fn pricelist ->
            Enum.map(pricelist.price_tiers || [], fn tier ->
              tier["unit_amount"] || tier[:unit_amount]
            end)
          end)
          |> Enum.uniq()

        required_amounts -- all_configured_amounts
    end
  end

  defp get_default_unit_amounts(product) do
    case Jason.decode(product.default_unit_amounts || "[]") do
      {:ok, amounts} when is_list(amounts) -> amounts
      _ -> []
    end
  end

  defp get_last_valid_date(product) do
    case product.pricelists do
      [] ->
        nil

      pricelists ->
        pricelists
        |> Enum.reject(&is_nil(&1.valid_to))
        |> case do
          [] -> nil
          valid_pricelists -> Enum.max_by(valid_pricelists, & &1.valid_to, Date).valid_to
        end
    end
  end
end

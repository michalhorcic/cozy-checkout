defmodule CozyCheckoutWeb.PricelistLive.Printable do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Catalog

  @impl true
  def mount(_params, _session, socket) do
    categories = Catalog.list_categories()
    all_category_ids = Enum.map(categories, & &1.id)

    pricelists_by_category = Catalog.get_active_pricelists_for_print(all_category_ids)

    {:ok,
     socket
     |> assign(:page_title, "Ceník")
     |> assign(:categories, categories)
     |> assign(:selected_category_ids, all_category_ids)
     |> assign(:pricelist_name, "Ceník")
     |> assign(:pricelists_by_category, pricelists_by_category)
     |> assign(:generated_at, Date.utc_today())}
  end

  @impl true
  def handle_event("print", _params, socket) do
    {:noreply, push_event(socket, "print", %{})}
  end

  @impl true
  def handle_event("toggle_category", %{"category-id" => category_id}, socket) do
    # category_id is already a binary_id string from the template
    selected_ids =
      if category_id in socket.assigns.selected_category_ids do
        List.delete(socket.assigns.selected_category_ids, category_id)
      else
        [category_id | socket.assigns.selected_category_ids]
      end

    pricelists_by_category = Catalog.get_active_pricelists_for_print(selected_ids)

    {:noreply,
     socket
     |> assign(:selected_category_ids, selected_ids)
     |> assign(:pricelists_by_category, pricelists_by_category)}
  end

  @impl true
  def handle_event("toggle_all", _params, socket) do
    all_category_ids = Enum.map(socket.assigns.categories, & &1.id)

    selected_ids =
      if length(socket.assigns.selected_category_ids) == length(all_category_ids) do
        []
      else
        all_category_ids
      end

    pricelists_by_category = Catalog.get_active_pricelists_for_print(selected_ids)

    {:noreply,
     socket
     |> assign(:selected_category_ids, selected_ids)
     |> assign(:pricelists_by_category, pricelists_by_category)}
  end

  @impl true
  def handle_event("update_name", %{"pricelist_name" => name}, socket) do
    {:noreply, assign(socket, :pricelist_name, name)}
  end
end

defmodule CozyCheckoutWeb.PricelistLive.Printable do
  use CozyCheckoutWeb, :live_view

  alias CozyCheckout.Catalog

  @impl true
  def mount(_params, _session, socket) do
    pricelists_by_category = Catalog.get_active_pricelists_for_print()

    {:ok,
     socket
     |> assign(:page_title, "Ceník")
     |> assign(:pricelists_by_category, pricelists_by_category)
     |> assign(:generated_at, Date.utc_today())}
  end

  @impl true
  def handle_event("print", _params, socket) do
    {:noreply, push_event(socket, "print", %{})}
  end
end

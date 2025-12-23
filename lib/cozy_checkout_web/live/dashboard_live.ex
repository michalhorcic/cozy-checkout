defmodule CozyCheckoutWeb.DashboardLive do
  use CozyCheckoutWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:expanded_sections, %{
       "catalog" => false,
       "inventory" => false,
       "sales" => false,
       "other" => false
     })}
  end

  def handle_event("toggle_section", %{"section" => section}, socket) do
    expanded = socket.assigns.expanded_sections
    {:noreply, assign(socket, :expanded_sections, Map.update!(expanded, section, &(!&1)))}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      <div class="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
        <%!-- Header --%>
        <div class="flex justify-between items-center mb-8">
          <div>
            <h1 class="text-4xl font-bold text-gray-900 mb-2">Admin Dashboard</h1>
            <p class="text-lg text-gray-600">Jindřichův dům Management</p>
          </div>
          <.link
            navigate={~p"/"}
            class="px-4 py-2 bg-gray-800 text-white rounded-lg hover:bg-gray-700 transition-colors flex items-center gap-2"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
          </.link>
        </div>

        <%!-- Quick Actions (Most Used) --%>
        <div class="mb-8">
          <h2 class="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
            Quick Actions
          </h2>
          <div class="grid grid-cols-2 md:grid-cols-5 gap-4">
            <.quick_action_card
              title="Bookings"
              icon="hero-calendar-days"
              navigate={~p"/admin/bookings"}
            />
            <.quick_action_card
              title="Calendar"
              icon="hero-calendar"
              navigate={~p"/admin/bookings/calendar"}
            />
            <.quick_action_card
              title="Products"
              icon="hero-cube"
              navigate={~p"/admin/products"}
            />
            <.quick_action_card
              title="Pricelists"
              icon="hero-currency-dollar"
              navigate={~p"/admin/pricelists"}
            />
            <.quick_action_card
              title="Meal Planner"
              icon="hero-clipboard-document-list"
              navigate={~p"/admin/meal-planner"}
            />
          </div>
        </div>

        <%!-- Expandable Sections --%>
        <div class="space-y-4">
          <%!-- Catalog Management --%>
          <.expandable_section
            title="Catalog & Pricing"
            section="catalog"
            expanded={@expanded_sections["catalog"]}
            count={5}
          >
            <div class="grid grid-cols-2 md:grid-cols-3 gap-3 pt-4">
              <.compact_card
                title="Categories"
                icon="hero-tag"
                navigate={~p"/admin/categories"}
              />
              <.compact_card
                title="Products"
                icon="hero-cube"
                navigate={~p"/admin/products"}
              />
              <.compact_card
                title="Pricelists"
                icon="hero-currency-dollar"
                navigate={~p"/admin/pricelists"}
              />
              <.compact_card
                title="Price Management"
                icon="hero-chart-bar"
                navigate={~p"/admin/pricelists/management"}
              />
              <.compact_card
                title="Print Pricelist"
                icon="hero-printer"
                navigate={~p"/admin/pricelists/print"}
              />
            </div>
          </.expandable_section>

          <%!-- Inventory --%>
          <.expandable_section
            title="Inventory & Stock"
            section="inventory"
            expanded={@expanded_sections["inventory"]}
            count={4}
          >
            <div class="grid grid-cols-2 md:grid-cols-3 gap-3 pt-4">
              <.compact_card
                title="Purchase Orders"
                icon="hero-archive-box"
                navigate={~p"/admin/purchase_orders"}
              />
              <.compact_card
                title="Stock Overview"
                icon="hero-chart-bar"
                navigate={~p"/admin/stock"}
              />
              <.compact_card
                title="Stock Adjustments"
                icon="hero-adjustments-horizontal"
                navigate={~p"/admin/stock-adjustments"}
              />
              <.compact_card
                title="Inventory Reports"
                icon="hero-chart-pie"
                navigate={~p"/admin/inventory-reports"}
              />
            </div>
          </.expandable_section>

          <%!-- Sales & Payments --%>
          <.expandable_section
            title="Sales & Finance"
            section="sales"
            expanded={@expanded_sections["sales"]}
            count={5}
          >
            <div class="grid grid-cols-2 md:grid-cols-3 gap-3 pt-4">
              <.compact_card title="Orders" icon="hero-shopping-cart" navigate={~p"/admin/orders"} />
              <.compact_card title="Payments" icon="hero-banknotes" navigate={~p"/admin/payments"} />
              <.compact_card title="Economy" icon="hero-chart-pie" navigate={~p"/admin/economy"} />
              <.compact_card
                title="Statistics"
                icon="hero-chart-bar-square"
                navigate={~p"/admin/statistics"}
              />
              <.compact_card
                title="POHODA Export"
                icon="hero-arrow-down-tray"
                navigate={~p"/admin/pohoda-export"}
              />
            </div>
          </.expandable_section>

          <%!-- Other Tools --%>
          <.expandable_section
            title="Guest Management & Tools"
            section="other"
            expanded={@expanded_sections["other"]}
            count={4}
          >
            <div class="grid grid-cols-2 md:grid-cols-3 gap-3 pt-4">
              <.compact_card title="Guests" icon="hero-user-group" navigate={~p"/admin/guests"} />
              <.compact_card title="Rooms" icon="hero-home" navigate={~p"/admin/rooms"} />
              <.compact_card
                title="Bookings"
                icon="hero-calendar-days"
                navigate={~p"/admin/bookings"}
              />
              <.compact_card
                title="Import Bookings"
                icon="hero-arrow-up-tray"
                navigate={~p"/admin/ical-import"}
              />
            </div>
          </.expandable_section>
        </div>
      </div>
    </div>
    """
  end

  # Quick Action Card (Larger, more prominent)
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :navigate, :string, required: true

  defp quick_action_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="group block p-6 bg-white rounded-xl shadow-md hover:shadow-xl transform transition-all duration-200 hover:-translate-y-1 border-2 border-transparent hover:border-blue-500"
    >
      <div class="flex flex-col items-center text-center space-y-3">
        <div class="p-3 rounded-full bg-blue-100 group-hover:bg-blue-200 transition-colors">
          <.icon name={@icon} class="w-8 h-8 text-blue-600" />
        </div>
        <h3 class="text-lg font-bold text-gray-900">{@title}</h3>
      </div>
    </.link>
    """
  end

  # Expandable Section
  attr :title, :string, required: true
  attr :section, :string, required: true
  attr :expanded, :boolean, required: true
  attr :count, :integer, required: true
  slot :inner_block, required: true

  defp expandable_section(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm overflow-hidden">
      <button
        type="button"
        phx-click="toggle_section"
        phx-value-section={@section}
        class="w-full px-6 py-4 flex items-center justify-between hover:bg-gray-50 transition-colors"
      >
        <div class="flex items-center gap-3">
          <h3 class="text-lg font-semibold text-gray-900">{@title}</h3>
          <span class="px-2 py-1 text-xs font-medium bg-gray-100 text-gray-600 rounded-full">
            {@count}
          </span>
        </div>
        <.icon
          name={if @expanded, do: "hero-chevron-up", else: "hero-chevron-down"}
          class="w-5 h-5 text-gray-400"
        />
      </button>

      <div class={["px-6 pb-4", !@expanded && "hidden"]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # Compact Card (For collapsed sections)
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :navigate, :string, required: true

  defp compact_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="group flex items-center gap-3 p-3 bg-gray-50 rounded-lg hover:bg-blue-50 hover:shadow-md transition-all duration-150"
    >
      <div class="p-2 rounded-lg bg-white group-hover:bg-blue-100 transition-colors">
        <.icon name={@icon} class="w-5 h-5 text-gray-600 group-hover:text-blue-600" />
      </div>
      <span class="text-sm font-medium text-gray-900 group-hover:text-blue-700">{@title}</span>
    </.link>
    """
  end
end

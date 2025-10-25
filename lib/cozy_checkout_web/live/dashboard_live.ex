defmodule CozyCheckoutWeb.DashboardLive do
  use CozyCheckoutWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      <div class="max-w-7xl mx-auto px-4 py-12 sm:px-6 lg:px-8">
        <div class="flex justify-between items-center mb-12">
          <div>
            <h1 class="text-5xl font-bold text-gray-900 mb-4">
              Admin Dashboard
            </h1>
            <p class="text-xl text-gray-600">
              Manage your mountain cottage system
            </p>
          </div>
          <.link
            navigate={~p"/"}
            class="px-6 py-3 bg-gray-800 text-white rounded-xl hover:bg-gray-700 transition-colors duration-200 flex items-center gap-2"
          >
            <.icon name="hero-arrow-left" class="w-5 h-5" /> Back to Menu
          </.link>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <%!-- Catalog Management --%>
          <.dashboard_card
            title="Categories"
            description="Manage product categories"
            icon="hero-tag"
            navigate={~p"/admin/categories"}
            color="blue"
          />

          <.dashboard_card
            title="Products"
            description="Manage your bar products"
            icon="hero-cube"
            navigate={~p"/admin/products"}
            color="indigo"
          />

          <.dashboard_card
            title="Pricelists"
            description="Manage product pricing & VAT"
            icon="hero-currency-dollar"
            navigate={~p"/admin/pricelists"}
            color="green"
          />

          <.dashboard_card
            title="Print Pricelist"
            description="Generate printable pricelist"
            icon="hero-printer"
            navigate={~p"/admin/pricelists/print"}
            color="emerald"
          />

          <%!-- Guest Management --%>
          <.dashboard_card
            title="Guests"
            description="Manage guest information"
            icon="hero-user-group"
            navigate={~p"/admin/guests"}
            color="purple"
          />

          <.dashboard_card
            title="Rooms"
            description="Manage cottage rooms"
            icon="hero-home"
            navigate={~p"/admin/rooms"}
            color="cyan"
          />

          <.dashboard_card
            title="Bookings"
            description="Manage guest bookings & stays"
            icon="hero-calendar-days"
            navigate={~p"/admin/bookings"}
            color="rose"
          />

          <.dashboard_card
            title="Calendar"
            description="View bookings calendar"
            icon="hero-calendar"
            navigate={~p"/admin/bookings/calendar"}
            color="pink"
          />

          <%!-- Sales Management --%>
          <.dashboard_card
            title="Orders"
            description="Create and manage orders"
            icon="hero-shopping-cart"
            navigate={~p"/admin/orders"}
            color="orange"
          />

          <.dashboard_card
            title="Payments"
            description="Record and track payments"
            icon="hero-banknotes"
            navigate={~p"/admin/payments"}
            color="teal"
          />

          <%!-- POHODA Export --%>
          <.dashboard_card
            title="POHODA Export"
            description="Export to accounting software"
            icon="hero-arrow-down-tray"
            navigate={~p"/admin/pohoda-export"}
            color="purple"
          />

          <%!-- iCal Import --%>
          <.dashboard_card
            title="Import Bookings"
            description="Import from iCal file"
            icon="hero-arrow-up-tray"
            navigate={~p"/admin/ical-import"}
            color="sky"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, required: true
  attr :navigate, :string, required: true
  attr :color, :string, default: "blue"

  defp dashboard_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "block p-8 bg-white rounded-2xl shadow-lg hover:shadow-2xl",
        "transform transition-all duration-200 hover:-translate-y-1",
        "border-2 border-transparent hover:border-#{@color}-500"
      ]}
    >
      <div class="flex flex-col items-center text-center space-y-4">
        <div class={[
          "p-4 rounded-full",
          "bg-#{@color}-100"
        ]}>
          <.icon name={@icon} class="w-10 h-10 text-gray-700" />
        </div>

        <div>
          <h3 class="text-2xl font-bold text-gray-900 mb-2">
            {@title}
          </h3>
          <p class="text-gray-600">
            {@description}
          </p>
        </div>
      </div>
    </.link>
    """
  end
end

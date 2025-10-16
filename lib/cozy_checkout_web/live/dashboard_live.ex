defmodule CozyCheckoutWeb.DashboardLive do
  use CozyCheckoutWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      <div class="max-w-7xl mx-auto px-4 py-12 sm:px-6 lg:px-8">
        <div class="text-center mb-12">
          <h1 class="text-5xl font-bold text-gray-900 mb-4">
            Cozy Checkout
          </h1>
          <p class="text-xl text-gray-600">
            Mountain Cottage Point of Sale System
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <%!-- Point of Sale --%>
          <.dashboard_card
            title="🍹 POS System"
            description="Touch-friendly bar interface"
            icon="hero-device-tablet"
            navigate={~p"/pos"}
            color="emerald"
          />

          <%!-- Catalog Management --%>
          <.dashboard_card
            title="Categories"
            description="Manage product categories"
            icon="hero-tag"
            navigate={~p"/categories"}
            color="blue"
          />

          <.dashboard_card
            title="Products"
            description="Manage your bar products"
            icon="hero-cube"
            navigate={~p"/products"}
            color="indigo"
          />

          <.dashboard_card
            title="Pricelists"
            description="Manage product pricing & VAT"
            icon="hero-currency-dollar"
            navigate={~p"/pricelists"}
            color="green"
          />

          <%!-- Guest Management --%>
          <.dashboard_card
            title="Guests"
            description="Manage guest information"
            icon="hero-user-group"
            navigate={~p"/guests"}
            color="purple"
          />

          <%!-- Sales Management --%>
          <.dashboard_card
            title="Orders"
            description="Create and manage orders"
            icon="hero-shopping-cart"
            navigate={~p"/orders"}
            color="orange"
          />

          <.dashboard_card
            title="Payments"
            description="Record and track payments"
            icon="hero-banknotes"
            navigate={~p"/payments"}
            color="teal"
          />

          <%!-- POHODA Export --%>
          <.dashboard_card
            title="POHODA Export"
            description="Export to accounting software"
            icon="hero-arrow-down-tray"
            navigate={~p"/pohoda-export"}
            color="purple"
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

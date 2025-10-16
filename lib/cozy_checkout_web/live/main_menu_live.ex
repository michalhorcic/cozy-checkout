defmodule CozyCheckoutWeb.MainMenuLive do
  use CozyCheckoutWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900">
      <div class="max-w-6xl mx-auto px-4 py-16 sm:px-6 lg:px-8">
        <div class="text-center mb-16">
          <h1 class="text-6xl font-bold text-white mb-4 tracking-tight">
            Cozy Checkout
          </h1>
          <p class="text-2xl text-purple-200">
            Mountain Cottage Point of Sale System
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-4xl mx-auto">
          <%!-- POS System Card --%>
          <.link
            navigate={~p"/pos"}
            class={[
              "group relative overflow-hidden",
              "bg-gradient-to-br from-emerald-500 to-teal-600",
              "rounded-3xl shadow-2xl hover:shadow-emerald-500/50",
              "transform transition-all duration-300 hover:scale-105",
              "p-12 text-center"
            ]}
          >
            <div class="relative z-10">
              <div class="mb-6">
                <.icon
                  name="hero-device-tablet"
                  class="w-24 h-24 text-white mx-auto group-hover:scale-110 transition-transform duration-300"
                />
              </div>
              <h2 class="text-4xl font-bold text-white mb-4">
                POS System
              </h2>
              <p class="text-xl text-emerald-50">
                Touch-friendly bar interface for quick orders
              </p>
            </div>
            <div class="absolute inset-0 bg-white opacity-0 group-hover:opacity-10 transition-opacity duration-300">
            </div>
          </.link>

          <%!-- Admin Dashboard Card --%>
          <.link
            navigate={~p"/admin"}
            class={[
              "group relative overflow-hidden",
              "bg-gradient-to-br from-blue-600 to-indigo-700",
              "rounded-3xl shadow-2xl hover:shadow-blue-500/50",
              "transform transition-all duration-300 hover:scale-105",
              "p-12 text-center"
            ]}
          >
            <div class="relative z-10">
              <div class="mb-6">
                <.icon
                  name="hero-computer-desktop"
                  class="w-24 h-24 text-white mx-auto group-hover:scale-110 transition-transform duration-300"
                />
              </div>
              <h2 class="text-4xl font-bold text-white mb-4">
                Admin Dashboard
              </h2>
              <p class="text-xl text-blue-50">
                Manage products, guests, orders & exports
              </p>
            </div>
            <div class="absolute inset-0 bg-white opacity-0 group-hover:opacity-10 transition-opacity duration-300">
            </div>
          </.link>
        </div>
      </div>
    </div>
    """
  end
end

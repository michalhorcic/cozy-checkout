defmodule CozyCheckoutWeb.BookingLive.InvoiceComponent do
  use CozyCheckoutWeb, :live_component
  alias CozyCheckout.Billing

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:balance, Billing.balance(assigns.booking.id))
     |> assign(:documents, Billing.list_documents(%{"booking_id" => assigns.booking.id}))}
  end

  def render(assigns) do
    ~H"""
    <section class="bg-white shadow rounded-xl p-6 space-y-4">
      <h2 class="text-2xl font-bold">Kalkulace a fakturace pobytu</h2>
      <div class="flex flex-wrap gap-6">
        <p><strong>{Billing.payment_state(@balance)}</strong></p>
        <p>
          Cena:
          <strong>{if @balance.total, do: format_currency(@balance.total), else: "Nedoplněná"}</strong>
        </p>
        <p>Přijato po vratkách: <strong>{format_currency(@balance.received)}</strong></p>
        <p :if={@balance.outstanding}>
          Zbývá / přeplatek: <strong>{format_currency(@balance.outstanding)}</strong>
        </p>
      </div>
      <p>{length(@documents)} vystavených dokladů</p>
      <.link navigate={~p"/admin/bookings/#{@booking.id}/billing"} class="btn btn-primary">Otevřít kalkulaci, doklady a platby</.link>
    </section>
    """
  end
end

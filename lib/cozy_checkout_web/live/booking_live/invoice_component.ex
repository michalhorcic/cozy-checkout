defmodule CozyCheckoutWeb.BookingLive.InvoiceComponent do
  use CozyCheckoutWeb, :live_component
  alias CozyCheckout.Billing
  alias CozyCheckout.Billing.Presentation

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:personal?, match?(%{state: "personal"}, Billing.calculation(assigns.booking.id)))
     |> assign(:balance, Billing.balance(assigns.booking.id))
     |> assign(:documents, Billing.list_documents(%{"booking_id" => assigns.booking.id}))}
  end

  def render(assigns) do
    ~H"""
    <section id="booking-billing-summary" class="min-w-0 bg-white shadow rounded-lg p-4 space-y-3">
      <h2 class="text-lg font-bold text-primary-500">Kalkulace a fakturace pobytu</h2>
      <p :if={@personal?} id="booking-personal">Soukromý pobyt · bez finanční evidence</p>
      <div :if={not @personal?} class="grid grid-cols-1 gap-x-4 gap-y-2 text-sm sm:grid-cols-2">
        <p><strong>{Billing.payment_state(@balance)}</strong></p>
        <p>
          Cena:
          <strong>{if @balance.total, do: Presentation.amount(@balance.total), else: "Nedoplněná"}</strong>
        </p>
        <p>Přijato po vratkách: <strong>{Presentation.amount(@balance.received)}</strong></p>
        <p :if={@balance.outstanding}>
          {Presentation.balance_label(@balance.outstanding)}:
          <strong>{Presentation.balance_amount(@balance.outstanding)}</strong>
        </p>
      </div>
      <p :if={not @personal?}>{length(@documents)} vystavených dokladů</p>
      <.link
        navigate={~p"/admin/bookings/#{@booking.id}/billing"}
        class="btn btn-primary h-auto min-h-10 py-2 text-center whitespace-normal"
      >Otevřít kalkulaci, doklady a platby</.link>
    </section>
    """
  end
end

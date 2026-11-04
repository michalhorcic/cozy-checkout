defmodule CozyCheckoutWeb.BookingLive.InvoiceComponent do
  use CozyCheckoutWeb, :live_component
  alias CozyCheckout.Billing.Presentation

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       :summary,
       CozyCheckout.Billing.BookingSummary.for_bookings([assigns.booking.id])[assigns.booking.id]
     )}
  end

  def render(assigns) do
    ~H"""
    <section id="booking-billing-summary" class="min-w-0 bg-white shadow rounded-lg p-4 space-y-3">
      <h2 class="text-lg font-bold text-primary-500">Kalkulace a fakturace pobytu</h2>
      <p :if={@summary.state == "personal"} id="booking-personal">
        Soukromý pobyt · bez finanční evidence
      </p>
      <div :if={@summary.state != "personal"} class="space-y-2 text-sm">
        <p>{CozyCheckout.Billing.BookingSummary.label(@summary.payment_state)}</p>
        <p>
          {@summary.account_count - @summary.final_count} plátci čekají na fakturu · {@summary.paid_count}/{@summary.final_count} faktur uhrazeno
        </p>
        <p :if={@summary.outstanding}>
          Zůstatek dokladů: {Presentation.amount(@summary.outstanding)}
        </p>
        <p :if={is_nil(@booking.allocation_completed_at)}>Rozdělení zatím není dokončeno.</p>
      </div>
      <.link
        navigate={~p"/admin/bookings/#{@booking.id}/billing"}
        class="btn btn-primary h-auto min-h-10 py-2 text-center whitespace-normal"
      >Otevřít kalkulaci, doklady a platby</.link>
    </section>
    """
  end
end

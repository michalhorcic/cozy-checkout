defmodule CozyCheckoutWeb.BillingLive.BankPaymentDialog do
  use CozyCheckoutWeb, :live_component

  alias CozyCheckout.Abra.{Bank, BankPayments}
  alias CozyCheckout.Billing.Presentation
  alias CozyCheckoutWeb.BillingLive.Helpers

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:preview, fn -> nil end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:notice, fn -> nil end)

    {:ok, refresh(socket)}
  end

  def handle_event("check-payment", %{"movement" => movement, "document" => document}, socket) do
    if Enum.any?(socket.assigns.rows, &(&1.movement.id == movement && &1.document.id == document)) do
      case BankPayments.preview(movement, document) do
        {:ok, preview} -> {:noreply, assign(socket, preview: preview, error: nil, notice: nil)}
        {:error, reason} -> {:noreply, assign(socket, :error, Helpers.error(reason))}
      end
    else
      {:noreply, assign(socket, :error, "Návrh již není dostupný. Obnovte přehled.")}
    end
  end

  def handle_event("back", _, socket),
    do: {:noreply, socket |> assign(preview: nil, error: nil) |> refresh()}

  def handle_event("confirm-payment", _, %{assigns: %{preview: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("confirm-payment", _, socket) do
    case BankPayments.confirm(socket.assigns.preview.token) do
      {:ok, _} ->
        send(self(), {__MODULE__, :payment_saved})

        {:noreply,
         socket
         |> assign(
           preview: nil,
           error: nil,
           notice: "Platba uložena. Účetní synchronizace byla zařazena."
         )
         |> refresh()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(preview: nil, error: Helpers.error(reason), notice: nil)
         |> refresh()}
    end
  end

  defp refresh(socket) do
    assign(socket,
      rows: Bank.for_booking(socket.assigns.booking.id),
      bank_import: Bank.status()
    )
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-5">
      <p :if={@error} role="alert" class="rounded-lg bg-error-light p-3 text-sm text-error-dark">
        {@error}
      </p>
      <p :if={@notice} role="status" class="rounded-lg bg-success-light p-3 text-sm text-success-dark">
        {@notice}
      </p>
      <p class="pr-10 text-sm text-primary-400">{@booking.guest.name}</p>
      <%= if @preview do %>
        <CozyCheckoutWeb.BillingComponents.bank_payment_confirmation
          id="booking-bank-payment-modal"
          preview={@preview}
          target={@myself}
          confirm_id="booking-bank-confirm-payment"
        />
        <button type="button" class="btn btn-sm" phx-click="back" phx-target={@myself}>
          Zpět na návrhy plateb
        </button>
      <% else %>
        <h2 id="booking-bank-payment-modal-title" class="pr-10 text-xl font-bold">
          Spárovat platbu z banky
        </h2>
        <p id="booking-bank-payment-modal-description" class="text-sm text-primary-400">
          Vyberte platbu k ověření. Návrh podle VS ještě nepotvrzuje přijetí peněz.
        </p>
        <p
          :if={@bank_import && (@bank_import.scan_id || @bank_import.error)}
          class="text-sm text-warning-dark"
        >
          Poslední načítání banky není dokončené. Návrhy mohou být neaktuální.
        </p>
        <p :if={@rows == []} class="text-sm">Žádné dostupné návrhy plateb pro tuto rezervaci.</p>
        <section
          :for={row <- @rows}
          id={"booking-bank-movement-#{row.movement.id}"}
          class="space-y-3 rounded-xl border border-secondary-200 bg-secondary-50 p-4 text-sm"
        >
          <p class="font-semibold tabular-nums">
            {Presentation.amount(row.movement.amount)} · {Presentation.date(row.movement.paid_on)}
          </p>
          <p>{row.movement.counterparty} · VS {row.movement.variable_symbol}</p>
          <p>Cílový doklad: {row.document.number}</p>
          <p>
            Rozdíl proti {if row.document.kind == "final",
              do: "zbývající úhradě faktury",
              else: "částce výzvy"}: {Presentation.amount(row.difference)}
          </p>
          <p class="text-primary-400">{row.reason}</p>
          <div :if={row.confirmation} class="space-y-2">
            <p class="font-medium">
              Platba zaevidována · účetní synchronizace: {BankPayments.state_label(
                row.confirmation.state
              )}
            </p>
            <p :if={row.confirmation.error} class="text-error-dark">{row.confirmation.error}</p>
          </div>
          <button
            :if={!row.confirmation && BankPayments.enabled_for?(row.document.kind)}
            id={"booking-bank-check-#{row.movement.id}"}
            type="button"
            class="btn btn-primary btn-sm"
            phx-click="check-payment"
            phx-target={@myself}
            phx-value-movement={row.movement.id}
            phx-value-document={row.document.id}
            phx-disable-with="Ověřuji v ABRA…"
          >{if row.document.kind == "final",
            do: "Zkontrolovat přijetí doplatku",
            else: "Zkontrolovat přijetí zálohy"}</button>
        </section>
        <button type="button" class="btn btn-sm" phx-click="back" phx-target={@myself}>
          Obnovit návrhy
        </button>
      <% end %>
      <div class="flex flex-wrap items-center justify-between gap-3 border-t border-secondary-200 pt-4 text-sm">
        <.link navigate={~p"/admin/billing/bank"} class="link">Bankovní pohyby a stav přenosu</.link>
        <button type="button" class="btn btn-sm" phx-click="close-bank-payment">Zavřít</button>
      </div>
    </div>
    """
  end
end

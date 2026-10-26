defmodule CozyCheckoutWeb.BillingLive.Bank do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Abra.{Bank, BankPayments}
  alias CozyCheckout.Billing.Presentation

  def mount(_, _, socket),
    do: {:ok, assign(socket, page_title: "Bankovní pohyby", confirmation_preview: nil)}

  def handle_params(params, _, socket) do
    page =
      case Integer.parse(params["page"] || "1") do
        {page, ""} when page > 0 -> min(page, 100_000)
        _ -> 1
      end

    {:noreply, socket |> assign(:page, page) |> refresh()}
  end

  def handle_event("import", _, socket) do
    case Bank.enqueue() do
      {:ok, _} -> {:noreply, socket |> refresh() |> put_flash(:info, "Načtení banky zařazeno")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("refresh", _, socket), do: {:noreply, refresh(socket)}

  def handle_event(
        "check-payment",
        %{"movement" => movement_id, "document" => document_id},
        socket
      ) do
    case BankPayments.preview(movement_id, document_id) do
      {:ok, preview} ->
        {:noreply, assign(socket, :confirmation_preview, preview)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, CozyCheckoutWeb.BillingLive.Helpers.error(reason))}
    end
  end

  def handle_event("cancel-payment", _, socket),
    do: {:noreply, assign(socket, :confirmation_preview, nil)}

  def handle_event("confirm-payment", _, %{assigns: %{confirmation_preview: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("confirm-payment", _, socket) do
    case BankPayments.confirm(socket.assigns.confirmation_preview.token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:confirmation_preview, nil)
         |> refresh()
         |> put_flash(:info, "Platba uložena. Účetní synchronizace byla zařazena.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:confirmation_preview, nil)
         |> refresh()
         |> put_flash(:error, CozyCheckoutWeb.BillingLive.Helpers.error(reason))}
    end
  end

  def handle_event("retry-payment-sync", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.rows, &(&1.confirmation && &1.confirmation.id == id)) do
      case BankPayments.retry(id) do
        {:ok, _} ->
          {:noreply, socket |> refresh() |> put_flash(:info, "Synchronizace zařazena znovu")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, reason)}
      end
    else
      {:noreply, put_flash(socket, :error, "Potvrzení není v aktuálním přehledu")}
    end
  end

  defp refresh(socket) do
    assign(socket,
      rows: Bank.list(socket.assigns.page),
      status: Bank.status(),
      enabled?: Bank.enabled?(),
      confirmation_enabled?: BankPayments.enabled?() || BankPayments.enabled_for?("final")
    )
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-6xl space-y-6">
        <h1 class="text-3xl font-bold">Bankovní pohyby</h1>
        <.link navigate={~p"/admin/billing"} class="link">Doklady z rezervací</.link>
        <p>
          Načtení pohybu nepotvrzuje platbu. Platba vznikne až po výslovném potvrzení a nové kontrole v ABRA. Doplatek konečné faktury nevytváří ZDD.
        </p>
        <p :if={!@enabled?} id="bank-disabled">Načítání banky je vypnuté.</p>
        <div class="flex flex-wrap gap-3">
          <button id="bank-import" class="btn btn-primary" phx-click="import" disabled={!@enabled?}>Načíst banku</button>
          <button class="btn" phx-click="refresh">Obnovit přehled</button>
        </div>
        <div id="bank-status" class="space-y-2">
          <p>
            Poslední úspěšné načtení: {if @status && @status.last_success_at,
              do: Calendar.strftime(@status.last_success_at, "%d.%m.%Y %H:%M UTC"),
              else: "dosud neproběhlo"}
          </p>
          <p :if={@status && @status.scan_id}>
            Probíhá neúplné načtení. Zobrazené údaje mohou být neaktuální.
          </p>
          <p :if={@status && @status.error} class="text-red-700">{@status.error}</p>
        </div>
        <p :if={@rows == []}>Žádné načtené pohyby na této stránce.</p>
        <section
          :for={row <- @rows}
          id={"bank-movement-#{row.movement.id}"}
          class="rounded-xl border border-secondary-200 bg-white p-4 space-y-2"
        >
          <p class="font-semibold">
            {CozyCheckoutWeb.CurrencyHelper.format_number(row.movement.amount,
              precision: 2,
              decimal_separator: ","
            )} {String.replace_prefix(row.movement.currency, "code:", "")} · {Presentation.date(
              row.movement.paid_on
            )}
          </p>
          <p>
            {row.movement.counterparty} · VS: {row.movement.variable_symbol || "—"} · ABRA ID: {row.movement.remote_id}
          </p>
          <p>{row.reason}</p>
          <div :if={row.confirmation} class="space-y-2">
            <p class="font-semibold">
              Platba zaevidována · účetní synchronizace: {BankPayments.state_label(
                row.confirmation.state
              )}
            </p>
            <p :if={row.confirmation.error} class="text-red-700">{row.confirmation.error}</p>
            <button
              :if={row.confirmation.state in ["failed", "retrying", "conflict"]}
              class="btn btn-sm"
              phx-click="retry-payment-sync"
              phx-value-id={row.confirmation.id}
            >Znovu ověřit a obnovit přenos</button>
          </div>
          <div :if={row.document}>
            <.link navigate={~p"/admin/bookings/#{row.booking_id}/billing"} class="link">Pobyt · {row.document.number}</.link>
            <p>
              Rozdíl proti {if row.document.kind == "final",
                do: "zbývající úhradě faktury",
                else: "částce výzvy"}: {Presentation.amount(row.difference)}
            </p>
            <button
              :if={
                @confirmation_enabled? && !row.confirmation &&
                  BankPayments.enabled_for?(row.document.kind)
              }
              id={"bank-check-#{row.movement.id}"}
              class="btn btn-primary btn-sm"
              phx-click="check-payment"
              phx-value-movement={row.movement.id}
              phx-value-document={row.document.id}
              phx-disable-with="Ověřuji v ABRA…"
            >{if row.document.kind == "final",
              do: "Zkontrolovat přijetí doplatku",
              else: "Zkontrolovat přijetí zálohy"}</button>
          </div>
        </section>
        <.modal
          :if={@confirmation_preview}
          id="bank-confirmation-modal"
          show
          on_cancel={JS.push("cancel-payment")}
        >
          <h2 class="text-xl font-bold">
            {if @confirmation_preview.document.kind == "final",
              do: "Potvrdit bankovní doplatek",
              else: "Potvrdit přijetí zálohy"}
          </h2>
          <p>
            Doklad {@confirmation_preview.document.number} · VS {@confirmation_preview.movement.variable_symbol}
          </p>
          <p>
            {Presentation.amount(@confirmation_preview.movement.amount)} · {Presentation.date(
              @confirmation_preview.movement.paid_on
            )} · {@confirmation_preview.movement.counterparty}
          </p>
          <p :if={@confirmation_preview.document.kind == "final"}>
            Potvrzením se zaeviduje doplatek a existující bankovní pohyb se spáruje s konečnou fakturou v ABRA. Nevznikne ZDD ani nový bankovní pohyb.
          </p>
          <p :if={@confirmation_preview.document.kind == "advance"}>
            Potvrzením vznikne skutečná platba a uzamčený daňový doklad k přijaté záloze. Účetní vazby se následně přenesou do ABRA. Potvrzení nelze jednoduše vrátit zpět.
          </p>
          <button
            id="bank-confirm-payment"
            class="btn btn-primary mt-4"
            phx-click="confirm-payment"
            phx-disable-with="Potvrzuji…"
          >{if @confirmation_preview.document.kind == "final",
            do: "Potvrdit doplatek a spárovat fakturu",
            else: "Potvrdit zálohu a vystavit ZDD"}</button>
        </.modal>
        <nav class="flex gap-4">
          <.link :if={@page > 1} patch={~p"/admin/billing/bank?page=#{@page - 1}"} class="link">Předchozí</.link>
          <span>Strana {@page}</span>
          <.link
            :if={length(@rows) == 50}
            patch={~p"/admin/billing/bank?page=#{@page + 1}"}
            class="link"
          >Další</.link>
        </nav>
      </div>
    </Layouts.app>
    """
  end
end

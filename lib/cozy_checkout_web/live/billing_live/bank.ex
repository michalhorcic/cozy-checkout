defmodule CozyCheckoutWeb.BillingLive.Bank do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Abra.Bank
  alias CozyCheckout.Billing.Presentation

  def mount(_, _, socket), do: {:ok, assign(socket, page_title: "Bankovní pohyby")}

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

  defp refresh(socket) do
    assign(socket,
      rows: Bank.list(socket.assigns.page),
      status: Bank.status(),
      enabled?: Bank.enabled?()
    )
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-6xl space-y-6">
        <h1 class="text-3xl font-bold">Bankovní pohyby</h1>
        <.link navigate={~p"/admin/billing"} class="link">Doklady z rezervací</.link>
        <p>
          Pohyby a návrhy podle VS jsou pouze informativní. Jejich načtení nepotvrzuje platbu ani nevystavuje doklad.
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
          <div :if={row.document}>
            <.link navigate={~p"/admin/bookings/#{row.booking_id}/billing"} class="link">Pobyt · {row.document.number}</.link>
            <p>
              Rozdíl proti {if row.document.kind == "final",
                do: "zbývající úhradě faktury",
                else: "částce výzvy"}: {Presentation.amount(row.difference)}
            </p>
          </div>
        </section>
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

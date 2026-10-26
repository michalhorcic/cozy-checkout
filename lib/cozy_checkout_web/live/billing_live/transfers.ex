defmodule CozyCheckoutWeb.BillingLive.Transfers do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Abra.Transfers
  alias CozyCheckoutWeb.BillingLive.Helpers

  def mount(_, _, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, 10_000)
    {:ok, assign(socket, page_title: "Přenosy do ABRA")}
  end

  def handle_params(params, _, socket) do
    mode = if params["mode"] in ["all", "pending"], do: params["mode"], else: "problems"

    page =
      case Integer.parse(params["page"] || "1") do
        {value, ""} when value > 0 -> min(value, 100_000)
        _ -> 1
      end

    {:noreply, socket |> assign(mode: mode, page: page) |> refresh()}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 10_000)
    {:noreply, refresh(socket)}
  end

  def handle_event("refresh", _, socket), do: {:noreply, refresh(socket)}

  def handle_event("retry", %{"id" => id, "category" => category}, socket) do
    if Enum.any?(
         socket.assigns.rows,
         &(&1.id == id and &1.category == category and &1.state != "synced")
       ) do
      case Transfers.retry(category, id) do
        {:ok, _} ->
          {:noreply, socket |> refresh() |> put_flash(:info, "Přenos zařazen k obnovení")}

        {:error, reason} ->
          {:noreply, socket |> refresh() |> put_flash(:error, Helpers.error(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Přenos není v aktuálním přehledu")}
    end
  end

  defp refresh(socket),
    do:
      assign(socket,
        rows: Transfers.list(socket.assigns.mode, socket.assigns.page),
        notice: Transfers.configuration_notice()
      )

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-6xl space-y-6">
        <h1 class="text-3xl font-bold">Přenosy do ABRA</h1>
        <nav class="flex flex-wrap gap-4">
          <.link navigate={~p"/admin/billing"} class="link">Doklady</.link>
          <.link navigate={~p"/admin/billing/bank"} class="link">Bankovní pohyby</.link>
          <.link patch={~p"/admin/billing/transfers?mode=problems"} class="link">Chyby a opakování</.link>
          <.link patch={~p"/admin/billing/transfers?mode=pending"} class="link">Čekající</.link>
          <.link patch={~p"/admin/billing/transfers?mode=all"} class="link">Všechny</.link>
        </nav>
        <p>Výpadek ABRA nemění vystavené doklady. Obnova pokračuje se stejným požadavkem.</p>
        <p :if={@notice} id="abra-configuration-notice" class="alert alert-warning">{@notice}</p>
        <button class="btn" phx-click="refresh">Obnovit přehled</button>
        <p :if={@rows == []} id="abra-transfers-empty">V tomto výběru nejsou žádné přenosy.</p>
        <section
          :for={row <- @rows}
          id={"abra-transfer-#{row.category}-#{row.id}"}
          class="rounded-xl border border-secondary-200 bg-white p-4 space-y-2"
        >
          <.link navigate={~p"/admin/billing/documents/#{row.document_id}"} class="link font-semibold">{row.number}</.link>
          <p>
            {if row.category == "document", do: "Export dokladu", else: "Platba a účetní vazby"} · {Transfers.label(
              row.state
            )}
          </p>
          <p
            :if={row.error}
            class={if row.state == "waiting", do: "text-primary-500", else: "text-red-700"}
          >
            {row.error}
          </p>
          <div class="flex flex-wrap gap-3">
            <.link navigate={~p"/admin/bookings/#{row.booking_id}/billing"} class="link">Pobyt</.link>
            <button
              :if={row.state in ["failed", "retrying", "conflict", "waiting"]}
              class="btn btn-sm"
              phx-click="retry"
              phx-value-id={row.id}
              phx-value-category={row.category}
              phx-disable-with="Ověřuji…"
            >Ověřit a obnovit přenos</button>
          </div>
        </section>
        <nav class="flex gap-4">
          <.link
            :if={@page > 1}
            patch={~p"/admin/billing/transfers?mode=#{@mode}&page=#{@page - 1}"}
            class="link"
          >Předchozí</.link>
          <span>Strana {@page}</span>
          <.link
            :if={length(@rows) == 50}
            patch={~p"/admin/billing/transfers?mode=#{@mode}&page=#{@page + 1}"}
            class="link"
          >Další</.link>
        </nav>
      </div>
    </Layouts.app>
    """
  end
end

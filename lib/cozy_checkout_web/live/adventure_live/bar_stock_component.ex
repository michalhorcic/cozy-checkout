defmodule CozyCheckoutWeb.AdventureLive.BarStockComponent do
  use CozyCheckoutWeb, :live_component
  alias CozyCheckout.Adventure
  alias CozyCheckout.Adventure.Sources.BarStock
  import CozyCheckoutWeb.CurrencyHelper, only: [format_number: 1]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, snapshot: nil, state: :loading, started: false, now: DateTime.utc_now())}
  end

  @impl true
  def update(%{action: :load}, socket), do: {:ok, load(socket)}

  def update(%{action: :tick}, socket) do
    schedule_tick(socket)
    {:ok, assign(socket, now: DateTime.utc_now())}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if connected?(socket) && !socket.assigns.started do
      send_update(__MODULE__, id: socket.assigns.id, action: :load)
      schedule_tick(socket)
      {:ok, assign(socket, started: true)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("refresh", _, socket) do
    if socket.assigns.state == :loading do
      {:noreply, socket}
    else
      send_update(__MODULE__, id: socket.assigns.id, action: :load)
      {:noreply, assign(socket, state: :loading)}
    end
  end

  defp load(socket) do
    socket = assign(socket, now: DateTime.utc_now())

    case BarStock.load() do
      {:ok, snapshot} -> assign(socket, snapshot: snapshot, state: :ready)
      {:error, :disabled} -> assign(socket, snapshot: nil, state: :error)
      {:error, _} -> assign(socket, state: :error)
    end
  end

  defp schedule_tick(socket),
    do: send_update_after(__MODULE__, [id: socket.assigns.id, action: :tick], 60_000)

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:enabled, Adventure.enabled?())
      |> assign(
        :alerts,
        if(assigns.snapshot,
          do:
            Enum.filter(
              assigns.snapshot.products,
              &(&1.status in [:out_of_stock, :low_stock, :unknown])
            ),
          else: []
        )
      )

    ~H"""
    <section
      id={@id}
      class="adventure-area-detail"
      aria-label="Zásoby baru"
      aria-busy={@state == :loading}
    >
      <header class="flex items-center justify-between gap-3">
        <h3>Zásoby baru</h3>
        <button
          type="button"
          id="adventure-bar-refresh"
          phx-click="refresh"
          phx-target={@myself}
          disabled={@state == :loading || !@enabled}
          class="adventure-text-link"
        >
          <.icon name="hero-arrow-path" class="size-4" /> Obnovit
        </button>
      </header>
      <div role="status" aria-live="polite" class="text-sm opacity-75">
        <p :if={@state == :loading}>Nahlížíme do baru…</p>
        <p :if={@state == :error}>Bar se teď neozývá. Zkus obnovit.</p>
        <p :if={!@snapshot || !@enabled}>Zatím bez přehledu.</p>
        <p :if={@snapshot && @enabled}>
          <time datetime={DateTime.to_iso8601(@snapshot.loaded_at)}>{age(@snapshot.loaded_at, @now)}</time>
          <span :if={BarStock.stale?(@snapshot, @now)}> · Starší přehled</span>
        </p>
      </div>
      <div :if={@snapshot && @enabled}>
        <dl class="grid grid-cols-3 gap-2 my-4 text-center">
          <div>
            <dt class="text-sm">Dochází</dt><dd class="text-xl font-bold">
              {count(@snapshot, :out_of_stock) + count(@snapshot, :low_stock)}
            </dd>
          </div>
          <div>
            <dt class="text-sm">Bez evidence</dt><dd class="text-xl font-bold">
              {count(@snapshot, :unknown)}
            </dd>
          </div>
          <div>
            <dt class="text-sm">Sledujeme</dt><dd class="text-xl font-bold">
              {@snapshot.tracked_count}
            </dd>
          </div>
        </dl>
        <p :if={@snapshot.tracked_count == 0}>Bar čeká na první zásoby.</p>
        <p :if={@snapshot.tracked_count > 0 && @alerts == []}>Žádné hlášené nedostatky.</p>
        <ul
          class="max-h-64 overflow-y-auto break-words space-y-3"
          aria-label="Upozornění skladu baru"
        >
          <li :for={product <- @alerts} class="flex items-start justify-between gap-3">
            <div>
              <strong>{product.name}</strong><small class="block opacity-75">{label(product.status)}</small>
            </div>
            <span :if={product.stock} class="shrink-0">{quantity(product.stock)} {product.unit}</span>
          </li>
        </ul>
        <p :if={Enum.any?(@snapshot.products, &is_nil(&1.threshold))} class="mt-3 text-sm opacity-75">
          Bez limitu: {Enum.count(@snapshot.products, &is_nil(&1.threshold))}
        </p>
      </div>
      <.link href={~p"/admin/bar-stock"} class="adventure-text-link">Do skladu
      <.icon name="hero-arrow-right" class="size-4" /></.link>
    </section>
    """
  end

  defp age(loaded_at, now) do
    minutes = max(div(DateTime.diff(now, loaded_at), 60), 0)

    cond do
      minutes == 0 -> "Právě načteno"
      minutes < 60 -> "Před #{minutes} min"
      minutes < 1440 -> "Před #{div(minutes, 60)} h"
      true -> "Před #{div(minutes, 1440)} d"
    end
  end

  defp quantity(value), do: value |> Decimal.normalize() |> format_number()
  defp count(snapshot, status), do: Enum.count(snapshot.products, &(&1.status == status))
  defp label(:unknown), do: "Chybí evidence"
  defp label(:out_of_stock), do: "Nulová nebo záporná zásoba"
  defp label(:low_stock), do: "Na limitu nebo pod ním"
end

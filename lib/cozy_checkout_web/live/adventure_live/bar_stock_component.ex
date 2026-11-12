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
    assigns = assign(assigns, :enabled, Adventure.enabled?())

    ~H"""
    <section id={@id} aria-label="Živý sklad baru" aria-busy={@state == :loading}>
      <h3>Evidovaný sklad baru</h3>
      <p>Stav evidence není fyzická inventura. Bez automatické obnovy.</p>
      <button
        type="button"
        id="adventure-bar-refresh"
        phx-click="refresh"
        phx-target={@myself}
        disabled={@state == :loading || !@enabled}
        class="adventure-text-link"
      >Obnovit sklad baru</button>
      <div role="status" aria-live="polite">
        <p :if={@state == :loading}>Načítání skladu…</p>
        <p :if={@state == :error}>
          Sklad se nepodařilo načíst. Zobrazené údaje mohou být neaktuální.
        </p>
        <p :if={!@snapshot || !@enabled}>Aktuální stav není známý. Neznámý stav není nula.</p>
        <p :if={@snapshot && @enabled}>
          Načteno
          <time datetime={DateTime.to_iso8601(@snapshot.loaded_at)}>{@snapshot.loaded_at} UTC</time>
          <strong :if={BarStock.stale?(@snapshot, @now)}> · Zastaralé údaje (15 minut nebo více)</strong>
        </p>
      </div>
      <div :if={@snapshot && @enabled}>
        <dl class="adventure-operation-counts">
          <div>
            <dt>Sledované produkty</dt><dd>{@snapshot.tracked_count}</dd>
          </div>
          <div>
            <dt>Evidovaný stav ≤ 0</dt><dd>{count(@snapshot, :out_of_stock)}</dd>
          </div>
          <div>
            <dt>Na limitu nebo pod ním</dt><dd>{count(@snapshot, :low_stock)}</dd>
          </div>
          <div>
            <dt>Bez skladových pohybů</dt><dd>{count(@snapshot, :unknown)}</dd>
          </div>
          <div>
            <dt>Bez nastaveného limitu</dt><dd>
              {Enum.count(@snapshot.products, &is_nil(&1.threshold))}
            </dd>
          </div>
        </dl>
        <p :if={@snapshot.tracked_count == 0}>
          Žádné sledované produkty. Dostupnost zásob není ověřena.
        </p>
        <ul class="max-h-80 overflow-y-auto break-words" aria-label="Upozornění skladu baru">
          <li :for={product <- @snapshot.products} :if={product.status != :in_stock}>
            <strong>{product.name}</strong>
            · {label(product.status)} ·
            <span :if={product.stock}>{format_number(product.stock)} {product.unit}</span>
            <span :if={!product.stock}>Množství není evidováno</span>
            <span :if={product.threshold}> · limit {format_number(product.threshold)} {product.unit}</span>
            <span :if={!product.threshold}> · limit nenastaven</span>
          </li>
        </ul>
      </div>
      <.link href={~p"/admin/bar-stock"} class="adventure-text-link">Otevřít sklad baru</.link>
    </section>
    """
  end

  defp count(snapshot, status), do: Enum.count(snapshot.products, &(&1.status == status))
  defp label(:unknown), do: "Chybí evidence"
  defp label(:out_of_stock), do: "Evidovaný stav ≤ 0"
  defp label(:low_stock), do: "Na limitu nebo pod ním"
  defp label(:no_limit), do: "Limit nenastaven"
end

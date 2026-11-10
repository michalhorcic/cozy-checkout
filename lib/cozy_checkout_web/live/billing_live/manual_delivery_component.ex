defmodule CozyCheckoutWeb.BillingLive.ManualDeliveryComponent do
  use CozyCheckoutWeb, :live_component
  alias CozyCheckout.Billing
  alias CozyCheckout.Billing.Presentation
  alias CozyCheckoutWeb.BillingLive.Helpers

  def update(assigns, socket) do
    changed? = socket.assigns[:document_id] != assigns.document_id
    socket = assign(socket, assigns)
    socket = if changed?, do: reset_form(socket, assigns[:open_form] || false), else: socket
    {:ok, load_history(socket)}
  end

  def handle_event("new", _, socket), do: {:noreply, reset_form(socket, true)}
  def handle_event("close", _, socket), do: {:noreply, reset_form(socket, false)}
  def handle_event("refresh", _, socket), do: {:noreply, load_history(socket)}

  def handle_event("edit", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.manual, &(&1.id == id && is_nil(&1.voided_at))) do
      nil ->
        {:noreply, assign(socket, :error, "Záznam již není platný. Obnovte historii.")}

      row ->
        {:noreply,
         assign(socket,
           editing_id: row.id,
           show_form: true,
           error: nil,
           form:
             to_form(
               %{
                 "sent_on" => to_string(row.sent_on),
                 "note" => row.note,
                 "request_id" => Ecto.UUID.generate()
               },
               as: :manual_delivery
             )
         )}
    end
  end

  def handle_event("save", %{"manual_delivery" => attrs}, socket) do
    case Billing.record_manual_delivery(
           socket.assigns.document_id,
           attrs,
           attrs["request_id"],
           socket.assigns.editing_id
         ) do
      {:ok, _} ->
        send(self(), {:manual_delivery_changed, socket.assigns.document_id})
        {:noreply, socket |> reset_form(false) |> load_history()}

      {:error, error} ->
        {:noreply,
         assign(socket,
           error: Helpers.error(error),
           form: to_form(attrs, as: :manual_delivery)
         )}
    end
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    case Billing.cancel_manual_delivery(socket.assigns.document_id, id) do
      {:ok, _} ->
        send(self(), {:manual_delivery_changed, socket.assigns.document_id})
        {:noreply, socket |> reset_form(false) |> load_history()}

      {:error, error} ->
        {:noreply, socket |> load_history() |> assign(:error, Helpers.error(error))}
    end
  end

  defp reset_form(socket, show?) do
    assign(socket,
      show_form: show?,
      editing_id: nil,
      error: nil,
      form:
        to_form(
          %{
            "sent_on" => to_string(Billing.today()),
            "note" => "",
            "request_id" => Ecto.UUID.generate()
          },
          as: :manual_delivery
        )
    )
  end

  defp load_history(socket) do
    manual = Billing.list_manual_deliveries(socket.assigns.document_id)

    history =
      (Enum.map(manual, &%{type: :manual, row: &1}) ++
         Enum.map(Billing.list_deliveries(socket.assigns.document_id), &%{type: :email, row: &1}))
      |> Enum.sort_by(& &1.row.inserted_at, {:desc, DateTime})

    assign(socket, manual: manual, history: history)
  end

  def render(assigns) do
    ~H"""
    <section id={@id} class="space-y-4">
      <button :if={!@show_form} type="button" class="btn btn-sm" phx-click="new" phx-target={@myself}>
        Zaznamenat ruční odeslání
      </button>
      <p :if={@error} role="alert" class="alert alert-error">{@error}</p>
      <.form
        :if={@show_form}
        for={@form}
        id={@id <> "-form"}
        phx-submit="save"
        phx-target={@myself}
        class="space-y-4"
      >
        <input type="hidden" name="manual_delivery[request_id]" value={@form[:request_id].value} />
        <h3 class="font-semibold">
          {if @editing_id, do: "Opravit ruční odeslání", else: "Zaznamenat ruční odeslání"}
        </h3>
        <.input
          field={@form[:sent_on]}
          type="date"
          label="Datum odeslání"
          max={to_string(Billing.today())}
          required
        />
        <.input
          field={@form[:note]}
          type="textarea"
          label="Poznámka (nepovinná)"
          maxlength="2000"
          rows="3"
        />
        <p class="text-sm text-primary-400">
          Záznam pouze eviduje odeslání mimo aplikaci. Odesílání z aplikace pokračuje beze změny.
        </p>
        <div class="flex flex-wrap gap-2">
          <button class="btn btn-primary" phx-disable-with="Ukládám…">Uložit záznam</button>
          <button type="button" class="btn" phx-click="close" phx-target={@myself}>Zavřít</button>
        </div>
      </.form>
      <div class="flex items-center justify-between gap-2">
        <h3 class="font-semibold">Historie odeslání</h3>
        <button type="button" class="link text-sm" phx-click="refresh" phx-target={@myself}>Obnovit historii</button>
      </div>
      <p :if={@history == []} class="text-sm text-primary-400">
        Zatím není zaznamenáno žádné odeslání.
      </p>
      <div
        :for={event <- @history}
        id={"delivery-history-#{event.row.id}"}
        class="border-b border-secondary-200 py-2 space-y-1"
      >
        <p :if={event.type == :manual} class="font-medium">
          {case event.row.void_reason do
            "corrected" -> "Ruční odeslání — opravený záznam"
            "cancelled" -> "Ruční odeslání — zrušený záznam"
            _ -> "Odesláno ručně"
          end} · {if event.type == :manual, do: Presentation.date(event.row.sent_on)}
        </p>
        <p
          :if={event.type == :manual && event.row.note}
          class="text-sm whitespace-pre-wrap break-words"
        >
          {event.row.note}
        </p>
        <p :if={event.type == :manual && event.row.replaces_id} class="text-xs text-primary-400">
          <a href={"#delivery-history-#{event.row.replaces_id}"} class="link">Oprava předchozího záznamu.</a>
        </p>
        <p :if={event.type == :manual && event.row.voided_at} class="text-xs text-primary-400">
          Změněno {Calendar.strftime(event.row.voided_at, "%d.%m.%Y %H:%M UTC")}.
        </p>
        <div :if={event.type == :manual && is_nil(event.row.voided_at)} class="flex gap-3 text-sm">
          <button
            type="button"
            class="link"
            phx-click="edit"
            phx-value-id={event.row.id}
            phx-target={@myself}
          >Opravit</button>
          <button
            type="button"
            class="link"
            phx-click="cancel"
            phx-value-id={event.row.id}
            phx-target={@myself}
            data-confirm="Zrušit tento záznam ručního odeslání? Zůstane zachován v historii."
          >Zrušit záznam</button>
        </div>
        <p :if={event.type == :email}>
          Z aplikace · {event.row.recipient} · {delivery_label(event.row.state)} · pokusů {event.row.attempts}
        </p>
        <p class="text-xs text-primary-400">
          Zaznamenáno {Calendar.strftime(event.row.inserted_at, "%d.%m.%Y %H:%M UTC")}.
        </p>
        <p
          :if={event.type == :email && event.row.state in ["failed", "retrying"]}
          class="text-red-700"
        >
          Příprava PDF nebo odeslání se nezdařily.
        </p>
        <details :if={
          event.type == :email && event.row.error && event.row.state in ["failed", "retrying"]
        }>
          <summary>Podrobnosti chyby</summary><pre class="whitespace-pre-wrap text-sm">{event.row.error}</pre>
        </details>
      </div>
      <p class="text-xs text-primary-400">
        Odeslání z aplikace znamená přijetí poštovním poskytovatelem. Ruční záznam vychází z vašeho potvrzení; doručení adresátovi neověřuje.
      </p>
    </section>
    """
  end

  defp delivery_label("accepted"), do: "Odesláno"
  defp delivery_label("queued"), do: "Ve frontě"
  defp delivery_label("retrying"), do: "Čeká na opakování"
  defp delivery_label(_), do: "Neodesláno"
end

defmodule CozyCheckoutWeb.BillingComponents do
  @moduledoc "Shared billing document presentation and delivery forms."
  use CozyCheckoutWeb, :html

  alias CozyCheckout.Billing.Presentation

  attr :document, :map, required: true
  attr :statuses, :list, default: []

  def abra_status(assigns) do
    ~H"""
    <div id={"abra-status-#{@document.id}"} class="mt-2 space-y-1 text-sm">
      <p :if={@statuses == []} class="text-primary-400">
        ABRA: {cond do
          @document.kind == "correction" -> "Opravu vyřešte s účetní"
          @document.kind == "tax_receipt" -> "ZDD bez bankovního přenosu"
          true -> "Nepřeneseno"
        end}
      </p>
      <div :for={status <- @statuses}>
        <p class={
          if status.state in ["failed", "conflict", "retrying"],
            do: "text-red-700",
            else: "text-primary-500"
        }>
          ABRA {if status.category == "payment", do: "· platba a vazby", else: "· doklad"}: {CozyCheckout.Abra.Transfers.label(
            status.state
          )}
        </p>
        <p :if={status.error} class="text-sm">{status.error}</p>
        <.link
          :if={status.state in ["failed", "conflict", "retrying", "waiting"]}
          navigate={
            if status.state == "waiting",
              do: ~p"/admin/billing/transfers?mode=pending",
              else: ~p"/admin/billing/transfers"
          }
          class="link"
        >Řešit přenos</.link>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :document, :map, required: true

  def advance_breakdown(assigns) do
    assigns = assign(assigns, :calculation, Presentation.advance_breakdown(assigns.document))

    ~H"""
    <section :if={@calculation} id={@id} class={["space-y-3"]}>
      <h3 class={["font-semibold"]}>Rozpis pobytu a objednaných služeb</h3>
      <div class={["overflow-x-auto rounded-lg border border-secondary-200"]}>
        <table class={["table w-full min-w-[640px] text-sm"]}>
          <thead>
            <tr>
              <th>Položka</th><th class={["text-right"]}>Osob / množství</th>
              <th class={["text-right"]}>Nocí / jednotek</th>
              <th class={["text-right"]}>Jedn. cena s DPH</th>
              <th class={["text-right"]}>Celkem s DPH</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={line <- @calculation["lines"]}>
              <td>{line["name"]}</td>
              <td class={["text-right tabular-nums"]}>{Presentation.number(line["quantity"])}</td>
              <td class={["text-right tabular-nums"]}>{Presentation.number(line["nights"])}</td>
              <td class={["whitespace-nowrap text-right tabular-nums"]}>
                {Presentation.amount(Presentation.gross_unit_price(line))}
              </td>
              <td class={["whitespace-nowrap text-right font-medium tabular-nums"]}>
                {Presentation.amount(line["gross"])}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class={["text-right font-semibold"]}>
        Celková cena pobytu: {Presentation.amount(@calculation["stay_total"])}
      </p>
      <p class={["text-xs text-primary-400"]}>
        Ceny jsou včetně DPH. Částky jsou zaokrouhlené na haléře.
      </p>
      <div class={["rounded-lg border border-secondary-200 bg-secondary-50 p-4"]}>
        <h3 class={["font-semibold"]}>Výpočet zálohy</h3>
        <p class={["mt-1 tabular-nums"]}>{Presentation.advance_explanation(@calculation)}</p>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :form, :any, required: true
  attr :error, :string, default: nil

  def email_form(assigns) do
    ~H"""
    <div class="space-y-4">
      <p :if={@error} id={@id <> "-error"} role="alert" class="alert alert-error">{@error}</p>
      <.form for={@form} id={@id} phx-submit="email" class="space-y-4">
        <input type="hidden" name="email[request_id]" value={@form[:request_id].value} />
        <.input field={@form[:recipient]} type="email" label="Příjemce" required />
        <.input field={@form[:subject]} label="Předmět" required />
        <.input field={@form[:body]} type="textarea" label="Zpráva" rows="5" required />
        <.input
          field={@form[:consent]}
          type="checkbox"
          label="Odběratel souhlasí s elektronickou podobou dokladu"
        />
        <button class="btn btn-primary w-full sm:w-auto" phx-disable-with="Zařazuji…">
          <.icon name="hero-envelope" class="size-4" />Odeslat s PDF
        </button>
      </.form>
      <p class="text-sm text-primary-400">E-mail bude zařazen k odeslání s uloženým PDF dokladu.</p>
    </div>
    """
  end
end

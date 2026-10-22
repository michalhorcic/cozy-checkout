defmodule CozyCheckoutWeb.BillingComponents do
  @moduledoc "Shared document delivery form for billing screens."
  use CozyCheckoutWeb, :html

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

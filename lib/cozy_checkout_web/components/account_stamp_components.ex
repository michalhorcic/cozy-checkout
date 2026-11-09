defmodule CozyCheckoutWeb.AccountStampComponents do
  use Phoenix.Component

  alias CozyCheckout.Sales.AccountStamps

  attr :stamp, :string, required: true
  attr :class, :string, default: "h-16 w-16"

  def account_stamp(assigns) do
    assigns = assign(assigns, :label, AccountStamps.label(assigns.stamp))

    ~H"""
    <span class={[
      "inline-flex shrink-0 -rotate-3 items-center justify-center rounded-full border border-secondary-300 bg-secondary-50 p-2 shadow-sm",
      @class
    ]}>
      <img
        src={"/images/account-stamps/#{@stamp}.svg"}
        alt={"Značka účtu: #{@label}"}
        width="64"
        height="64"
        class="h-full w-full"
      />
    </span>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :id, :string, required: true

  def account_stamp_picker(assigns) do
    assigns = assign(assigns, :stamps, AccountStamps.all())

    ~H"""
    <fieldset id={@id} class="mt-4">
      <legend class="text-sm font-semibold text-primary-500">Značka účtu</legend>
      <p class="mt-1 text-sm text-primary-400">
        Vybrali jsme vám značku. Klepnutím si můžete zvolit jinou.
      </p>
      <div class="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-4">
        <label :for={{key, label} <- @stamps} class="cursor-pointer text-center">
          <input
            type="radio"
            name={@name}
            value={key}
            checked={@value == key}
            class="peer sr-only"
          />
          <span class="flex min-h-20 flex-col items-center justify-center gap-1 rounded-xl border-2 border-transparent p-1 transition-colors peer-checked:border-tertiary-500 peer-checked:bg-tertiary-50 peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-primary-500">
            <.account_stamp stamp={key} class="h-12 w-12" />
            <span class="text-xs font-semibold text-primary-500">{label}</span>
          </span>
        </label>
      </div>
    </fieldset>
    """
  end
end

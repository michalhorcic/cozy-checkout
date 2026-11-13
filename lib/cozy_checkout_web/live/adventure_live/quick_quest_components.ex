defmodule CozyCheckoutWeb.AdventureLive.QuickQuestComponents do
  use CozyCheckoutWeb, :html
  import CozyCheckoutWeb.AdventureLive.GameComponents, only: [symbol: 1]
  alias CozyCheckout.Adventure.Quest

  attr :form, :any, required: true
  attr :profile, :any, required: true
  attr :full, :boolean, required: true

  def card(assigns) do
    mine = assigns.form.params["disposition"] != "free"
    assigns = assign(assigns, mine: mine, later: mine && assigns.full)

    ~H"""
    <section class="adventure-duty-card space-y-4">
      <header class="adventure-duty-card-hero">
        <div class="adventure-duty-crest" aria-hidden="true"><.symbol name="backpack" /></div>
        <div>
          <p class="adventure-eyebrow">Vlastní dobrodružství</p>
          <h2 id="adventure-quick-task-title" class="text-xl font-bold pr-8">Nový quest</h2>
        </div>
      </header>
      <.form
        for={@form}
        id="adventure-quick-task-form"
        phx-change="validate-quick-task"
        phx-submit="save-quick-task"
        class="grid gap-4"
      >
        <.input
          field={@form[:title]}
          id="quick_title"
          label="Co podnikneme?"
          placeholder="Třeba připravit dřevo na večer…"
          required
          maxlength="200"
        />
        <fieldset class="adventure-duty-choice">
          <legend class="sr-only">Kdo vyrazí?</legend>
          <label>
            <input type="radio" name="quick[disposition]" value="mine" checked={@mine} />
            <span><.symbol name="backpack" /><strong>Pro mě</strong><small>{@profile.display_name}</small></span>
          </label>
          <label>
            <input type="radio" name="quick[disposition]" value="free" checked={!@mine} />
            <span><.symbol name="flag" /><strong>Pro všechny</strong><small>Volný quest k převzetí</small></span>
          </label>
        </fieldset>
        <fieldset class="adventure-quick-size">
          <legend class="sr-only">Velikost výpravy</legend>
          <label :for={
            {label, size, xp} <- [
              {"Malý", "small", 50},
              {"Střední", "medium", 100},
              {"Velký", "large", 250}
            ]
          }>
            <input type="radio" name="quick[size]" value={size} checked={@form[:size].value == size} />
            <span><strong>{label}</strong><small>{xp} XP</small></span>
          </label>
        </fieldset>
        <p :for={error <- @form[:size].errors} class="text-error">{translate_error(error)}</p>
        <.input field={@form[:category]} type="select" label="Kategorie" options={Quest.categories()} />
        <p :if={@later} role="status" class="adventure-muted">Tři výpravy už běží.</p>
        <input type="hidden" name="quick[intent]" value={if @later, do: "later", else: "start"} />
        <button
          type="submit"
          class="adventure-button adventure-button--primary"
          phx-disable-with="Chystám…"
        >
          {cond do
            @later -> "Uložit na později"
            @mine -> "Vytvořit a vyrazit"
            true -> "Vyvěsit quest"
          end}
        </button>
      </.form>
      <button type="button" phx-click="cancel-quick-task" class="adventure-text-link">Zpět</button>
    </section>
    """
  end
end

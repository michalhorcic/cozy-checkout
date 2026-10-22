defmodule CozyCheckoutWeb.KitchenComponents do
  use CozyCheckoutWeb, :html

  def field_class,
    do:
      "block w-full rounded-lg border border-secondary-300 bg-white px-3 py-2.5 text-sm text-primary-500 shadow-sm outline-none transition focus:border-tertiary-400 focus:ring-4 focus:ring-tertiary-50"

  attr :id, :string, required: true
  attr :item, :any, required: true
  attr :href, :string, default: nil

  def menu_recipe_links(assigns) do
    {item, main_changed?, extras_changed?} =
      case assigns.item do
        %Ecto.Changeset{} = cs ->
          {Ecto.Changeset.apply_changes(cs),
           not is_nil(cs.data.id) &&
             Ecto.Changeset.get_field(cs, :menu_text) != cs.data.menu_text,
           not is_nil(cs.data.id) &&
             Ecto.Changeset.get_field(cs, :supplements) != cs.data.supplements}

        item ->
          {item, false, false}
      end

    main = if item.recipe_id && not main_changed?, do: item.recipe

    extras =
      if Ecto.assoc_loaded?(item.recipe_supplements) && not extras_changed?,
        do: item.recipe_supplements |> Enum.sort_by(& &1.position) |> Enum.map(& &1.recipe),
        else: []

    assigns =
      assigns
      |> assign(:main, main)
      |> assign(:extras, extras)
      |> assign(:has_links?, not is_nil(main) || extras != [])
      |> assign(:text_changed?, main_changed? || extras_changed?)
      |> assign(:has_supplements?, String.trim(item.supplements || "") != "")

    ~H"""
    <div
      id={@id}
      class="mt-3 space-y-2 rounded-lg border border-secondary-200 bg-secondary-50/80 p-3 text-sm"
    >
      <p :if={@main} class="flex items-start gap-2 text-emerald-800" data-linked-main>
        <.icon name="hero-check-circle" class="mt-0.5 h-4 w-4 shrink-0" />
        <span><span class="font-semibold">Hlavní recept:</span> {@main.name}</span>
      </p>
      <p :if={is_nil(@main)} class="flex items-center gap-2 text-amber-800" data-missing-main>
        <.icon name="hero-exclamation-circle" class="h-4 w-4 shrink-0" /> Chybí hlavní recept
      </p>
      <p :if={@extras != []} class="text-primary-400" data-linked-extras>
        <span class="font-semibold">Připojené doplňky:</span> {Enum.map_join(
          @extras,
          " · ",
          & &1.name
        )}
      </p>
      <p :if={@has_supplements? && @extras == []} class="text-amber-800" data-missing-extras>
        Doplňky zatím nemají připojené recepty.
      </p>
      <p :if={@text_changed?} class="text-amber-800" data-text-changed>
        Nejdřív uložte změny textu. Recepty změněného chodu nebo doplňků se odpojí.
      </p>
      <.link
        :if={@href && not @text_changed?}
        navigate={@href}
        class="inline-flex items-center gap-1.5 font-semibold text-tertiary-600 underline decoration-tertiary-300 underline-offset-4 transition hover:text-tertiary-800"
      >
        <.icon name="hero-link" class="h-4 w-4" />
        {if @has_links?, do: "Upravit připojené recepty", else: "Připojit recepty"}
      </.link>
      <p :if={is_nil(@href)} class="text-xs text-primary-400">
        Recepty připojíte po uložení varianty.
      </p>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :ingredients, :list, required: true
  attr :index, :string, required: true
  attr :query, :string, default: nil
  attr :open, :boolean, default: false

  def ingredient_picker(assigns) do
    available =
      Enum.reject(
        assigns.ingredients,
        &(&1.archived_at && &1.id != to_string(assigns.field.value))
      )

    selected = Enum.find(available, &(&1.id == to_string(assigns.field.value)))
    query = assigns.query || if(selected, do: selected.name, else: "")

    words =
      if selected && query == selected.name,
        do: [],
        else: String.split(CozyCheckout.Recipes.normalize(query))

    matches =
      Enum.filter(available, fn ingredient ->
        name = CozyCheckout.Recipes.normalize(ingredient.name)
        Enum.all?(words, &String.contains?(name, &1))
      end)

    assigns =
      assigns
      |> assign(:query, query)
      |> assign(:matches, Enum.take(matches, 8))
      |> assign(:match_count, length(matches))
      |> assign(:options, Enum.map(available, &{&1.name <> " (" <> &1.base_unit <> ")", &1.id}))

    ~H"""
    <div
      id={"#{@field.id}-picker"}
      class="relative min-w-0"
      phx-click-away={@open && "close_ingredient_search"}
    >
      <.input
        id={"#{@field.id}-search"}
        name={"ingredient_search[#{@index}]"}
        type="search"
        value={@query}
        label="Surovina"
        placeholder="Hledat surovinu podle názvu…"
        autocomplete="off"
        phx-change="search_ingredients"
        phx-debounce="150"
        phx-focus="open_ingredient_search"
        phx-value-index={@index}
        phx-keydown="close_ingredient_search"
        phx-key="Escape"
        aria-controls={"#{@field.id}-options"}
        aria-expanded={to_string(@open)}
        aria-invalid={to_string(@field.errors != [])}
        aria-describedby={@field.errors != [] && "#{@field.id}-error"}
        class={field_class()}
        required
      />
      <div
        :if={@open}
        id={"#{@field.id}-options"}
        class="absolute left-0 right-0 z-30 max-h-72 overflow-y-auto overscroll-contain rounded-lg border border-secondary-200 bg-white p-1 shadow-xl"
        aria-label="Nalezené suroviny"
      >
        <button
          :for={ingredient <- @matches}
          id={"#{@field.id}-option-#{ingredient.id}"}
          type="button"
          phx-click={JS.push("select_ingredient") |> JS.focus(to: "##{@field.form[:quantity].id}")}
          phx-value-index={@index}
          phx-value-id={ingredient.id}
          class="flex w-full items-center justify-between gap-3 rounded-lg px-3 py-2.5 text-left text-sm text-primary-500 transition hover:bg-tertiary-50 focus:bg-secondary-100 focus:outline-none"
        >
          <span>{ingredient.name}</span><span class="shrink-0 text-xs text-primary-400">{ingredient.base_unit}</span>
        </button>
        <p :if={@match_count == 0} class="px-3 py-3 text-sm text-primary-400" role="status">
          Žádná surovina nenalezena. Zkuste jiný název nebo založte novou surovinu dole ve formuláři.
        </p>
        <p
          :if={@match_count > 8}
          class="border-t border-secondary-200 px-3 py-2 text-xs text-primary-400"
          role="status"
        >
          Zobrazeno 8 z {@match_count} surovin. Upřesněte název.
        </p>
      </div>
      <div hidden>
        <.input field={@field} type="select" options={@options} prompt="Vyberte surovinu" />
      </div>
      <p
        :if={@field.errors != []}
        id={"#{@field.id}-error"}
        role="alert"
        class="mt-1 text-sm text-red-700"
      >
        {if @field.value in [nil, ""],
          do: "Vyberte surovinu z nabídky.",
          else: Enum.map_join(@field.errors, " ", &translate_error/1)}
      </p>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: ""
  attr :back, :string, default: nil
  attr :back_label, :string, default: "Zpět"
  slot :actions

  def kitchen_header(assigns) do
    ~H"""
    <header class="mb-7">
      <.link
        :if={@back}
        id="food-back"
        navigate={@back}
        class="mb-4 inline-flex items-center gap-2 text-sm text-tertiary-600 hover:underline"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" />{@back_label}
      </.link>
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-3xl font-bold text-primary-500">{@title}</h1>
          <p :if={@subtitle != ""} class="mt-3 max-w-2xl text-sm leading-relaxed text-primary-400">
            {@subtitle}
          </p>
        </div>
        <div :if={@actions != []} class="flex flex-wrap items-center gap-3">
          {render_slot(@actions)}
        </div>
      </div>
    </header>
    """
  end

  attr :result, :map, required: true
  attr :id, :string, default: "consumption"

  def consumption_table(assigns) do
    ~H"""
    <section
      id={@id}
      class="overflow-hidden rounded-lg border border-secondary-200 bg-white shadow-sm"
    >
      <div class="flex flex-wrap items-center justify-between gap-4 border-b border-secondary-200 p-5">
        <div>
          <h2 class="font-bold text-primary-500">Potřebné suroviny</h2><p class="mt-1 text-sm text-primary-400">
            {@result.actual} porcí pro výdej · přepočet {Decimal.to_string(
              Decimal.normalize(@result.effective),
              :normal
            )} dospělých porcí
          </p>
        </div>
        <span class="rounded-full bg-secondary-50 px-3 py-1 text-xs font-semibold text-tertiary-600">Dětská porce {Decimal.to_string(
          Decimal.mult(@result.factor, 100),
          :normal
        )} %</span>
      </div>
      <div
        :if={@result.issues != []}
        id={"#{@id}-warnings"}
        class="border-b border-amber-100 bg-amber-50 p-5 text-sm text-amber-900"
      >
        <p class="font-bold">Výpočet není úplný</p><p :for={issue <- @result.issues} class="mt-1">
          {issue}
        </p>
      </div>
      <table class="w-full text-left text-sm">
        <thead class="bg-secondary-50 text-xs uppercase tracking-wide text-primary-400">
          <tr>
            <th class="px-5 py-3">Surovina</th><th class="px-5 py-3 text-right">Množství</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-secondary-200">
          <tr
            :for={row <- @result.quantities}
            id={"#{@id}-#{row.id}"}
            class="transition hover:bg-secondary-50"
          >
            <td class="px-5 py-3.5 font-medium text-primary-500">{row.ingredient.name}</td><td class="px-5 py-3.5 text-right font-semibold tabular-nums text-primary-500">
              {CozyCheckout.Recipes.format_quantity(row.quantity, row.unit)}
            </td>
          </tr>
        </tbody>
      </table>
      <p class="border-t border-secondary-200 px-5 py-4 text-xs leading-relaxed text-primary-400">
        Množství vychází z aktuálních receptur. Výpočet je bez nákupních balení a rezervy; zobrazení je zaokrouhlené, výpočet používá přesné hodnoty.
      </p>
    </section>
    """
  end
end

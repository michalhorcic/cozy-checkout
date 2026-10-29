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
  attr :required, :boolean, default: true
  attr :focus_id, :string, default: nil

  def ingredient_picker(assigns) do
    options =
      assigns.ingredients
      |> Enum.reject(&(&1.archived_at && &1.id != to_string(assigns.field.value)))
      |> Enum.map(fn ingredient ->
        %{
          id: ingredient.id,
          name: ingredient.name,
          hint: ingredient.base_unit,
          search_text:
            Enum.join([ingredient.name, ingredient.category, ingredient.notes || ""], " ")
        }
      end)

    error_message =
      if assigns.field.errors != [] do
        if assigns.field.value in [nil, ""],
          do: "Vyberte surovinu z nabídky.",
          else: Enum.map_join(assigns.field.errors, " ", &translate_error/1)
      end

    assigns = assigns |> assign(:options, options) |> assign(:error_message, error_message)

    ~H"""
    <.searchable_picker
      field={@field}
      options={@options}
      index={@index}
      query={@query}
      open={@open}
      required={@required}
      focus_id={@focus_id || @field.form[:quantity].id}
      label="Surovina"
      placeholder="Hledat podle názvu, kategorie nebo poznámky…"
      search_name="ingredient_search"
      search_event="search_ingredients"
      open_event="open_ingredient_search"
      close_event="close_ingredient_search"
      select_event="select_ingredient"
      prompt="Vyberte surovinu"
      count_label="surovin"
      empty_message="Žádná surovina nenalezena. Zkuste jiný název nebo založte novou surovinu."
      error_message={@error_message}
    />
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :options, :list, required: true
  attr :index, :string, default: "0"
  attr :query, :string, default: nil
  attr :open, :boolean, default: false
  attr :required, :boolean, default: true
  attr :focus_id, :string, default: nil
  attr :label, :string, required: true
  attr :placeholder, :string, default: "Hledat podle názvu…"
  attr :prompt, :string, default: "Vyberte položku"
  attr :empty_message, :string, default: "Žádná položka nenalezena. Zkuste jiný název."
  attr :count_label, :string, default: "položek"
  attr :error_message, :string, default: nil
  attr :search_name, :string, required: true
  attr :search_event, :string, required: true
  attr :open_event, :string, required: true
  attr :close_event, :string, required: true
  attr :select_event, :string, required: true

  @doc "Searchable options with id, name and hint; optional search_text includes extra keywords."
  def searchable_picker(assigns) do
    selected = Enum.find(assigns.options, &(&1.id == to_string(assigns.field.value)))
    query = assigns.query || if(selected, do: selected.name, else: "")
    search = if selected && query == selected.name, do: "", else: query
    words = search |> CozyCheckout.Recipes.normalize() |> String.split()

    matches =
      Enum.filter(assigns.options, fn option ->
        text = CozyCheckout.Recipes.normalize(Map.get(option, :search_text, option.name))
        Enum.all?(words, &String.contains?(text, &1))
      end)

    assigns =
      assigns
      |> assign(:query, query)
      |> assign(:matches, Enum.take(matches, 8))
      |> assign(:match_count, length(matches))

    ~H"""
    <div
      id={"#{@field.id}-picker"}
      class="relative min-w-0"
      phx-click-away={@open && @close_event}
    >
      <.input
        id={"#{@field.id}-search"}
        name={"#{@search_name}[#{@index}]"}
        type="search"
        value={@query}
        label={@label}
        placeholder={@placeholder}
        autocomplete="off"
        phx-change={@search_event}
        phx-debounce="150"
        phx-focus={@open_event}
        phx-value-index={@index}
        phx-keydown={@close_event}
        phx-key="Escape"
        aria-controls={"#{@field.id}-options"}
        aria-expanded={to_string(@open)}
        aria-invalid={to_string(not is_nil(@error_message))}
        aria-describedby={not is_nil(@error_message) && "#{@field.id}-error"}
        class={field_class()}
        required={@required}
      />
      <div
        :if={@open}
        id={"#{@field.id}-options"}
        class="absolute left-0 right-0 z-30 max-h-72 overflow-y-auto overscroll-contain rounded-lg border border-secondary-200 bg-white p-1 shadow-xl"
        aria-label={@label}
      >
        <button
          :for={option <- @matches}
          id={"#{@field.id}-option-#{option.id}"}
          type="button"
          phx-click={picker_select(@select_event, @focus_id)}
          phx-value-index={@index}
          phx-value-id={option.id}
          class="flex w-full items-center justify-between gap-3 rounded-lg px-3 py-2.5 text-left text-sm text-primary-500 transition hover:bg-tertiary-50 focus:bg-secondary-100 focus:outline-none"
        >
          <span>{option.name}</span><span class="shrink-0 text-xs text-primary-400">{option.hint}</span>
        </button>
        <p :if={@match_count == 0} class="px-3 py-3 text-sm text-primary-400" role="status">
          {@empty_message}
        </p>
        <p
          :if={@match_count > 8}
          class="border-t border-secondary-200 px-3 py-2 text-xs text-primary-400"
          role="status"
        >
          Zobrazeno 8 z {@match_count} {@count_label}. Upřesněte název.
        </p>
      </div>
      <div hidden>
        <.input
          field={@field}
          type="select"
          options={Enum.map(@options, &{&1.name, &1.id})}
          prompt={@prompt}
        />
      </div>
      <p
        :if={not is_nil(@error_message)}
        id={"#{@field.id}-error"}
        role="alert"
        class="mt-1 text-sm text-red-700"
      >
        {@error_message}
      </p>
    </div>
    """
  end

  defp picker_select(event, nil), do: JS.push(event)
  defp picker_select(event, focus_id), do: JS.push(event) |> JS.focus(to: "##{focus_id}")

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

  attr :items, :list, required: true
  attr :title, :string, default: "V mrazáku"
  attr :context, :map, default: %{}

  def freezer_notice(assigns) do
    ~H"""
    <details
      :if={@items != []}
      class="my-2 rounded-lg border border-secondary-200 bg-secondary-50 p-3 text-xs print:hidden"
      data-freezer-notice
    >
      <summary class="cursor-pointer font-semibold">{@title} ({length(@items)})</summary>
      <p class="my-2">
        Aktuální stav, informativní; nákupní množství se nemění. Zásoby nejsou rezervované.
      </p>
      <ul class="space-y-1">
        <li :for={item <- @items}>
          {item.name} · {CozyCheckout.Recipes.format_quantity(item.quantity, item.unit)} · zamrazeno {Calendar.strftime(
            item.frozen_on,
            "%d. %m. %Y"
          )} · {Date.diff(CozyCheckout.Kitchen.Freezer.today(), item.frozen_on)} dní
          <span :if={item.location}> · {item.location}</span>
          <span :if={
            (item.ingredient && item.ingredient.archived_at) ||
              (item.recipe && item.recipe.archived_at)
          }> · vazba archivována</span>
        </li>
      </ul>
      <.link
        navigate={CozyCheckoutWeb.FoodNavigation.path(:freezer, @context)}
        class="mt-2 inline-block underline"
      >Otevřít mrazák</.link>
    </details>
    """
  end
end

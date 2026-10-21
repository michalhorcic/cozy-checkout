defmodule CozyCheckoutWeb.KitchenComponents do
  use CozyCheckoutWeb, :html

  def field_class,
    do:
      "block w-full rounded-xl border border-slate-300 bg-white px-3 py-2.5 text-sm text-slate-900 shadow-sm outline-none transition focus:border-emerald-500 focus:ring-4 focus:ring-emerald-50"

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
        class="absolute left-0 right-0 z-30 max-h-72 overflow-y-auto overscroll-contain rounded-xl border border-slate-200 bg-white p-1 shadow-xl"
        aria-label="Nalezené suroviny"
      >
        <button
          :for={ingredient <- @matches}
          id={"#{@field.id}-option-#{ingredient.id}"}
          type="button"
          phx-click={JS.push("select_ingredient") |> JS.focus(to: "##{@field.form[:quantity].id}")}
          phx-value-index={@index}
          phx-value-id={ingredient.id}
          class="flex w-full items-center justify-between gap-3 rounded-lg px-3 py-2.5 text-left text-sm text-slate-800 transition hover:bg-emerald-50 focus:bg-emerald-100 focus:outline-none"
        >
          <span>{ingredient.name}</span><span class="shrink-0 text-xs text-slate-500">{ingredient.base_unit}</span>
        </button>
        <p :if={@match_count == 0} class="px-3 py-3 text-sm text-slate-500" role="status">
          Žádná surovina nenalezena. Zkuste jiný název nebo založte novou surovinu dole ve formuláři.
        </p>
        <p
          :if={@match_count > 8}
          class="border-t border-slate-100 px-3 py-2 text-xs text-slate-500"
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
  attr :active, :string, default: "recipes"
  slot :actions

  def kitchen_header(assigns) do
    ~H"""
    <div class="mb-8">
      <.link
        navigate={~p"/admin/meal-planner"}
        class="inline-flex items-center gap-2 text-sm font-medium text-slate-500 hover:text-emerald-700"
      ><.icon name="hero-arrow-left" class="h-4 w-4" />Plánovač jídel</.link>
      <div class="mt-5 flex flex-wrap items-end justify-between gap-5">
        <div>
          <p class="text-xs font-bold uppercase tracking-[0.2em] text-emerald-700">
            Kuchyně Jindřichova domu
          </p><h1 class="mt-2 text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">
            {@title}
          </h1><p class="mt-3 max-w-2xl text-slate-500">{@subtitle}</p>
        </div>
        <div class="flex items-center gap-3">{render_slot(@actions)}</div>
      </div>
      <nav class="mt-7 flex flex-wrap gap-2 border-b border-slate-200 pb-3" aria-label="Kuchyně">
        <.link
          id="kitchen-shopping"
          navigate={~p"/admin/kitchen-shopping"}
          class={[
            "rounded-xl px-4 py-2 text-sm font-semibold transition",
            if(@active == "shopping",
              do: "bg-emerald-100 text-emerald-800",
              else: "text-slate-500 hover:bg-white"
            )
          ]}
        >Nákup</.link>
        <.link
          id="kitchen-recipes"
          navigate={~p"/admin/recipes"}
          class={[
            "rounded-xl px-4 py-2 text-sm font-semibold transition",
            if(@active == "recipes",
              do: "bg-emerald-100 text-emerald-800",
              else: "text-slate-500 hover:bg-white"
            )
          ]}
        >Recepty</.link>
        <.link
          id="kitchen-ingredients"
          navigate={~p"/admin/ingredients"}
          class={[
            "rounded-xl px-4 py-2 text-sm font-semibold transition",
            if(@active == "ingredients",
              do: "bg-emerald-100 text-emerald-800",
              else: "text-slate-500 hover:bg-white"
            )
          ]}
        >Suroviny</.link>
        <.link
          navigate={~p"/admin/meal-planner/variants"}
          class="rounded-xl px-4 py-2 text-sm font-semibold text-slate-500 transition hover:bg-white"
        >Varianty menu</.link>
      </nav>
    </div>
    """
  end

  attr :result, :map, required: true
  attr :id, :string, default: "consumption"

  def consumption_table(assigns) do
    ~H"""
    <section id={@id} class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
      <div class="flex flex-wrap items-center justify-between gap-4 border-b border-slate-100 p-5">
        <div>
          <h2 class="font-bold text-slate-900">Potřebné suroviny</h2><p class="mt-1 text-sm text-slate-500">
            {@result.actual} porcí pro výdej · přepočet {Decimal.to_string(
              Decimal.normalize(@result.effective),
              :normal
            )} dospělých porcí
          </p>
        </div>
        <span class="rounded-full bg-emerald-50 px-3 py-1 text-xs font-semibold text-emerald-700">Dětská porce {Decimal.to_string(
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
        <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
          <tr>
            <th class="px-5 py-3">Surovina</th><th class="px-5 py-3 text-right">Množství</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr
            :for={row <- @result.quantities}
            id={"#{@id}-#{row.id}"}
            class="transition hover:bg-slate-50"
          >
            <td class="px-5 py-3.5 font-medium text-slate-800">{row.ingredient.name}</td><td class="px-5 py-3.5 text-right font-semibold tabular-nums text-slate-900">
              {CozyCheckout.Recipes.format_quantity(row.quantity, row.unit)}
            </td>
          </tr>
        </tbody>
      </table>
      <p class="border-t border-slate-100 px-5 py-4 text-xs leading-relaxed text-slate-500">
        Množství vychází z aktuálních receptur. Výpočet je bez nákupních balení a rezervy; zobrazení je zaokrouhlené, výpočet používá přesné hodnoty.
      </p>
    </section>
    """
  end
end

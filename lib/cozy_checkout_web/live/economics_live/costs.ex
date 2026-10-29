defmodule CozyCheckoutWeb.EconomicsLive.Costs do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.Economics
  alias CozyCheckoutWeb.EconomicsLive.CostMappingComponents
  alias CozyCheckout.Economics.{CostMapping, CostRule, CostOverride}
  import CozyCheckoutWeb.EconomicsLive.Components
  import CozyCheckoutWeb.EconomicsLive.CostMappingComponents, only: [mapping_tables: 1]
  import CozyCheckoutWeb.KitchenComponents, only: [searchable_picker: 1]

  @behaviors [
    {"Fixní", "fixed"},
    {"Variabilní", "variable"},
    {"Smíšené", "mixed"},
    {"Nezařazené", "unclassified"}
  ]

  @impl true
  def mount(_, _, socket) do
    if Economics.enabled?(),
      do: {:ok, assign(socket, page_title: "Nákladovost")},
      else: {:ok, redirect(socket, to: ~p"/admin")}
  end

  @impl true
  def handle_params(params, _, socket) do
    if socket.assigns[:data] &&
         Map.drop(socket.assigns.params, ["tab"]) == Map.drop(params, ["tab"]) do
      {:noreply, assign(socket, params: params, tab: params["tab"] || "overview")}
    else
      {:noreply, load(socket, params)}
    end
  end

  defp load(socket, params) do
    case Economics.costs(params) do
      {:ok, data} ->
        accounts =
          Enum.map(
            data.accounts,
            &%{id: &1["account"], name: "#{&1["account"]} · #{&1["name"]}", hint: &1["category"]}
          )

        partners = CostMappingComponents.partner_options(data.classification_months, data.rules)

        accounts =
          (accounts ++
             Enum.map(
               data.rules,
               &%{id: &1.account, name: &1.account, hint: "Pravidlo mimo tento snapshot"}
             ))
          |> Enum.uniq_by(& &1.id)

        editable =
          data.snapshot.active and version_id(data.version) == version_id(data.active_version)

        socket
        |> assign(
          data: data,
          error: nil,
          params: params,
          tab: params["tab"] || "overview",
          draft_rules: Enum.map(data.rules, &CostMapping.rule_attrs/1),
          draft_overrides: Enum.map(data.overrides, &CostMapping.override_attrs/1),
          draft_base: %{source_id: data.source.id, version_id: version_id(data.active_version)},
          draft_items: data.items,
          mapping_query: "",
          mapping_page: 1,
          entries_query: "",
          expanded_entries: MapSet.new(),
          mapping_catalog:
            CostMappingComponents.catalog(data.classification_months, data.accounts),
          editable: editable,
          preview: nil,
          accounts: accounts,
          partners: partners,
          picker_queries: %{},
          picker_open: nil,
          note: "",
          filter: "all",
          page: 1,
          range_queries: %{},
          range_open: nil,
          behaviors: @behaviors,
          suggestions: CostMapping.suggestions(data.snapshot.payload["months"]),
          range:
            to_form(
              %{
                "snapshot" => data.snapshot.id,
                "version" => version_id(data.version) || "none",
                "from" => data.report.from,
                "to" => data.report.to
              },
              as: :range
            )
        )
        |> reset_editor()

      {:error, reason} ->
        assign(socket, data: nil, error: reason, params: params, tab: "overview")
    end
  end

  @impl true
  def handle_event("range", %{"range" => range}, socket) do
    changed = range["snapshot"] != socket.assigns.data.snapshot.id
    params = range |> Map.reject(fn {_, v} -> v == "" end)
    params = if changed, do: Map.drop(params, ["from", "to"]), else: params
    {:noreply, push_patch(socket, to: ~p"/admin/economics/costs?#{params}")}
  end

  def handle_event("filter-items", %{"filter" => filter}, socket),
    do: {:noreply, assign(socket, filter: filter, page: 1)}

  def handle_event("page", %{"direction" => direction}, socket) do
    delta = if direction == "next", do: 1, else: -1

    {:noreply,
     assign(socket,
       page:
         max(
           1,
           min(
             pages(socket.assigns.data.items, socket.assigns.filter),
             socket.assigns.page + delta
           )
         )
     )}
  end

  def handle_event("range-search", params, socket) do
    {:noreply,
     assign(socket,
       range_queries: Map.merge(socket.assigns.range_queries, params["range_query"] || %{}),
       range_open: List.last(params["_target"] || []),
       range: to_form(Map.merge(socket.assigns.range.params, params["range"] || %{}), as: :range)
     )}
  end

  def handle_event("range-open", %{"index" => index}, socket),
    do: {:noreply, assign(socket, range_open: index)}

  def handle_event("range-close", _, socket), do: {:noreply, assign(socket, range_open: nil)}

  def handle_event("range-select", %{"index" => index, "id" => id}, socket)
      when index in ["snapshot", "version"] do
    if Enum.any?(range_options(socket.assigns.data, index), &(&1.id == id)) do
      {:noreply,
       assign(socket,
         range: to_form(Map.put(socket.assigns.range.params, index, id), as: :range),
         range_open: nil,
         range_queries: Map.delete(socket.assigns.range_queries, index)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("entries-search", %{"entries_search" => %{"query" => query}}, socket) do
    {:noreply, assign(socket, entries_query: query)}
  end

  def handle_event("entry-detail", %{"kind" => kind, "index" => index}, socket)
      when kind in ["rule", "override"] do
    rows = if kind == "rule", do: socket.assigns.draft_rules, else: socket.assigns.draft_overrides

    if at(rows, index) do
      key = "#{kind}-#{index}"
      expanded = socket.assigns.expanded_entries

      expanded =
        if MapSet.member?(expanded, key),
          do: MapSet.delete(expanded, key),
          else: MapSet.put(expanded, key)

      {:noreply, assign(socket, expanded_entries: expanded)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reload", _, socket), do: {:noreply, load(socket, socket.assigns.params)}

  # The normal admin on_mount authenticates every event; these guards additionally
  # prevent publishing from disabled reporting or a historical view.
  def handle_event(event, params, socket) do
    if Economics.enabled?() and socket.assigns[:editable],
      do: edit_event(event, params, socket),
      else:
        {:noreply,
         put_flash(socket, :error, "Úpravy jsou dostupné v aktuálním snapshotu a aktivní verzi.")}
  end

  defp edit_event("mapping-search", %{"mapping_search" => %{"query" => query}}, socket) do
    {:noreply, assign(socket, mapping_query: query, mapping_page: 1)}
  end

  defp edit_event("mapping-page", %{"direction" => direction}, socket) do
    delta = if direction == "next", do: 1, else: -1
    pages = mapping_pages(socket.assigns.draft_items, socket.assigns.mapping_query)

    {:noreply,
     assign(socket, mapping_page: max(1, min(pages, socket.assigns.mapping_page + delta)))}
  end

  defp edit_event("editor-change", %{"editor" => attrs}, socket) do
    {:noreply, update_editor(socket, attrs)}
  end

  defp edit_event("picker-search", params, socket) do
    queries = params["picker_query"] || %{}
    socket = update_editor(socket, params["editor"] || %{})

    {:noreply,
     assign(socket,
       picker_queries: Map.merge(socket.assigns.picker_queries, queries),
       picker_open: (params["_target"] || []) |> List.last()
     )}
  end

  defp edit_event("picker-open", %{"index" => index}, socket),
    do: {:noreply, assign(socket, picker_open: index)}

  defp edit_event("picker-close", _, socket), do: {:noreply, assign(socket, picker_open: nil)}

  defp edit_event("picker-select", %{"index" => index, "id" => id}, socket)
       when index in ["account", "partner_choice"] do
    options = if index == "account", do: socket.assigns.accounts, else: socket.assigns.partners

    if Enum.any?(options, &(&1.id == id)) do
      {:noreply,
       socket
       |> update_editor(%{index => id})
       |> assign(
         picker_open: nil,
         picker_queries: Map.delete(socket.assigns.picker_queries, index)
       )}
    else
      {:noreply, socket}
    end
  end

  defp edit_event("clear-partner", _, socket),
    do:
      {:noreply,
       socket |> update_editor(%{"partner_choice" => ""}) |> assign(picker_queries: %{})}

  defp edit_event("new-rule", _, socket), do: {:noreply, reset_editor(socket)}

  defp edit_event("from-item", %{"index" => index, "kind" => kind}, socket)
       when kind in ["rule", "override"] do
    case at(socket.assigns.data.items, index) do
      nil ->
        {:noreply, socket}

      item ->
        existing =
          if kind == "override",
            do:
              Enum.find_index(socket.assigns.draft_overrides, fn o ->
                {o["module"], o["document_id"], o["account"], o["month"]} == item.key
              end)

        attrs = %{
          "account" => item.account,
          "module" => item.module,
          "document_id" => item.document_id,
          "month" => item.month,
          "fingerprint" => item.fingerprint,
          "valid_from" => String.slice(item.month, 0, 7),
          "valid_to" => "",
          "partner_choice" => "",
          "description_contains" => "",
          "behavior" => "unclassified",
          "extraordinary" => false,
          "fixed_percent" => "",
          "reason" => ""
        }

        {:noreply,
         assign(socket,
           tab: "mapping",
           edit_kind: kind,
           edit_index: existing,
           editor: to_form(attrs, as: :editor),
           mapping_item: item,
           picker_queries: %{},
           picker_open: nil,
           preview: nil
         )}
    end
  end

  defp edit_event("edit-entry", %{"kind" => kind, "index" => index}, socket)
       when kind in ["rule", "override"] do
    rows = if kind == "rule", do: socket.assigns.draft_rules, else: socket.assigns.draft_overrides

    case at(rows, index) do
      nil ->
        {:noreply, socket}

      attrs ->
        attrs =
          attrs
          |> Map.update("valid_from", "", &month_input/1)
          |> Map.update("valid_to", "", &month_input/1)
          |> then(&Map.put(&1, "partner_choice", CostMappingComponents.partner_choice(&1)))

        {:noreply,
         assign(socket,
           tab: "mapping",
           edit_kind: kind,
           edit_index: String.to_integer(index),
           editor: to_form(attrs, as: :editor),
           mapping_item: nil,
           picker_queries: %{},
           picker_open: nil,
           preview: nil
         )}
    end
  end

  defp edit_event("remove-entry", %{"kind" => kind, "index" => index}, socket)
       when kind in ["rule", "override"] do
    key = if kind == "rule", do: :draft_rules, else: :draft_overrides
    rows = socket.assigns[key]

    if at(rows, index) do
      {:noreply,
       socket
       |> assign(key, List.delete_at(rows, String.to_integer(index)))
       |> assign(preview: nil)
       |> refresh_draft_items()
       |> reset_editor()}
    else
      {:noreply, socket}
    end
  end

  defp edit_event("save-entry", %{"editor" => attrs}, socket) do
    socket = update_editor(socket, attrs)
    attrs = socket.assigns.editor.params
    kind = socket.assigns.edit_kind

    attrs =
      attrs
      |> Map.update("valid_from", nil, &month_date/1)
      |> Map.update("valid_to", nil, &month_date/1)

    schema = if kind == "rule", do: CostRule, else: CostOverride

    result =
      with {:ok, partner_attrs} <-
             editor_partner_attrs(kind, attrs["partner_choice"], socket.assigns.partners) do
        schema.changeset(struct(schema), Map.merge(attrs, partner_attrs))
        |> Ecto.Changeset.apply_action(:insert)
      end

    case result do
      {:ok, entry} ->
        key = if kind == "rule", do: :draft_rules, else: :draft_overrides

        attrs =
          if kind == "rule",
            do: CostMapping.rule_attrs(entry),
            else: CostMapping.override_attrs(entry)

        rows = socket.assigns[key]

        rows =
          if is_nil(socket.assigns.edit_index),
            do: rows ++ [attrs],
            else: List.replace_at(rows, socket.assigns.edit_index, attrs)

        {:noreply,
         socket
         |> assign(key, rows)
         |> assign(preview: nil)
         |> refresh_draft_items()
         |> reset_editor()
         |> put_flash(
           :info,
           "Položka přidána do návrhu. Pro použití zobrazte náhled a publikujte verzi."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, mapping_error(reason))}
    end
  end

  defp edit_event("suggestions", _, socket) do
    rules =
      Enum.reduce(socket.assigns.suggestions, socket.assigns.draft_rules, fn suggestion, rules ->
        if Enum.any?(rules, &(&1["account"] == suggestion["account"])),
          do: rules,
          else: rules ++ [suggestion]
      end)

    {:noreply, socket |> assign(draft_rules: rules, preview: nil) |> refresh_draft_items()}
  end

  defp edit_event("preview", %{"publication" => %{"note" => note}}, socket) do
    case Economics.preview_cost_mapping(
           socket.assigns.draft_rules,
           socket.assigns.draft_overrides,
           note,
           socket.assigns.draft_base
         ) do
      {:ok, preview} ->
        {:noreply, assign(socket, preview: preview, note: note)}

      {:error, reason} ->
        {:noreply,
         socket |> assign(preview: nil, note: note) |> put_flash(:error, mapping_error(reason))}
    end
  end

  defp edit_event("publish", _, socket) do
    case socket.assigns.preview && Economics.publish_cost_mapping(socket.assigns.preview.token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load(Map.drop(socket.assigns.params, ["version"]))
         |> put_flash(:info, "Nová verze mapování byla publikována.")}

      _ ->
        {:noreply,
         socket |> assign(preview: nil) |> put_flash(:error, mapping_error(:stale_preview))}
    end
  end

  defp edit_event(_, _, socket), do: {:noreply, socket}

  defp reset_editor(socket) do
    first = socket.assigns.data.report.from

    assign(socket,
      edit_kind: "rule",
      edit_index: nil,
      mapping_item: nil,
      picker_queries: %{},
      picker_open: nil,
      editor:
        to_form(
          %{
            "account" => "",
            "partner_choice" => "",
            "description_contains" => "",
            "valid_from" => first,
            "valid_to" => "",
            "behavior" => "unclassified",
            "extraordinary" => false,
            "fixed_percent" => "",
            "reason" => ""
          },
          as: :editor
        )
    )
  end

  defp refresh_draft_items(socket) do
    {:ok, items} =
      Economics.cost_draft_items(
        socket.assigns.data,
        socket.assigns.draft_rules,
        socket.assigns.draft_overrides
      )

    page = min(socket.assigns.mapping_page, mapping_pages(items, socket.assigns.mapping_query))
    assign(socket, draft_items: items, mapping_page: page, expanded_entries: MapSet.new())
  end

  defp mapping_items(items, query) do
    words = query |> String.downcase() |> String.split()

    items
    |> Enum.with_index()
    |> Enum.filter(fn {item, _} ->
      text =
        ([item.account, item.name, item.module, item.document_id, item.month] ++
           Enum.flat_map(item.rows, fn row ->
             info = row["identification"] || %{}

             Enum.map(
               [
                 "company",
                 "document_number",
                 "description",
                 "variable_symbol",
                 "supplier_number"
               ],
               &info[&1]
             )
           end))
        |> Enum.join(" ")
        |> String.downcase()

      item.status != :classified and Enum.all?(words, &String.contains?(text, &1))
    end)
  end

  defp mapping_pages(items, query), do: max(1, div(length(mapping_items(items, query)) + 19, 20))

  defp mapping_page_items(items, query, page),
    do: items |> mapping_items(query) |> Enum.slice((page - 1) * 20, 20)

  defp editor_partner_attrs("override", _, _), do: {:ok, %{}}

  defp editor_partner_attrs("rule", choice, _) when choice in [nil, ""],
    do: {:ok, %{"partner_id" => nil, "partner_name" => nil}}

  defp editor_partner_attrs("rule", choice, options) do
    case Enum.find(options, &(&1.id == choice)) do
      nil -> {:error, :invalid_partner}
      %{partner_name: nil} = option -> {:ok, %{"partner_id" => option.id, "partner_name" => nil}}
      option -> {:ok, %{"partner_id" => nil, "partner_name" => option.partner_name}}
    end
  end

  defp update_editor(socket, attrs) do
    # Identity of an exception comes exclusively from the chosen local bundle.
    allowed =
      ~w(account partner_choice description_contains valid_from valid_to behavior extraordinary fixed_percent reason)

    allowed = if socket.assigns.edit_kind == "override", do: allowed -- ["account"], else: allowed
    values = Map.merge(socket.assigns.editor.params, Map.take(attrs, allowed))
    assign(socket, editor: to_form(values, as: :editor), preview: nil)
  end

  defp range_options(data, "snapshot"),
    do:
      Enum.map(
        data.snapshots,
        &%{
          id: &1.id,
          name:
            "#{&1.period_code} · #{if &1.active, do: "aktuální", else: "historický"} · #{&1.checked_at}",
          hint: ""
        }
      )

  defp range_options(data, "version"),
    do:
      [%{id: "", name: "Aktivní verze", hint: ""}, %{id: "none", name: "Bez pravidel", hint: ""}] ++
        Enum.map(
          data.versions,
          &%{id: &1.id, name: "v#{&1.number} · #{&1.published_at}", hint: &1.state}
        )

  defp visible_items(items, filter, page),
    do:
      items
      |> Enum.with_index()
      |> Enum.filter(fn {item, _} -> visible?(item, filter) end)
      |> Enum.slice((page - 1) * 50, 50)

  defp pages(items, filter), do: max(1, ceil(Enum.count(items, &visible?(&1, filter)) / 50))

  defp at(rows, index) do
    case Integer.parse(index) do
      {i, ""} when i >= 0 -> Enum.at(rows, i)
      _ -> nil
    end
  end

  defp month_input(nil), do: ""
  defp month_input(value), do: String.slice(value, 0, 7)
  defp month_date(value) when value in [nil, ""], do: nil
  defp month_date(value) when byte_size(value) == 7, do: value <> "-01"
  defp month_date(value), do: value
  defp version_id(nil), do: nil
  defp version_id(version), do: version.id
  defp amount(value), do: value |> Decimal.to_string(:normal) |> money()
  defp behavior("fixed"), do: "Fixní"
  defp behavior("variable"), do: "Variabilní"
  defp behavior("mixed"), do: "Smíšené"
  defp behavior(_), do: "Nezařazené"
  defp status(:conflict), do: "Konflikt mapování"
  defp status(:stale_override), do: "Změněný podklad · výjimka pozastavena"
  defp status(:moved_override), do: "Přesunutý podklad · výjimka pozastavena"
  defp status(:unclassified), do: "Nezařazeno"
  defp status(_), do: "Zařazeno"
  defp visible?(item, "extraordinary"), do: item.extraordinary
  defp visible?(item, "unresolved"), do: item.status != :classified
  defp visible?(item, "conflict"), do: item.status == :conflict
  defp visible?(item, "estimated"), do: item.estimated
  defp visible?(_, _), do: true

  defp validation_error(cs),
    do: cs.errors |> Enum.map_join("; ", fn {field, {message, _}} -> "#{field}: #{message}" end)

  defp mapping_error(%Ecto.Changeset{} = cs), do: validation_error(cs)

  defp mapping_error(:stale_preview),
    do: "Podklady nebo aktivní mapování se změnily. Obnovte přehled a připravte nový náhled."

  defp mapping_error(reason) when reason in [:invalid_partner, :invalid_partner_name],
    do: "Vyberte firmu z nabídky podle interního ID nebo přesného názvu dostupného v podkladech."

  defp mapping_error(:invalid_account), do: "Zvolte skutečný nákladový účet z načtených podkladů."

  defp mapping_error(:invalid_override),
    do: "Výjimka musí odkazovat na aktuální podklad tohoto zdroje. Znovu jej vyberte v přehledu."

  defp mapping_error(:duplicate_override),
    do: "Pro jeden podklad může být pouze jedna výjimka. Upravte existující výjimku."

  defp mapping_error(_), do: "Zkontrolujte návrh a vyplňte důvod publikace."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      content_class="mx-auto w-full max-w-7xl space-y-6"
      main_class="px-4 py-6 sm:px-6 lg:px-8"
    >
      <h1 class="text-3xl font-bold">Nákladovost</h1>
      <.navigation active="costs" />
      <p :if={@error} class="alert alert-warning">{error(@error)}</p>
      <div :if={@data} id="economics-costs" class="space-y-6">
        <p class="text-sm">
          Zaúčtované náklady MD − Dal. Místní snapshot {@data.snapshot.id} · mapování {if @data.version,
            do: "v#{@data.version.number}",
            else: "dosud bez pravidel"}. Nejde o platby ani smluvní měsíční základ.
        </p>
        <.form
          for={@range}
          id="cost-range"
          phx-submit="range"
          class="grid gap-3 sm:grid-cols-2 lg:grid-cols-5 items-end"
        >
          <div :for={
            {field, label} <- [
              {"snapshot", "Účetní období a snapshot"},
              {"version", "Verze mapování"}
            ]
          }>
            <.input
              :if={length(range_options(@data, field)) <= 30}
              field={@range[String.to_existing_atom(field)]}
              type="select"
              label={label}
              options={Enum.map(range_options(@data, field), &{&1.name, &1.id})}
            />
            <.searchable_picker
              :if={length(range_options(@data, field)) > 30}
              field={@range[String.to_existing_atom(field)]}
              options={range_options(@data, field)}
              index={field}
              label={label}
              query={@range_queries[field]}
              open={@range_open == field}
              search_name="range_query"
              search_event="range-search"
              open_event="range-open"
              close_event="range-close"
              select_event="range-select"
            />
          </div>
          <.input field={@range[:from]} type="month" label="Od měsíce" />
          <.input field={@range[:to]} type="month" label="Do měsíce" />
          <button class="btn btn-primary">Zobrazit</button>
        </.form>
        <p class="alert">
          Účetní úplnost: {Enum.map_join(
            @data.report.confirmations,
            ", ",
            &(String.slice(&1.month, 0, 7) <> if(&1.confirmed, do: " potvrzena", else: " neověřena"))
          )}. Manažerská pravidla účetní potvrzení nemění.
        </p>
        <div class="flex flex-wrap gap-2">
          <button phx-click="reload" class="btn btn-sm btn-outline">Obnovit přehled</button>
          <.link
            patch={~p"/admin/economics/costs?#{Map.put(@params, "tab", "overview")}"}
            class={["btn btn-sm", @tab == "overview" && "btn-primary"]}
          >Přehled nákladů</.link>
          <.link
            patch={~p"/admin/economics/costs?#{Map.put(@params, "tab", "mapping")}"}
            class={["btn btn-sm", @tab == "mapping" && "btn-primary"]}
          >Mapování</.link>
        </div>
        <section :if={@tab == "overview"} class="space-y-5">
          <div id="cost-totals" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <.metric
              :for={
                {key, label} <- [
                  fixed: "Fixní složka",
                  variable: "Variabilní složka",
                  mixed: "Smíšené bez rozdělení",
                  unclassified: "Nezařazené"
                ]
              }
              title={label}
              value={Decimal.to_string(@data.totals.display[key], :normal)}
              explanation="Součást zaúčtovaných nákladů"
            />
          </div>
          <p>
            Celkem <strong>{amount(@data.totals.total)}</strong>
            · Mimořádné {amount(@data.totals.extraordinary)} (podmnožina celku) · Podklady s ručním odhadem {amount(
              @data.totals.estimated
            )}.
          </p>
          <p>
            Nevyřešeno {@data.totals.unresolved_count} podkladů, absolutní objem {amount(
              @data.totals.unresolved_volume
            )}. Pokrytí dle absolutních částek: {if @data.totals.coverage,
              do: CozyCheckoutWeb.CurrencyHelper.format_number(@data.totals.coverage) <> " %",
              else: "nelze určit"}.
          </p>
          <div class="overflow-x-auto">
            <table id="cost-months" class="table">
              <thead>
                <tr>
                  <th>Měsíc</th><th>Fixní</th><th>Variabilní</th><th>Smíšené nerozdělené</th><th>
                    Nezařazené
                  </th><th>Celkem</th>
                </tr>
              </thead><tbody>
                <tr :for={month <- @data.monthly}>
                  <td>{String.slice(month.month, 0, 7)}</td>
                  <td :for={key <- [:fixed, :variable, :mixed, :unclassified]}>
                    {amount(month.totals.display[key])}
                  </td>
                  <td>{amount(month.totals.total)}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <section id="cost-categories" class="space-y-2">
            <h2 class="text-xl font-semibold">Kategorie a firmy</h2>
            <details :for={category <- @data.categories} class="rounded-xl border border-base-300 p-4">
              <summary class="cursor-pointer">
                {category.name} · {amount(category.totals.total)}
              </summary>
              <p :for={firm <- category.firms}>
                {firm.name} · {amount(firm.totals.total)} · {firm.count} podkladů
              </p>
              <p class="text-xs">Podklady bez stabilního ID firmy zůstávají oddělené.</p>
            </details>
          </section>
          <.form for={%{}} phx-change="filter-items" id="cost-filter">
            <.input
              type="select"
              name="filter"
              value={@filter}
              label="Zobrazit podklady"
              options={[
                {"Všechny", "all"},
                {"Mimořádné", "extraordinary"},
                {"Nevyřešené", "unresolved"},
                {"Konflikty", "conflict"},
                {"S odhadem", "estimated"}
              ]}
            />
          </.form>
          <div class="flex flex-wrap gap-3 items-center">
            <button
              phx-click="page"
              phx-value-direction="previous"
              disabled={@page <= 1}
              class="btn btn-sm"
            >Předchozí</button>
            <span>Strana {@page} / {pages(@data.items, @filter)}</span>
            <button
              phx-click="page"
              phx-value-direction="next"
              disabled={@page >= pages(@data.items, @filter)}
              class="btn btn-sm"
            >Další</button>
          </div>
          <div id="cost-documents" class="space-y-3">
            <details
              :for={{item, index} <- visible_items(@data.items, @filter, @page)}
              class="rounded-xl border border-base-300 p-4"
            >
              <summary class="cursor-pointer font-semibold">
                {item.month |> String.slice(0, 7)} · {item.category} · {item.account} · {(hd(
                                                                                            item.rows
                                                                                          )[
                                                                                            "identification"
                                                                                          ] || %{})[
                  "company"
                ] || "Firma neuvedena"} · {amount(item.amount)} · {behavior(item.behavior)} · {status(
                  item.status
                )}
              </summary>
              <div class="mt-4 space-y-3">
                <p :if={item.extraordinary} class="badge badge-warning">Mimořádné</p>
                <p :if={item.estimated} class="alert">
                  Ruční odhad: fixní {amount(Decimal.round(item.fixed, 2))}, variabilní {amount(
                    Decimal.sub(Decimal.round(item.amount, 2), Decimal.round(item.fixed, 2))
                  )}. Podíl {hd(item.matches).fixed_percent} %.
                </p>
                <p :if={item.noncash} class="alert">
                  Odpisy · nepeněžní náklad, nikoli aktuální platba.
                </p>
                <p>
                  Rozsah podkladu: {@data.source.id} / {item.module} / {item.document_id} / účet {item.account} / {item.month}. Obsahuje {length(
                    item.rows
                  )} účetních zápisů.
                </p>
                <p :for={match <- item.matches}>
                  Použité nebo konfliktní pravidlo/výjimka {match.id} · v{if @data.version,
                    do: @data.version.number} · {match.reason}
                </p>
                <div :for={row <- item.rows} class="border-t border-base-200 pt-2">
                  <.document_identity record={row} />
                  <p>
                    {row["date"]} · zápis {row["journal_id"]} · MD {money(row["md"])} · Dal {money(
                      row["dal"]
                    )}
                  </p>
                  <p
                    :if={get_in(row, ["identification", "description_truncated"])}
                    class="text-warning"
                  >
                    Popis byl zkrácen; textové pravidlo pracuje s uloženou částí.
                  </p>
                </div>
                <.link
                  navigate={
                    ~p"/admin/economics/accounts/#{item.account}?#{%{period: @data.snapshot.period_code, from: String.slice(item.month, 0, 7), to: String.slice(item.month, 0, 7)}}"
                  }
                  class="btn btn-sm btn-outline"
                >Účetní pohyby (aktuální snapshot)</.link>
                <button
                  :if={@editable}
                  phx-click="from-item"
                  phx-value-index={index}
                  phx-value-kind="override"
                  class="btn btn-sm"
                >Jen tento podklad / znovu potvrdit výjimku</button>
                <button
                  :if={@editable}
                  phx-click="from-item"
                  phx-value-index={index}
                  phx-value-kind="rule"
                  class="btn btn-sm"
                >Pravidlo pro další doklady</button>
              </div>
            </details>
          </div>
        </section>
        <section :if={@tab == "mapping"} class="space-y-5">
          <h2 class="text-xl font-semibold">Mapování · návrh úplné další verze</h2>
          <p :if={!@editable} class="alert">
            Historický pohled je pouze ke čtení. Pro úpravy vyberte aktuální snapshot a aktivní mapování.
          </p>
          <p>
            Pravidla se vyhodnocují podle přesnosti: výjimka, účet + firma + text, účet + firma, účet + text, účet. Rozdílné výsledky stejné přednosti zůstanou konfliktem. Změny návrhu jsou zatím jen v této otevřené stránce.
          </p>
          <p :if={@partners == []} class="alert">
            V načtených podkladech nejsou dostupné firmy pro výběr. Lze použít účet, text nebo výjimku.
          </p>
          <details
            :if={@editable && @suggestions != []}
            class="rounded-xl border border-base-300 p-4 space-y-2"
          >
            <summary class="cursor-pointer font-semibold">Pracovní návrhy pro běžné náklady</summary>
            <p :for={suggestion <- @suggestions}>
              {suggestion["account"]} · {behavior(suggestion["behavior"])} · {suggestion["reason"]}
            </p>
            <button id="cost-suggestions" phx-click="suggestions" class="btn btn-outline">Přidat návrhy pro účty bez pravidla</button>
            <p class="text-sm">Návrhy se aktivují teprve po náhledu a výslovném publikování.</p>
          </details>
          <div
            :if={@editable}
            id="cost-mapping-workbench"
            class="grid gap-5 lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)] items-start"
          >
            <aside
              class="min-w-0 rounded-xl border border-base-300 p-4 space-y-3"
              aria-label="Nevyřešené podklady k mapování"
            >
              <h3 class="text-lg font-semibold">Nevyřešené podklady</h3>
              <p id="cost-mapping-progress" role="status" aria-live="polite">
                Nevyřešené podklady podle návrhu: {Enum.count(
                  @draft_items,
                  &(&1.status != :classified)
                )}.
              </p>
              <p class="text-sm text-base-content/70">
                Po uložení zmizí všechny podklady vyřešené tímto návrhem. Další vyberte ručně. Aktivní verze se změní až publikací.
              </p>
              <.form
                for={to_form(%{"query" => @mapping_query}, as: :mapping_search)}
                id="cost-mapping-search"
                phx-change="mapping-search"
              >
                <.input
                  type="search"
                  name="mapping_search[query]"
                  value={@mapping_query}
                  label="Hledat firmu, doklad, účet nebo popis"
                  phx-debounce="200"
                />
              </.form>
              <div class="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  phx-click="mapping-page"
                  phx-value-direction="previous"
                  disabled={@mapping_page <= 1}
                  class="btn btn-sm"
                >Předchozí</button>
                <span>{@mapping_page} / {mapping_pages(@draft_items, @mapping_query)}</span>
                <button
                  type="button"
                  phx-click="mapping-page"
                  phx-value-direction="next"
                  disabled={@mapping_page >= mapping_pages(@draft_items, @mapping_query)}
                  class="btn btn-sm"
                >Další</button>
              </div>
              <div
                id="cost-mapping-queue"
                class="max-h-72 space-y-3 overflow-y-auto pr-1 sm:max-h-96 lg:max-h-[65vh]"
              >
                <article
                  :for={
                    {item, index} <- mapping_page_items(@draft_items, @mapping_query, @mapping_page)
                  }
                  id={"cost-mapping-item-#{index}"}
                  class={[
                    "rounded-lg border p-3 space-y-2",
                    if(@mapping_item && @mapping_item.key == item.key,
                      do: "border-primary bg-primary/5",
                      else: "border-base-300"
                    )
                  ]}
                >
                  <p class="font-semibold">
                    {(hd(item.rows)["identification"] || %{})["company"] || "Firma neuvedena"}
                  </p>
                  <p>
                    {(hd(item.rows)["identification"] || %{})["document_number"] ||
                      "#{item.module} / #{item.document_id}"}
                  </p>
                  <p class="text-sm">
                    {item.account} · {String.slice(item.month, 0, 7)} · {amount(item.amount)}
                  </p>
                  <p class="text-sm">{status(item.status)}</p>
                  <p :for={match <- item.matches} class="text-xs text-base-content/70">
                    {match.reason}
                  </p>
                  <div class="flex flex-wrap gap-2">
                    <button
                      type="button"
                      phx-click={JS.push("from-item") |> JS.focus(to: "#cost-mapping-editor")}
                      phx-value-index={index}
                      phx-value-kind="rule"
                      class="btn btn-sm"
                    >Pravidlo pro další doklady</button>
                    <button
                      type="button"
                      phx-click={JS.push("from-item") |> JS.focus(to: "#cost-mapping-editor")}
                      phx-value-index={index}
                      phx-value-kind="override"
                      class="btn btn-sm btn-outline"
                    >Jen tento podklad</button>
                  </div>
                </article>
                <p
                  :if={mapping_items(@draft_items, @mapping_query) == []}
                  id="cost-mapping-empty"
                  class="rounded-lg bg-base-200 p-4"
                >
                  {if Enum.any?(@draft_items, &(&1.status != :classified)),
                    do: "Hledání neodpovídá žádný nevyřešený podklad.",
                    else:
                      "Všechny podklady ve vybraném období jsou podle návrhu vyřešené. Můžete přejít k náhledu a publikaci."}
                </p>
              </div>
            </aside>
            <div
              id="cost-mapping-editor"
              tabindex="-1"
              class="min-w-0 rounded-xl border border-base-300 p-5 space-y-4 lg:sticky lg:top-4 lg:self-start"
            >
              <button phx-click="new-rule" class="btn btn-sm btn-outline">Nové pravidlo</button>
              <h3 class="font-semibold">
                {if @edit_kind == "override", do: "Výjimka pro celý podklad", else: "Pravidlo"}
              </h3>
              <p :if={@edit_kind == "override"}>
                {@editor.params["module"]} / {@editor.params["document_id"]} · účet {@editor.params[
                  "account"
                ]} · měsíc {@editor.params["month"]}. Platí pro všechny zápisy tohoto podkladu; finanční změna vyžádá novou kontrolu.
              </p>
              <div
                :if={@mapping_item}
                id="cost-mapping-selected"
                class="rounded-lg bg-base-200 p-3 space-y-3"
              >
                <p class="font-semibold">
                  Vybraný podklad · {@mapping_item.account} · {String.slice(@mapping_item.month, 0, 7)} · {amount(
                    @mapping_item.amount
                  )}
                </p>
                <div :for={row <- @mapping_item.rows}>
                  <.document_identity record={row} />
                  <p
                    :if={get_in(row, ["identification", "description_truncated"])}
                    class="text-sm text-warning"
                  >
                    Popis byl zkrácen.
                  </p>
                </div>
              </div>
              <.form
                for={@editor}
                id="cost-editor"
                phx-change="editor-change"
                phx-submit="save-entry"
                class="grid gap-4 sm:grid-cols-2"
              >
                <.searchable_picker
                  :if={@edit_kind == "rule"}
                  field={@editor[:account]}
                  options={@accounts}
                  index="account"
                  label="Přesný nákladový účet"
                  query={@picker_queries["account"]}
                  open={@picker_open == "account"}
                  search_name="picker_query"
                  search_event="picker-search"
                  open_event="picker-open"
                  close_event="picker-close"
                  select_event="picker-select"
                />
                <div :if={@edit_kind == "rule"}>
                  <.searchable_picker
                    field={@editor[:partner_choice]}
                    options={@partners}
                    index="partner_choice"
                    label="Firma podle ID nebo názvu (volitelné)"
                    required={false}
                    query={@picker_queries["partner_choice"]}
                    open={@picker_open == "partner_choice"}
                    search_name="picker_query"
                    search_event="picker-search"
                    open_event="picker-open"
                    close_event="picker-close"
                    select_event="picker-select"
                  />
                  <p
                    :if={String.starts_with?(@editor.params["partner_choice"] || "", "name-")}
                    class="mt-2 text-sm text-base-content/70"
                  >
                    Firma podle názvu: přesná shoda bez rozlišení velikosti písmen a okolních mezer, pouze pro doklady bez interního ID. Přejmenování vyžaduje kontrolu pravidla.
                  </p>
                  <button type="button" phx-click="clear-partner" class="btn btn-xs">Libovolná firma</button>
                </div>
                <.input
                  :if={@edit_kind == "rule"}
                  field={@editor[:description_contains]}
                  label="Popis obsahuje (bez rozlišení velikosti písmen)"
                  maxlength="500"
                />
                <.input
                  :if={@edit_kind == "rule"}
                  field={@editor[:valid_from]}
                  type="month"
                  label="Platnost od měsíce včetně"
                  required
                />
                <.input
                  :if={@edit_kind == "rule"}
                  field={@editor[:valid_to]}
                  type="month"
                  label="Platnost do měsíce včetně (volitelné)"
                />
                <.input
                  field={@editor[:behavior]}
                  type="select"
                  label="Chování nákladu"
                  options={@behaviors}
                />
                <.input
                  field={@editor[:extraordinary]}
                  type="checkbox"
                  label="Mimořádný náklad (samostatný příznak)"
                />
                <.input
                  field={@editor[:fixed_percent]}
                  type="number"
                  label="Ruční odhad fixního podílu % (jen smíšené; prázdné = nerozdělovat)"
                  min="0"
                  max="100"
                  step="0.000001"
                />
                <.input
                  field={@editor[:reason]}
                  type="textarea"
                  label="Důvod / podklad odhadu"
                  required
                  maxlength="1000"
                />
                <button type="submit" class="btn btn-primary sm:col-span-2">Uložit položku do návrhu</button>
              </.form>
            </div>
          </div>
          <details id="cost-mapping-entries" class="rounded-xl border border-base-300 p-4 space-y-3">
            <summary class="cursor-pointer font-semibold">
              {if @editable,
                do: "Pravidla a výjimky v návrhu",
                else: "Pravidla a výjimky ve vybrané verzi"} · {length(@draft_rules)} pravidel · {length(
                @draft_overrides
              )} výjimek
            </summary>
            <.mapping_tables
              rules={@draft_rules}
              overrides={@draft_overrides}
              catalog={@mapping_catalog}
              query={@entries_query}
              expanded={@expanded_entries}
              editable={@editable}
              source_id={@data.source.id}
            />
          </details>
          <div :if={@editable} class="rounded-xl border border-base-300 p-5 space-y-4">
            <.form
              for={to_form(%{"note" => @note}, as: :publication)}
              id="cost-preview-form"
              phx-submit="preview"
              class="space-y-3"
            >
              <.input
                name="publication[note]"
                value={@note}
                type="textarea"
                label="Důvod publikace nové verze"
                required
                maxlength="1000"
              />
              <button class="btn btn-primary" type="submit">Přepočítat náhled dopadu na všechna načtená období</button>
            </.form>
          </div>
          <section
            :if={@preview}
            id="cost-preview"
            class="rounded-xl border border-primary p-5 space-y-4"
          >
            <h3 class="text-lg font-semibold">Náhled nové verze</h3>
            <p>
              Publikace změní manažerský výklad uvedených historických období. Účetní částky zůstanou zachované. Důvod: {@note}
            </p>
            <div :for={impact <- @preview.impacts} class="space-y-3">
              <h4 class="font-semibold">
                {impact.period} · snapshot {impact.snapshot_id} · {length(impact.changed)} změněných podkladů · konflikty {impact.conflicts}
              </h4>
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Měsíc</th><th>Složka</th><th>Před</th><th>Po</th>
                    </tr>
                  </thead><tbody>
                    <tr :for={
                      row <-
                        for month <- impact.months,
                            key <- [:fixed, :variable, :mixed, :unclassified],
                            do: {month, key}
                    }>
                      <td>{elem(row, 0).month}</td><td>
                        {%{
                          fixed: "Fixní",
                          variable: "Variabilní",
                          mixed: "Smíšené nerozdělené",
                          unclassified: "Nezařazené"
                        }[elem(row, 1)]}
                      </td><td>{amount(elem(row, 0).before.display[elem(row, 1)])}</td><td>
                        {amount(elem(row, 0).after.display[elem(row, 1)])}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <details>
                <summary>Změněné podklady</summary><p :for={item <- impact.changed}>
                  {item.month} · {item.account} · {item.module} / {item.document_id} · {amount(
                    item.amount
                  )} · {behavior(item.behavior)} · {status(item.status)}
                </p>
              </details>
            </div>
            <button id="cost-publish" phx-click="publish" class="btn btn-primary">Publikovat tuto verzi mapování</button>
          </section>
          <section id="cost-history" class="space-y-2">
            <h3 class="font-semibold">Historie publikovaných verzí</h3>
            <p :for={version <- @data.versions}>
              v{version.number} · {version.published_at} UTC · {version.note} · {version.state}
            </p>
            <p>
              Historické verze vyberete nahoře spolu s původním snapshotem. Sdílený PIN neprokazuje identitu konkrétní osoby.
            </p>
          </section>
        </section>
      </div>
    </Layouts.app>
    """
  end
end

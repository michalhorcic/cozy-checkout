defmodule CozyCheckoutWeb.EconomicsLive.CostMappingComponents do
  use CozyCheckoutWeb, :html
  alias CozyCheckout.Economics.Costs
  alias CozyCheckoutWeb.CurrencyHelper

  @doc false
  def catalog(months, accounts) do
    bundles = Costs.bundles(months)

    account_names =
      Map.new(bundles, &{&1.account, &1.name})
      |> Map.merge(Map.new(accounts, &{&1["account"], &1["name"]}))

    partners =
      bundles
      |> Enum.flat_map(& &1.rows)
      |> Enum.reduce(%{}, fn row, acc ->
        info = row["identification"] || %{}

        if info["partner_id"] && info["company"],
          do: Map.put_new(acc, info["partner_id"], info["company"]),
          else: acc
      end)

    %{
      accounts: account_names,
      partners: partners,
      targets: Map.new(bundles, &{&1.key, &1}),
      documents: Enum.group_by(bundles, &{&1.module, &1.document_id})
    }
  end

  @doc false
  def entries(rules, overrides, catalog, query) do
    words = query |> String.downcase() |> String.split()

    rules =
      rules
      |> Enum.with_index()
      |> Enum.map(fn {rule, index} -> rule_row(rule, index, catalog) end)

    overrides =
      overrides
      |> Enum.with_index()
      |> Enum.map(fn {override, index} -> override_row(override, index, catalog) end)

    %{rules: filter_rows(rules, words), overrides: filter_rows(overrides, words)}
  end

  defp rule_row(rule, index, catalog) do
    firm =
      if rule["partner_id"],
        do: Map.get(catalog.partners, rule["partner_id"], "Název firmy není v podkladech"),
        else: "Všechny firmy"

    row(
      "rule",
      index,
      rule,
      [
        cell("Účet", rule["account"], catalog.accounts[rule["account"]]),
        cell("Firma", firm),
        cell("Popis obsahuje", rule["description_contains"] || "Bez omezení"),
        cell(
          "Platnost",
          "#{month(rule["valid_from"])} → #{if rule["valid_to"], do: month(rule["valid_to"]), else: "bez konce"}"
        ),
        behavior_cell(rule),
        split_cell(rule),
        extraordinary_cell(rule)
      ],
      [{"ID firmy", rule["partner_id"]}],
      {rule["account"], String.downcase(firm), rule["description_contains"] || "",
       rule["valid_from"], index}
    )
  end

  defp override_row(override, index, catalog) do
    key = {override["module"], override["document_id"], override["account"], override["month"]}
    target = catalog.targets[key]
    locations = Map.get(catalog.documents, {override["module"], override["document_id"]}, [])
    document = target || List.first(locations)
    info = if document, do: hd(document.rows)["identification"] || %{}, else: %{}

    status =
      cond do
        target && target.fingerprint != override["fingerprint"] -> "Pozastavena · změněný podklad"
        target -> "Platná"
        locations != [] -> "Pozastavena · přesunutý podklad"
        true -> "Podklad chybí"
      end

    row(
      "override",
      index,
      override,
      [
        cell(
          "Doklad a firma",
          info["document_number"] || "Číslo dokladu není v podkladech",
          info["company"] || "Firma neuvedena"
        ),
        cell("Účet", override["account"], catalog.accounts[override["account"]]),
        cell("Měsíc", month(override["month"])),
        behavior_cell(override),
        split_cell(override),
        extraordinary_cell(override),
        Map.put(cell("Stav", status), :warning, status != "Platná")
      ],
      [
        {"Modul", override["module"]},
        {"ID dokladu", override["document_id"]},
        {"Finanční otisk", override["fingerprint"]}
      ],
      {override["month"], info["document_number"] || override["document_id"], override["account"],
       index}
    )
  end

  defp row(kind, index, attrs, cells, references, sort) do
    references = Enum.reject(references, fn {_, value} -> is_nil(value) end)

    %{
      key: "#{kind}-#{index}",
      kind: kind,
      index: index,
      cells: cells,
      reason: attrs["reason"],
      references: references,
      sort: sort
    }
  end

  defp filter_rows(rows, words) do
    rows
    |> Enum.filter(fn row ->
      text =
        (Enum.flat_map(row.cells, &[&1.value, &1.secondary]) ++
           [row.reason] ++ Enum.map(row.references, &elem(&1, 1)))
        |> Enum.join(" ")
        |> String.downcase()

      Enum.all?(words, &String.contains?(text, &1))
    end)
    |> Enum.sort_by(& &1.sort)
  end

  defp cell(label, value, secondary \\ nil),
    do: %{label: label, value: value, secondary: secondary, warning: false}

  defp behavior_cell(attrs) do
    label =
      case attrs["behavior"] do
        "fixed" -> "Fixní"
        "variable" -> "Variabilní"
        "mixed" -> "Smíšené"
        _ -> "Nezařazené"
      end

    cell("Chování", label)
  end

  defp split_cell(%{"behavior" => "mixed", "fixed_percent" => percent})
       when not is_nil(percent) do
    fixed = Decimal.new(percent)

    cell(
      "Rozdělení",
      "Odhad: #{number(fixed)} % fixní",
      "#{number(Decimal.sub(100, fixed))} % variabilní"
    )
  end

  defp split_cell(%{"behavior" => "mixed"}), do: cell("Rozdělení", "Nerozděleno")
  defp split_cell(_), do: cell("Rozdělení", "—")

  defp extraordinary_cell(attrs),
    do: cell("Mimořádné", if(attrs["extraordinary"], do: "Ano", else: "Neoznačeno"))

  defp number(value) do
    value
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
    |> Decimal.new()
    |> CurrencyHelper.format_number()
    |> String.replace(".", ",")
  end

  defp month(<<year::binary-size(4), "-", month::binary-size(2), _::binary>>),
    do: month <> "/" <> year

  attr :rules, :list, required: true
  attr :overrides, :list, required: true
  attr :catalog, :map, required: true
  attr :query, :string, required: true
  attr :expanded, :any, required: true
  attr :editable, :boolean, required: true
  attr :source_id, :string, required: true

  def mapping_tables(assigns) do
    assigns =
      assign(
        assigns,
        :rows,
        entries(assigns.rules, assigns.overrides, assigns.catalog, assigns.query)
      )

    ~H"""
    <div class="space-y-5">
      <p :if={@editable} class="text-sm">
        Celá připravovaná verze. Úpravy a odebrání se projeví až po náhledu a publikaci.
      </p>
      <.form
        for={to_form(%{"query" => @query}, as: :entries_search)}
        id="cost-entries-search"
        phx-change="entries-search"
      >
        <.input
          type="search"
          name="entries_search[query]"
          value={@query}
          label="Hledat v pravidlech a výjimkách"
          placeholder="Účet, firma, doklad, text pravidla nebo důvod…"
          phx-debounce="200"
        />
      </.form>
      <.entry_table
        id="cost-draft-rules"
        title="Pravidla"
        rows={@rows.rules}
        total={length(@rules)}
        expanded={@expanded}
        editable={@editable}
        source_id={@source_id}
        headers={[
          "Účet",
          "Firma",
          "Popis obsahuje",
          "Platnost",
          "Chování",
          "Rozdělení",
          "Mimořádné",
          "Akce"
        ]}
      />
      <.entry_table
        id="cost-draft-overrides"
        title="Výjimky pro konkrétní podklady"
        rows={@rows.overrides}
        total={length(@overrides)}
        expanded={@expanded}
        editable={@editable}
        source_id={@source_id}
        headers={[
          "Doklad a firma",
          "Účet",
          "Měsíc",
          "Chování",
          "Rozdělení",
          "Mimořádné",
          "Stav",
          "Akce"
        ]}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :headers, :list, required: true
  attr :total, :integer, required: true
  attr :expanded, :any, required: true
  attr :editable, :boolean, required: true
  attr :source_id, :string, required: true

  defp entry_table(assigns) do
    ~H"""
    <section class="min-w-0 space-y-2">
      <h3 id={@id <> "-title"} class="text-lg font-semibold">
        {@title}
        <span class="text-sm font-normal text-base-content/60">{length(@rows)} / {@total}</span>
      </h3>
      <table
        id={@id}
        aria-labelledby={@id <> "-title"}
        class="table block w-full lg:table lg:table-fixed"
      >
        <thead class="hidden lg:table-header-group">
          <tr>
            <th :for={header <- @headers} scope="col">{header}</th>
          </tr>
        </thead>
        <tbody
          :for={row <- @rows}
          class="mb-3 block rounded-xl border border-base-300 lg:mb-0 lg:table-row-group lg:rounded-none lg:border-0"
        >
          <tr id={"cost-entry-#{row.key}"} data-mapping-entry class="block p-3 lg:table-row lg:p-0">
            <td
              :for={cell <- row.cells}
              class="block whitespace-normal break-words py-2 lg:table-cell lg:max-w-56 lg:align-top"
            >
              <span class="block text-xs font-semibold text-base-content/60 lg:hidden">{cell.label}</span>
              <span class={["block", cell.warning && "font-semibold text-warning"]}>{cell.value}</span>
              <span :if={cell.secondary} class="block text-xs text-base-content/70">{cell.secondary}</span>
            </td>
            <td class="block py-2 lg:table-cell lg:align-top">
              <span class="block text-xs font-semibold text-base-content/60 lg:hidden">Akce</span>
              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  phx-click="entry-detail"
                  phx-value-kind={row.kind}
                  phx-value-index={row.index}
                  aria-expanded={to_string(MapSet.member?(@expanded, row.key))}
                  aria-controls={"cost-entry-detail-#{row.key}"}
                  class="btn btn-xs btn-outline"
                >{if MapSet.member?(@expanded, row.key), do: "Skrýt detail", else: "Detail"}</button>
                <button
                  :if={@editable}
                  type="button"
                  id={"cost-entry-edit-#{row.key}"}
                  phx-click={JS.push("edit-entry") |> JS.focus(to: "#cost-mapping-editor")}
                  phx-value-kind={row.kind}
                  phx-value-index={row.index}
                  class="btn btn-xs"
                >Upravit</button>
                <button
                  :if={@editable}
                  type="button"
                  phx-click="remove-entry"
                  phx-value-kind={row.kind}
                  phx-value-index={row.index}
                  title="Odebrat z nové verze"
                  class="btn btn-xs btn-outline"
                >Odebrat</button>
              </div>
            </td>
          </tr>
          <tr
            :if={MapSet.member?(@expanded, row.key)}
            id={"cost-entry-detail-#{row.key}"}
            class="block bg-base-200/50 lg:table-row"
          >
            <td colspan="8" class="block whitespace-normal break-words p-4 lg:table-cell">
              <p><strong>Důvod:</strong> {row.reason}</p>
              <dl class="mt-3 grid gap-2 text-xs sm:grid-cols-2">
                <div>
                  <dt class="font-semibold">ID zdroje</dt><dd class="break-all">{@source_id}</dd>
                </div>
                <div :for={{label, value} <- row.references}>
                  <dt class="font-semibold">{label}</dt><dd class="break-all">{value}</dd>
                </div>
              </dl>
            </td>
          </tr>
        </tbody>
        <tbody :if={@rows == []} class="block lg:table-row-group">
          <tr class="block lg:table-row">
            <td colspan="8" class="block py-4 text-base-content/70 lg:table-cell">
              {if @total == 0, do: "Zatím bez položek.", else: "Hledání neodpovídá žádná položka."}
            </td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end
end

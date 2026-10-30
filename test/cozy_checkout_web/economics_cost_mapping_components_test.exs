defmodule CozyCheckoutWeb.EconomicsCostMappingComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias CozyCheckout.Economics.Costs
  alias CozyCheckoutWeb.EconomicsLive.CostMappingComponents, as: Components

  defp months do
    [
      %{
        "from" => "2026-07-01",
        "movements" => [
          %{
            "account" => "502001",
            "name" => "Energie",
            "category" => "Energie",
            "kind" => "expense",
            "module" => "FAP",
            "document_id" => "17",
            "journal_id" => "18",
            "date" => "2026-07-10",
            "md" => "100",
            "dal" => "0",
            "currency" => "CZK",
            "identification" => %{
              "partner_id" => "42",
              "company" => "Čaj & káva",
              "document_number" => "FP-017"
            }
          }
        ]
      }
    ]
  end

  defp catalog,
    do: Components.catalog(months(), [%{"account" => "501100", "name" => "Potraviny"}])

  defp rule(attrs \\ %{}),
    do:
      Map.merge(
        %{
          "account" => "502001",
          "partner_id" => "42",
          "description_contains" => nil,
          "valid_from" => "2026-07-01",
          "valid_to" => nil,
          "behavior" => "mixed",
          "fixed_percent" => "30",
          "extraordinary" => false,
          "reason" => "Smluvní odhad"
        },
        attrs
      )

  defp override(attrs \\ %{}) do
    [bundle] = Costs.bundles(months())

    Map.merge(
      %{
        "module" => "FAP",
        "document_id" => "17",
        "account" => "502001",
        "month" => "2026-07-01",
        "fingerprint" => bundle.fingerprint,
        "behavior" => "fixed",
        "extraordinary" => true,
        "reason" => "Kontrola konkrétního dokladu"
      },
      attrs
    )
  end

  defp field(row, label), do: Enum.find(row.cells, &(&1.label == label))

  defp render_tables(rules, overrides, opts \\ []) do
    render_component(
      &Components.mapping_tables/1,
      Keyword.merge(
        [
          rules: rules,
          overrides: overrides,
          catalog: catalog(),
          query: "",
          expanded: MapSet.new(),
          editable: true,
          source_id: "synthetic-source"
        ],
        opts
      )
    )
  end

  test "rule cells separate scope, validity, classification and estimates with human names" do
    [row] = Components.entries([rule()], [], catalog(), "").rules
    assert field(row, "Účet").secondary == "Energie"
    assert field(row, "Firma").value == "Čaj & káva"
    assert field(row, "Popis obsahuje").value == "Bez omezení"
    assert field(row, "Platnost").value == "07/2026 → bez konce"
    assert field(row, "Chování").value == "Smíšené"
    assert field(row, "Rozdělení").value == "Odhad: 30 % fixní"
    assert field(row, "Rozdělení").secondary == "70 % variabilní"
    assert field(row, "Mimořádné").value == "Neoznačeno"

    [row] =
      Components.entries(
        [rule(%{"partner_id" => nil, "valid_to" => "2026-09-01", "fixed_percent" => nil})],
        [],
        catalog(),
        ""
      ).rules

    assert field(row, "Firma").value == "Všechny firmy"
    assert field(row, "Platnost").value == "07/2026 → 09/2026"
    assert field(row, "Rozdělení").value == "Nerozděleno"

    for percent <- ["0", "100", "0.123456"] do
      [row] = Components.entries([rule(%{"fixed_percent" => percent})], [], catalog(), "").rules

      assert field(row, "Rozdělení").value ==
               "Odhad: #{String.replace(percent, ".", ",")} % fixní"
    end
  end

  test "overrides show the actual document and distinguish valid, changed, moved and missing targets" do
    overrides = [
      override(),
      override(%{"fingerprint" => String.duplicate("a", 64)}),
      override(%{"month" => "2026-08-01"}),
      override(%{"document_id" => "missing"})
    ]

    rows = Components.entries([], overrides, catalog(), "").overrides |> Map.new(&{&1.index, &1})
    assert field(rows[0], "Doklad a firma").value == "FP-017"
    assert field(rows[0], "Doklad a firma").secondary == "Čaj & káva"
    assert field(rows[0], "Mimořádné").value == "Ano"
    assert field(rows[0], "Stav").value == "Platná"
    refute field(rows[0], "Stav").warning
    assert field(rows[1], "Stav").value == "Pozastavena · změněný podklad"
    assert field(rows[2], "Stav").value == "Pozastavena · přesunutý podklad"
    assert field(rows[3], "Stav").value == "Podklad chybí"
    assert field(rows[3], "Stav").warning
  end

  test "sorting and shared search preserve original action indices" do
    rules = [
      rule(),
      rule(%{"account" => "501100", "partner_id" => nil, "reason" => "Pravidlo potravin"})
    ]

    rows = Components.entries(rules, [], catalog(), "").rules
    assert Enum.map(rows, & &1.index) == [1, 0]
    assert [%{index: 0}] = Components.entries(rules, [], catalog(), "Čaj").rules
    assert [%{index: 1}] = Components.entries(rules, [], catalog(), "Pravidlo potravin").rules
    assert [%{index: 0}] = Components.entries([], [override()], catalog(), "FP-017").overrides
    assert Components.entries(rules, [], catalog(), "nenalezeno").rules == []
  end

  test "unknown metadata stays explicit and is never joined by a company name" do
    [row] = Components.entries([rule(%{"partner_id" => "99"})], [], catalog(), "").rules
    assert field(row, "Firma").value == "Název firmy není v podkladech"
    assert {"ID firmy", "99"} in row.references

    [row] =
      Components.entries([], [override(%{"document_id" => "not-loaded"})], catalog(), "").overrides

    assert field(row, "Doklad a firma").value == "Číslo dokladu není v podkladech"
    assert field(row, "Doklad a firma").secondary == "Firma neuvedena"
  end

  test "name-only firms have safe searchable choices and an explicit label in the rule table" do
    months =
      Enum.map(
        months(),
        &Map.update!(&1, "movements", fn rows ->
          Enum.map(rows, fn row -> put_in(row, ["identification", "partner_id"], nil) end)
        end)
      )

    options = Components.partner_options(months, [])
    assert [%{name: "Čaj & káva (podle názvu)", partner_name: "Čaj & káva", id: id}] = options
    assert id =~ ~r/^name-[A-Za-z0-9_-]+$/
    assert Components.partner_choice(%{"partner_name" => " ČAJ & KÁVA "}) == id
    assert Components.partner_choice(%{"partner_id" => "42"}) == "42"
    assert [%{partner_name: nil, id: "42"}] = Components.partner_options(months(), [])

    [row] =
      Components.entries(
        [rule(%{"partner_id" => nil, "partner_name" => "Čaj & káva"})],
        [],
        catalog(),
        "čaj"
      ).rules

    assert field(row, "Firma").value == "Čaj & káva"
    assert field(row, "Firma").secondary =~ "Firma podle názvu"
  end

  test "table details stay collapsed and untrusted text is escaped in read-only views" do
    rules = [rule(%{"reason" => "<script>secret reason</script>"})]
    html = render_tables(rules, [override()])
    assert html =~ "<table"
    assert html =~ "Popis obsahuje"
    assert html =~ "Čaj &amp; káva"
    refute html =~ "secret reason"
    html = render_tables(rules, [], expanded: MapSet.new(["rule-0"]), editable: false)
    assert html =~ "&lt;script&gt;secret reason&lt;/script&gt;"
    assert html =~ "ID firmy"
    assert html =~ "synthetic-source"
    refute html =~ "<script>"
    refute html =~ "cost-entry-edit-"
    refute html =~ "phx-click=\"remove-entry\""
  end
end

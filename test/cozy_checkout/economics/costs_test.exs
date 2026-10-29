defmodule CozyCheckout.Economics.CostsTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.Economics.{Costs, CostRule, CostOverride, Reports}

  defp row(attrs \\ %{}) do
    Map.merge(
      %{
        "account" => "501100",
        "kind" => "expense",
        "name" => "Potraviny",
        "category" => "Potraviny",
        "module" => "FAP",
        "document_id" => "10",
        "journal_id" => "20",
        "date" => "2026-07-05",
        "md" => "100",
        "dal" => "0",
        "currency" => "CZK",
        "identification" => %{
          "partner_id" => "42",
          "company" => "Firma",
          "description" => "Pravidelný ÚKLID"
        }
      },
      attrs
    )
  end

  defp month(rows), do: %{"from" => "2026-07-01", "movements" => rows}

  defp rule(attrs \\ %{}) do
    struct(
      CostRule,
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          account: "501100",
          valid_from: ~D[2026-07-01],
          behavior: "fixed",
          reason: "Smlouva"
        },
        attrs
      )
    )
  end

  defp classify(rows, rules \\ [], overrides \\ []),
    do: Costs.classify([month(rows)], rules, overrides)

  defp override(bundle, attrs \\ %{}) do
    struct(
      CostOverride,
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          account: bundle.account,
          module: bundle.module,
          document_id: bundle.document_id,
          month: Date.from_iso8601!(bundle.month),
          fingerprint: bundle.fingerprint,
          behavior: "variable",
          reason: "Ruční kontrola"
        },
        attrs
      )
    )
  end

  defp equal(a, b), do: assert(Decimal.equal?(a, b))

  test "deterministic precedence; all predicates must match and names do not identify firms" do
    rules = [
      rule(%{behavior: "variable"}),
      rule(%{description_contains: "úklid", behavior: "mixed"}),
      rule(%{partner_id: "42", behavior: "fixed"}),
      rule(%{
        partner_id: "42",
        description_contains: "Úklid",
        behavior: "variable",
        extraordinary: true
      })
    ]

    for order <- [rules, Enum.reverse(rules)] do
      [item] = classify([row()], order).items
      assert item.behavior == "variable" and item.extraordinary
      assert length(item.matches) == 1
    end

    [item] = classify([put_in(row(), ["identification", "partner_id"], nil)], rules).items
    assert item.behavior == "mixed"
    [item] = classify([put_in(row(), ["identification", "company"], "Nový název")], rules).items
    assert item.behavior == "variable"
    [item] = classify([put_in(row(), ["identification", "description"], nil)], rules).items
    assert item.behavior == "fixed"
    [item] = classify([Map.delete(row(), "identification")], rules).items
    assert item.behavior == "variable" and not item.extraordinary
  end

  test "explicit name rules match only exact trimmed case-insensitive names without an internal ID" do
    named = rule(%{partner_name: "  Alza.cz a.s.  ", behavior: "variable"})

    without_id =
      put_in(row(), ["identification"], %{"company" => " ALZA.CZ A.S. ", "partner_id" => nil})

    assert [%{status: :classified, behavior: "variable"}] = classify([without_id], [named]).items
    with_id = put_in(without_id, ["identification", "partner_id"], "42")
    assert [%{status: :unclassified}] = classify([with_id], [named]).items
    assert [%{behavior: "fixed"}] = classify([with_id], [named, rule(%{partner_id: "42"})]).items

    for company <- [nil, "", "Alza", "Alza.cz a.s. nová", "Alza.cz  a.s."] do
      assert [%{status: :unclassified}] =
               classify([put_in(without_id, ["identification", "company"], company)], [named]).items
    end

    second = Map.put(with_id, "journal_id", "21")
    assert [%{status: :unclassified}] = classify([without_id, second], [named]).items

    other_firm =
      without_id
      |> put_in(["identification", "company"], "Jiná firma")
      |> Map.put("journal_id", "21")

    assert [%{status: :unclassified}] = classify([without_id, other_firm], [named]).items
  end

  test "name rules share firm specificity, support text and expose conflicts" do
    without_id = put_in(row(), ["identification", "partner_id"], nil)

    rules = [
      rule(),
      rule(%{description_contains: "úklid", behavior: "variable"}),
      rule(%{partner_name: "Firma", behavior: "mixed"}),
      rule(%{partner_name: "Firma", description_contains: "úklid", behavior: "variable"})
    ]

    assert [%{behavior: "variable"}] = classify([without_id], rules).items
    assert [%{behavior: "mixed"}] = classify([without_id], Enum.take(rules, 3)).items

    assert [%{status: :conflict}] =
             classify([without_id], [
               rule(%{partner_name: "Firma"}),
               rule(%{partner_name: " FIRMA ", behavior: "variable"})
             ]).items

    attrs = %{
      "account" => "501100",
      "valid_from" => "2026-07-01",
      "behavior" => "fixed",
      "reason" => "Důvod",
      "partner_name" => " Firma "
    }

    changeset = CostRule.changeset(%CostRule{}, attrs)
    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :partner_name) == "Firma"
    refute CostRule.changeset(%CostRule{}, Map.put(attrs, "partner_id", "42")).valid?
  end

  test "same precedence conflicting outcomes remain unclassified; identical outcomes retain evidence" do
    a = rule()
    b = rule(%{behavior: "variable"})
    [item] = classify([row()], [a, b]).items
    assert item.status == :conflict
    equal(item.unclassified, "100")
    assert length(item.matches) == 2

    [item] =
      classify([row()], [a, %{a | id: Ecto.UUID.generate(), reason: "Další podklad"}]).items

    assert item.status == :classified and length(item.matches) == 2
    [item] = classify([row()], [a, %{a | extraordinary: true}]).items
    assert item.status == :conflict

    [item] =
      classify([row()], [
        rule(%{behavior: "mixed", fixed_percent: Decimal.new("50.0")}),
        rule(%{behavior: "mixed", fixed_percent: Decimal.new("50")})
      ]).items

    assert item.status == :classified
  end

  test "validity includes whole first and last months and ignores expired rules" do
    for attrs <- [
          %{valid_from: ~D[2026-08-01]},
          %{valid_from: ~D[2026-06-01], valid_to: ~D[2026-06-01]}
        ] do
      [item] = classify([row()], [rule(attrs)]).items
      assert item.status == :unclassified
    end

    [item] = classify([row()], [rule(%{valid_to: ~D[2026-07-01]})]).items
    assert item.status == :classified
  end

  test "bundle includes all postings of a document on an account in a month and excludes non-expenses" do
    rows = [
      row(),
      row(%{"journal_id" => "21", "md" => "-20"}),
      row(%{"kind" => "revenue"}),
      row(%{"kind" => "other", "account" => "343001"})
    ]

    result = classify(rows)
    assert [%{rows: [_, _]}] = result.items
    equal(result.totals.total, "80")
    [bundle] = Costs.bundles([month(rows)])
    result = classify(rows, [rule()], [override(bundle, %{extraordinary: true})])
    [item] = result.items
    assert item.via == :override and item.extraordinary
    equal(result.totals.variable, "80")
    equal(result.totals.extraordinary, "80")
  end

  test "override financial identity ignores labels and order but suspends on financial composition change" do
    rows = [row(), row(%{"journal_id" => "21", "md" => "20"})]
    [bundle] = Costs.bundles([month(rows)])
    exception = override(bundle)

    renamed =
      Enum.reverse(rows) |> Enum.map(&put_in(&1, ["identification", "company"], "Přejmenováno"))

    [item] = classify(renamed, [rule()], [exception]).items
    assert item.via == :override

    for changed <- [
          List.replace_at(rows, 1, row(%{"journal_id" => "22", "md" => "20"})),
          [row(%{"md" => "120"})]
        ] do
      [item] = classify(changed, [rule()], [exception]).items
      assert item.status == :stale_override and is_nil(item.via)
      equal(item.unclassified, "120")
    end

    assert classify([], [], [exception]).missing_overrides == [exception]
    shifted = %{month(rows) | "from" => "2026-08-01"}
    result = Costs.classify([shifted], [rule()], [exception])
    assert hd(result.items).status == :moved_override
    assert result.missing_overrides == [exception]
  end

  test "an override valid in another month is not a moved target and account moves require review" do
    [bundle] = Costs.bundles([month([row()])])
    exception = override(bundle)
    july = month([row()])
    august = %{"from" => "2026-08-01", "movements" => [row(%{"date" => "2026-08-15"})]}
    result = Costs.classify([july, august], [rule()], [exception])
    assert Enum.all?(result.items, &(&1.status == :classified))
    assert result.missing_overrides == []
    moved = classify([row(%{"account" => "518001"})], [rule(%{account: "518001"})], [exception])
    assert hd(moved.items).status == :moved_override
    equal(moved.totals.unclassified, "100")
  end

  test "exact reconciliation with signed credits, unsplit mixed and estimated 0/50/100 percent" do
    for amount <- ["0.01", "-0.01", "100.25", "-100.25", "0"], percent <- ["0", "50", "100"] do
      result =
        classify([row(%{"md" => amount})], [
          rule(%{behavior: "mixed", fixed_percent: Decimal.new(percent)})
        ])

      t = result.totals
      equal(Decimal.add(t.fixed, t.variable), amount)
      equal(Decimal.add(t.display.fixed, t.display.variable), amount)

      equal(
        Enum.reduce(
          [t.fixed, t.variable, t.mixed, t.unclassified],
          Decimal.new(0),
          &Decimal.add/2
        ),
        t.total
      )

      assert hd(result.items).estimated
    end

    rows =
      for {account, md} <- [{"1", "100"}, {"2", "50"}, {"3", "-20"}, {"4", "-130"}],
          do: row(%{"account" => account, "md" => md})

    rules = [
      rule(%{account: "1"}),
      rule(%{account: "2", behavior: "variable", extraordinary: true}),
      rule(%{account: "3", behavior: "mixed"})
    ]

    t = classify(rows, rules).totals
    equal(t.total, "0")
    equal(t.extraordinary, "50")
    equal(t.absolute, "300")
    equal(t.unresolved_volume, "130")
    assert t.unresolved_count == 1
    refute is_nil(t.coverage)
    assert is_nil(classify([row(%{"md" => "0"})]).totals.coverage)
  end

  test "normalization metadata does not affect accounting confirmations" do
    import CozyCheckout.EconomicsFixtures

    rows =
      Enum.map(
        posted(),
        &Map.merge(&1, %{
          "firma" => "code:FIRMA",
          "firma@internalId" => 42,
          "popis" => String.duplicate("á", 510)
        })
      )

    {:ok, month} =
      Reports.month(period(), ~D[2026-07-01], ~D[2026-07-31], catalog(), rows, [], trial(), [])

    assert hd(month["movements"])["identification"]["partner_id"] == "42"
    assert hd(month["movements"])["identification"]["description_truncated"]

    legacy =
      Map.update!(
        month,
        "movements",
        &Enum.map(&1, fn row -> Map.delete(row, "identification") end)
      )

    assert Reports.month_fingerprint(legacy) == Reports.month_fingerprint(month)

    for reference <- [nil, "", "code:FIRMA", "Stejný název", "0", -1] do
      {:ok, [item]} = Reports.saldo([open_item(%{"firma" => reference})], ~D[2026-07-31])
      assert is_nil(item["identification"]["partner_id"])
    end
  end

  test "rule and override validations reject invalid percentages, dates and missing estimate reasons" do
    valid = %{
      "account" => "501100",
      "valid_from" => "2026-07-01",
      "behavior" => "mixed",
      "reason" => "Odhad podle smlouvy"
    }

    assert CostRule.changeset(%CostRule{}, valid).valid?

    for attrs <- [
          %{"fixed_percent" => "-1"},
          %{"fixed_percent" => "101"},
          %{"fixed_percent" => "1.1234567"},
          %{"fixed_percent" => "50", "behavior" => "fixed"},
          %{"valid_from" => "2026-07-02"},
          %{"valid_to" => "2026-06-01"},
          %{"valid_to" => "2026-08-02"},
          %{"behavior" => "other"},
          %{"reason" => "  ", "fixed_percent" => "50"}
        ] do
      refute CostRule.changeset(%CostRule{}, Map.merge(valid, attrs)).valid?
    end

    refute CostOverride.changeset(%CostOverride{}, %{}).valid?
  end

  test "reasons are optional except for manual mixed estimates, including zero and 100 percent" do
    rule_attrs = %{"account" => "501100", "valid_from" => "2026-07-01"}

    override_attrs = %{
      "account" => "501100",
      "module" => "FAP",
      "document_id" => "1",
      "month" => "2026-07-01",
      "fingerprint" => String.duplicate("a", 64)
    }

    for {schema, attrs} <- [{CostRule, rule_attrs}, {CostOverride, override_attrs}],
        behavior <- ["fixed", "variable", "mixed", "unclassified"],
        reason <- [nil, "", "  "] do
      values = Map.merge(attrs, %{"behavior" => behavior, "reason" => reason})
      assert schema.changeset(struct(schema), values).valid?

      for percent <- ["0", "50", "100"] do
        values = Map.merge(values, %{"behavior" => "mixed", "fixed_percent" => percent})
        refute schema.changeset(struct(schema), values).valid?

        assert schema.changeset(struct(schema), Map.put(values, "reason", "Podklad odhadu")).valid?
      end
    end

    changeset =
      CostRule.changeset(
        %CostRule{reason: "Dřívější poznámka"},
        Map.merge(rule_attrs, %{"behavior" => "fixed", "reason" => nil})
      )

    assert changeset.valid?
    assert is_nil(Ecto.Changeset.get_field(changeset, :reason))
  end
end

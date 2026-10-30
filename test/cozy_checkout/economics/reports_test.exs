defmodule CozyCheckout.Economics.ReportsTest do
  use ExUnit.Case, async: true
  import CozyCheckout.EconomicsFixtures
  alias CozyCheckout.Economics.Reports

  defp build(
         posted \\ posted(),
         trial \\ trial(),
         items \\ [],
         unposted \\ [],
         catalog \\ catalog()
       ) do
    Reports.month(
      period(),
      ~D[2026-07-01],
      ~D[2026-07-31],
      catalog,
      posted,
      unposted,
      trial,
      items
    )
  end

  test "Decimal totals, posted account control, opening balance, and historical partial payment" do
    assert {:ok, month} = build(posted(), trial(), [open_item()])
    assert Decimal.equal?(month["totals"]["result"], "74.50")
    assert Decimal.equal?(month["totals"]["revenue"], "120")
    assert Enum.find(month["balances"], &(&1["account"] == "221001"))["closing"] == "174.50"
    assert hd(month["open_items"])["amount"] == "75"
    refute Map.has_key?(hd(month["open_items"]), "zbyvaUhradit")
  end

  test "normalizes identification for movements and saldo without changing money" do
    assert {:ok, month} = build(posted(), trial(), [open_item()])
    sale = Enum.find(month["movements"], &(&1["account"] == "602001"))

    assert sale["identification"] == %{
             "company" => "Ukázkový odběratel s.r.o.",
             "partner_id" => nil,
             "description_truncated" => false,
             "document_number" => "FV-2026-1",
             "description" => "Prodej čaje a limonády",
             "variable_symbol" => "2026001",
             "supplier_number" => "OBJ-001",
             "counter_account" => "311001: Odběratelé"
           }

    assert hd(month["open_items"])["identification"]["company"] == "Ukázková firma s.r.o."
    assert hd(month["open_items"])["identification"]["document_number"] == "FV-2026-100"
    assert month["totals"]["result"] == "74.50"
  end

  test "optional identification tolerates empty data, uses the company reference and bounds free text" do
    row =
      open_item(%{
        "nazFirmy" => "  ",
        "firma@showAs" => "Firma z reference",
        "popis" => String.duplicate("á", 600),
        "varSym" => nil
      })

    assert {:ok, [normalized]} = Reports.saldo([row], ~D[2026-07-31])
    assert normalized["identification"]["company"] == "Firma z reference"
    assert String.length(normalized["identification"]["description"]) == 501
    assert String.ends_with?(normalized["identification"]["description"], "…")
    assert is_nil(normalized["identification"]["variable_symbol"])
  end

  test "financial confirmation hashes remain compatible with legacy snapshots and ignore labels" do
    assert {:ok, month} = build(posted(), trial(), [open_item()])

    legacy =
      month
      |> Map.update!("movements", fn rows ->
        Enum.map(rows, &Map.delete(&1, "identification")) |> Enum.sort()
      end)
      |> Map.update!("open_items", fn rows ->
        Enum.map(rows, &Map.delete(&1, "identification"))
      end)

    assert Reports.month_fingerprint(month) == Reports.fingerprint(legacy)

    enriched =
      month
      |> Map.update!("movements", fn rows ->
        Enum.reverse(rows)
        |> Enum.map(&put_in(&1, ["identification", "company"], "Opravený název firmy"))
      end)
      |> Map.update!("open_items", fn rows ->
        Enum.map(rows, &put_in(&1, ["identification", "description"], "Doplněný popis"))
      end)

    assert Reports.month_fingerprint(enriched) == Reports.month_fingerprint(month)
    refute Reports.fingerprint(enriched) == Reports.fingerprint(month)

    changed =
      Map.update!(month, "movements", fn [row | rest] -> [Map.put(row, "md", "999") | rest] end)

    refute Reports.month_fingerprint(changed) == Reports.month_fingerprint(month)
  end

  test "negative corrections and unmapped accounts stay in totals by ABRA kind, irrespective of code prefix" do
    catalog = catalog() ++ [account("999001", "Další náklad", "vysledkovy", "naklady")]
    correction = movement("999001", "-0.25", "0", "4")
    balance = balance("999001", "-0.25", "0", "-0.25", "0")
    assert {:ok, month} = build(posted() ++ [correction], trial() ++ [balance], [], [], catalog)
    assert Decimal.equal?(month["totals"]["expense"], "45.25")
    assert "unmapped_accounts" in month["warnings"]
  end

  test "unknown account, amount, type, currency, and ignored filters refuse publication" do
    for {field, value, error} <- [
          {"ucet", "code:UNKNOWN", :unknown_account},
          {"sumTuzMd", nil, :invalid_amount},
          {"sumTuzMd", "NaN", :invalid_amount},
          {"mena", "code:EUR", :unsupported_currency},
          {"datUcto", "2026-08-01+02:00", :ignored_date_filter},
          {"zuctovano", "false", :ignored_posting_filter}
        ] do
      [row | rest] = posted()
      assert {:error, ^error} = build([Map.put(row, field, value) | rest])
    end

    [account | rest] = catalog()

    assert {:error, :unknown_account_type} =
             build(posted(), trial(), [], [], [Map.put(account, "druhUctuK", "unknown") | rest])
  end

  test "missing data is distinct from zero; stale or partial controls cannot pass" do
    assert {:error, :trial_balance_mismatch} = build([], trial())
    assert {:error, :trial_balance_mismatch} = build(posted(), [])
    [row | rest] = trial()

    assert {:error, :invalid_balance} =
             build(posted(), [Map.put(row, "zustatekDal", "999") | rest])

    assert {:error, :ignored_period_filter} =
             build(posted(), [Map.put(row, "ucetniObdobi", "code:other") | rest])

    assert {:ok, month} = build([], [])
    assert Decimal.equal?(month["totals"]["result"], "0")
  end

  test "missing local currency and unposted data have explicit warnings and separate totals" do
    [row | rest] = posted()
    unposted = movement("602001", "0", "999", "9") |> Map.put("zuctovano", "false")
    assert {:ok, month} = build([Map.put(row, "mena", "") | rest], trial(), [], [unposted])
    assert "missing_currency" in month["warnings"]
    assert "unposted_documents" in month["warnings"]
    assert month["totals"]["revenue"] == "120"
    assert month["preliminary_totals"]["revenue"] == "999"
  end

  test "unposted documents without an assigned account stay outside posted totals" do
    row =
      movement("602001", "0", "999", "9") |> Map.merge(%{"zuctovano" => "false", "ucet" => ""})

    assert {:ok, month} = build(posted(), trial(), [], [row])
    assert month["totals"]["revenue"] == "120"
    assert month["unposted_count"] == 1
    assert is_nil(month["preliminary_totals"])
    assert "unposted_incomplete" in month["warnings"]
  end

  test "historical credits preserve sign, changed documents are unavailable, duplicates fail" do
    credit = open_item(%{"sumCelkem" => "-20", "sumCelkemAkt" => "-20", "juhSumDat" => "-5"})
    assert {:ok, month} = build(posted(), trial(), [credit])
    assert hd(month["open_items"])["amount"] == "-15"
    changed = open_item(%{"sumCelkemAkt" => "80"})
    assert {:ok, month} = build(posted(), trial(), [changed])
    assert hd(month["open_items"])["amount"] == nil
    assert "unsupported_open_items" in month["warnings"]
    assert {:error, :duplicate_open_item} = build(posted(), trial(), [credit, credit])

    assert {:error, :ignored_saldo_date} =
             build(posted(), trial(), [open_item(%{"datUcto" => "2026-08-01"})])
  end

  test "settled items are removed by Decimal zero comparison" do
    assert {:ok, month} = build(posted(), trial(), [open_item(%{"juhSumDat" => "100.00"})])
    assert month["open_items"] == []
  end

  test "fiscal boundaries come from actual dates rather than the code" do
    rows = [
      %{
        "kod" => "OTHER",
        "platiOdData" => "2026-07-01+02:00",
        "platiDoData" => "2027-06-30+02:00"
      }
    ]

    assert {:ok, [%{"code" => "OTHER", "from" => "2026-07-01", "to" => "2027-06-30"}]} =
             Reports.periods(rows)

    assert {:error, :invalid_period} =
             Reports.periods([Map.put(hd(rows), "platiOdData", "2026-07-02")])
  end
end

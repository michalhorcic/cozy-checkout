defmodule CozyCheckout.AbraFinalInvoiceVerificationTest do
  use ExUnit.Case, async: true
  @moduletag :financial
  alias CozyCheckout.Abra.FinalInvoiceVerification, as: Verification

  test "multiple deduction items bind to each source ZDD; binding castka can be zero" do
    {invoice, metadata, snapshot} = fixture()
    assert {:ok, applied} = Verification.progress(invoice, metadata, snapshot)
    assert applied == metadata["sources"]
    assert :ok = Verification.check(invoice, metadata, snapshot)
  end

  test "partial progress uses complete item deductions and resumes only the remaining source" do
    {invoice, metadata, snapshot} = fixture()
    [first, _second] = metadata["sources"]

    snapshot = %{
      snapshot
      | items: Enum.reject(snapshot.items, &(&1["id"] in ["2001", "2002"])),
        amounts: Enum.reject(snapshot.amounts, &(&1["id"] in ["2001", "2002"])),
        links: Enum.reject(snapshot.links, &(&1["idDokl"] == "200")),
        invoice: Map.merge(snapshot.invoice, totals("500", "60", "10", "570"))
    }

    assert {:ok, [^first]} = Verification.progress(invoice, metadata, snapshot)
  end

  test "document graph can consolidate multiple item deductions into one source node" do
    {invoice, metadata, snapshot} = fixture()
    snapshot = %{snapshot | links: Enum.uniq_by(snapshot.links, & &1["idDokl"])}
    assert {:ok, _} = Verification.progress(invoice, metadata, snapshot)
  end

  for fault <- [
        :foreign_source,
        :foreign_item,
        :duplicate,
        :missing,
        :cancelled,
        :wrong_type,
        :different_company,
        :contradicting_id,
        :swapped_sources
      ] do
    test "#{fault} cannot pass even with correct overall totals" do
      {invoice, metadata, snapshot} = fixture()
      [first | rest] = snapshot.amounts

      amounts =
        case unquote(fault) do
          :foreign_source ->
            [Map.put(first, "b@ref", "/c/test/faktura-vydana/999.json") | rest]

          :foreign_item ->
            [Map.put(first, "a@ref", "/c/test/faktura-vydana-polozka/999.json") | rest]

          :duplicate ->
            [first, Map.put(first, "id", "999") | rest]

          :missing ->
            rest

          :cancelled ->
            [Map.put(first, "storno", true) | rest]

          :wrong_type ->
            [Map.put(first, "typVazbyK", "typVazbyDokl.uhrada") | rest]

          :different_company ->
            [Map.put(first, "b@ref", "/c/other/faktura-vydana/100.json") | rest]

          :contradicting_id ->
            [Map.put(first, "a@internalId", 999) | rest]

          :swapped_sources ->
            Enum.map(snapshot.amounts, fn row ->
              target = if String.contains?(row["b@ref"], "/100."), do: "200", else: "100"
              Map.put(row, "b@ref", "/c/test/faktura-vydana/#{target}.json")
            end)
        end

      assert {:error, reason} =
               Verification.progress(invoice, metadata, %{snapshot | amounts: amounts})

      assert reason =~ "vazby"
    end
  end

  defp fixture do
    invoice = %{
      "id" => "ext:test:final",
      "kod" => "FINAL-TEST",
      "ucetni" => true,
      "bezPolozek" => false,
      "storno" => false,
      "polozkyFaktury" => [
        row("1", "1000", "120", "typSzbDph.dphSniz", "typPolozky.obecny"),
        row("2", "20", "0", "typSzbDph.dphOsv", "typPolozky.obecny")
      ]
    }

    invoice =
      Enum.reduce(~w(datVyst datSplat duzpPuv datUcto), invoice, &Map.put(&2, &1, "2026-10-26"))

    sources = [source("100", "500", "60", "10", "570"), source("200", "250", "30", "5", "285")]

    deductions =
      for {id, net, vat, type} <- [
            {"1001", "-500", "-60", "typSzbDph.dphSniz"},
            {"1002", "-10", "0", "typSzbDph.dphOsv"},
            {"2001", "-250", "-30", "typSzbDph.dphSniz"},
            {"2002", "-5", "0", "typSzbDph.dphOsv"}
          ],
          do: row(id, net, vat, type, "typPolozky.odpocetZdd")

    bindings =
      for item <- deductions do
        source = if String.starts_with?(item["id"], "100"), do: "100", else: "200"

        %{
          "id" => item["id"],
          "storno" => false,
          "castka" => "0.00",
          "typVazbyK" => "typVazbyDokl.odpocetZDD",
          "a@ref" => "/c/test/faktura-vydana-polozka/#{item["id"]}.json",
          "b@ref" => "/c/test/faktura-vydana/#{source}.json"
        }
      end

    links =
      for binding <- bindings do
        %{
          "idVazby" => binding["id"],
          "idDokl" => if(String.contains?(binding["b@ref"], "/100."), do: "100", else: "200"),
          "modulK" => "modulUcetni.FAV",
          "uroven" => 1,
          "storno" => false,
          "typVazbyK" => "typVazbyDokl.odpocetZDD"
        }
      end

    expected = totals("250", "30", "5", "285")

    snapshot = %{
      invoice: invoice |> Map.put("id", 236) |> Map.merge(expected),
      items: invoice["polozkyFaktury"] ++ deductions,
      amounts: bindings,
      links: links
    }

    {invoice, %{"sources" => sources, "expected" => expected}, snapshot}
  end

  defp totals(net, vat, fee, gross) do
    Map.merge(zero_totals(), %{
      "sumZklSniz" => net,
      "sumDphSniz" => vat,
      "sumOsv" => fee,
      "sumCelkem" => gross,
      "juhSum" => "0",
      "zbyvaUhradit" => gross
    })
  end

  defp source(id, net, vat, fee, gross),
    do: %{
      "remote_id" => id,
      "gross" => gross,
      "totals" =>
        Map.merge(zero_totals(), %{"sumZklSniz" => net, "sumDphSniz" => vat, "sumOsv" => fee})
    }

  defp zero_totals,
    do:
      Map.new(
        ~w(sumOsv sumZklSniz sumDphSniz sumZklSniz2 sumDphSniz2 sumZklZakl sumDphZakl),
        &{&1, "0"}
      )

  defp row(id, net, vat, rate, type),
    do: %{
      "id" => id,
      "storno" => false,
      "typPolozkyK" => type,
      "typSzbDphK" => rate,
      "sumZkl" => net,
      "sumDph" => vat,
      "sumCelkem" => to_string(Decimal.add(net, vat))
    }
end

defmodule CozyCheckout.Abra.FinalInvoiceBuilder do
  @moduledoc "Final invoice from frozen local lines and explicit source-ZDD deductions."
  alias CozyCheckout.Billing.{Document, Money}
  alias CozyCheckout.Abra.{BankVerification, TaxReceiptBuilder}

  def build(%Document{kind: "final"} = doc, sources, cfg) do
    deductions = doc.snapshot["deductions"] || []
    remaining = Decimal.add(doc.total, Money.total(deductions))

    cond do
      String.length(doc.number) > 20 or doc.snapshot["currency"] != "CZK" ->
        {:error, "Export vyžaduje CZK a číslo nejvýše 20 znaků"}

      not Decimal.equal?(Money.total(doc.lines), doc.total) ->
        {:error, "Částka faktury neodpovídá uloženým položkám"}

      Decimal.negative?(remaining) ->
        {:error, "Přeplatek nad cenu pobytu musí nejprve vyřešit účetní"}

      true ->
        with {:ok, items} <- items(doc, cfg),
             {:ok, totals} <- TaxReceiptBuilder.summary_totals(doc.lines ++ deductions, cfg) do
          invoice = %{
            "@create" => "ok",
            "@update" => "fail",
            "id" => "ext:cozy-checkout:accommodation:#{doc.id}",
            "kod" => doc.number,
            "varSym" => doc.variable_symbol,
            "typDokl" => "code:#{cfg[:final_type_code]}",
            "bankovniUcet" => "code:#{cfg[:bank_account_code]}",
            "mena" => "code:CZK",
            "datVyst" => to_string(doc.issued_on),
            "datSplat" => to_string(doc.due_on),
            "duzpPuv" => to_string(doc.tax_date),
            "datUcto" => to_string(doc.tax_date),
            "ucetni" => true,
            "bezPolozek" => false,
            "clenDph" => "code:#{cfg[:final_vat_code]}",
            "clenKonVykDph" => "code:#{cfg[:final_vat_report_code]}",
            "szbDphSniz" => "12",
            "szbDphZakl" => "21",
            "zaokrNaSumK" => "zaokrNa.zadne",
            "popis" => "Vyúčtování #{doc.number} · Cozy Checkout",
            "polozkyFaktury" => items
          }

          invoice =
            if sources == [],
              do: invoice,
              else:
                Map.put(invoice, "odpocty-zaloh", %{
                  "odpocet" => Enum.map(sources, &deduction/1)
                })

          buyer = doc.snapshot["customer"]

          invoice =
            Enum.reduce(
              [
                {"name", "nazFirmy"},
                {"street", "ulice"},
                {"city", "mesto"},
                {"postcode", "psc"},
                {"company_id", "ic"},
                {"vat_id", "dic"},
                {"email", "kontaktEmail"}
              ],
              invoice,
              fn {key, field}, acc ->
                if buyer[key] in [nil, ""], do: acc, else: Map.put(acc, field, buyer[key])
              end
            )

          invoice =
            if buyer["country"] in [nil, ""],
              do: invoice,
              else: Map.put(invoice, "stat", "code:#{buyer["country"]}")

          expected =
            Map.merge(totals, %{
              "sumCelkem" => to_string(remaining),
              "juhSum" => "0.00",
              "zbyvaUhradit" => to_string(remaining)
            })

          {:ok, %{"winstrom" => %{"faktura-vydana" => [invoice]}}, expected}
        end
    end
  end

  defp items(doc, cfg) do
    Enum.with_index(doc.lines, 1)
    |> Enum.reduce_while({:ok, []}, fn {line, position}, {:ok, rows} ->
      outside? = line["tax_mode"] == "outside"
      rate = BankVerification.amount(line["vat_rate"])

      type =
        cond do
          outside? and cfg[:tax_receipt_outside_mode] == "sumOsv" ->
            "typSzbDph.dphOsv"

          (line["tax_mode"] == "taxable" and rate) && Decimal.equal?(rate, 12) ->
            "typSzbDph.dphSniz"

          (line["tax_mode"] == "taxable" and rate) && Decimal.equal?(rate, 21) ->
            "typSzbDph.dphZakl"

          true ->
            nil
        end

      if type do
        item = %{
          "id" => "ext:cozy-checkout:final-item:#{doc.id}:#{position}",
          "nazev" => line["name"],
          "mnozMj" =>
            to_string(
              Decimal.mult(Money.decimal(line["quantity"]), Money.decimal(line["nights"]))
            ),
          "cenaMj" => line["unit"],
          "poznam" => "Původní rozpis: #{line["quantity"]} × #{line["nights"]}",
          "sumZkl" => line["net"],
          "sumDph" => line["vat"],
          "sumCelkem" => line["gross"],
          "typCenyDphK" =>
            if(not outside? and line["basis"] == "gross",
              do: "typCeny.sDph",
              else: "typCeny.bezDph"
            ),
          "typSzbDphK" => type,
          "szbDph" => if(outside?, do: "0", else: line["vat_rate"]),
          "zaokrNaK" => "zaokrNa.setiny",
          "kopZklDalUcet" => false,
          "zklDalUcet" =>
            "code:#{if outside?, do: cfg[:final_fee_account], else: cfg[:final_service_account]}",
          "kopClenDph" => false,
          "clenDph" =>
            "code:#{if outside?, do: cfg[:final_outside_vat_code], else: cfg[:final_vat_code]}",
          "kopClenKonVykDph" => false,
          "clenKonVykDph" =>
            "code:#{if outside?, do: cfg[:final_outside_vat_report_code], else: cfg[:final_vat_report_code]}"
        }

        {:cont, {:ok, rows ++ [item]}}
      else
        {:halt, {:error, "Faktura obsahuje daňový režim nebo sazbu bez podporovaného mapování"}}
      end
    end)
  end

  defp deduction(source) do
    totals = source["totals"]

    %{
      "id" => source["deduction_id"],
      "doklad" => source["remote_id"],
      "castkyBezDph" => true,
      "skupPlneni" => "OTHER",
      "castkaZaklMen" => totals["sumZklZakl"],
      "castkaSnizMen" => totals["sumZklSniz"],
      "castkaSniz2Men" => "0.00",
      "castkaOsvMen" => totals["sumOsv"]
    }
  end
end

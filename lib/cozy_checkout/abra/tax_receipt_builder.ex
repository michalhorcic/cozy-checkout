defmodule CozyCheckout.Abra.TaxReceiptBuilder do
  @moduledoc "Summary ZDD from issued local tax groups; configuration requires accounting verification."
  alias CozyCheckout.Billing.{Document, Money}

  @required ~w(tax_receipt_type_code tax_receipt_vat_code tax_receipt_vat_report_code tax_receipt_operation_code tax_receipt_primary_account tax_receipt_counter_account tax_receipt_vat12_account tax_receipt_vat21_account)a

  def configured?(cfg) do
    Enum.all?(@required, &(is_binary(cfg[&1]) and String.trim(cfg[&1]) != ""))
  end

  def build(%Document{kind: "tax_receipt"} = doc, cfg) do
    with true <- configured?(cfg),
         true <- String.length(doc.number) <= 20,
         true <- doc.snapshot["currency"] == "CZK",
         true <- Decimal.equal?(Money.total(doc.lines), doc.total),
         {:ok, totals} <- totals(doc.lines, cfg) do
      invoice =
        Map.merge(totals, %{
          "@create" => "ok",
          "@update" => "fail",
          "id" => "ext:cozy-checkout:accommodation:#{doc.id}",
          "kod" => doc.number,
          "varSym" => doc.variable_symbol,
          "typDokl" => "code:#{cfg[:tax_receipt_type_code]}",
          "bankovniUcet" => "code:#{cfg[:bank_account_code]}",
          "mena" => "code:CZK",
          "ucetni" => true,
          "bezPolozek" => true,
          "datVyst" => to_string(doc.issued_on),
          "datSplat" => to_string(doc.due_on),
          "duzpPuv" => to_string(doc.tax_date),
          "datUcto" => to_string(doc.tax_date),
          "clenDph" => "code:#{cfg[:tax_receipt_vat_code]}",
          "clenKonVykDph" => "code:#{cfg[:tax_receipt_vat_report_code]}",
          "typUcOp" => "code:#{cfg[:tax_receipt_operation_code]}",
          "primUcet" => "code:#{cfg[:tax_receipt_primary_account]}",
          "protiUcet" => "code:#{cfg[:tax_receipt_counter_account]}",
          "dphSnizUcet" => "code:#{cfg[:tax_receipt_vat12_account]}",
          "dphZaklUcet" => "code:#{cfg[:tax_receipt_vat21_account]}",
          "szbDphSniz" => "12",
          "szbDphZakl" => "21",
          "zaokrNaSumK" => "zaokrNa.zadne",
          "popis" => "Doklad k přijaté záloze #{doc.number} · Cozy Checkout"
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
          fn {source, target}, acc ->
            if buyer[source] in [nil, ""], do: acc, else: Map.put(acc, target, buyer[source])
          end
        )

      invoice =
        if buyer["country"] in [nil, ""],
          do: invoice,
          else: Map.put(invoice, "stat", "code:#{buyer["country"]}")

      {:ok, %{"winstrom" => %{"faktura-vydana" => [invoice]}}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "ZDD nelze exportovat: ověřte mapování, měnu, číslo a částky dokladu"}
    end
  end

  def supported_lines?(lines, cfg), do: match?({:ok, _}, totals(lines, cfg))

  defp totals(lines, cfg) do
    initial =
      Map.new(
        ~w(sumOsv sumZklSniz sumDphSniz sumZklSniz2 sumDphSniz2 sumZklZakl sumDphZakl),
        &{&1, "0.00"}
      )

    Enum.reduce_while(Money.groups(lines), {:ok, initial}, fn line, {:ok, sums} ->
      keys =
        cond do
          line["tax_mode"] == "taxable" and Decimal.equal?(Money.value(line, "vat_rate"), 12) ->
            {"sumZklSniz", "sumDphSniz"}

          line["tax_mode"] == "taxable" and Decimal.equal?(Money.value(line, "vat_rate"), 21) ->
            {"sumZklZakl", "sumDphZakl"}

          line["tax_mode"] == "outside" and cfg[:tax_receipt_outside_mode] == "sumOsv" ->
            {"sumOsv", nil}

          true ->
            nil
        end

      case keys do
        {net, vat} ->
          sums = Map.update!(sums, net, &to_string(Decimal.add(&1, line["net"])))

          sums =
            if vat,
              do: Map.update!(sums, vat, &to_string(Decimal.add(&1, line["vat"]))),
              else: sums

          {:cont, {:ok, sums}}

        nil ->
          {:halt, {:error, "ZDD obsahuje daňový režim nebo sazbu bez ověřeného mapování"}}
      end
    end)
  end
end

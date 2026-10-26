defmodule CozyCheckout.Abra.AdvanceBuilder do
  @moduledoc "Builds non-accounting advance requests from immutable billing snapshots."
  alias CozyCheckout.Billing.{Document, Money, Presentation}

  def build(%Document{kind: "advance"} = doc, cfg) do
    cond do
      String.length(doc.number) > 20 ->
        {:error, "Číslo dokladu překračuje limit ABRA 20 znaků"}

      doc.snapshot["currency"] != "CZK" ->
        {:error, "Export záloh podporuje pouze CZK"}

      not Decimal.equal?(Money.total(doc.lines), doc.total) ->
        {:error, "Částka zálohy neodpovídá uloženým položkám"}

      true ->
        invoice = %{
          "@create" => "ok",
          "@update" => "fail",
          "id" => "ext:cozy-checkout:accommodation:#{doc.id}",
          "kod" => doc.number,
          "varSym" => doc.variable_symbol,
          "typDokl" => "code:#{cfg[:advance_type_code]}",
          "bankovniUcet" => "code:#{cfg[:bank_account_code]}",
          "mena" => "code:CZK",
          "datVyst" => Date.to_iso8601(doc.issued_on),
          "datSplat" => Date.to_iso8601(doc.due_on),
          "popis" => "Zálohová výzva #{doc.number} · Cozy Checkout",
          "poznam" => breakdown_note(doc),
          "ucetni" => false,
          "bezPolozek" => false,
          "clenDph" => "code:000U",
          "clenKonVykDph" => "code:0.0.",
          "zaokrNaSumK" => "zaokrNa.zadne",
          "polozkyFaktury" => Enum.map(doc.lines, &item/1)
        }

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
    end
  rescue
    _ in ArgumentError -> {:error, "Nepodporovaná sazba DPH zálohy"}
  end

  def build(_, _), do: {:error, "Tato etapa podporuje pouze zálohové výzvy"}

  defp breakdown_note(doc) do
    stay =
      "Pobyt: #{Presentation.date(doc.snapshot["check_in"])} – #{Presentation.date(doc.snapshot["check_out"])}"

    case Presentation.advance_breakdown(doc) do
      nil ->
        Enum.join(
          [
            stay,
            "Záloha na pobyt a objednané služby: #{Presentation.amount(doc.total)}",
            "Původní rozpis položek nebyl u tohoto dokladu uložen."
          ],
          "\n"
        )

      calculation ->
        rows =
          Enum.map(calculation["lines"], fn line ->
            "#{line["name"]}: #{Presentation.number(line["quantity"])} × #{Presentation.number(line["nights"])} × #{Presentation.amount(Presentation.gross_unit_price(line))} = #{Presentation.amount(line["gross"])}"
          end)

        Enum.join(
          [stay, "Rozpis celého pobytu a objednaných služeb (ceny včetně DPH):"] ++
            rows ++
            [
              "Celková cena pobytu: #{Presentation.amount(calculation["stay_total"])}",
              "Výpočet požadované zálohy: #{Presentation.advance_explanation(calculation)}"
            ],
          "\n"
        )
    end
  end

  defp item(line) do
    %{
      "nazev" => "Záloha na pobyt",
      "mnozMj" => "1",
      "cenaMj" => line["gross"],
      "typCenyDphK" =>
        if(line["tax_mode"] == "outside", do: "typCeny.bezDph", else: "typCeny.sDph"),
      "typSzbDphK" => vat_type(line),
      "zaokrNaK" => "zaokrNa.setiny",
      "ucetni" => false,
      "clenDph" => "code:000U",
      "clenKonVykDph" => "code:0.0."
    }
  end

  # This is only the non-accounting request; tax receipts need their own mapping.
  defp vat_type(%{"tax_mode" => "outside"}), do: "typSzbDph.dphOsv"

  defp vat_type(line) do
    cond do
      Decimal.equal?(Money.value(line, "vat_rate"), 12) -> "typSzbDph.dphSniz"
      Decimal.equal?(Money.value(line, "vat_rate"), 21) -> "typSzbDph.dphZakl"
      Decimal.equal?(Money.value(line, "vat_rate"), 0) -> "typSzbDph.dphOsv"
      true -> raise ArgumentError, "Unsupported VAT rate"
    end
  end
end

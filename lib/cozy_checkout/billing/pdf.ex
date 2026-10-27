defmodule CozyCheckout.Billing.Pdf do
  @moduledoc "Self-contained A4 HTML rendered by Chromium; issued PDF bytes are persisted once."
  alias CozyCheckout.Billing.{Money, Document, Presentation}
  alias CozyCheckout.Billing

  @external_resource "priv/static/images/cozy-knot.svg"
  @logo Base.encode64(File.read!(@external_resource))

  @render_timeout 60_000

  def render(document, opts \\ []) do
    renderer = Keyword.get(opts, :renderer, CozyCheckout.Billing.PdfBrowser)
    timeout = Keyword.get(opts, :timeout, @render_timeout)

    task =
      Task.Supervisor.async_nolink(CozyCheckout.Billing.PdfTasks, fn ->
        # A temporary Chrome supervisor may send EXIT during startup or teardown.
        # Keep those signals in this isolated process, away from HTTP/Oban callers.
        Process.flag(:trap_exit, true)
        render_in_task(document, renderer)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, chrome_error(Exception.format_exit(reason))}
      nil -> {:error, chrome_error("Příprava překročila časový limit")}
    end
  end

  defp render_in_task(document, renderer) do
    try do
      with {:ok, encoded} <-
             renderer.print_to_pdf({:html, html(document)},
               print_to_pdf: %{printBackground: true, preferCSSPageSize: true}
             ),
           {:ok, bytes} <- Base.decode64(encoded) do
        {:ok, bytes}
      else
        {:error, reason} -> {:error, chrome_error(inspect(reason))}
        :error -> {:error, chrome_error("Prohlížeč nevrátil platné PDF")}
      end
    rescue
      exception -> {:error, chrome_error(Exception.message(exception))}
    catch
      :exit, reason -> {:error, chrome_error(Exception.format_exit(reason))}
    end
  end

  defp chrome_error(reason),
    do:
      "PDF: #{reason}. Zkontrolujte spuštění Chrome/Chromium a případně nastavte CHROME_EXECUTABLE."

  def html(document) do
    supplier = document.snapshot["supplier"]
    buyer = document.snapshot["customer"]
    deductions = document.snapshot["deductions"] || []
    due = Decimal.add(document.total, Money.total(deductions))
    preview? = not match?(%Document{}, document)

    payment_params =
      if not preview? and document.kind in ["advance", "final"] and Decimal.gt?(due, 0) do
        %{
          account_number: supplier["bank_account"],
          amount: due,
          variable_symbol: document.variable_symbol,
          message: document.number
        }
      end

    qr =
      if payment_params do
        data = CozyCheckout.Payments.QrCode.generate_qr_data(payment_params)

        if Regex.match?(~r/\*ACC:CZ\d{22}\*/, data),
          do: CozyCheckout.Payments.QrCode.generate_qr_svg(payment_params)
      end

    """
    <!doctype html><html lang="cs"><head><meta charset="utf-8"><title>#{escape(Billing.kind_label(document.kind))}</title>
    <style>@page { size:A4; margin:16mm; } body{font:12px 'DejaVu Sans',sans-serif;color:#192c32} h1{font-size:23px;margin:0 0 8px}.header{display:flex;align-items:center;gap:20px;border-bottom:2px solid #b8826f;padding-bottom:16px;margin-bottom:22px}.brand-logo{width:64px;height:64px;flex-shrink:0}.brand-name{font-size:15px;font-weight:bold;margin:0 0 8px;color:#627078} td{font-variant-numeric:tabular-nums} th{font-size:11px} .subject{max-width:270px} h2{font-size:14px} .parties{display:flex;gap:24px;align-items:flex-start;break-inside:avoid}.parties>.party{flex:1;min-width:0;overflow-wrap:anywhere}.payment-qr{flex:0 0 110px;text-align:center}.payment-qr h2{color:#627078}.contacts{line-height:1.5} table{width:100%;border-collapse:collapse;margin:18px 0} th,td{padding:7px 4px;border-bottom:1px solid #ccd3d7;text-align:right} th:first-child,td:first-child{text-align:left} thead{display:table-header-group} tr,.party{break-inside:avoid} .total{font-size:18px;font-weight:bold;text-align:right}.qr{width:110px;height:110px} .muted{color:#627078} .preview{color:#b33;font-size:24px}</style></head><body>
    #{if preview?, do: "<p class=preview>NÁHLED – NEVYSTAVENÝ DOKLAD</p>", else: ""}
    <div class="header"><img class="brand-logo" alt="Cozy Checkout" src="data:image/svg+xml;base64,#{@logo}"><div><p class="brand-name">Jindřichův dům</p><h1>#{escape(Billing.kind_label(document.kind))} #{escape(Map.get(document, :number, ""))}</h1></div></div>
    #{if document.kind == "advance", do: "<p>Výzva k úhradě zálohy – není daňovým dokladem.</p>", else: ""}
    <div class="parties">
    <div class="party"><h2>Dodavatel</h2>#{party(supplier)}<p class="muted contacts">#{escape(supplier["email"])}<br>#{escape(supplier["phone"])}</p></div>
    <div class="party"><h2>Odběratel</h2>#{party(buyer)}</div>
    #{if qr, do: "<div class=\"payment-qr\"><h2>QR platba</h2><img class=qr alt=\"QR platba\" src=\"data:image/svg+xml;base64,#{qr}\"></div>", else: ""}
    </div>
    <p>Vystaveno: #{date(document.issued_on)} #{if document.kind == "advance", do: "", else: " · #{if document.kind == "tax_receipt", do: "Přijetí platby", else: "DUZP"}: #{date(document.tax_date)}"}<br>#{if document.kind == "tax_receipt", do: "", else: "Splatnost: #{date(document.due_on)}<br>"}Pobyt: #{date(document.snapshot["check_in"])} – #{date(document.snapshot["check_out"])}</p>
    #{if document.snapshot["original_number"], do: "<p>Oprava dokladu #{escape(document.snapshot["original_number"])}<br>Důvod: #{escape(document.snapshot["reason"])}</p>", else: ""}
    #{items_table(document)}
    #{if document.kind == "advance", do: "", else: vat_table(document.lines)}
    #{if Presentation.advance_breakdown(document), do: "", else: "<p class=total>Celkem: #{money(document.total)} CZK</p>"}
    #{if deductions != [], do: "<h2>Odpočty přijatých záloh</h2><table><thead><tr><th>Doklad</th><th>Základ CZK</th><th>Daň CZK</th><th>Celkem CZK</th></tr></thead><tbody>#{Enum.map_join(deductions, &deduction_row/1)}</tbody></table>#{vat_table(document.lines ++ deductions)}", else: ""}
    #{if document.kind in ["advance", "final"], do: "<p class=total>#{Presentation.balance_label(due)}: #{Presentation.balance_amount(due)}</p>", else: ""}
    <p>Účet: #{escape(supplier["bank_account"])} · IBAN: #{escape(supplier["iban"])}</p>
    #{if preview?, do: "", else: "<p>Variabilní symbol: #{escape(document.variable_symbol)}</p>"}
    #{if payment_params && !qr, do: "<p>QR platba není k dispozici. Platební údaje ověřte s vystavovatelem.</p>", else: ""}
    </body></html>
    """
  end

  defp items_table(document) do
    if calculation = Presentation.advance_breakdown(document) do
      rows =
        Enum.map_join(calculation["lines"], fn line ->
          "<tr><td>#{escape(line["name"])}</td><td>#{Presentation.number(line["quantity"])}</td><td>#{Presentation.number(line["nights"])}</td><td>#{money(Presentation.gross_unit_price(line))}</td><td>#{money(Money.value(line, "gross"))}</td></tr>"
        end)

      """
      <h2>Rozpis pobytu a objednaných služeb</h2>
      <table><thead><tr><th>Položka</th><th>Osob / množství</th><th>Nocí / jednotek</th><th>Jedn. cena s DPH</th><th>Celkem s DPH</th></tr></thead><tbody>#{rows}</tbody></table>
      <p class="total">Celková cena pobytu: #{Presentation.amount(calculation["stay_total"])}</p>
      <p class="muted">Ceny jsou včetně DPH. Částky jsou zaokrouhlené na haléře.</p>
      <h2>Výpočet zálohy</h2><p>#{escape(Presentation.advance_explanation(calculation))}</p>
      """
    else
      "<table><thead><tr>#{line_headers(document.kind)}</tr></thead><tbody>#{document_rows(document)}</tbody></table>"
    end
  end

  defp document_rows(document),
    do: Enum.map_join(Presentation.lines(document), &row(&1, document.kind))

  defp line_headers("advance"), do: "<th>Předmět zálohy</th><th>Částka CZK</th>"

  defp line_headers("tax_receipt"),
    do: "<th>Předmět přijaté platby</th><th>Základ CZK</th><th>DPH</th><th>Celkem CZK</th>"

  defp line_headers(_),
    do:
      "<th>Položka</th><th>Počet</th><th>Nocí</th><th>Jedn. bez DPH</th><th>Základ</th><th>DPH</th><th>Celkem</th>"

  defp row(line, "advance") do
    "<tr><td class=subject>#{escape(Presentation.line_label(line, "advance"))}</td><td>#{money(Money.value(line, "gross"))}</td></tr>"
  end

  defp row(line, "tax_receipt") do
    "<tr><td class=subject>#{escape(Presentation.line_label(line, "tax_receipt"))}</td><td>#{money(Money.value(line, "net"))}</td><td>#{tax_label(line)}</td><td>#{money(Money.value(line, "gross"))}</td></tr>"
  end

  defp row(line, _kind) do
    unit_net =
      if (line["unit"] && line["basis"] == "gross") and line["tax_mode"] != "outside",
        do:
          Decimal.div(
            Money.value(line, "unit"),
            Decimal.add(1, Decimal.div(Money.value(line, "vat_rate"), 100))
          ),
        else: Money.value(line, "unit")

    label = tax_label(line)

    "<tr><td>#{escape(line["name"])}</td><td>#{Presentation.number(line["quantity"])}</td><td>#{Presentation.number(line["nights"])}</td><td>#{money(unit_net)}</td><td>#{money(Money.value(line, "net"))}</td><td>#{escape(label)}</td><td>#{money(Money.value(line, "gross"))}</td></tr>"
  end

  defp deduction_row(line) do
    "<tr><td>#{escape(line["name"])}</td><td>#{money(Money.value(line, "net"))}</td><td>#{money(Money.value(line, "vat"))}</td><td>#{money(Money.value(line, "gross"))}</td></tr>"
  end

  defp vat_table(lines) do
    rows =
      Money.groups(lines)
      |> Enum.map_join(fn group ->
        "<tr><td>#{if group["tax_mode"] == "outside", do: "Mimo předmět DPH", else: "DPH #{Presentation.number(group["vat_rate"])} %"}</td><td>#{money(Money.value(group, "net"))}</td><td>#{money(Money.value(group, "vat"))}</td><td>#{money(Money.value(group, "gross"))}</td></tr>"
      end)

    "<table><thead><tr><th>Rekapitulace</th><th>Základ CZK</th><th>Daň CZK</th><th>Celkem CZK</th></tr></thead><tbody>#{rows}</tbody></table>"
  end

  defp party(data) do
    [
      data["name"],
      data["street"],
      "#{data["postcode"]} #{data["city"]}",
      Presentation.country_name(data["country"]),
      if(data["company_id"] not in [nil, ""], do: "IČO: #{data["company_id"]}"),
      if(data["vat_id"] not in [nil, ""], do: "DIČ: #{data["vat_id"]}"),
      data["registry"]
    ]
    |> Enum.map(&String.trim(&1 || ""))
    |> Enum.reject(&(&1 == ""))
    |> Enum.map_join("<br>", &escape/1)
  end

  defp tax_label(line),
    do:
      if(line["tax_mode"] == "outside",
        do: "mimo DPH",
        else: "#{Presentation.number(line["vat_rate"])} %"
      )

  defp date(value), do: Presentation.date(value)
  defp money(value), do: Presentation.number(value)
  defp escape(nil), do: ""

  defp escape(value),
    do: value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end

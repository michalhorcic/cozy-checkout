defmodule CozyCheckout.Billing.Pdf do
  @moduledoc "Self-contained A4 HTML rendered by Chromium; issued PDF bytes are persisted once."
  alias CozyCheckout.Billing.{Money, Document}
  alias CozyCheckout.Billing

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
    <style>@page { size:A4; margin:16mm; } body{font:12px 'DejaVu Sans',sans-serif;color:#192c32} h1{font-size:25px} h2{font-size:14px} .parties{display:flex;gap:45px}.parties>div{flex:1} table{width:100%;border-collapse:collapse;margin:18px 0} th,td{padding:7px 4px;border-bottom:1px solid #ccd3d7;text-align:right} th:first-child,td:first-child{text-align:left} thead{display:table-header-group} tr,.party{break-inside:avoid} .total{font-size:18px;font-weight:bold;text-align:right}.qr{width:110px;height:110px} .muted{color:#627078} .preview{color:#b33;font-size:24px}</style></head><body>
    #{if preview?, do: "<p class=preview>NÁHLED – NEVYSTAVENÝ DOKLAD</p>", else: ""}
    <h1>#{escape(Billing.kind_label(document.kind))} #{escape(Map.get(document, :number, ""))}</h1>
    #{if document.kind == "advance", do: "<p>Výzva k úhradě zálohy – není daňovým dokladem.</p>", else: ""}
    <div class="parties"><div class="party"><h2>Dodavatel</h2>#{party(supplier)}</div><div class="party"><h2>Odběratel</h2>#{party(buyer)}</div></div>
    <p>Vystaveno: #{date(document.issued_on)} · #{if document.kind == "tax_receipt", do: "Přijetí platby", else: "DUZP"}: #{date(document.tax_date)}<br>Splatnost: #{date(document.due_on)}<br>Pobyt: #{escape(document.snapshot["check_in"])} – #{escape(document.snapshot["check_out"])}</p>
    #{if document.snapshot["original_number"], do: "<p>Oprava dokladu #{escape(document.snapshot["original_number"])}<br>Důvod: #{escape(document.snapshot["reason"])}</p>", else: ""}
    <table><thead><tr><th>Položka</th><th>Počet</th><th>Nocí</th><th>Jedn. bez DPH</th><th>Základ</th><th>DPH</th><th>Celkem</th></tr></thead><tbody>
    #{Enum.map_join(document.lines, &row(&1, document.kind == "advance"))}
    </tbody></table>
    #{if document.kind == "advance", do: "", else: vat_table(document.lines)}
    <p class="total">Celkem: #{money(document.total)} CZK</p>
    #{if deductions != [], do: "<h2>Odpočty přijatých záloh</h2><table><thead><tr><th>Doklad</th><th>Základ CZK</th><th>Daň CZK</th><th>Celkem CZK</th></tr></thead><tbody>#{Enum.map_join(deductions, &deduction_row/1)}</tbody></table>#{vat_table(document.lines ++ deductions)}", else: ""}
    #{if document.kind in ["advance", "final"], do: "<p class=total>K úhradě / přeplatek: #{money(due)} CZK</p>", else: ""}
    <p>Účet: #{escape(supplier["bank_account"])} · IBAN: #{escape(supplier["iban"])}</p>
    #{if preview?, do: "", else: "<p>Variabilní symbol: #{escape(document.variable_symbol)}</p>"}
    #{if payment_params && !qr, do: "<p>QR platba není k dispozici. Platební údaje ověřte s vystavovatelem.</p>", else: ""}
    #{if qr, do: "<img class=qr alt=\"QR platba\" src=\"data:image/svg+xml;base64,#{qr}\">", else: ""}
    <p class="muted">#{escape(supplier["email"])} · #{escape(supplier["phone"])}</p>
    </body></html>
    """
  end

  defp row(line, advance?) do
    unit_net =
      if (line["unit"] && line["basis"] == "gross") and line["tax_mode"] != "outside",
        do:
          Decimal.div(
            Money.value(line, "unit"),
            Decimal.add(1, Decimal.div(Money.value(line, "vat_rate"), 100))
          ),
        else: Money.value(line, "unit")

    label = if line["tax_mode"] == "outside", do: "mimo DPH", else: "#{line["vat_rate"]} %"

    "<tr><td>#{escape(line["name"])}</td><td>#{escape(line["quantity"])}</td><td>#{escape(line["nights"])}</td><td>#{if advance?, do: "—", else: unit_money(unit_net)}</td><td>#{if advance?, do: "—", else: money(Money.value(line, "net"))}</td><td>#{if advance?, do: "—", else: escape(label)}</td><td>#{money(Money.value(line, "gross"))}</td></tr>"
  end

  defp deduction_row(line) do
    "<tr><td>#{escape(line["name"])}</td><td>#{money(Money.value(line, "net"))}</td><td>#{money(Money.value(line, "vat"))}</td><td>#{money(Money.value(line, "gross"))}</td></tr>"
  end

  defp vat_table(lines) do
    rows =
      Money.groups(lines)
      |> Enum.map_join(fn group ->
        "<tr><td>#{if group["tax_mode"] == "outside", do: "Mimo předmět DPH", else: "DPH #{escape(group["vat_rate"])} %"}</td><td>#{money(Money.value(group, "net"))}</td><td>#{money(Money.value(group, "vat"))}</td><td>#{money(Money.value(group, "gross"))}</td></tr>"
      end)

    "<table><thead><tr><th>Rekapitulace</th><th>Základ CZK</th><th>Daň CZK</th><th>Celkem CZK</th></tr></thead><tbody>#{rows}</tbody></table>"
  end

  defp party(data) do
    [
      data["name"],
      data["street"],
      "#{data["postcode"]} #{data["city"]}",
      data["country"],
      if(data["company_id"] not in [nil, ""], do: "IČO: #{data["company_id"]}"),
      if(data["vat_id"] not in [nil, ""], do: "DIČ: #{data["vat_id"]}"),
      data["registry"]
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map_join("<br>", &escape/1)
  end

  defp date(value), do: Calendar.strftime(value, "%d.%m.%Y")

  defp unit_money(value),
    do: value |> Decimal.round(6, :half_up) |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp money(value), do: value |> Money.round() |> CozyCheckoutWeb.CurrencyHelper.format_number()
  defp escape(nil), do: ""

  defp escape(value),
    do: value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end

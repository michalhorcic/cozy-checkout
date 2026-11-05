defmodule CozyCheckout.IncomingDocuments.ResponseDiagnostics do
  @moduledoc "Bounded text-only diagnostics for non-API responses. HTML is never rendered or executed."

  def describe(status, raw, headers \\ %{}) do
    html = if is_binary(raw) and String.valid?(raw), do: String.slice(raw, 0, 100_000), else: ""

    title =
      case Regex.run(~r/<title\b[^>]*>(.*?)<\/title\s*>/is, html, capture: :all_but_first) do
        [value] -> text(value) |> String.slice(0, 250)
        _ -> ""
      end

    visible = text(html)
    template? = Regex.match?(~r/FreeMarker template error/i, visible)

    html? =
      Regex.match?(~r/<!doctype\s+html|<html\b|<head\b|<body\b/i, html) or
        String.contains?(String.downcase(headers["content-type"] || ""), "text/html")

    login? =
      Regex.match?(~r/<input\b[^>]*type\s*=\s*["']?password/i, html) or
        Regex.match?(
          ~r/login|sign in|přihl[aá][sš]en[ií]/iu,
          title <> " " <> String.slice(visible, 0, 200)
        )

    {kind, summary, hint} =
      cond do
        template? ->
          {"server_template_error",
           "ABRA selhala při vykreslení webové odpovědi (FreeMarker). Chybí strojově čitelný výsledek validace.",
           "Zkontrolujte níže adresu API a požadovaný JSON. Pokud je správně přípona .json i Accept, může jít o problém ABRA nebo přepis požadavku na proxy. Technickou chybu předejte správci ABRA; z tohoto HTML nelze určit správnost dokladu."}

        status in 300..399 ->
          {"redirect", "Server vrátil přesměrování místo výsledku importu.",
           "Zkontrolujte adresu přesměrování a nastavení základní URL/API/proxy. Aplikace přesměrování automaticky nenásleduje."}

        status == 401 ->
          {"authentication", "Server odmítl přihlášení k API (HTTP 401).",
           "Ověřte přihlašovací údaje ABRA používané také pro synchronizaci faktur za ubytování."}

        status == 403 ->
          {"access_denied", "Server odmítl přístup k API (HTTP 403).",
           "Ověřte oprávnění uživatele pro cílovou firmu a agendu, případně omezení proxy."}

        status >= 500 ->
          {"server_error", "Server nebo proxy vrátily chybu HTTP #{status}.",
           "Podrobnosti níže předejte správci ABRA nebo proxy. Nejde o potvrzení výsledku importu."}

        html? and login? ->
          {"login_page", "Odpověď vypadá jako přihlašovací HTML stránka, nikoli výsledek API.",
           "Ověřte přihlášení, cílovou adresu a proxy. Samotné HTML nepotvrzuje, zda doklad prošel validací."}

        html? ->
          {"html_page", "Místo JSON API přišla webová HTML stránka.",
           "Zkontrolujte volanou adresu a požadovaný formát. Titulek a čitelný text stránky jsou níže; z HTML nelze potvrdit import."}

        String.trim(html) == "" ->
          {"empty_or_binary", "Odpověď je prázdná nebo nemá čitelný text.",
           "Zkontrolujte HTTP stav a spojení s API. Výsledek importu není potvrzený."}

        true ->
          {"unexpected_format", "Odpověď nemá očekávanou strukturu JSON API.",
           "Zkontrolujte níže čitelnou odpověď a adresu API. Výsledek importu není potvrzený."}
      end

    focused =
      if template? do
        html |> String.split(~r/FreeMarker template error!?/i, parts: 2) |> List.last() |> text()
      else
        visible
      end

    version =
      case Regex.run(~r/\/flexibee-static\/([0-9][0-9A-Za-z.\-]{0,39})\//, html,
             capture: :all_but_first
           ) do
        [value] -> value
        _ -> nil
      end

    %{
      "kind" => kind,
      "summary" => summary,
      "hint" => hint,
      "title" => title,
      "text" => String.slice(focused, 0, 6000),
      "version_in_html" => version
    }
  end

  def safe_url(value) when is_binary(value) do
    case URI.new(value) do
      {:ok, uri} ->
        URI.to_string(%{uri | userinfo: nil, query: nil, fragment: nil}) |> String.slice(0, 1500)

      _ ->
        "Neplatná adresa"
    end
  end

  def for_display(response) when is_map(response) do
    cond do
      is_map(response["format_diagnostic"]) ->
        response

      is_map(response["body"]) ->
        response

      is_integer(response["http_status"]) and is_binary(response["raw_body"]) ->
        case Jason.decode(response["raw_body"]) do
          {:ok, %{"winstrom" => _}} ->
            response

          _ ->
            Map.put(
              response,
              "format_diagnostic",
              describe(response["http_status"], response["raw_body"], %{
                "content-type" => response["content_type"] || ""
              })
            )
        end

      true ->
        response
    end
  end

  defp text(html) do
    html
    |> String.replace(~r/<!--.*?-->/s, " ")
    |> String.replace(~r/<script\b[^>]*>.*?(?:<\/script\s*>|$)/is, " ")
    |> String.replace(~r/<style\b[^>]*>.*?(?:<\/style\s*>|$)/is, " ")
    |> String.replace(~r/<head\b[^>]*>.*?<\/head\s*>/is, " ")
    |> String.replace(~r/<[^>]*>/s, " ")
    |> String.replace(~r/&(?:amp|lt|gt|quot|apos|nbsp|#\d{1,7}|#x[0-9a-f]{1,6});/i, &entity/1)
    |> String.replace(~r/[\x00-\x08\x0b\x0c\x0e-\x1f]/, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp entity(value) do
    case String.downcase(value) do
      "&amp;" ->
        "&"

      "&lt;" ->
        "<"

      "&gt;" ->
        ">"

      "&quot;" ->
        "\""

      "&apos;" ->
        "'"

      "&nbsp;" ->
        " "

      numeric ->
        {digits, base} =
          if String.starts_with?(numeric, "&#x"),
            do: {String.slice(numeric, 3..-2//1), 16},
            else: {String.slice(numeric, 2..-2//1), 10}

        case Integer.parse(digits, base) do
          {codepoint, ""}
          when codepoint >= 32 and codepoint <= 0x10FFFF and codepoint not in 0xD800..0xDFFF ->
            <<codepoint::utf8>>

          _ ->
            " "
        end
    end
  end
end

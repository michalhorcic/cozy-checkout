defmodule CozyCheckout.GuestEmails.TemplateCatalog do
  @moduledoc """
  Catalog and renderer for the checked-in guest email templates.
  """

  @templates [
    %{
      id: "cs_winter",
      label: "Před příjezdem – česky, zima",
      language: "cs",
      season: :winter,
      subject: "Informace k pobytu od {{check_in_date}} – Jindřichův dům",
      file: "cs_winter.html"
    },
    %{
      id: "cs_summer",
      label: "Před příjezdem – česky, léto",
      language: "cs",
      season: :summer,
      subject: "Informace k pobytu od {{check_in_date}} – Jindřichův dům",
      file: "cs_summer.html"
    },
    %{
      id: "de_winter",
      label: "Před příjezdem – německy, zima",
      language: "de",
      season: :winter,
      subject: "Informationen zum Aufenthalt ab {{check_in_date}} – Jindřichův dům",
      file: "de_winter.html"
    },
    %{
      id: "de_summer",
      label: "Před příjezdem – německy, léto",
      language: "de",
      season: :summer,
      subject: "Informationen zum Aufenthalt ab {{check_in_date}} – Jindřichův dům",
      file: "de_summer.html"
    }
  ]

  def list, do: @templates

  def fetch(id) when is_binary(id) do
    case Enum.find(@templates, &(&1.id == id)) do
      nil -> {:error, :unknown_template}
      template -> {:ok, template}
    end
  end

  def fetch(_id), do: {:error, :unknown_template}

  def render(id, booking \\ nil, subject_override \\ nil, guest_name_override \\ nil) do
    with {:ok, template} <- fetch(id),
         {:ok, body} <- read_body(template),
         values <- personalization_values(template, booking, guest_name_override),
         html_body <- interpolate_html(body, values),
         subject <- interpolate_text(subject_override || template.subject, values) do
      {:ok,
       Map.merge(template, %{
         html: wrap_html(template, html_body),
         text: nil,
         subject: subject
       })}
    end
  end

  def render_custom(body) when is_binary(body) do
    normalized_body = String.replace(body, ~r/\r\n?/, "\n")

    if String.trim(normalized_body) == "" do
      {:error, :empty_body}
    else
      escaped_body =
        normalized_body
        |> Phoenix.HTML.html_escape()
        |> Phoenix.HTML.safe_to_string()
        |> String.replace("\n", "<br>\n")

      template = %{language: "cs", label: "Vlastní text", season: :summer}

      {:ok,
       %{
         html: wrap_html(template, "<p>#{escaped_body}</p>"),
         text: normalized_body
       }}
    end
  end

  def render_custom(_body), do: {:error, :empty_body}

  defp read_body(template) do
    path =
      Path.join(:code.priv_dir(:cozy_checkout), "email_templates/pre_arrival/#{template.file}")

    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, {:template_read_failed, template.id, reason}}
    end
  end

  defp personalization_values(template, booking, guest_name_override) do
    language = template.language

    guest_name =
      case guest_name_override do
        name when is_binary(name) and name != "" -> name
        _name when not is_nil(booking) -> booking.guest.name
        _name -> guest_fallback(language)
      end

    %{
      "guest_name" => guest_name,
      "check_in_date" => date_value(booking && booking.check_in_date, language),
      "check_out_date" => date_value(booking && booking.check_out_date, language)
    }
  end

  defp guest_fallback("de"), do: "Gast"
  defp guest_fallback(_language), do: "hoste"

  defp date_value(%Date{} = date, _language), do: Calendar.strftime(date, "%d.%m.%Y")
  defp date_value(nil, "de"), do: "wird noch bekannt gegeben"
  defp date_value(nil, _language), do: "bude upřesněno"

  defp interpolate_html(body, values) do
    Enum.reduce(values, body, fn {key, value}, html ->
      String.replace(html, "{{#{key}}}", escaped_html(value))
    end)
  end

  defp interpolate_text(text, values) do
    Enum.reduce(values, text, fn {key, value}, subject ->
      String.replace(subject, "{{#{key}}}", value)
    end)
  end

  defp escaped_html(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp wrap_html(template, body) do
    {accent, subtitle} = theme(template)

    """
    <!doctype html>
    <html lang="#{template.language}">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{template.label}</title>
      </head>
      <body style="margin:0;padding:24px 12px;background:#f5f5f5;font-family:Arial,Helvetica,sans-serif;color:#374151;line-height:1.6;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
          <tr>
            <td align="center">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:680px;background:#ffffff;border-radius:12px;overflow:hidden;">
                <tr>
                  <td style="padding:26px 22px;text-align:center;background:#{accent};color:#ffffff;">
                    <h1 style="margin:0;font-size:24px;line-height:1.3;">🏔️ Jindřichův dům</h1>
                    <p style="margin:8px 0 0;opacity:0.95;">#{subtitle}</p>
                  </td>
                </tr>
                <tr>
                  <td style="padding:28px 24px;">
                    #{body}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  defp theme(%{season: :winter, language: "cs"}),
    do: {"#0284c7", "Těšíme se na vás v Krkonoších!"}

  defp theme(%{season: :summer, language: "cs"}),
    do: {"#16a34a", "Těšíme se na vás v Krkonoších!"}

  defp theme(%{season: :winter, language: "de"}),
    do: {"#0284c7", "Wir freuen uns auf Sie im Riesengebirge!"}

  defp theme(%{season: :summer, language: "de"}),
    do: {"#16a34a", "Wir freuen uns auf Sie im Riesengebirge!"}
end

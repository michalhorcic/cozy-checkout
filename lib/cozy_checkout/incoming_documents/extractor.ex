defmodule CozyCheckout.IncomingDocuments.Extractor do
  @moduledoc "Stateless extraction with selectable detailed JSON or short template-based XML prompts."
  alias CozyCheckout.IncomingDocuments.Transcription

  def strategies, do: ["structured", "simple_xml", "header_form"]
  def strategy(doc), do: Map.get(doc.extraction_metadata, "strategy", "structured")
  def max_attempts(doc), do: if(strategy(doc) in ["simple_xml", "header_form"], do: 1, else: 2)
  def strategy_label("header_form"), do: "Návrhy do formuláře bez položek"
  def strategy_label("simple_xml"), do: "Jednoduché zadání → XML"
  def strategy_label(_), do: "Podrobný přepis → JSON → XML"

  def instructions(strategy \\ "structured") do
    filename =
      case strategy do
        "simple_xml" -> "extraction_instructions_simple.md"
        "header_form" -> "extraction_instructions_form.md"
        _ -> "extraction_instructions.md"
      end

    :cozy_checkout
    |> Application.app_dir("priv/incoming_documents/" <> filename)
    |> File.read!()
  end

  def prompt_version(strategy \\ "structured"),
    do: Base.encode16(:crypto.hash(:sha256, instructions(strategy)), case: :lower)

  def extract(doc, cfg, parts, feedback \\ nil) do
    if cfg[:openai_api_key] in [nil, ""] or cfg[:openai_model] in [nil, ""] do
      {:error, "Chybí OPENAI_API_KEY nebo INCOMING_DOCUMENTS_OPENAI_MODEL", %{}}
    else
      request(doc, cfg, parts, feedback)
    end
  end

  defp request(doc, cfg, parts, feedback) do
    context =
      if feedback do
        "Opravný pokus nad stejným originálem. Znovu jej přečti. Chyba kontroly: #{feedback.error}\nPředchozí přepis (může být chybný):\n#{Jason.encode!(feedback.data)}"
      else
        "Přepiš přiložený originál, všechny nákupní řádky i patičku. Vrať pouze údaje doložené originálem."
      end

    payload = %{
      model: cfg[:openai_model],
      store: false,
      max_output_tokens: 24000,
      instructions: instructions(strategy(doc)),
      text: %{
        format: %{
          type: "json_schema",
          name: "receipt_transcription",
          strict: true,
          schema: Transcription.schema()
        }
      },
      input: [%{role: "user", content: [%{type: "input_text", text: context} | parts]}]
    }

    payload =
      if strategy(doc) == "simple_xml" do
        payload
        |> Map.delete(:text)
        |> Map.put(:instructions, instructions("simple_xml"))
        |> Map.put(:input, [
          %{
            role: "user",
            content: [
              %{
                type: "input_text",
                text:
                  "Selected agenda: #{doc.agenda}. XML template:\n" <>
                    CozyCheckout.IncomingDocuments.XML.template_for(doc)
              }
              | parts
            ]
          }
        ])
      else
        payload
      end

    case Req.post("https://api.openai.com/v1/responses",
           auth: {:bearer, cfg[:openai_api_key]},
           json: payload,
           retry: false,
           redirect: false,
           receive_timeout: 120_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, %{status: 200, body: %{"status" => "completed", "output" => output} = body}}
      when is_list(output) ->
        raw =
          for %{"type" => "message", "content" => content} <- output,
              %{"type" => "output_text", "text" => text} <- content,
              do: text

        raw = Enum.join(raw) |> String.trim()

        metadata = %{
          "http_status" => 200,
          "provider_status" => "completed",
          "usage" => body["usage"] || %{},
          "raw_output" => String.slice(raw, 0, 250_000)
        }

        if strategy(doc) == "simple_xml" do
          if raw != "" and byte_size(raw) <= 250_000,
            do: {:ok_xml, raw, metadata},
            else: {:error, "OpenAI nevrátilo XML v povolené velikosti", metadata}
        else
          with true <- byte_size(raw) <= 250_000,
               {:ok, data} <- Jason.decode(raw),
               :ok <- Transcription.validate(data) do
            {:ok, data, metadata}
          else
            _ -> {:error, "OpenAI nevrátilo úplný přepis v očekávané JSON struktuře", metadata}
          end
        end

      {:ok, %{status: status, body: body}} ->
        kind = if is_map(body), do: body["status"] || "error", else: "error"

        incomplete_reason = if is_map(body), do: get_in(body, ["incomplete_details", "reason"])
        suffix = if incomplete_reason, do: ", důvod #{incomplete_reason}", else: ""

        {:error,
         "Vytěžení OpenAI selhalo (HTTP #{status}, stav #{kind}#{suffix}). Opakujte je ručně; automatický opravný pokus se nespouští.",
         %{
           "http_status" => status,
           "provider_status" => kind,
           "incomplete_reason" => incomplete_reason,
           "usage" => if(is_map(body), do: body["usage"] || %{}, else: %{})
         }}

      {:error, _} ->
        {:error, "OpenAI není dostupné nebo vypršel časový limit. Zkuste vytěžení znovu.", %{}}
    end
  end
end

defmodule CozyCheckout.IncomingDocuments.Extractor do
  @moduledoc "One stateless source transcription request. Persistent call limits live in the context."
  alias CozyCheckout.IncomingDocuments.Transcription

  def instructions do
    :cozy_checkout
    |> Application.app_dir("priv/incoming_documents/extraction_instructions.md")
    |> File.read!()
  end

  def prompt_version, do: Base.encode16(:crypto.hash(:sha256, instructions()), case: :lower)

  def extract(doc, cfg, parts, feedback \\ nil) do
    if cfg[:openai_api_key] in [nil, ""] or cfg[:openai_model] in [nil, ""] do
      {:error, "Chybí OPENAI_API_KEY nebo INCOMING_DOCUMENTS_OPENAI_MODEL", %{}}
    else
      request(doc, cfg, parts, feedback)
    end
  end

  defp request(_doc, cfg, parts, feedback) do
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
      instructions: instructions(),
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

        with true <- byte_size(raw) <= 250_000,
             {:ok, data} <- Jason.decode(raw),
             :ok <- Transcription.validate(data) do
          {:ok, data, metadata}
        else
          _ -> {:error, "OpenAI nevrátilo úplný přepis v očekávané JSON struktuře", metadata}
        end

      {:ok, %{status: status, body: body}} ->
        kind = if is_map(body), do: body["status"] || "error", else: "error"

        {:error,
         "Vytěžení OpenAI selhalo (HTTP #{status}, stav #{kind}). Opakujte je ručně; automatický opravný pokus se nespouští.",
         %{
           "http_status" => status,
           "provider_status" => kind,
           "usage" => if(is_map(body), do: body["usage"] || %{}, else: %{})
         }}

      {:error, _} ->
        {:error, "OpenAI není dostupné nebo vypršel časový limit. Zkuste vytěžení znovu.", %{}}
    end
  end
end

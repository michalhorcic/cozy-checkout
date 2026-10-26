defmodule CozyCheckout.Abra.Client do
  @moduledoc """
  HTTP client for ABRA Flexi REST API using Basic authentication.
  """

  require Logger

  @doc """
  POSTs a new invoice (faktura-vydana) to Abra Flexi.
  Returns {:ok, abra_id} on success or {:error, reason} on failure.
  """
  def create_invoice(payload, cfg \\ config()) do
    url = "#{cfg[:base_url]}/c/#{cfg[:company_id]}/faktura-vydana.json"

    case Req.post(url,
           json: payload,
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           headers: [{"Accept", "application/json"}],
           retry: false
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in [200, 201] ->
        parse_abra_id(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        reason = extract_error(body, status)
        Logger.warning("[Abra] Invoice creation failed: #{reason}")
        {:error, reason}

      {:error, exception} ->
        reason = Exception.message(exception)
        Logger.warning("[Abra] HTTP error: #{reason}")
        {:error, reason}
    end
  end

  @doc "Reads an invoice by stable external identity without changing it."
  def find_invoice(external_id, cfg) do
    id = URI.encode(external_id, &URI.char_unreserved?/1)
    url = "#{cfg[:base_url]}/c/#{cfg[:company_id]}/faktura-vydana/#{id}.json"

    case Req.get(url,
           params: [
             detail:
               "custom:id,kod,varSym,sumCelkem,mena,typDokl,bankovniUcet,ucetni,clenDph,clenKonVykDph"
           ],
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           headers: [{"Accept", "application/json"}],
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: %{"winstrom" => %{"faktura-vydana" => [invoice]}}}}
      when is_map(invoice) ->
        {:ok, invoice}

      {:ok, %Req.Response{status: 200, body: %{"winstrom" => %{"faktura-vydana" => []}}}} ->
        :not_found

      {:ok, %Req.Response{status: 404}} ->
        :not_found

      {:ok, %Req.Response{status: 200}} ->
        {:error, "unexpected_response"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "ABRA lookup HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  @doc "Reads one bank page; no date filter, so late imports are included."
  def bank_page(offset, limit, cfg) do
    url = "#{cfg[:base_url]}/c/#{cfg[:company_id]}/banka.json"

    case Req.get(url,
           params: [detail: "full", limit: limit, start: offset, order: "id"],
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           headers: [{"Accept", "application/json"}],
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: %{"winstrom" => %{"banka" => rows}}}}
      when is_list(rows) ->
        {:ok, rows}

      {:ok, %Req.Response{status: 200}} ->
        {:error, "ABRA vrátila neplatný seznam bankovních pohybů"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "ABRA banka HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  @doc "Fresh bank data and complete direct relationship lists for a confirmation."
  def bank_snapshot(id, cfg) do
    path = "banka/#{URI.encode(to_string(id), &URI.char_unreserved?/1)}"

    with {:ok, [bank]} when is_map(bank) <- read_records(path, "banka", cfg, detail: "full"),
         {:ok, links} <- relation_pages(path <> "/vazebni-doklady", "vazebni-doklad", cfg, 0, []),
         {:ok, amounts} <- relation_pages(path <> "/vazby", "vazba", cfg, 0, []) do
      {:ok, %{bank: bank, links: links, amounts: amounts}}
    else
      {:ok, _} -> {:error, "Bankovní pohyb již neexistuje nebo není jednoznačný"}
      {:error, reason} -> {:error, reason}
    end
  end

  def read_invoice(id, cfg) do
    path = "faktura-vydana/#{URI.encode(to_string(id), &URI.char_unreserved?/1)}"

    case read_records(path, "faktura-vydana", cfg, detail: "full") do
      {:ok, [invoice]} when is_map(invoice) -> {:ok, invoice}
      {:ok, []} -> :not_found
      {:error, :not_found} -> :not_found
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Nejednoznačná faktura v ABRA"}
    end
  end

  def deductible_amounts(id, cfg) do
    path = "faktura-vydana/#{URI.encode(to_string(id), &URI.char_unreserved?/1)}/castky-k-odpoctu"

    case read_records(path, "castky-k-odpoctu", cfg, detail: "full", limit: 2) do
      {:ok, [amounts]} when is_map(amounts) ->
        {:ok, amounts}

      {:ok, _} ->
        {:error, "ABRA nevrátila jednoznačné zbývající částky ZDD k odpočtu"}

      {:error, :not_found} ->
        {:error, "ABRA nenabízí zbývající částky ZDD k odpočtu; ověřte verzi a oprávnění API"}

      error ->
        error
    end
  end

  # polozkyFaktury is the import property; polozkyDokladu is the read relation.
  def final_invoice_snapshot(id, cfg, source_ids \\ []) do
    path = "faktura-vydana/#{URI.encode(to_string(id), &URI.char_unreserved?/1)}"

    with {:ok, invoice} <- read_invoice(id, cfg),
         {:ok, items} <-
           invoice_relation(path, "polozkyDokladu", "faktura-vydana-polozka", cfg),
         {:ok, links} <- invoice_relation(path, "vazebni-doklady", "vazebni-doklad", cfg),
         {:ok, amounts} <- invoice_relation(path, "vazby", "vazba", cfg),
         {:ok, source_bindings} <- source_invoice_bindings(source_ids, cfg) do
      {:ok,
       %{
         invoice: invoice,
         items: items,
         links: links,
         amounts: amounts,
         source_bindings: source_bindings
       }}
    else
      :not_found -> {:error, "Vyúčtování v ABRA po importu chybí"}
      error -> error
    end
  end

  # A deduction's a endpoint is an invoice ITEM, so the final invoice's header
  # relation need not contain it. Read the b endpoint (source ZDD) as documented.
  defp source_invoice_bindings(source_ids, cfg) do
    Enum.reduce_while(Enum.uniq(source_ids), {:ok, []}, fn id, {:ok, acc} ->
      path = "faktura-vydana/#{URI.encode(to_string(id), &URI.char_unreserved?/1)}"

      case invoice_relation(path, "vazby", "vazba", cfg) do
        {:ok, rows} -> {:cont, {:ok, acc ++ rows}}
        {:error, reason} -> {:halt, {:error, "Čtení vazeb zdrojového ZDD ID #{id}: #{reason}"}}
      end
    end)
  end

  defp invoice_relation(path, relation, key, cfg) do
    case relation_pages(path <> "/" <> relation, key, cfg, 0, []) do
      {:error, :not_found} -> {:error, "ABRA nevrátila relaci #{relation} vyúčtování (HTTP 404)"}
      {:error, reason} -> {:error, "Čtení relace #{relation} vyúčtování selhalo: #{reason}"}
      result -> result
    end
  end

  @doc "Pairs an existing bank movement; never supplies fields that create a bank receipt."
  def match_bank(bank_id, invoice_id, amount, cfg) do
    payload = %{
      "winstrom" => %{
        "banka" => [
          %{
            "@create" => "fail",
            "@update" => "ok",
            "id" => bank_id,
            "sparovani" => %{
              "uhrazovanaFak" => %{
                "@castka" => to_string(amount),
                "@type" => "faktura-vydana",
                "filter" => to_string(invoice_id)
              },
              "zbytek" => "ne"
            }
          }
        ]
      }
    }

    post_operation("banka", payload, cfg)
  end

  def link_tax_receipt(receipt_id, bank_id, cfg) do
    payload = %{
      "winstrom" => %{
        "faktura-vydana" => [
          %{
            "@create" => "fail",
            "@update" => "ok",
            "id" => receipt_id,
            "vytvor-vazbu-zdd" => %{"uhrada" => bank_id, "uhrada@type" => "banka"}
          }
        ]
      }
    }

    post_operation("faktura-vydana", payload, cfg)
  end

  @doc "Apply one stable deduction to an existing invoice without resending its prices or header."
  def apply_invoice_deduction(invoice_id, deduction, cfg) do
    post_operation(
      "faktura-vydana",
      %{
        "winstrom" => %{
          "faktura-vydana" => [
            %{
              "@create" => "fail",
              "@update" => "ok",
              "id" => invoice_id,
              # JSON collections omit the XML child element (odpocet).
              "odpocty-zaloh" => [deduction]
            }
          ]
        }
      },
      cfg
    )
  end

  defp post_operation(evidence, payload, cfg) do
    case Req.post("#{cfg[:base_url]}/c/#{cfg[:company_id]}/#{evidence}.json",
           json: payload,
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           retry: false
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in [200, 201] ->
        case parse_abra_id(body) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, extract_error(body, status)}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp relation_pages(_path, _key, _cfg, offset, _acc) when offset >= 10_000,
    do: {:error, "Příliš mnoho vazeb; dostupnost pohybu nelze bezpečně ověřit"}

  defp relation_pages(path, key, cfg, offset, acc) do
    with {:ok, rows} <-
           read_records(path, key, cfg, detail: "full", limit: 100, start: offset, order: "id") do
      if length(rows) < 100,
        do: {:ok, acc ++ rows},
        else: relation_pages(path, key, cfg, offset + 100, acc ++ rows)
    end
  end

  defp read_records(path, key, cfg, params) do
    case Req.get("#{cfg[:base_url]}/c/#{cfg[:company_id]}/#{path}.json",
           params: params,
           auth: {:basic, "#{cfg[:username]}:#{cfg[:password]}"},
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: %{"winstrom" => body}}} when is_map(body) ->
        case body[key] do
          rows when is_list(rows) -> {:ok, rows}
          _ -> {:error, "ABRA nevrátila úplná data evidence #{key}"}
        end

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status}} ->
        {:error, "ABRA čtení HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp parse_abra_id(%{"winstrom" => %{"results" => [%{} = result | _]}}) do
    case Map.get(result, "errors") do
      [error | _] = errors ->
        reason = error_message(error)
        Logger.warning("[Abra] Invoice import failed: #{inspect(errors)}")
        {:error, reason}

      errors when errors in [nil, []] ->
        case valid_document_id(Map.get(result, "id")) do
          {:ok, id} ->
            {:ok, id}

          :error ->
            Logger.warning("[Abra] Response did not contain a valid document ID")
            {:error, "unexpected_response"}
        end

      _ ->
        Logger.warning("[Abra] Unexpected response errors: #{inspect(result)}")
        {:error, "unexpected_response"}
    end
  end

  defp parse_abra_id(body) do
    Logger.warning("[Abra] Unexpected response body: #{inspect(body)}")
    {:error, "unexpected_response"}
  end

  defp valid_document_id(id) when is_integer(id) and id > 0, do: {:ok, Integer.to_string(id)}

  defp valid_document_id(id) when is_binary(id) do
    if String.trim(id) == "", do: :error, else: {:ok, id}
  end

  defp valid_document_id(_), do: :error

  defp error_message(%{"message" => message}) when is_binary(message) and message != "",
    do: message

  defp error_message(_), do: "import_error"

  defp extract_error(
         %{"winstrom" => %{"results" => [%{"errors" => [%{"message" => msg} | _]} | _]}},
         _
       ),
       do: msg

  defp extract_error(_, status), do: "HTTP #{status}"

  defp config, do: Application.fetch_env!(:cozy_checkout, :abra)
end

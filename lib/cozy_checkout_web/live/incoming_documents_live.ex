defmodule CozyCheckoutWeb.IncomingDocumentsLive do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.IncomingDocuments
  alias CozyCheckout.IncomingDocuments.{Builder, Client, Editor, Extractor, XML}
  import CozyCheckoutWeb.KitchenComponents, only: [searchable_picker: 1]

  def mount(_, _, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, 2000)

    {:ok,
     socket
     |> assign(
       page_title: "Přijaté doklady",
       doc: nil,
       fields: %{},
       edit_form: to_form(%{}, as: :fields),
       dirty: false
     )
     |> allow_upload(:original,
       accept: ~w(.pdf .jpg .jpeg .png),
       max_entries: 1,
       max_file_size: IncomingDocuments.max_size()
     )}
  end

  def handle_params(params, _, socket) do
    {:noreply, load(socket, params["id"])}
  end

  def handle_info(:refresh, socket) do
    doc = socket.assigns.doc

    socket =
      if doc && doc.state in ~w(uploaded processing validating sending uncertain),
        do: load(socket, doc.id),
        else: socket

    Process.send_after(self(), :refresh, 2000)
    {:noreply, socket}
  end

  def handle_event("upload-change", _, socket), do: {:noreply, socket}

  def handle_event("upload", %{"agenda" => agenda} = params, socket) do
    results =
      consume_uploaded_entries(socket, :original, fn %{path: path}, entry ->
        {:ok,
         IncomingDocuments.upload(
           File.read!(path),
           entry.client_name,
           agenda,
           params["strategy"] || "structured"
         )}
      end)

    case results do
      [{:ok, %{document: doc, duplicate?: duplicate}}] ->
        message =
          if duplicate,
            do:
              "Pozor: soubor se stejným obsahem už byl nahrán. Před odesláním ověřte duplicitu.",
            else: "Doklad nahrán. Probíhá vytěžování."

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_patch(to: ~p"/admin/incoming-documents/#{doc.id}")}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, error(reason))}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Vyberte jeden soubor a počkejte na dokončení nahrávání")}
    end
  end

  def handle_event("change", %{"fields" => attrs}, socket),
    do:
      {:noreply,
       assign(socket, dirty: true, edit_form: to_form(input_fields(attrs), as: :fields))}

  def handle_event("save", %{"fields" => attrs}, socket) do
    result(
      socket,
      IncomingDocuments.save(socket.assigns.doc.id, input_fields(attrs), socket.assigns.hash),
      "Změny uloženy. Spusťte kontrolu v ABRA."
    )
  end

  def handle_event("accounting-load", _, socket) do
    case IncomingDocuments.accounting_presets(socket.assigns.doc.id) do
      {:ok, rows} ->
        options =
          Enum.map(rows, fn row ->
            %{
              id: Base.url_encode64(row["kod"], padding: false),
              name: "#{row["kod"]} — #{row["nazev"]}",
              hint: row["protiUcetVydej"] || "Účet neurčen",
              search_text: "#{row["kod"]} #{row["nazev"]} #{row["protiUcetVydej"]}"
            }
          end)

        {:noreply,
         assign(socket, accounting_options: options, accounting_open: true, accounting_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, accounting_error: reason)}
    end
  end

  def handle_event("accounting-open", _, socket),
    do: {:noreply, assign(socket, accounting_open: true)}

  def handle_event("accounting-close", _, socket),
    do: {:noreply, assign(socket, accounting_open: false)}

  def handle_event("accounting-search", params, socket),
    do:
      {:noreply,
       assign(socket,
         accounting_query: get_in(params, ["accounting_search", "0"]) || "",
         accounting_open: true
       )}

  def handle_event("accounting-select", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.accounting_options, &(&1.id == id)) do
      attrs = Map.put(socket.assigns.accounting_form.params, "preset", id)

      {:noreply,
       assign(socket,
         accounting_form: to_form(attrs, as: :fields),
         accounting_query: nil,
         accounting_open: false,
         accounting_dirty: true
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("accounting-change", %{"fields" => attrs}, socket),
    do:
      {:noreply,
       assign(socket, accounting_form: to_form(attrs, as: :fields), accounting_dirty: true)}

  def handle_event("accounting-save", %{"fields" => attrs}, socket) do
    case Base.url_decode64(attrs["preset"] || "", padding: false) do
      {:ok, preset} ->
        result(
          socket,
          IncomingDocuments.save_accounting(
            socket.assigns.doc.id,
            Map.put(attrs, "preset", preset),
            socket.assigns.transcription_hash
          ),
          "Účetní nastavení uloženo. Spusťte nový dry-run ABRA."
        )

      :error ->
        {:noreply, put_flash(socket, :error, "Vyberte předpis z načteného číselníku")}
    end
  end

  def handle_event("diagnose", _, socket) do
    if socket.assigns.source_dirty or socket.assigns.accounting_dirty or socket.assigns.dirty do
      {:noreply, put_flash(socket, :error, "Nejprve uložte změny návrhu")}
    else
      result(
        socket,
        IncomingDocuments.diagnose(socket.assigns.doc.id, socket.assigns.transcription_hash),
        "Probíhá diagnostické testovací uložení v ABRA; žádný doklad se nevytvoří."
      )
    end
  end

  def handle_event("source-change", %{"fields" => %{"source" => attrs}}, socket) do
    {:noreply, source_draft(socket, Editor.apply(socket.assigns.source_data, attrs))}
  end

  def handle_event("source-save", %{"fields" => %{"source" => attrs}}, socket) do
    data = Editor.apply(socket.assigns.source_data, attrs)

    result(
      socket,
      IncomingDocuments.save_transcription(
        socket.assigns.doc.id,
        data,
        socket.assigns.transcription_hash
      ),
      "Návrh uložen. Výsledek kontroly je uveden u dokladu; XML lze stáhnout i s chybami."
    )
  end

  def handle_event("source-add", %{"collection" => collection}, socket),
    do: {:noreply, source_draft(socket, Editor.add(socket.assigns.source_data, collection))}

  def handle_event("source-delete", %{"collection" => collection, "index" => index}, socket),
    do:
      {:noreply,
       source_draft(socket, Editor.delete(socket.assigns.source_data, collection, index))}

  def handle_event("repair-data-change", %{"fields" => %{"data" => json}}, socket),
    do:
      {:noreply,
       assign(socket,
         source_dirty: true,
         transcription_form: to_form(%{"data" => json}, as: :fields)
       )}

  def handle_event("repair-data", %{"fields" => %{"data" => json}}, socket) do
    socket =
      assign(socket,
        source_dirty: true,
        transcription_form: to_form(%{"data" => json}, as: :fields)
      )

    result(
      socket,
      IncomingDocuments.repair_transcription(
        socket.assigns.doc.id,
        json,
        socket.assigns.transcription_hash
      ),
      "Přepis opraven. Zkontrolujte údaje a spusťte nový dry-run."
    )
  end

  def handle_event("repair-change", %{"fields" => %{"xml" => xml}}, socket),
    do: {:noreply, repair_draft(socket, xml)}

  def handle_event("repair", %{"fields" => %{"xml" => xml}} = params, socket) do
    doc = socket.assigns.doc
    socket = repair_draft(socket, xml)

    if params["action"] == "restore" do
      case XML.restore_accounting(xml, doc.agenda, XML.template_for(doc), doc.external_id) do
        {:ok, draft} ->
          {:noreply,
           socket
           |> repair_draft(draft)
           |> put_flash(
             :info,
             "Účetní nastavení v návrhu převzato ze vzoru. Zkontrolujte XML a uložte opravu."
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, error(reason))}
      end
    else
      result(
        socket,
        IncomingDocuments.repair_xml(doc.id, xml, socket.assigns.extraction_hash),
        "Oprava prošla kontrolou. Porovnejte údaje s originálem a spusťte kontrolu ABRA."
      )
    end
  end

  def handle_event("validate", _, socket) do
    if socket.assigns.dirty or socket.assigns.source_dirty or socket.assigns.accounting_dirty,
      do: {:noreply, put_flash(socket, :error, "Nejprve uložte změny")},
      else:
        result(
          socket,
          IncomingDocuments.validate(socket.assigns.doc.id, socket.assigns.hash),
          "Probíhá kontrola v ABRA"
        )
  end

  def handle_event("approve", attrs, socket) do
    if socket.assigns.dirty or socket.assigns.source_dirty or socket.assigns.accounting_dirty or
         attrs["reviewed"] != "true",
       do:
         {:noreply, put_flash(socket, :error, "Uložte změny a potvrďte porovnání s originálem")},
       else:
         result(
           socket,
           IncomingDocuments.approve(
             socket.assigns.doc.id,
             socket.assigns.hash,
             attrs["warnings"] == "true",
             attrs["rounding"] == "true"
           ),
           "Doklad schválen. Probíhá přenos do ABRA."
         )
  end

  def handle_event("retry", params, socket),
    do:
      result(
        socket,
        IncomingDocuments.retry_extraction(socket.assigns.doc.id, params["strategy"]),
        "Vytěžení zařazeno znovu"
      )

  def handle_event("verify", _, socket),
    do:
      result(
        socket,
        IncomingDocuments.verify(socket.assigns.doc.id),
        "Ověření zařazeno. Zápis se neopakuje."
      )

  defp result(socket, {:ok, _}, message),
    do: {:noreply, socket |> load(socket.assigns.doc.id) |> put_flash(:info, message)}

  defp result(socket, {:error, reason}, _),
    do: {:noreply, put_flash(socket, :error, error(reason))}

  defp input_fields(attrs) when is_map(attrs) do
    attrs
    |> Map.reject(fn {key, _} -> String.starts_with?(key, "_unused_") end)
    |> Map.new(fn {key, value} -> {key, input_fields(value)} end)
  end

  defp input_fields(value), do: value

  defp error(reason) when is_binary(reason), do: reason
  defp error(_), do: "Operaci se nepodařilo dokončit"

  defp load(socket, nil),
    do:
      assign(socket,
        documents: IncomingDocuments.list(),
        enabled: IncomingDocuments.enabled?(),
        doc: nil
      )

  defp load(socket, id) do
    doc = IncomingDocuments.get!(id)

    fields =
      case XML.parse(doc.current_xml || "", doc.agenda) do
        {:ok, fields} -> fields
        _ -> %{}
      end

    accounting_options =
      if socket.assigns.doc && socket.assigns.doc.id == doc.id,
        do: Map.get(socket.assigns, :accounting_options, []),
        else: []

    socket = assign(socket, doc: doc)
    socket = repair_draft(socket, doc.generated_xml || "")

    assign(socket,
      doc: doc,
      fields: fields,
      template_fields:
        case XML.parse(XML.template_for(doc), doc.agenda) do
          {:ok, fields} -> fields
          _ -> %{}
        end,
      edit_form:
        to_form(Map.take(fields, XML.editable()) |> Map.put("items", form_items(fields)),
          as: :fields
        ),
      items: XML.items(fields),
      import_xml:
        case XML.import_xml(doc.current_xml || "", doc.agenda) do
          {:ok, xml} -> xml
          _ -> nil
        end,
      dirty: false,
      hash: if(doc.current_xml, do: IncomingDocuments.digest(doc.current_xml)),
      extraction_hash: IncomingDocuments.digest(doc.generated_xml || ""),
      transcription_form:
        to_form(%{"data" => Jason.encode!(IncomingDocuments.transcription(doc), pretty: true)},
          as: :fields
        ),
      transcription_hash: IncomingDocuments.transcription_hash(doc),
      accounting_options: accounting_options,
      accounting_form:
        to_form(%{"preset" => "", "internal_code" => doc.accounting_settings["kod"] || ""},
          as: :fields
        ),
      accounting_query: nil,
      accounting_open: false,
      accounting_dirty: false,
      accounting_error: nil,
      source_data: IncomingDocuments.transcription(doc),
      source_issues: Builder.summary_issues(IncomingDocuments.transcription(doc)),
      source_dirty: false,
      source_locked:
        doc.state not in ["failed", "review"] or not is_nil(doc.sent_xml) or
          (doc.state == "failed" and doc.error_stage != "extraction"),
      draft_available: match?({:ok, _}, IncomingDocuments.diagnostic_xml(doc)),
      rounding:
        case XML.rounding_adjustments(doc.current_xml || "", doc.agenda) do
          {:ok, adjustments} -> adjustments
          _ -> []
        end,
      enabled: IncomingDocuments.enabled?()
    )
  end

  defp source_draft(socket, data) do
    assign(socket,
      source_data: data,
      source_dirty: true,
      source_issues: Builder.summary_issues(data),
      transcription_form: to_form(%{"data" => Jason.encode!(data, pretty: true)}, as: :fields)
    )
  end

  defp source_error(issues, path),
    do: for(issue <- issues, issue.path == Enum.join(path, "."), do: issue.message)

  defp form_items(fields),
    do:
      fields
      |> XML.items()
      |> Enum.with_index()
      |> Map.new(fn {row, i} -> {to_string(i), Map.take(row, XML.item_editable())} end)

  defp item_value(form, index, key), do: get_in(form.params, ["items", to_string(index), key])

  defp repair_draft(socket, xml) do
    doc = socket.assigns.doc

    differences =
      case XML.accounting_differences(xml, doc.agenda, XML.template_for(doc)) do
        {:ok, differences} -> differences
        _ -> []
      end

    assign(socket,
      repair_form: to_form(%{"xml" => xml}, as: :fields),
      accounting_differences: differences
    )
  end

  defp state_label(state),
    do:
      Map.get(
        %{
          "uploaded" => "Nahráno",
          "processing" => "Vytěžování",
          "review" => "Ke kontrole",
          "validating" => "Kontrola v ABRA",
          "sending" => "Odesílání",
          "sent" => "Odesláno",
          "failed" => "Chyba vytěžení",
          "uncertain" => "Nutno ověřit v ABRA"
        },
        state,
        state
      )

  defp label(key),
    do:
      Map.get(
        %{
          "cisDosle" => "Číslo původního dokladu",
          "varSym" => "Variabilní symbol",
          "datVyst" => "Datum vystavení",
          "duzpPuv" => "DUZP",
          "duzpUcto" => "Uplatnění DPH",
          "datSplat" => "Splatnost",
          "datUcto" => "Datum zaúčtování",
          "popis" => "Popis",
          "nazFirmy" => "Dodavatel",
          "ic" => "IČO",
          "dic" => "DIČ",
          "ulice" => "Ulice",
          "mesto" => "Město",
          "psc" => "PSČ",
          "buc" => "Bankovní účet",
          "iban" => "IBAN",
          "sumOsv" => "Osvobozeno / bez DPH (Kč)",
          "sumZklSniz" => "Základ 12 % (Kč)",
          "sumZklSniz2" => "Základ 2. snížené sazby (Kč)",
          "sumZklZakl" => "Základ 21 % (Kč)",
          "sumDphSniz" => "DPH 12 % (Kč)",
          "sumDphSniz2" => "DPH 2. snížené sazby (Kč)",
          "sumDphZakl" => "DPH 21 % (Kč)",
          "sumCelkem" => "Celkem včetně DPH (Kč)",
          "typDokl" => "Typ dokladu",
          "mena" => "Měna",
          "typUcOp" => "Předpis zaúčtování",
          "kod" => "Interní číslo ABRA",
          "primUcet" => "Účet DAL",
          "protiUcet" => "Účet MD",
          "clenDph" => "Řádky DPH",
          "clenKonVykDph" => "Kontrolní hlášení",
          "pokladna" => "Pokladna",
          "stredisko" => "Středisko",
          "stat" => "Stát",
          "statDph" => "Stát DPH",
          "typPohybuK" => "Typ pohybu",
          "dphZaklUcet" => "Účet DPH — základní sazba",
          "dphSnizUcet" => "Účet DPH — snížená sazba",
          "dphSniz2Ucet" => "Účet DPH — 2. snížená sazba",
          "szbDphZakl" => "Základní sazba DPH",
          "szbDphSniz" => "Snížená sazba DPH",
          "szbDphSniz2" => "2. snížená sazba DPH",
          "bezPolozek" => "Bezpoložkový doklad",
          "ucetni" => "Účetní doklad",
          "nazev" => "Název položky",
          "mnozMj" => "Množství",
          "cenaMj" => "Jednotková cena před slevou",
          "slevaPol" => "Sleva (%)"
        },
        key,
        key
      )

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      content_class="mx-auto w-full max-w-7xl space-y-6"
      main_class="px-4 py-6 sm:px-6 lg:px-8 lg:py-8"
    >
      <div class="flex items-center justify-between gap-4">
        <h1 class="text-3xl font-bold">Přijaté doklady</h1>
        <.link :if={@doc} navigate={~p"/admin/incoming-documents"} class="btn">Seznam dokladů</.link>
      </div>
      <p :if={!@enabled} class="alert alert-warning">
        Modul je vypnutý. Pro pilot nastavte připojení a INCOMING_DOCUMENTS_ENABLED=true.
      </p>
      <div :if={!@doc} class="space-y-6">
        <form
          id="incoming-upload"
          phx-change="upload-change"
          phx-submit="upload"
          class="bg-white rounded-xl p-6 space-y-4"
        >
          <p>Jeden soubor = jeden doklad. PDF (i vícestránkové), JPEG nebo PNG, nejvýše 10 MB.</p>
          <.input
            name="agenda"
            value="faktura-prijata"
            type="select"
            label="Agenda"
            options={IncomingDocuments.agendas()}
          />
          <.input
            name="strategy"
            value="structured"
            type="select"
            label="Způsob vytěžení"
            options={Enum.map(Extractor.strategies(), &{Extractor.strategy_label(&1), &1})}
          />
          <.live_file_input upload={@uploads.original} />
          <div :for={entry <- @uploads.original.entries}>
            <p>{entry.client_name} — {entry.progress} %</p>
            <p :for={err <- upload_errors(@uploads.original, entry)} class="text-error">
              {upload_error(err)}
            </p>
          </div>
          <p :for={err <- upload_errors(@uploads.original)} class="text-error">{upload_error(err)}</p>
          <button class="btn btn-primary" disabled={!@enabled} phx-disable-with="Ukládám…">Nahrát a vytěžit</button>
        </form>
        <div class="overflow-x-auto bg-white rounded-xl">
          <p class="p-4">Posledních 100 dokladů</p>
          <table class="table" id="incoming-list">
            <thead>
              <tr>
                <th>Soubor</th><th>Agenda</th><th>Stav</th><th>Cílová firma</th><th>Nahráno</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={doc <- @documents}>
                <td>
                  <.link navigate={~p"/admin/incoming-documents/#{doc.id}"} class="link">{doc.filename}</.link>
                </td>
                <td>{IncomingDocuments.agenda_label(doc.agenda)}</td><td>{state_label(doc.state)}</td><td>
                  {doc.company_id}
                </td><td>{doc.inserted_at}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <div :if={@doc} class="space-y-4" id="incoming-detail">
        <p>
          <strong>{IncomingDocuments.agenda_label(@doc.agenda)}</strong>
          · {state_label(@doc.state)} · Firma ABRA: <strong>{@doc.company_id}</strong>
        </p>
        <p :if={@doc.error} class="alert alert-error" id="incoming-error">{@doc.error}</p>
        <div
          :if={@draft_available}
          class="bg-white rounded-xl p-4 space-y-2"
          id="incoming-draft-download"
        >
          <p>
            XML návrh lze stáhnout i přes účetní chyby. Stažení neprovádí zápis ani kontrolu v ABRA. Není-li doklad schválený, jde o neověřený návrh; před ručním importem zkontrolujte chyby a cílovou firmu.
          </p>
          <p :if={@source_dirty or @accounting_dirty} class="text-warning">
            Před stažením nejdříve uložte změny návrhu.
          </p>
          <.link
            :if={!@source_dirty and !@accounting_dirty}
            href={~p"/admin/incoming-documents/#{@doc.id}/draft.xml"}
            class="btn"
            download
          >Stáhnout XML pro ABRA</.link>
          <button
            :if={!@source_locked}
            id="incoming-diagnose"
            class="btn"
            phx-click="diagnose"
            disabled={@source_dirty or @accounting_dirty or @dirty or !@enabled}
            phx-disable-with="Zařazuji…"
          >Ověřit návrh v ABRA bez zápisu (dry-run)</button>
        </div>
        <p :if={@doc.dry_run["diagnostic"]} class="alert alert-info" id="incoming-diagnostic-result">
          Diagnostický dry-run: {if @doc.dry_run["accepted"],
            do: "ABRA návrh přijala",
            else: "ABRA návrh nepřijala"}. Návrh se neuložil. Tato kontrola nenahrazuje schválení validního XML.
        </p>
        <details
          :if={@doc.extracted_data != %{} || @doc.extraction_metadata != %{}}
          class="bg-white rounded-xl p-4"
          id="incoming-transcription"
        >
          <summary>Přepis originálu a informace o vytěžení</summary>
          <p>
            Způsob: {Extractor.strategy_label(Extractor.strategy(@doc))}. Počet rezervovaných pokusů: {@doc.extraction_attempts} / {Extractor.max_attempts(
              @doc
            )}. Opravené starší doklady se modelu neposílají.
          </p>
          <p :if={get_in(@doc.extraction_metadata, ["images", "warning"])} class="text-warning">
            {get_in(@doc.extraction_metadata, ["images", "warning"])}
          </p>
          <details class="mt-3">
            <summary>Verze zadání, obrazové vstupy a spotřeba tokenů</summary><pre class="text-xs whitespace-pre-wrap break-all max-h-96 overflow-auto">{Jason.encode!(Map.update(@doc.extraction_metadata, "calls", [], &Enum.map(&1, fn call -> Map.delete(call, "raw_output") end)), pretty: true)}</pre>
          </details>
        </details>
        <div :if={@rounding != []} class="alert alert-warning" id="incoming-rounding">
          <div>
            <strong>Haléřová korekce DPH podle rekapitulace originálu</strong>
            <p>
              Celková cena i původní položky zůstávají stejné. Do ABRA přidáme samostatnou účetní položku pro rozdíl zaokrouhlení:
            </p>
            <p :for={row <- @rounding}>
              Sazba {row["szbDph"]} %: základ {format_currency(Decimal.new(row["sumZkl"]))}, DPH {format_currency(
                Decimal.new(row["sumDph"])
              )}, celkem {format_currency(Decimal.new(row["sumCelkem"]))}.
            </p>
          </div>
        </div>
        <p :if={@doc.state == "uncertain"} class="alert alert-warning">
          Výsledek zápisu není jistý. Ověřte doklad v ABRA. Opakované založení je blokováno.
        </p>
        <button
          :if={@doc.state == "uncertain"}
          phx-click="verify"
          class="btn"
          phx-disable-with="Zařazuji…"
        >Ověřit v ABRA bez opakování zápisu</button>
        <button
          :for={strategy <- Extractor.strategies()}
          :if={
            (@doc.state == "failed" && @doc.error_stage == "extraction") ||
              (@doc.state == "review" && is_nil(@doc.sent_xml))
          }
          phx-click="retry"
          phx-value-strategy={strategy}
          data-confirm="Nové vytěžení nahradí dosavadní opravy a zruší kontrolu ABRA. Pokračovat?"
          class="btn"
          phx-disable-with="Zařazuji…"
        >Znovu vytěžit: {Extractor.strategy_label(strategy)}</button>
        <p :if={@doc.state == "sent"} class="alert alert-success">
          Doklad byl nalezen v ABRA, ID {@doc.remote_id}.
          <a href={Client.document_url(@doc)} target="_blank" rel="noopener" class="link">Otevřít v ABRA</a>
        </p>
        <ul
          :if={@doc.state == "sent" && @doc.response["warnings"] not in [nil, []]}
          class="alert alert-warning"
        >
          <li :for={warning <- @doc.response["warnings"]}>Upozornění při zápisu: {warning}</li>
        </ul>
        <details
          :for={
            {title, response} <- [
              {"Kontrola ABRA (dry-run)", @doc.dry_run},
              {"Přenos do ABRA", @doc.response}
            ]
          }
          :if={response["http_status"]}
          class="bg-white rounded-xl p-4"
          data-abra-response
        >
          <summary>{title} — podrobnosti odpovědi (HTTP {response["http_status"]})</summary>
          <p class="mt-3">
            Typ obsahu: {if response["content_type"] in [nil, ""],
              do: "neuveden",
              else: response["content_type"]}
          </p>
          <ul class="space-y-2 my-3">
            <li :for={message <- response["errors"] || []} class="text-error">{message}</li>
            <li :for={message <- response["warnings"] || []} class="text-warning">{message}</li>
          </ul>
          <div :for={preview <- response["preview"] || []} class="border rounded p-3 mb-3">
            <p :for={{key, value} <- preview}>
              {label(key)}: {if is_binary(value), do: value, else: inspect(value)}
            </p>
            <p>
              Interní číslo z dry-runu není rezervované; při skutečném zápisu může ABRA přidělit jiné.
            </p>
          </div>
          <p :if={response["truncated"]}>Výpis těla je zkrácen na prvních 100 000 znaků.</p>
          <pre class="text-xs whitespace-pre-wrap break-all max-h-96 overflow-auto">{response["raw_body"] || Jason.encode!(response["body"] || %{}, pretty: true)}</pre>
        </details>
        <div class="grid lg:grid-cols-2 gap-6">
          <div class="space-y-3 min-w-0">
            <a
              href={~p"/admin/incoming-documents/#{@doc.id}/original"}
              target="_blank"
              rel="noopener"
              class="btn btn-sm"
            >Otevřít originál ve větším okně</a>
            <iframe
              :if={@doc.content_type == "application/pdf"}
              src={~p"/admin/incoming-documents/#{@doc.id}/original"}
              title="Originál dokladu — prohlížeč PDF se stránkováním a zvětšením"
              class="w-full h-[80vh] border rounded-lg bg-white"
            ></iframe>
            <div
              :if={@doc.content_type != "application/pdf"}
              id={"source-#{@doc.id}"}
              phx-hook="IncomingDocumentPreview"
              class="space-y-2"
            >
              <label class="flex gap-3 items-center">Zvětšení
              <input
                type="range"
                min="50"
                max="250"
                value="100"
                data-zoom
                aria-label="Zvětšení originálu"
              /></label>
              <div class="overflow-auto max-h-[80vh] border rounded-lg bg-white">
                <img
                  src={~p"/admin/incoming-documents/#{@doc.id}/original"}
                  alt="Originál přijatého dokladu"
                  data-original
                  class="max-w-none"
                  style="width:100%"
                />
              </div>
            </div>
          </div>
          <div class="min-w-0 space-y-4">
            <section class="bg-white rounded-xl p-4 space-y-3" id="incoming-accounting">
              <h2 class="text-xl font-bold">Účetní nastavení dokladu</h2>
              <p>
                Aktuální předpis: <strong>{@template_fields["typUcOp"] || "neurčen"}</strong>. Nákladový účet MD: <strong>{@template_fields["protiUcet"] || "doplní ABRA"}</strong>.
              </p>
              <p>
                Pro O2 zvolte odpovídající předpis služeb z vaší ABRA. Výběr převezme také jeho nákladový účet a účty DPH; původní účet potravin se nezachová.
              </p>
              <button
                :if={!@source_locked}
                type="button"
                class="btn"
                phx-click="accounting-load"
                phx-disable-with="Načítám…"
              >Načíst předpisy zaúčtování z ABRA</button>
              <p :if={@accounting_error} class="alert alert-error">{@accounting_error}</p>
              <.form
                for={@accounting_form}
                id="incoming-accounting-form"
                phx-change="accounting-change"
                phx-submit="accounting-save"
                class="space-y-3"
              >
                <fieldset disabled={@source_locked} class="space-y-3">
                  <.searchable_picker
                    field={@accounting_form[:preset]}
                    options={@accounting_options}
                    label="Nový předpis zaúčtování"
                    required={false}
                    prompt="Ponechat aktuální předpis"
                    placeholder="Načtěte číselník a hledejte název nebo účet…"
                    search_name="accounting_search"
                    search_event="accounting-search"
                    open_event="accounting-open"
                    close_event="accounting-close"
                    select_event="accounting-select"
                    query={@accounting_query}
                    open={@accounting_open}
                    empty_message="Žádný odpovídající předpis. Načtěte číselník z ABRA nebo upravte hledání."
                  />
                  <.input
                    field={@accounting_form[:internal_code]}
                    label="Interní číslo ABRA (nepovinné)"
                    maxlength="20"
                  />
                  <p class="text-sm">
                    Prázdné pole ponechá číslování na ABRA podle typu dokladu a jeho řady. Číslo dodavatelské faktury patří do „Číslo dokladu“, ne sem. Pokud ruční import číslo vyžaduje, lze je zde zadat a stáhnout nové XML.
                  </p>
                  <button
                    :if={!@source_locked}
                    class="btn btn-primary"
                    phx-disable-with="Ukládám…"
                  >Uložit účetní nastavení</button>
                </fieldset>
              </.form>
            </section>
            <section
              :if={@source_data != %{}}
              class="bg-white rounded-xl p-4 space-y-4"
              id="incoming-source-editor"
            >
              <h2 class="text-xl font-bold">Údaje přečtené z originálu</h2>
              <p>
                Částky lze zadat česky, např. 1 803,34. Prázdné pole znamená neznámý údaj. Uložení uchová návrh i s chybami a znovu sestaví XML z těchto údajů. Nahradí dosavadní opravy XML a zruší kontrolu ABRA; nic neodesílá.
              </p>
              <form
                id="incoming-source-form"
                phx-change="source-change"
                phx-submit="source-save"
                class="space-y-4"
              >
                <fieldset disabled={@source_locked} class="space-y-4">
                  <div class="grid md:grid-cols-3 gap-3">
                    <.input
                      :for={
                        {key, title} <- [
                          {"document_number", "Číslo dokladu"},
                          {"document_number_label", "Popisek čísla (např. EV-č)"},
                          {"variable_symbol", "Variabilní symbol"},
                          {"issue_date", "Datum vystavení"},
                          {"tax_date", "DUZP"},
                          {"due_date", "Datum splatnosti"},
                          {"currency", "Měna"},
                          {"total", "Celkem s DPH"}
                        ]
                      }
                      name={Editor.name([key])}
                      value={Editor.value(@source_data, [key])}
                      label={title}
                    />
                  </div>
                  <h3 class="font-bold">Dodavatel</h3>
                  <div class="grid md:grid-cols-3 gap-3">
                    <.input
                      :for={
                        {key, title} <- [
                          {"name", "Název"},
                          {"ic", "IČO"},
                          {"dic", "DIČ"},
                          {"street", "Ulice"},
                          {"city", "Město"},
                          {"postal_code", "PSČ"}
                        ]
                      }
                      name={Editor.name(["supplier", key])}
                      value={Editor.value(@source_data, ["supplier", key])}
                      label={title}
                    />
                  </div>
                  <h3 class="font-bold">Rekapitulace DPH</h3>
                  <div
                    :for={{row, index} <- Enum.with_index(@source_data["vat_summary"])}
                    class="border rounded-lg p-3 space-y-2"
                    data-vat-summary={index}
                  >
                    <p>Řádek {index + 1}</p>
                    <div class="grid md:grid-cols-4 gap-3">
                      <.input
                        :for={
                          {key, title} <- [
                            {"rate", "Sazba (%)"},
                            {"net", "Základ bez DPH"},
                            {"vat", "DPH"},
                            {"gross", "Částka s DPH (nepovinná)"}
                          ]
                        }
                        name={Editor.name(["vat_summary", index, key])}
                        value={row[key] || ""}
                        label={title}
                        errors={source_error(@source_issues, ["vat_summary", index, key])}
                      />
                    </div>
                    <button
                      type="button"
                      class="btn btn-sm"
                      phx-click="source-delete"
                      phx-value-collection="vat_summary"
                      phx-value-index={index}
                    >Odebrat sazbu</button>
                  </div>
                  <button
                    type="button"
                    class="btn btn-sm"
                    phx-click="source-add"
                    phx-value-collection="vat_summary"
                  >Přidat sazbu</button>
                  <details>
                    <summary>Legenda značek DPH</summary>
                    <div
                      :for={{row, index} <- Enum.with_index(@source_data["vat_legend"])}
                      class="flex flex-wrap items-end gap-3 my-3"
                    >
                      <.input
                        :for={{key, title} <- [{"marker", "Značka"}, {"rate", "Sazba (%)"}]}
                        name={Editor.name(["vat_legend", index, key])}
                        value={row[key] || ""}
                        label={title}
                      />
                      <button
                        type="button"
                        class="btn btn-sm"
                        phx-click="source-delete"
                        phx-value-collection="vat_legend"
                        phx-value-index={index}
                      >Odebrat</button>
                    </div>
                    <button
                      type="button"
                      class="btn btn-sm"
                      phx-click="source-add"
                      phx-value-collection="vat_legend"
                    >Přidat značku</button>
                  </details>
                  <h3 class="font-bold">Jednotlivé položky ({length(@source_data["items"])})</h3>
                  <details
                    :for={{row, index} <- Enum.with_index(@source_data["items"])}
                    class="border rounded-lg p-3"
                    data-source-item={index}
                  >
                    <summary>
                      Položka {index + 1}: {row["name"] || "bez názvu"} · množství {row["quantity"] ||
                        "?"} · celkem {row[
                        "line_total"
                      ] || "?"}
                    </summary>
                    <div class="grid md:grid-cols-3 gap-3 mt-3">
                      <.input
                        :for={
                          {key, title} <- [
                            {"name", "Název"},
                            {"quantity", "Množství"},
                            {"unit_price", "Jednotková cena"},
                            {"line_total", "Celkem za řádek"},
                            {"discount_percent", "Sleva (%)"},
                            {"vat_marker", "Značka DPH"},
                            {"vat_rate", "Sazba DPH (%)"},
                            {"raw_text", "Text přečtený z originálu"}
                          ]
                        }
                        name={Editor.name(["items", index, key])}
                        value={row[key] || ""}
                        label={title}
                      />
                      <.input
                        name={Editor.name(["items", index, "price_includes_vat"])}
                        value={Editor.value(@source_data, ["items", index, "price_includes_vat"])}
                        type="select"
                        label="Jednotková cena"
                        options={[
                          {"Neznámý typ ceny", ""},
                          {"Včetně DPH", "true"},
                          {"Bez DPH", "false"}
                        ]}
                      />
                    </div>
                    <button
                      type="button"
                      class="btn btn-sm mt-3"
                      phx-click="source-delete"
                      phx-value-collection="items"
                      phx-value-index={index}
                    >Odebrat položku</button>
                  </details>
                  <button
                    type="button"
                    class="btn btn-sm"
                    phx-click="source-add"
                    phx-value-collection="items"
                  >Přidat položku</button>
                  <.input
                    name={Editor.name(["complete"])}
                    value={Editor.value(@source_data, ["complete"])}
                    type="select"
                    label="Je přepis úplný?"
                    options={[{"Ano", "true"}, {"Ne", "false"}]}
                  />
                  <.input
                    name={Editor.name(["uncertainties"])}
                    value={Editor.value(@source_data, ["uncertainties"])}
                    type="textarea"
                    label="Nejasnosti (každá na samostatném řádku)"
                  />
                  <button
                    :if={!@source_locked}
                    class="btn btn-primary"
                    phx-disable-with="Ukládám…"
                  >Uložit návrh a zkontrolovat</button>
                </fieldset>
              </form>
              <details id="incoming-source-json">
                <summary>JSON aktuálního návrhu (pokročilé úpravy)</summary>
                <.form
                  :if={!@source_locked}
                  for={@transcription_form}
                  id="incoming-repair-data"
                  phx-change="repair-data-change"
                  phx-submit="repair-data"
                  class="space-y-3 mt-3"
                >
                  <.input
                    field={@transcription_form[:data]}
                    type="textarea"
                    label="JSON návrhu"
                    rows="16"
                    spellcheck="false"
                    class="textarea w-full font-mono text-xs"
                  />
                  <button class="btn" phx-disable-with="Ukládám…">Uložit JSON návrhu</button>
                </.form>
                <pre :if={@source_locked} class="text-xs whitespace-pre-wrap break-all">{Jason.encode!(@source_data, pretty: true)}</pre>
              </details>
              <details>
                <summary>Původní JSON modelu</summary><pre class="text-xs whitespace-pre-wrap break-all max-h-96 overflow-auto">{Jason.encode!(@doc.extracted_data, pretty: true)}</pre>
              </details>
            </section>
            <div :if={@doc.state == "failed" && @doc.error_stage == "extraction"} class="space-y-4">
              <p :if={!@doc.generated_xml} class="alert alert-info">
                XML z tohoto pokusu není uložené. Je-li dostupný přepis originálu níže, opravte jej; jinak spusťte vytěžení znovu.
              </p>
              <div :if={@accounting_differences != []} class="bg-white rounded-xl p-4 overflow-x-auto">
                <h2 class="text-lg font-bold">Rozdíly účetního nastavení</h2>
                <table id="incoming-accounting-differences" class="table">
                  <thead>
                    <tr>
                      <th>Pole</th><th>Hodnota ze vzoru</th><th>Hodnota v návrhu XML</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={diff <- @accounting_differences}>
                      <td>{label(diff.field)} <code>({diff.field})</code></td>
                      <td class="break-all">
                        {if diff.expected in [nil, ""],
                          do: "(ve vzoru není vyplněno)",
                          else: diff.expected}
                      </td>
                      <td class="break-all">
                        {if diff.actual == "", do: "(prázdné)", else: diff.actual}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <.form
                :if={@doc.generated_xml}
                for={@repair_form}
                id="incoming-repair"
                phx-change="repair-change"
                phx-submit="repair"
                class="bg-white rounded-xl p-4 space-y-3"
              >
                <h2 class="text-lg font-bold">Opravit výstup vytěžení</h2>
                <p>
                  Opravte XML podle uvedené chyby a originálu. Účetní nastavení musí odpovídat vzoru. Uložení znovu ověří celý doklad a nic neodesílá do ABRA.
                  Převzetí nastavení ze vzoru nemění částky ani nepřepočítává měnu; nastavení musí odpovídat originálu.
                </p>
                <.input
                  field={@repair_form[:xml]}
                  type="textarea"
                  label="XML k opravě"
                  rows="20"
                  spellcheck="false"
                  class="textarea w-full font-mono text-xs"
                />
                <div class="flex flex-wrap gap-3">
                  <button
                    class="btn btn-primary"
                    name="action"
                    value="save"
                    phx-disable-with="Kontroluji…"
                  >Uložit opravené XML</button>
                  <button
                    :if={@accounting_differences != []}
                    class="btn"
                    name="action"
                    value="restore"
                  >Použít účetní nastavení ze vzoru</button>
                </div>
              </.form>
            </div>
            <.form
              :if={@doc.current_xml}
              for={@edit_form}
              id="incoming-fields"
              phx-change="change"
              phx-submit="save"
              class="bg-white rounded-xl p-4 grid sm:grid-cols-2 gap-3"
            >
              <p class="sm:col-span-2">
                Porovnejte všechny údaje s originálem. XML i kontrola ABRA mohou obsahovat účetní chyby.
                Číslo původního dokladu může být označeno jako číslo účtenky či evidenční číslo; u PENNY hledejte EV-č i v patičce. Zachovejte počáteční nuly a oddělovače.
              </p>
              <.input
                :for={key <- XML.editable()}
                field={@edit_form[key]}
                label={label(key)}
                type={if XML.date?(key), do: "date", else: "text"}
                readonly={@doc.state != "review"}
              />
              <section :if={@items != []} class="sm:col-span-2 space-y-4" id="incoming-items">
                <h2 class="text-xl font-bold">Položky dokladu ({length(@items)})</h2>
                <p>
                  Částky hlavičky slouží ke kontrole proti rekapitulaci originálu. Do ABRA se odešlou položky a ABRA z nich spočítá součty. Změny položek musí odpovídat rekapitulaci. Případná doložená haléřová korekce je uvedena samostatně a vyžaduje potvrzení.
                </p>
                <fieldset
                  :for={{row, index} <- Enum.with_index(@items)}
                  class="border rounded-lg p-3 grid sm:grid-cols-2 gap-3"
                >
                  <legend class="font-semibold">Položka {index + 1}</legend>
                  <.input
                    :for={key <- ~w(nazev mnozMj cenaMj slevaPol)}
                    name={"fields[items][#{index}][#{key}]"}
                    value={item_value(@edit_form, index, key)}
                    label={label(key)}
                    readonly={@doc.state != "review"}
                  />
                  <.input
                    name={"fields[items][#{index}][typCenyDphK]"}
                    value={item_value(@edit_form, index, "typCenyDphK")}
                    type="select"
                    label="Typ ceny"
                    options={[{"Včetně DPH", "typCeny.sDph"}, {"Bez DPH", "typCeny.bezDph"}]}
                    disabled={@doc.state != "review"}
                  />
                  <.input
                    name={"fields[items][#{index}][typSzbDphK]"}
                    value={item_value(@edit_form, index, "typSzbDphK")}
                    type="select"
                    label="Sazba DPH položky"
                    options={[
                      {"Osvobozeno / bez DPH", "typSzbDph.dphOsv"},
                      {"Snížená sazba ze vzoru", "typSzbDph.dphSniz"},
                      {"Základní sazba ze vzoru", "typSzbDph.dphZakl"}
                    ]}
                    disabled={@doc.state != "review"}
                  />
                  <p class="sm:col-span-2 text-sm">
                    Uložené částky: základ {format_currency(Decimal.new(row["sumZkl"]))}, DPH {format_currency(
                      Decimal.new(row["sumDph"])
                    )}, celkem {format_currency(Decimal.new(row["sumCelkem"]))}.
                  </p>
                </fieldset>
              </section>
              <button
                :if={@doc.state == "review"}
                class="btn btn-primary sm:col-span-2"
                phx-disable-with="Ukládám…"
              >Uložit opravy</button>
            </.form>
            <details :if={@doc.template_xml} class="bg-white rounded-xl p-4">
              <summary>Účetní nastavení dokladu (vzor a vybraný předpis)</summary><dl class="space-y-1 mt-3">
                <div :for={key <- XML.fixed()} :if={@template_fields[key]}>
                  <dt class="font-semibold">{label(key)}</dt><dd>
                    {if key == "bezPolozek" && @doc.current_xml,
                      do: @fields[key],
                      else: @template_fields[key]}
                  </dd>
                </div>
              </dl>
            </details>
            <details :if={@doc.current_xml} class="bg-white rounded-xl p-4">
              <summary>XML k odeslání</summary><pre class="text-xs whitespace-pre-wrap break-all mt-3">{@doc.sent_xml && @doc.state != "review" && @doc.sent_xml || @import_xml}</pre>
            </details>
            <button
              :if={@doc.state == "review"}
              id="incoming-validate"
              class="btn"
              phx-click="validate"
              disabled={@dirty || @source_dirty || @accounting_dirty || !@enabled}
              phx-disable-with="Zařazuji…"
            >Zkontrolovat aktuální XML v ABRA</button>
            <div :if={@doc.dry_run["ok"]} class="alert alert-info">
              Kontrola ABRA proběhla. Před odesláním zkontrolujte originál, částky a účtování.
            </div>
            <ul :if={@doc.dry_run["warnings"] not in [nil, []]} class="bg-amber-50 p-4 rounded-xl">
              <li :for={warning <- @doc.dry_run["warnings"]}>{warning}</li>
            </ul>
            <form
              :if={@doc.state == "review" && @doc.dry_run["ok"]}
              id="incoming-approve"
              phx-submit="approve"
              class="space-y-3"
            >
              <label class="flex items-start gap-3"><input
                type="checkbox"
                name="reviewed"
                value="true"
                required
                class="checkbox"
              />
              Porovnal/a jsem údaje s originálem a schvaluji založení dokladu ve firmě {@doc.company_id}.</label>
              <label :if={@doc.dry_run["warnings"] != []} class="flex items-start gap-3"><input
                type="checkbox"
                name="warnings"
                value="true"
                required
                class="checkbox"
              /> Zkontroloval/a jsem upozornění ABRA a výslovně potvrzuji odeslání.</label>
              <label :if={@rounding != []} class="flex items-start gap-3"><input
                type="checkbox"
                name="rounding"
                value="true"
                required
                class="checkbox"
              />
              Zkontroloval/a jsem rekapitulaci originálu a schvaluji uvedenou samostatnou haléřovou korekci DPH.</label>
              <button
                class="btn btn-primary"
                disabled={@dirty || @source_dirty || @accounting_dirty || !@enabled}
                phx-disable-with="Schvaluji…"
              >Schválit a odeslat</button>
            </form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp upload_error(:too_large), do: "Soubor je větší než 10 MB"
  defp upload_error(:not_accepted), do: "Vyberte PDF, JPEG nebo PNG"
  defp upload_error(:too_many_files), do: "Nahrajte pouze jeden soubor"
  defp upload_error(_), do: "Nahrání souboru selhalo"
end

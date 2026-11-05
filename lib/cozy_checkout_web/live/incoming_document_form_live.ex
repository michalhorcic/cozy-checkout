defmodule CozyCheckoutWeb.IncomingDocumentFormLive do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.IncomingDocuments
  alias CozyCheckout.IncomingDocuments.{Client, Extractor, HeaderForm, ResponseDiagnostics, XML}
  import CozyCheckoutWeb.KitchenComponents, only: [searchable_picker: 1]

  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Nový doklad — formulář",
       doc: nil,
       agenda: "faktura-prijata",
       values: HeaderForm.defaults(),
       reviewed: false,
       dirty: false,
       accounting_options: [],
       accounting_open: false,
       accounting_query: nil,
       accounting_error: nil,
       accounting_dirty: false,
       accounting_form: to_form(%{"preset" => "", "internal_code" => ""}, as: :fields)
     )
     |> allow_upload(:source,
       accept: ~w(.pdf .png .jpg .jpeg),
       max_entries: 1,
       max_file_size: IncomingDocuments.max_size()
     )}
  end

  def handle_params(params, _, socket) do
    socket =
      case socket.assigns.live_action do
        :index ->
          assign(socket,
            page_title: "Přijaté doklady",
            doc: nil,
            documents: IncomingDocuments.list()
          )

        :new ->
          assign(socket,
            doc: nil,
            values: HeaderForm.defaults(),
            agenda: "faktura-prijata",
            dirty: false,
            reviewed: false
          )

        :edit ->
          load(socket, params["id"])
      end

    if connected?(socket) and busy?(socket.assigns.doc),
      do: Process.send_after(self(), :refresh, 2000)

    {:noreply, socket}
  end

  def handle_info(:refresh, %{assigns: %{doc: nil}} = socket), do: {:noreply, socket}

  def handle_info(:refresh, socket) do
    doc = IncomingDocuments.get!(socket.assigns.doc.id)
    if busy?(doc), do: Process.send_after(self(), :refresh, 2000)

    {:noreply,
     if(socket.assigns.dirty or socket.assigns.accounting_dirty,
       do: assign(socket, doc: doc),
       else: assign_document(socket, doc)
     )}
  end

  defp busy?(nil), do: false
  defp busy?(doc), do: doc.state in ~w(uploaded processing validating sending uncertain)

  def handle_event("upload-change", _, socket), do: {:noreply, socket}

  def handle_event("change", %{"document" => attrs} = params, socket) do
    {:noreply,
     assign(socket,
       values: Map.take(attrs, HeaderForm.keys()),
       reviewed: params["reviewed"] == "true",
       agenda:
         if(socket.assigns.doc,
           do: socket.assigns.doc.agenda,
           else: params["agenda"] || socket.assigns.agenda
         ),
       dirty: true
     )}
  end

  def handle_event("upload", %{"agenda" => agenda}, socket) do
    if socket.assigns.doc do
      {:noreply, put_flash(socket, :error, "Pro další originál založte nový formulář.")}
    else
      results =
        consume_uploaded_entries(socket, :source, fn %{path: path}, entry ->
          {:ok,
           IncomingDocuments.upload(File.read!(path), entry.client_name, agenda, "header_form")}
        end)

      case results do
        [{:ok, %{document: doc, duplicate?: duplicate}}] ->
          message =
            if duplicate,
              do: "Pozor, tento soubor už je nahraný. Ověřte duplicitu.",
              else: "Originál nahrán. Připravujeme návrhy do formuláře."

          {:noreply,
           socket
           |> put_flash(:info, message)
           |> assign(reviewed: false, dirty: false)
           |> push_patch(to: ~p"/admin/incoming-document-form/#{doc.id}")}

        [{:error, reason}] ->
          {:noreply, put_flash(socket, :error, reason)}

        _ ->
          {:noreply,
           put_flash(socket, :error, "Vyberte soubor a počkejte na dokončení nahrávání.")}
      end
    end
  end

  def handle_event("save", %{"document" => attrs} = params, socket) do
    socket = assign(socket, values: Map.take(attrs, HeaderForm.keys()), dirty: true)

    if params["reviewed"] != "true" do
      {:noreply, put_flash(socket, :error, "Potvrďte kontrolu údajů, měny CZK a rozpisu DPH.")}
    else
      result =
        if socket.assigns.doc do
          IncomingDocuments.save_header(socket.assigns.doc.id, attrs, socket.assigns.hash)
        else
          IncomingDocuments.create_header(params["agenda"], attrs)
        end

      case result do
        {:ok, doc} ->
          {:noreply,
           socket
           |> assign_document(doc)
           |> put_flash(
             :info,
             "Formulář uložen. Níže můžete zvolit předpis, ověřit doklad nebo jej odeslat do ABRA."
           )
           |> push_patch(to: ~p"/admin/incoming-document-form/#{doc.id}")}

        {:error, reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             if(is_binary(reason), do: reason, else: "Doklad se nepodařilo uložit.")
           )}
      end
    end
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
    with {:ok, preset} <- Base.url_decode64(attrs["preset"] || "", padding: false),
         {:ok, doc} <-
           IncomingDocuments.save_accounting(
             socket.assigns.doc.id,
             Map.put(attrs, "preset", preset),
             socket.assigns.hash
           ) do
      previous = Map.take(socket.assigns, [:values, :dirty, :reviewed])
      socket = socket |> assign(accounting_dirty: false) |> assign_document(doc)
      socket = if previous.dirty, do: assign(socket, previous), else: socket
      {:noreply, put_flash(socket, :info, "Předpis zaúčtování uložen.")}
    else
      :error -> {:noreply, put_flash(socket, :error, "Vyberte předpis z načteného číselníku")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("validate", _, socket) do
    operation(
      socket,
      fn doc ->
        if doc.current_xml,
          do: IncomingDocuments.validate(doc.id, IncomingDocuments.digest(doc.current_xml)),
          else: {:error, "Nejprve uložte formulář"}
      end,
      "Probíhá dry-run v ABRA bez zápisu."
    )
  end

  def handle_event("send", params, socket) do
    operation(
      socket,
      fn doc ->
        if doc.current_xml do
          IncomingDocuments.send_header(
            doc.id,
            IncomingDocuments.digest(doc.current_xml),
            params["confirm_send"] == "true"
          )
        else
          {:error, "Nejprve uložte formulář"}
        end
      end,
      "Doklad byl zařazen k odeslání do ABRA."
    )
  end

  def handle_event("verify", _, socket) do
    operation(
      socket,
      fn doc -> IncomingDocuments.verify(doc.id) end,
      "Ověřujeme existenci dokladu v ABRA bez opakování zápisu."
    )
  end

  def handle_event("retry", _, socket) do
    operation(
      socket,
      fn doc -> IncomingDocuments.retry_extraction(doc.id, "header_form") end,
      "Probíhá nové vytěžení."
    )
  end

  defp operation(socket, action, message) do
    if socket.assigns.dirty or socket.assigns.accounting_dirty do
      {:noreply,
       put_flash(socket, :error, "Nejprve uložte změny formuláře a účetního nastavení.")}
    else
      case action.(socket.assigns.doc) do
        {:ok, doc} ->
          if busy?(doc), do: Process.send_after(self(), :refresh, 2000)
          {:noreply, socket |> assign_document(doc) |> put_flash(:info, message)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, reason)}
      end
    end
  end

  defp load(socket, id), do: assign_document(socket, IncomingDocuments.get!(id))

  defp assign_document(socket, doc) do
    same? = socket.assigns.doc && socket.assigns.doc.id == doc.id

    socket =
      if same? && socket.assigns.accounting_dirty do
        socket
      else
        assign(socket,
          accounting_dirty: false,
          accounting_form:
            to_form(%{"preset" => "", "internal_code" => doc.accounting_settings["kod"] || ""},
              as: :fields
            ),
          accounting_open: false,
          accounting_query: nil
        )
      end

    {:ok, template_fields} = XML.parse(XML.template_for(doc), doc.agenda)

    assign(socket,
      doc: doc,
      agenda: doc.agenda,
      values: HeaderForm.values(doc),
      hash: IncomingDocuments.transcription_hash(doc),
      reviewed: false,
      dirty: false,
      template_fields: template_fields,
      responses: [
        {"Kontrola ABRA (dry-run)", ResponseDiagnostics.for_display(doc.dry_run)},
        {"Odeslání do ABRA", ResponseDiagnostics.for_display(doc.response)}
      ]
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
          "uncertain" => "Nutno ověřit v ABRA",
          "sent" => "Odesláno",
          "failed" => "Chyba"
        },
        state,
        state
      )

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :locked,
        assigns.doc &&
          (assigns.doc.state not in ~w(review failed) or not is_nil(assigns.doc.sent_xml) or
             (assigns.doc.state == "failed" and assigns.doc.error_stage != "extraction"))
      )

    ~H"""
    <Layouts.app flash={@flash} content_class="mx-auto w-full max-w-7xl space-y-6">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h1 class="text-3xl font-bold">
          {if @live_action == :index, do: "Přijaté doklady", else: "Přijatý doklad"}
        </h1>
        <.link :if={@live_action != :index} navigate={~p"/admin/incoming-documents"} class="btn">Přijaté doklady</.link>
      </div>
      <div :if={@live_action == :index} class="space-y-4">
        <.link navigate={~p"/admin/incoming-document-form"} class="btn btn-primary">Nový doklad</.link>
        <div class="overflow-x-auto">
          <table class="table" id="incoming-list">
            <thead>
              <tr>
                <th>Doklad</th><th>Agenda</th><th>Stav</th><th>Firma ABRA</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={doc <- @documents}>
                <td>
                  <.link navigate={~p"/admin/incoming-document-form/#{doc.id}"} class="link">{doc.filename}</.link>
                </td>
                <td>{IncomingDocuments.agenda_label(doc.agenda)}</td><td>{state_label(doc.state)}</td><td>
                  {doc.company_id}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <div :if={@live_action != :index} class="space-y-6">
        <p>
          Vyberte agendu a vyplňte hlavičku a souhrnnou DPH. Obrázek nebo PDF může navrhnout údaje. Položky zůstanou pouze v poznámce.
        </p>
        <p class="alert alert-info">
          Pilot pro tuzemské doklady v CZK se sazbami 0 %, 12 % a 21 %. Účetní nastavení vychází ze vzoru vybrané agendy; před odesláním je zkontrolujte níže.
        </p>
        <p :if={@doc} class="font-semibold">
          {IncomingDocuments.agenda_label(@doc.agenda)} · {state_label(@doc.state)} · Firma ABRA: {@doc.company_id}
        </p>
        <p
          :if={@doc && Extractor.strategy(@doc) != "header_form" && is_nil(@doc.sent_xml)}
          class="alert alert-info"
        >
          Tento doklad vznikl ve starším postupu. Uložením formuláře se převede na souhrnný doklad bez nákupních položek.
        </p>
        <p :if={@doc && @doc.error} class="alert alert-warning">
          {@doc.error} Údaje můžete doplnit ručně.
        </p>
        <p :if={@doc && @doc.state in ~w(uploaded processing)} role="status">
          Probíhá vytěžení originálu…
        </p>
        <p :if={@doc && @doc.extracted_data != %{}} class="alert alert-info">
          Návrhy z originálu vyžadují kontrolu. Měna v originálu: {@doc.extracted_data["currency"] ||
            "nezjištěna"}. {Enum.join(@doc.extracted_data["uncertainties"] || [], "; ")}
        </p>
        <details :if={@doc && @doc.extracted_data != %{}} class="bg-base-200 rounded-lg p-4">
          <summary>Rekapitulace DPH přečtená z originálu</summary>
          <table class="table">
            <thead>
              <tr>
                <th>Sazba</th><th>Základ</th><th>DPH</th><th>Celkem</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @doc.extracted_data["vat_summary"] || []}>
                <td>{row["rate"]}</td><td>{row["net"]}</td><td>{row["vat"]}</td><td>
                  {row["gross"]}
                </td>
              </tr>
            </tbody>
          </table>
        </details>
        <div class="grid gap-6 lg:grid-cols-2">
          <.form
            for={to_form(@values, as: :document)}
            id="incoming-header-form"
            phx-change="change"
            phx-submit="save"
            class="space-y-4"
          >
            <.input
              type="select"
              name="agenda"
              value={@agenda}
              label="Agenda"
              options={IncomingDocuments.agendas()}
              disabled={@doc != nil}
            />
            <input :if={@doc} type="hidden" name="agenda" value={@agenda} />
            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                :for={{key, label, type} <- HeaderForm.fields()}
                type={type}
                name={"document[#{key}]"}
                value={@values[key] || ""}
                label={label}
                disabled={@locked}
              />
            </div>
            <.input
              type="textarea"
              name="document[poznam]"
              value={@values["poznam"] || ""}
              label="Poznámka — orientační přepis položek"
              disabled={@locked}
            />
            <.input
              type="checkbox"
              name="reviewed"
              value="true"
              checked={@reviewed}
              label="Zkontroloval/a jsem údaje, měnu CZK a souhrnný rozpis DPH."
              disabled={@locked}
            />
            <button class="btn btn-primary" disabled={@locked} phx-disable-with="Ukládám…">Uložit formulář</button>
          </.form>
          <div class="space-y-4">
            <.form
              :if={!@doc}
              for={%{}}
              id="incoming-header-upload"
              phx-change="upload-change"
              phx-submit="upload"
              class="card bg-base-200 p-4 space-y-3"
            >
              <h2 class="text-xl font-semibold">Navrhnout údaje z originálu</h2>
              <input type="hidden" name="agenda" value={@agenda} />
              <p>
                Nahrajte originál před ručním vyplňováním. Otevře se nový návrh podle zvolené agendy.
              </p>
              <.live_file_input upload={@uploads.source} />
              <p :for={error <- upload_errors(@uploads.source)} class="text-error">
                {inspect(error)}
              </p>
              <p :for={entry <- @uploads.source.entries}>{entry.client_name} — {entry.progress} %</p>
              <button class="btn">Vytěžit přes OpenAI</button>
            </.form>
            <iframe
              :if={@doc && @doc.original && @doc.content_type == "application/pdf"}
              src={~p"/admin/incoming-documents/#{@doc.id}/original"}
              title="Originál dokladu"
              class="w-full min-h-[75vh] border rounded-lg"
            />
            <img
              :if={@doc && @doc.original && @doc.content_type != "application/pdf"}
              src={~p"/admin/incoming-documents/#{@doc.id}/original"}
              alt="Originál dokladu"
              class="w-full rounded-lg"
            />
          </div>
        </div>
        <div :if={@doc} class="space-y-5">
          <section class="bg-white rounded-xl p-4 space-y-3" id="incoming-accounting">
            <h2 class="text-xl font-bold">Účetní nastavení dokladu</h2>
            <p>
              Aktuální předpis: <strong>{@template_fields["typUcOp"] || "neurčen"}</strong>. Nákladový účet MD: <strong>{@template_fields["protiUcet"] || "doplní ABRA"}</strong>.
            </p>
            <p>Výběr předpisu převezme nákladový účet a účty DPH z ABRA.</p>
            <button
              :if={!@locked}
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
              <fieldset disabled={@locked} class="space-y-3">
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
                  :if={!@locked}
                  class="btn btn-primary"
                  phx-disable-with="Ukládám…"
                >Uložit účetní nastavení</button>
              </fieldset>
            </.form>
          </section>
          <section class="bg-base-200 rounded-xl p-4 space-y-4" id="incoming-delivery">
            <h2 class="text-xl font-bold">Kontrola a odeslání do ABRA</h2>
            <p>
              Dry-run je volitelná kontrola bez zápisu. Tlačítko Nahrát do ABRA provede skutečné vytvoření uloženého dokladu i bez úspěšného dry-runu.
            </p>
            <p :if={@dirty or @accounting_dirty} class="text-warning">
              Nejprve uložte změny formuláře a účetního nastavení.
            </p>
            <.link
              :if={@doc.current_xml && !@dirty && !@accounting_dirty}
              href={~p"/admin/incoming-documents/#{@doc.id}/draft.xml"}
              class="btn"
              download
            >Stáhnout XML</.link>
            <button
              :if={@doc.current_xml && is_nil(@doc.sent_xml)}
              id="incoming-validate"
              phx-click="validate"
              class="btn"
              disabled={@locked or @dirty or @accounting_dirty}
              phx-disable-with="Zařazuji…"
            >Ověřit v ABRA (dry-run)</button>
            <p :if={@doc.dry_run["ok"]} class="alert alert-success">
              Dry-run aktuálního dokladu proběhl úspěšně.
            </p>
            <ul :if={@doc.dry_run["warnings"] not in [nil, []]} class="text-warning">
              <li :for={warning <- @doc.dry_run["warnings"]}>{warning}</li>
            </ul>
            <.form
              :if={
                @doc.current_xml && is_nil(@doc.sent_xml) && Extractor.strategy(@doc) == "header_form"
              }
              for={%{}}
              id="incoming-send"
              phx-submit="send"
              class="space-y-3"
            >
              <.input
                type="checkbox"
                name="confirm_send"
                checked={false}
                label="Potvrzuji skutečné vytvoření dokladu v ABRA. Zkontroloval/a jsem údaje, předpis a případný dřívější ruční import."
                disabled={@locked or @dirty or @accounting_dirty}
              />
              <button
                class="btn btn-primary"
                disabled={@locked or @dirty or @accounting_dirty}
                phx-disable-with="Odesílám…"
              >Nahrát do ABRA</button>
            </.form>
            <p :if={@doc.state == "uncertain"} class="alert alert-warning">
              Výsledek zápisu není potvrzený. Zkontrolujte ABRA; nový zápis je zablokovaný, aby nevznikl duplicitní doklad.
            </p>
            <button
              :if={@doc.state == "uncertain"}
              phx-click="verify"
              class="btn"
              phx-disable-with="Ověřuji…"
            >Ověřit v ABRA bez opakování zápisu</button>
            <p :if={@doc.state == "sent"} class="alert alert-success">
              Doklad je v ABRA, ID {@doc.remote_id}.
              <a href={Client.document_url(@doc)} class="link" target="_blank" rel="noopener">Otevřít v ABRA</a>
            </p>
            <button
              :if={@doc.original && !@locked}
              phx-click="retry"
              class="btn"
              data-confirm="Nové vytěžení nahradí ruční opravy. Pokračovat?"
            >Znovu vytěžit originál</button>
          </section>
          <details
            :for={{title, response} <- @responses}
            :if={response["http_status"]}
            class="bg-base-200 rounded-xl p-4"
            data-abra-response
          >
            <summary>{title} — HTTP {response["http_status"]}</summary>
            <p :if={response["format_diagnostic"]}>{response["format_diagnostic"]["summary"]}</p>
            <p :if={response["format_diagnostic"]}>{response["format_diagnostic"]["hint"]}</p>
            <ul>
              <li :for={error <- response["errors"] || []}>{error}</li><li :for={
                warning <- response["warnings"] || []
              }>
                {warning}
              </li>
            </ul>
            <details>
              <summary>Technické podrobnosti odpovědi</summary><pre class="text-xs whitespace-pre-wrap break-all max-h-96 overflow-auto">{Jason.encode!(response, pretty: true)}</pre>
            </details>
          </details>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

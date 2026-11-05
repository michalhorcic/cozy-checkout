defmodule CozyCheckoutWeb.IncomingDocumentsLive do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.IncomingDocuments
  alias CozyCheckout.IncomingDocuments.{Client, XML}

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

  def handle_event("upload", %{"agenda" => agenda}, socket) do
    results =
      consume_uploaded_entries(socket, :original, fn %{path: path}, entry ->
        {:ok, IncomingDocuments.upload(File.read!(path), entry.client_name, agenda)}
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

  def handle_event("validate", _, socket) do
    if socket.assigns.dirty,
      do: {:noreply, put_flash(socket, :error, "Nejprve uložte změny")},
      else:
        result(
          socket,
          IncomingDocuments.validate(socket.assigns.doc.id, socket.assigns.hash),
          "Probíhá kontrola v ABRA"
        )
  end

  def handle_event("approve", attrs, socket) do
    if socket.assigns.dirty or attrs["reviewed"] != "true",
      do: {:noreply, put_flash(socket, :error, "Uložte změny a potvrďte porovnání s originálem")},
      else:
        result(
          socket,
          IncomingDocuments.approve(
            socket.assigns.doc.id,
            socket.assigns.hash,
            attrs["warnings"] == "true"
          ),
          "Doklad schválen. Probíhá přenos do ABRA."
        )
  end

  def handle_event("retry", _, socket),
    do:
      result(
        socket,
        IncomingDocuments.retry_extraction(socket.assigns.doc.id),
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

  defp input_fields(attrs),
    do: Map.reject(attrs, fn {key, _} -> String.starts_with?(key, "_unused_") end)

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

    assign(socket,
      doc: doc,
      fields: fields,
      edit_form: to_form(Map.take(fields, XML.editable()), as: :fields),
      dirty: false,
      hash: if(doc.current_xml, do: IncomingDocuments.digest(doc.current_xml)),
      enabled: IncomingDocuments.enabled?()
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
          "cisDosle" => "Číslo dokladu",
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
          "primUcet" => "Účet DAL",
          "protiUcet" => "Účet MD",
          "clenDph" => "Řádky DPH",
          "clenKonVykDph" => "Kontrolní hlášení",
          "pokladna" => "Pokladna",
          "stredisko" => "Středisko"
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
          :if={@doc.state == "failed" && @doc.error_stage == "extraction"}
          phx-click="retry"
          class="btn"
          phx-disable-with="Zařazuji…"
        >Znovu vytěžit</button>
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
              </p>
              <.input
                :for={key <- XML.editable()}
                field={@edit_form[key]}
                label={label(key)}
                type={if XML.date?(key), do: "date", else: "text"}
                readonly={@doc.state != "review"}
              />
              <button
                :if={@doc.state == "review"}
                class="btn btn-primary sm:col-span-2"
                phx-disable-with="Ukládám…"
              >Uložit opravy</button>
            </.form>
            <details :if={@doc.current_xml} class="bg-white rounded-xl p-4">
              <summary>Účetní nastavení ze vzoru</summary><dl class="space-y-1 mt-3">
                <div :for={key <- XML.fixed()} :if={@fields[key]}>
                  <dt class="font-semibold">{label(key)}</dt><dd>{@fields[key]}</dd>
                </div>
              </dl>
            </details>
            <details :if={@doc.current_xml} class="bg-white rounded-xl p-4">
              <summary>XML k odeslání</summary><pre class="text-xs whitespace-pre-wrap break-all mt-3">{@doc.sent_xml && @doc.state != "review" && @doc.sent_xml || @doc.current_xml}</pre>
            </details>
            <button
              :if={@doc.state == "review"}
              id="incoming-validate"
              class="btn"
              phx-click="validate"
              disabled={@dirty || !@enabled}
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
              <button
                class="btn btn-primary"
                disabled={@dirty || !@enabled}
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

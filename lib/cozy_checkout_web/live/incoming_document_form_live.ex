defmodule CozyCheckoutWeb.IncomingDocumentFormLive do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.IncomingDocuments
  alias CozyCheckout.IncomingDocuments.{Extractor, HeaderForm}

  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Nový doklad — formulář",
       doc: nil,
       agenda: "faktura-prijata",
       values: HeaderForm.defaults(),
       reviewed: false,
       dirty: false
     )
     |> allow_upload(:source,
       accept: ~w(.pdf .png .jpg .jpeg),
       max_entries: 1,
       max_file_size: IncomingDocuments.max_size()
     )}
  end

  def handle_params(params, _, socket) do
    socket = if params["id"], do: load(socket, params["id"]), else: socket

    if (connected?(socket) and socket.assigns.doc) &&
         socket.assigns.doc.state in ~w(uploaded processing),
       do: Process.send_after(self(), :refresh, 2000)

    {:noreply, socket}
  end

  def handle_info(:refresh, socket) do
    doc = IncomingDocuments.get!(socket.assigns.doc.id)
    if doc.state in ~w(uploaded processing), do: Process.send_after(self(), :refresh, 2000)
    {:noreply, if(socket.assigns.dirty, do: assign(socket, doc: doc), else: load(socket, doc.id))}
  end

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
           |> put_flash(
             :info,
             "Formulář uložen. Zkontrolujte účetní předpis a spusťte dry-run v ABRA."
           )
           |> push_navigate(to: ~p"/admin/incoming-documents/#{doc.id}")}

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

  defp load(socket, id) do
    doc = IncomingDocuments.get!(id)

    if Extractor.strategy(doc) != "header_form",
      do: raise(Ecto.NoResultsError, queryable: "incoming document form")

    assign(socket,
      doc: doc,
      agenda: doc.agenda,
      values: HeaderForm.values(doc),
      hash: IncomingDocuments.transcription_hash(doc),
      reviewed: false,
      dirty: false
    )
  end

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
        <h1 class="text-3xl font-bold">Nový doklad — formulář</h1>
        <.link navigate={~p"/admin/incoming-documents"} class="btn">Přijaté doklady</.link>
      </div>
      <p>
        Vyberte agendu a vyplňte hlavičku a souhrnnou DPH. Obrázek nebo PDF může navrhnout údaje. Položky zůstanou pouze v poznámce.
      </p>
      <p class="alert alert-info">
        Pilot pro tuzemské doklady v CZK se sazbami 0 %, 12 % a 21 %. Účetní nastavení vychází ze vzoru vybrané agendy; před odesláním je ověříte v dalším kroku.
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
              <td>{row["rate"]}</td><td>{row["net"]}</td><td>{row["vat"]}</td><td>{row["gross"]}</td>
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
          <button class="btn btn-primary" disabled={@locked}>Uložit a pokračovat ke kontrole ABRA</button>
          <.link
            :if={@doc}
            navigate={~p"/admin/incoming-documents/#{@doc.id}"}
            class="btn"
          >Detail a účetní nastavení</.link>
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
            <p :for={error <- upload_errors(@uploads.source)} class="text-error">{inspect(error)}</p>
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
    </Layouts.app>
    """
  end
end

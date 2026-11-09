defmodule CozyCheckoutWeb.IncomingDocumentBatchesLive do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.IncomingDocuments
  alias CozyCheckout.IncomingDocuments.Batches
  import CozyCheckoutWeb.KitchenComponents, only: [searchable_picker: 1]

  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Dávky dokladů",
       batch: nil,
       rows: [],
       page: 0,
       presets: [],
       preset: "",
       accounting_open: false,
       accounting_query: nil,
       settings_dirty: false,
       include_items: false,
       duplicates: %{},
       upload_messages: [],
       queued_uploads: [],
       upload_preparing: false
     )
     |> allow_upload(:sources,
       accept: ~w(.pdf .png .jpg .jpeg),
       max_entries: max(2, Batches.limit()),
       max_file_size: IncomingDocuments.max_size(),
       auto_upload: true,
       progress: &upload_progress/3
     )}
  end

  def handle_params(params, _, socket) do
    socket =
      case socket.assigns.live_action do
        :index ->
          assign(socket, batches: Batches.list(socket.assigns.page))

        :new ->
          assign(socket, batch: nil)

        :show ->
          {:ok, batch} = Batches.refresh(params["id"])
          socket |> assign(batch: batch, include_items: batch.include_items) |> reload()
      end

    if connected?(socket), do: Process.send_after(self(), :refresh, 2000)
    {:noreply, socket}
  end

  def handle_info(:refresh, socket) do
    socket =
      case socket.assigns.live_action do
        :index -> assign(socket, batches: Batches.list(socket.assigns.page))
        :show -> reload(socket)
        _ -> socket
      end

    Process.send_after(self(), :refresh, 2000)
    {:noreply, socket}
  end

  def handle_event("create", %{"batch" => attrs}, socket) do
    case Batches.create(attrs) do
      {:ok, batch} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/incoming-document-batches/#{batch.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("cancel-queued", %{"index" => index}, socket),
    do: {:noreply, push_event(socket, "batch-upload-remove", %{index: index})}

  def handle_event("upload-queue", %{"names" => names} = params, socket) do
    {:noreply,
     assign(socket,
       queued_uploads: Enum.take(names, 1000),
       upload_preparing: params["preparing"] == true
     )}
  end

  def handle_event("upload-preparation-error", %{"name" => name}, socket) do
    message =
      "Fotku #{String.slice(name, 0, 150)} se nepodařilo připravit. Zkuste ji vybrat jako JPEG nebo vyfotit znovu."

    {:noreply, assign(socket, upload_messages: [message | socket.assigns.upload_messages])}
  end

  def handle_event("preset-change", _, socket), do: {:noreply, socket}

  def handle_event("upload-change", _, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do:
      {:noreply,
       socket
       |> cancel_upload(:sources, ref)
       |> assign(duplicates: Map.delete(socket.assigns.duplicates, ref))}

  def handle_event("allow-duplicate", %{"ref" => ref}, socket) do
    entry = Enum.find(socket.assigns.uploads.sources.entries, &(&1.ref == ref))

    if entry && socket.assigns.duplicates[ref] do
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok,
           Batches.add_source(socket.assigns.batch.id, File.read!(path), entry.client_name,
             allow_duplicate: true
           )}
        end)

      {:noreply,
       socket
       |> assign(duplicates: Map.delete(socket.assigns.duplicates, ref))
       |> upload_result(result)
       |> reload()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove", %{"id" => id}, socket),
    do: result(socket, Batches.remove_source(socket.assigns.batch.id, id))

  def handle_event("start", _, socket) do
    cond do
      socket.assigns.upload_preparing || socket.assigns.uploads.sources.entries != [] ||
          socket.assigns.queued_uploads != [] ->
        {:noreply, put_flash(socket, :error, "Počkejte na dokončení uploadů nebo je odeberte.")}

      socket.assigns.settings_dirty ->
        {:noreply, put_flash(socket, :error, "Nejprve uložte společné účetní nastavení.")}

      true ->
        result(socket, Batches.start(socket.assigns.batch.id))
    end
  end

  def handle_event("settings-change", params, socket),
    do:
      {:noreply,
       assign(socket, include_items: params["include_items"] == "true", settings_dirty: true)}

  def handle_event("settings-save", _, socket),
    do:
      result(
        socket,
        Batches.save_settings(
          socket.assigns.batch.id,
          socket.assigns.preset,
          socket.assigns.include_items
        ),
        true
      )

  def handle_event("accounting-load", _, socket) do
    case Batches.presets(socket.assigns.batch.id) do
      {:ok, rows} ->
        {:noreply,
         assign(socket,
           presets:
             Enum.map(rows, &%{id: &1["kod"], hint: "", name: "#{&1["kod"]} — #{&1["nazev"]}"}),
           accounting_open: true
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("accounting-open", _, socket),
    do: {:noreply, assign(socket, accounting_open: true)}

  def handle_event("accounting-close", _, socket),
    do: {:noreply, assign(socket, accounting_open: false)}

  def handle_event("accounting-search", params, socket),
    do:
      {:noreply,
       assign(socket, accounting_query: get_in(params, ["accounting_search", "0"]) || "")}

  def handle_event("accounting-select", %{"id" => id}, socket),
    do: {:noreply, assign(socket, preset: id, settings_dirty: true, accounting_open: false)}

  def handle_event("page", %{"delta" => delta}, socket) do
    page = max(0, socket.assigns.page + String.to_integer(delta))
    {:noreply, assign(socket, page: page, batches: Batches.list(page))}
  end

  defp upload_progress(:sources, entry, socket) do
    if entry.done? do
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          case Batches.add_source(socket.assigns.batch.id, File.read!(path), entry.client_name) do
            {:error, {:duplicate, duplicate}} -> {:postpone, {:duplicate, duplicate}}
            result -> {:ok, result}
          end
        end)

      socket =
        case result do
          {:duplicate, duplicate} ->
            assign(socket, duplicates: Map.put(socket.assigns.duplicates, entry.ref, duplicate))

          result ->
            upload_result(socket, result)
        end

      {:noreply, reload(socket)}
    else
      {:noreply, socket}
    end
  end

  defp upload_result(socket, {:ok, _}), do: socket

  defp upload_result(socket, {:error, reason}),
    do: assign(socket, upload_messages: [reason | socket.assigns.upload_messages])

  defp result(socket, result, settings \\ false) do
    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(settings_dirty: if(settings, do: false, else: socket.assigns.settings_dirty))
         |> reload()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  defp reload(socket) do
    {:ok, batch} = Batches.refresh(socket.assigns.batch.id)

    assign(socket,
      batch: batch,
      rows: Batches.documents(batch.id, batch.max_files),
      counts: Batches.progress(batch.id)
    )
  end

  defp review_id(rows),
    do: Enum.find(rows, &(&1.state != "sent" and is_nil(&1.deferred_at))) || List.first(rows)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} content_class="mx-auto w-full max-w-7xl space-y-6">
      <h1 class="text-3xl font-bold">
        {if @live_action == :new, do: "Nahrát doklady", else: "Dávky přijatých dokladů"}
      </h1>
      <div class="flex gap-3 flex-wrap">
        <.link navigate={~p"/admin/incoming-documents"} class="btn">Přijaté doklady</.link>
        <.link navigate={~p"/admin/incoming-document-batches"} class="btn">Přehled dávek</.link>
        <.link navigate={~p"/admin/incoming-document-batches/new"} class="btn btn-primary"><.icon
          name="hero-camera"
          class="size-5"
        /> Nahrát doklady</.link>
      </div>
      <div :if={@live_action == :index} id="batch-list" class="space-y-4">
        <article :for={row <- @batches} class="card bg-base-100 p-4 border">
          <.link
            navigate={~p"/admin/incoming-document-batches/#{row.batch.id}"}
            class="link font-bold"
          >{row.batch.name}</.link>
          <p>{row.total} dokladů · Odesláno {row.sent} · Firma {row.batch.company_id}</p>
          <p :if={row.batch.extraction_finished_at} role="status">
            Vytěžování dokončeno: {row.extracted} vytěženo, {row.failed} chyb. Dávka je připravena ke kontrole.
          </p>
          <p :if={!row.batch.started_at}>Příprava — AI dosud nebyla spuštěna.</p>
          <p :if={row.batch.started_at && !row.batch.extraction_finished_at}>Probíhá vytěžování…</p>
        </article>
        <button class="btn" phx-click="page" phx-value-delta="-1" disabled={@page == 0}>Předchozí stránka</button>
        <button class="btn" phx-click="page" phx-value-delta="1" disabled={length(@batches) < 25}>Další stránka</button>
      </div>
      <.form
        :if={@live_action == :new}
        for={to_form(%{}, as: :batch)}
        id="batch-create"
        phx-submit="create"
        class="space-y-4"
      >
        <.input
          name="batch[agenda]"
          type="select"
          label="Kategorie"
          options={Batches.categories()}
          value="faktura-prijata"
        />
        <.input name="batch[name]" label="Název (nepovinný)" value="" maxlength="150" />
        <p>Cílová firma ABRA: {IncomingDocuments.config()[:company_id]}</p>
        <button class="btn btn-primary">Pokračovat k nahrávání</button>
      </.form>
      <div :if={@live_action == :show && @batch} class="space-y-5">
        <h2 class="text-2xl font-bold">{@batch.name}</h2>
        <p>{IncomingDocuments.agenda_label(@batch.agenda)} · Firma ABRA: {@batch.company_id}</p>
        <section :if={!@batch.started_at} class="space-y-4">
          <p>
            Jedna fotka nebo PDF = jeden doklad. Nejvýše {@batch.max_files} souborů, 10 MB na soubor. Nahrání nespouští AI.
          </p>
          <div
            id="batch-upload-queue"
            phx-hook="IncomingBatchUpload"
            data-active={length(@uploads.sources.entries)}
          >
            <.form for={to_form(%{})} id="batch-upload" phx-change="upload-change">
              <div class="grid gap-3 sm:grid-cols-2">
                <label for="batch-camera" class="btn btn-primary min-h-14 text-base cursor-pointer">
                  <.icon name="hero-camera" class="size-6" /> Vyfotit doklad
                </label>
                <label
                  for={@uploads.sources.ref}
                  class="btn btn-outline min-h-14 text-base cursor-pointer"
                >
                  <.icon name="hero-photo" class="size-6" /> Vybrat fotky / PDF
                </label>
              </div>
              <input
                id="batch-camera"
                type="file"
                accept="image/*"
                capture="environment"
                class="sr-only"
                aria-label="Vyfotit doklad zadním fotoaparátem"
              />
              <.live_file_input
                upload={@uploads.sources}
                class="sr-only"
                aria-label="Vybrat fotky nebo PDF"
              />
              <p class="mt-3 text-sm">
                Fotky před nahráním automaticky zmenšíme na delší stranu nejvýše 1920 px. PDF ponecháme beze změny.
              </p>
              <p :if={@upload_preparing} role="status">Připravujeme fotky k nahrání…</p>
              <p :for={error <- upload_errors(@uploads.sources)} class="text-error">
                {upload_error(error)}
              </p>
              <div :for={entry <- @uploads.sources.entries} class="space-y-1">
                <p>{entry.client_name} — {entry.progress} %</p>
                <p :for={error <- upload_errors(@uploads.sources, entry)} class="text-error">
                  {upload_error(error)}
                </p>
                <p :if={@duplicates[entry.ref]} class="text-warning">
                  Stejný soubor už existuje:
                  <.link
                    navigate={~p"/admin/incoming-document-form/#{@duplicates[entry.ref].id}"}
                    class="link"
                  >{@duplicates[entry.ref].filename}</.link>
                  ({@duplicates[entry.ref].state}).
                </p>
                <button
                  :if={@duplicates[entry.ref]}
                  type="button"
                  phx-click="allow-duplicate"
                  phx-value-ref={entry.ref}
                  class="btn"
                >Přesto přidat</button>
                <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref} class="btn">Odebrat upload</button>
              </div>
            </.form>
            <p :for={{name, index} <- Enum.with_index(@queued_uploads)}>
              Čeká na nahrání: {name}
              <button
                type="button"
                class="btn btn-sm"
                phx-click="cancel-queued"
                phx-value-index={index}
              >Odebrat</button>
            </p>
          </div>
          <p :for={message <- @upload_messages} class="text-error">{message}</p>
          <.batch_documents batch={@batch} rows={@rows} />
          <p>
            Předpis: {@batch.accounting_settings["preset_name"] || "podle šablony agendy"}. Interní čísla přidělí ABRA.
          </p>
          <button phx-click="accounting-load" class="btn">Načíst předpisy z ABRA</button>
          <.form
            for={to_form(%{"preset" => @preset}, as: :fields)}
            id="batch-preset-form"
            phx-change="preset-change"
          >
            <.searchable_picker
              field={to_form(%{"preset" => @preset}, as: :fields)[:preset]}
              label="Společný účetní předpis"
              options={@presets}
              open={@accounting_open}
              query={@accounting_query}
              open_event="accounting-open"
              close_event="accounting-close"
              search_event="accounting-search"
              select_event="accounting-select"
              search_name="accounting_search"
              required={false}
            />
          </.form>
          <.form
            for={to_form(%{})}
            id="batch-settings"
            phx-change="settings-change"
            phx-submit="settings-save"
          >
            <.input
              name="include_items"
              type="checkbox"
              label="Načítat také položky (orientační přepis)"
              checked={@include_items}
              value="true"
            />
            <button class="btn" disabled={!@settings_dirty}>Uložit společné nastavení</button>
          </.form>
          <p>Model při spuštění: {IncomingDocuments.config()[:openai_model] || "nenastaven"}</p>
          <button
            id="batch-start"
            phx-click="start"
            class="btn btn-primary"
            disabled={
              @counts.total == 0 || @upload_preparing || @uploads.sources.entries != [] ||
                @queued_uploads != [] ||
                @settings_dirty
            }
          >Spustit vytěžování {@counts.total} dokladů</button>
        </section>
        <div :if={@batch.started_at} role="status" class="space-y-2">
          <p>
            Model: {@batch.model} · Čeká {@counts.waiting} · Zpracovává se {@counts.processing} · Vytěženo {@counts.extracted} · Chyba {@counts.failed}
          </p>
          <p>Odesláno do ABRA {@counts.sent} z {@counts.total} · Odloženo {@counts.deferred}</p>
          <p :if={@batch.extraction_finished_at && @counts.extracted == 0} class="alert alert-warning">
            Vytěžení všech dokladů selhalo. Otevřete kontrolu a vyřešte chyby nebo vyplňte doklady ručně.
          </p>
          <.link
            :if={@batch.extraction_finished_at && review_id(@rows)}
            navigate={~p"/admin/incoming-document-batches/#{@batch.id}/review/#{review_id(@rows).id}"}
            class="btn btn-primary"
          >Zahájit kontrolu</.link>
          <p :if={!@batch.extraction_finished_at}>
            Kontrola bude dostupná po ukončení všech prvních běhů. Stránku můžete zavřít.
          </p>
        </div>
        <.batch_documents :if={@batch.started_at} batch={@batch} rows={@rows} />
      </div>
    </Layouts.app>
    """
  end

  attr :batch, :any, required: true
  attr :rows, :list, required: true

  defp batch_documents(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table" id="batch-documents">
        <thead>
          <tr>
            <th>Pořadí</th><th>Soubor</th><th>Stav</th><th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows}>
            <td>{row.position}</td><td>{row.filename}</td><td>
              {row.state}
              <p :if={row.error} class="text-error">{row.error}</p><span :if={row.deferred_at}>Odloženo</span>
            </td>
            <td>
              <button
                :if={!@batch.started_at}
                phx-click="remove"
                phx-value-id={row.id}
                class="btn"
              >Odebrat</button>
              <.link
                :if={@batch.extraction_finished_at}
                navigate={~p"/admin/incoming-document-batches/#{@batch.id}/review/#{row.id}"}
                class="link"
              >Otevřít</.link>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp upload_error(:too_large), do: "Soubor je větší než 10 MB"
  defp upload_error(:too_many_files), do: "Překročen počet souborů v dávce"
  defp upload_error(:not_accepted), do: "Podporujeme PDF, JPEG a PNG"
  defp upload_error(_), do: "Upload se nepodařil; odeberte jej a zkuste znovu"
end

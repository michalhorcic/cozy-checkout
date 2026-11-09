defmodule CozyCheckoutWeb.IncomingDocumentBatchesLive do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.IncomingDocuments
  alias CozyCheckout.IncomingDocuments.SourceAttachments
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

          socket
          |> assign(
            batch: batch,
            include_items: batch.include_items,
            preset: String.replace_prefix(batch.accounting_settings["typUcOp"] || "", "code:", "")
          )
          |> reload()
          |> maybe_open_review(params)
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

  def handle_event("source-attachment-retry", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.rows, &(&1.id == id && &1.state == "sent")) do
      result(socket, SourceAttachments.enqueue(id))
    else
      {:noreply, put_flash(socket, :error, "Doklad nepatří této dávce nebo není odeslaný")}
    end
  end

  def handle_event("remove", %{"id" => id}, socket),
    do: result(socket, Batches.remove_source(socket.assigns.batch.id, id))

  def handle_event("start", _, socket) do
    cond do
      socket.assigns.upload_preparing || socket.assigns.uploads.sources.entries != [] ||
          socket.assigns.queued_uploads != [] ->
        {:noreply, put_flash(socket, :error, "Počkejte na dokončení uploadů nebo je odeberte.")}

      true ->
        pending =
          if socket.assigns.settings_dirty,
            do: %{preset: socket.assigns.preset, include_items: socket.assigns.include_items}

        result(socket, Batches.start(socket.assigns.batch.id, pending), true)
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
           accounting_open: true,
           accounting_query: nil
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
       assign(socket,
         accounting_query: get_in(params, ["accounting_search", "0"]) || "",
         accounting_open: true
       )}

  def handle_event("accounting-select", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.presets, &(&1.id == id)) do
      {:noreply,
       assign(socket,
         preset: id,
         settings_dirty: true,
         accounting_open: false,
         accounting_query: nil
       )}
    else
      {:noreply, socket}
    end
  end

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

  defp maybe_open_review(socket, %{"review" => "true"}) do
    if socket.assigns.batch.extraction_finished_at && review_id(socket.assigns.rows) do
      push_navigate(socket,
        to:
          ~p"/admin/incoming-document-batches/#{socket.assigns.batch.id}/review/#{review_id(socket.assigns.rows).id}"
      )
    else
      socket
    end
  end

  defp maybe_open_review(socket, _), do: socket

  defp batch_status(row) do
    cond do
      is_nil(row.batch.started_at) -> "Příprava"
      is_nil(row.batch.extraction_finished_at) -> "Probíhá vytěžování"
      row.sent == row.total -> "Vše odesláno"
      row.failed > 0 -> "Ke kontrole · chyby vytěžení"
      true -> "Ke kontrole"
    end
  end

  defp batch_status_class(row) do
    cond do
      is_nil(row.batch.started_at) -> "badge-ghost"
      is_nil(row.batch.extraction_finished_at) -> "badge-info"
      row.sent == row.total -> "badge-success"
      row.failed > 0 -> "badge-error"
      true -> "badge-warning"
    end
  end

  defp batch_action(row) do
    cond do
      is_nil(row.batch.started_at) -> "Pokračovat v nahrávání"
      is_nil(row.batch.extraction_finished_at) -> "Zobrazit průběh"
      row.sent == row.total -> "Otevřít dávku"
      row.sent > 0 -> "Pokračovat v kontrole"
      true -> "Zkontrolovat doklady"
    end
  end

  defp batch_action_path(row) do
    if row.batch.extraction_finished_at && row.sent < row.total,
      do: ~p"/admin/incoming-document-batches/#{row.batch.id}?review=true",
      else: ~p"/admin/incoming-document-batches/#{row.batch.id}"
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} content_class="mx-auto w-full max-w-7xl space-y-6">
      <h1 class="text-3xl font-bold">
        {if @live_action == :index,
          do: "Přijaté doklady",
          else: if(@live_action == :new, do: "Nahrát doklady", else: "Dávka přijatých dokladů")}
      </h1>
      <CozyCheckoutWeb.IncomingDocumentComponents.navigation
        :if={@live_action == :index}
        active="batches"
      />
      <.link
        :if={@live_action != :index}
        navigate={~p"/admin/incoming-documents"}
        class="btn btn-ghost min-h-11"
      ><.icon name="hero-arrow-left" class="size-4" /> Zpět na dávky</.link>
      <div :if={@live_action == :index} id="batch-list" class="space-y-4">
        <p
          :if={@batches == []}
          class="rounded-xl border border-base-300 bg-base-100 p-6 text-base-content/60"
        >
          {if @page == 0,
            do: "Zatím tu nejsou žádné dávky. Začněte tlačítkem Nahrát doklady.",
            else: "Na této stránce nejsou další dávky."}
        </p>
        <div
          :if={@batches != []}
          class="rounded-xl border border-base-300 bg-base-100 overflow-hidden"
        >
          <table class="table w-full table-fixed">
            <thead class="hidden md:table-header-group bg-base-200/50">
              <tr>
                <th>Dávka</th><th>Stav a průběh</th><th class="w-52">
                  <span class="sr-only">Akce</span>
                </th>
              </tr>
            </thead>
            <tbody class="block md:table-row-group">
              <tr
                :for={row <- @batches}
                id={"batch-#{row.batch.id}"}
                class="block p-4 space-y-3 md:table-row md:p-0 md:space-y-0"
              >
                <td class="block p-0 md:table-cell md:p-4">
                  <.link
                    navigate={~p"/admin/incoming-document-batches/#{row.batch.id}"}
                    class="link font-semibold break-words"
                  >{row.batch.name}</.link>
                  <p class="mt-1 text-sm text-base-content/60 break-words">
                    {IncomingDocuments.agenda_label(row.batch.agenda)} · Firma {row.batch.company_id}
                  </p>
                  <p class="mt-1 text-sm">Dokladů: {row.total}</p>
                </td>
                <td class="block p-0 md:table-cell md:p-4">
                  <span class={[
                    "badge badge-outline h-auto py-1 whitespace-normal",
                    batch_status_class(row)
                  ]}>{batch_status(row)}</span>
                  <div :if={row.batch.started_at} class="mt-2 space-y-1 text-sm" role="status">
                    <p>
                      Vytěženo {row.extracted} z {row.total}<span class={
                        row.failed > 0 && "text-error font-semibold"
                      }> · Chyby {row.failed}</span>
                    </p>
                    <p>Odesláno do ABRA {row.sent} z {row.total}</p>
                  </div>
                </td>
                <td class="block p-0 md:table-cell md:p-4 md:text-right">
                  <.link
                    navigate={batch_action_path(row)}
                    class="btn btn-outline btn-sm min-h-11 w-full md:w-auto"
                  >{batch_action(row)}</.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <nav
          :if={@page > 0 || length(@batches) == 25}
          aria-label="Stránkování dávek"
          class="flex items-center justify-between gap-2"
        >
          <button class="btn min-h-11" phx-click="page" phx-value-delta="-1" disabled={@page == 0}>Předchozí</button>
          <span class="text-sm">Strana {@page + 1}</span>
          <button
            class="btn min-h-11"
            phx-click="page"
            phx-value-delta="1"
            disabled={length(@batches) < 25}
          >Další</button>
        </nav>
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
          <details id="batch-upload-help" phx-mounted={JS.ignore_attributes("open")}>
            <summary class="text-sm cursor-pointer">Nápověda k nahrávání</summary><p>
              Jedna fotka / PDF = jeden doklad. Nejvýše {@batch.max_files} souborů, 10 MB na soubor. Fotky zmenšujeme na 1920 px.
            </p>
          </details>
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
          <details
            id="batch-accounting-settings"
            phx-mounted={JS.ignore_attributes("open")}
            class="rounded-lg border p-3 space-y-3"
          >
            <summary class="cursor-pointer">
              Předpis: {Enum.find_value(@presets, fn option ->
                if option.id == @preset, do: option.name
              end) || @batch.accounting_settings["preset_name"] || "podle šablony agendy"}{if @settings_dirty,
                do: " · Změněno"} · Změnit
            </summary>
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
              phx-submit="start"
            >
              <.input
                name="include_items"
                type="checkbox"
                label="Načítat také položky (orientační přepis)"
                checked={@include_items}
                value="true"
              />
            </.form>
          </details>
          <details id="batch-model">
            <summary class="text-sm cursor-pointer">Podrobnosti vytěžování</summary>Model: {IncomingDocuments.config()[
              :openai_model
            ] || "nenastaven"}
          </details>
          <button
            id="batch-start"
            phx-click="start"
            class="btn btn-primary"
            disabled={
              @counts.total == 0 || @upload_preparing || @uploads.sources.entries != [] ||
                @queued_uploads != []
            }
          >Spustit vytěžování {@counts.total} dokladů</button>
        </section>
        <div :if={@batch.started_at} role="status" class="space-y-2">
          <p>
            Hotovo {@counts.extracted + @counts.failed} z {@counts.total} · Chyby {@counts.failed}
          </p>
          <p>Odesláno do ABRA {@counts.sent} z {@counts.total} · Odloženo {@counts.deferred}</p>
          <p :if={@batch.extraction_finished_at && @counts.extracted == 0} class="alert alert-warning">
            Vytěžení všech dokladů selhalo. Otevřete kontrolu a vyřešte chyby nebo vyplňte doklady ručně.
          </p>
          <.link
            :if={@batch.extraction_finished_at && @counts.sent < @counts.total && review_id(@rows)}
            navigate={~p"/admin/incoming-document-batches/#{@batch.id}/review/#{review_id(@rows).id}"}
            class="btn btn-primary"
          >{if @counts.sent > 0, do: "Pokračovat v nevyřízených", else: "Zkontrolovat doklady"}</.link>
          <p :if={@batch.extraction_finished_at && @counts.sent == @counts.total} class="text-success">
            Všechny doklady jsou odeslané.
          </p>
          <p :if={!@batch.extraction_finished_at}>
            Doklady se zpracovávají na pozadí.
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
      <table class="table w-full table-fixed sm:table-auto" id="batch-documents">
        <thead>
          <tr>
            <th class="hidden sm:table-cell">Pořadí</th><th>Soubor</th><th class="hidden sm:table-cell">
              Stav
            </th><th class="w-28 sm:w-auto"></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows}>
            <td class="hidden sm:table-cell">{row.position}</td>
            <td class="break-all">
              {row.filename}
              <p :if={row.state == "sent" && row.has_source} class="text-sm">
                {attachment_label(row.source_attachment["state"])}
              </p>
              <p :if={row.source_attachment["error"]} class="text-error text-sm">
                {row.source_attachment["error"]}
              </p>
              <span class="block text-sm sm:hidden">{document_state(row.state)}{if row.deferred_at,
                do: " · Odloženo"}</span>
              <p :if={row.error} class="text-error sm:hidden">{row.error}</p>
            </td>
            <td class="hidden sm:table-cell">
              {document_state(row.state)}
              <p :if={row.error} class="text-error">{row.error}</p><span :if={row.deferred_at}>Odloženo</span>
            </td>
            <td>
              <button
                :if={row.state == "sent" && row.source_attachment["state"] == "failed"}
                class="btn btn-sm min-h-11"
                phx-click="source-attachment-retry"
                phx-value-id={row.id}
              >Zopakovat</button>
              <button
                :if={!@batch.started_at}
                phx-click="remove"
                phx-value-id={row.id}
                class="btn btn-sm min-h-11"
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

  defp attachment_label("uploaded"), do: "Podklad přiložen v ABRA"
  defp attachment_label("failed"), do: "Chyba přenosu přílohy"
  defp attachment_label(state) when state in ["queued", "processing"], do: "Přenos přílohy…"
  defp attachment_label(_), do: "Podklad nepřiložen"

  defp document_state(state),
    do:
      Map.get(
        %{
          "staged" => "Uloženo",
          "uploaded" => "Čeká",
          "processing" => "Vytěžování",
          "review" => "Ke kontrole",
          "failed" => "Chyba",
          "validating" => "Ověřování",
          "sending" => "Odesílání",
          "sent" => "Odesláno",
          "uncertain" => "Nutno ověřit"
        },
        state,
        state
      )

  defp upload_error(:too_large), do: "Soubor je větší než 10 MB"
  defp upload_error(:too_many_files), do: "Překročen počet souborů v dávce"
  defp upload_error(:not_accepted), do: "Podporujeme PDF, JPEG a PNG"
  defp upload_error(_), do: "Upload se nepodařil; odeberte jej a zkuste znovu"
end

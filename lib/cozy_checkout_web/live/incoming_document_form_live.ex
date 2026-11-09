defmodule CozyCheckoutWeb.IncomingDocumentFormLive do
  use CozyCheckoutWeb, :live_view
  alias CozyCheckout.IncomingDocuments
  alias CozyCheckout.IncomingDocuments.SourceAttachments
  alias CozyCheckout.IncomingDocuments.Batches

  alias CozyCheckout.IncomingDocuments.{
    Client,
    Extractor,
    FormSuggestions,
    HeaderForm,
    ResponseDiagnostics,
    SupplierProfiles,
    XML
  }

  import CozyCheckoutWeb.KitchenComponents, only: [searchable_picker: 1]

  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Nový doklad — formulář",
       mobile_view: "form",
       workflow_error: nil,
       batch: nil,
       batch_rows: [],
       review_filter: "pending",
       pending_navigation: nil,
       advance_after_send: false,
       doc: nil,
       agenda: "faktura-prijata",
       values: HeaderForm.defaults(),
       loaded_values: HeaderForm.defaults(),
       include_items: false,
       extraction_run: nil,
       supplier_form: to_form(%{}, as: :supplier),
       supplier_id: nil,
       supplier_revision: nil,
       supplier_dirty: false,
       supplier_options: [],
       supplier_open: false,
       supplier_query: nil,
       extraction_history: [],
       history_page: 0,
       suggestion_messages: [],
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
            loaded_values: HeaderForm.defaults(),
            agenda: "faktura-prijata",
            include_items: false,
            dirty: false
          )

        :batch_review ->
          {batch, rows} = Batches.review!(params["batch_id"], params["id"])

          socket
          |> assign(
            batch: batch,
            batch_rows: rows,
            pending_navigation: nil,
            advance_after_send: false,
            mobile_view: "form"
          )
          |> load(params["id"])

        :edit ->
          doc = IncomingDocuments.get!(params["id"])

          if doc.batch_id do
            {:ok, batch} = Batches.refresh(doc.batch_id)

            if batch.extraction_finished_at,
              do: assign_document(assign(socket, batch: nil), doc),
              else: push_navigate(socket, to: ~p"/admin/incoming-document-batches/#{batch.id}")
          else
            load(assign(socket, batch: nil), params["id"])
          end
      end

    if connected?(socket) and (socket.assigns.live_action == :index || busy?(socket.assigns.doc)),
      do: Process.send_after(self(), :refresh, 2000)

    {:noreply, socket}
  end

  def handle_info(:refresh, %{assigns: %{live_action: :index}} = socket) do
    Process.send_after(self(), :refresh, 5000)
    {:noreply, assign(socket, documents: IncomingDocuments.list())}
  end

  def handle_info(:refresh, %{assigns: %{doc: nil}} = socket), do: {:noreply, socket}

  def handle_info(:refresh, socket) do
    doc = IncomingDocuments.get!(socket.assigns.doc.id)
    if busy?(doc), do: Process.send_after(self(), :refresh, 2000)

    socket =
      cond do
        socket.assigns.doc.state in ~w(uploaded processing) and
            doc.state not in ~w(uploaded processing) ->
          # Browser form recovery may mark a blank form dirty before extraction finishes.
          # Merge real edits over the new source instead of suppressing the whole update.
          overrides =
            Map.reject(socket.assigns.values, fn {key, value} ->
              value == Map.get(socket.assigns.loaded_values, key, "")
            end)

          socket = assign_document(socket, doc)

          assign(socket,
            values: Map.merge(socket.assigns.values, overrides),
            dirty: map_size(overrides) > 0
          )

        socket.assigns.dirty or socket.assigns.accounting_dirty ->
          socket |> assign(doc: doc) |> assign_supplier(doc)

        true ->
          assign_document(socket, doc)
      end

    socket =
      cond do
        socket.assigns.batch && socket.assigns.advance_after_send && doc.state == "sent" ->
          navigate_review(assign(socket, advance_after_send: false), :next_pending)

        socket.assigns.advance_after_send && doc.state not in ["sending", "sent"] ->
          assign(socket, advance_after_send: false)

        true ->
          socket
      end

    {:noreply, socket}
  end

  defp busy?(nil), do: false

  defp busy?(doc),
    do:
      doc.state in ~w(uploaded processing validating sending uncertain) ||
        doc.source_attachment["state"] in ["queued", "processing"] ||
        doc.source_attachment["retry_pending"] == true

  def handle_event("review-summary", _, socket) do
    if unsaved?(socket),
      do: {:noreply, assign(socket, pending_navigation: :summary)},
      else: {:noreply, navigate_review(socket, :summary)}
  end

  def handle_event("review-move", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.batch_rows, &(&1.id == id)) do
      if unsaved?(socket),
        do: {:noreply, assign(socket, pending_navigation: id)},
        else: {:noreply, navigate_review(socket, id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("review-stay", _, socket),
    do: {:noreply, assign(socket, pending_navigation: nil)}

  def handle_event("review-discard", _, socket),
    do: {:noreply, navigate_review(socket, socket.assigns.pending_navigation)}

  def handle_event("review-save-leave", _, socket) do
    result =
      with {:ok, accounting} <- pending_accounting(socket) do
        if socket.assigns.dirty || socket.assigns.accounting_dirty,
          do:
            IncomingDocuments.save_form(
              socket.assigns.doc.id,
              socket.assigns.values,
              socket.assigns.hash,
              accounting
            ),
          else: {:ok, socket.assigns.doc}
      end

    case result do
      {:ok, doc} ->
        socket = socket |> assign(accounting_dirty: false) |> assign_document(doc)

        case save_pending_supplier(socket) do
          :ok -> {:noreply, navigate_review(socket, socket.assigns.pending_navigation)}
          {:error, reason} -> {:noreply, assign(socket, workflow_error: reason)}
        end

      {:error, reason} ->
        {:noreply, assign(socket, workflow_error: reason)}
    end
  end

  def handle_event("review-filter", %{"filter" => filter}, socket),
    do: {:noreply, assign(socket, review_filter: filter)}

  def handle_event("review-defer", _, socket) do
    if unsaved?(socket),
      do: {:noreply, assign(socket, pending_navigation: :defer)},
      else: {:noreply, navigate_review(socket, :defer)}
  end

  def handle_event("review-return", _, socket) do
    case Batches.defer(socket.assigns.batch.id, socket.assigns.doc.id, false) do
      {:ok, _} ->
        {:noreply, assign(socket, batch_rows: Batches.documents(socket.assigns.batch.id))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("mobile-view", %{"view" => view}, socket) when view in ["form", "original"],
    do: {:noreply, assign(socket, mobile_view: view)}

  def handle_event("workflow-save", %{"fields" => attrs}, socket),
    do:
      workflow_save(
        assign(socket, accounting_form: to_form(attrs, as: :fields), accounting_dirty: true),
        false
      )

  def handle_event("workflow-save", _, socket), do: workflow_save(socket, false)
  def handle_event("send-next", _, socket), do: workflow_save(socket, true)

  def handle_event("upload-change", _, socket), do: {:noreply, socket}

  def handle_event("extraction-options", params, socket),
    do: {:noreply, assign(socket, include_items: params["include_items"] == "true")}

  def handle_event("change", %{"document" => attrs} = params, socket) do
    values = Map.merge(socket.assigns.values, Map.take(attrs, HeaderForm.keys()))

    {:noreply,
     assign(socket,
       values: values,
       agenda:
         if(socket.assigns.doc,
           do: socket.assigns.doc.agenda,
           else: params["agenda"] || socket.assigns.agenda
         ),
       dirty: values != socket.assigns.loaded_values
     )}
  end

  def handle_event("prefill-vat", _, socket) do
    if editable?(socket.assigns.doc) and socket.assigns.doc do
      suggestions = FormSuggestions.from(socket.assigns.doc.extracted_data)

      {:noreply,
       assign(socket,
         values: Map.merge(socket.assigns.values, suggestions.vat),
         suggestion_messages: suggestions.messages,
         dirty: true
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("prefill-dates", _, socket) do
    if editable?(socket.assigns.doc) do
      source =
        if socket.assigns.doc,
          do: FormSuggestions.from(socket.assigns.doc.extracted_data).dates,
          else: %{}

      current = Map.reject(socket.assigns.values, fn {_, value} -> value in [nil, ""] end)
      dates = FormSuggestions.dates(Map.merge(source, current))

      values =
        Enum.reduce(dates, socket.assigns.values, fn {key, value}, acc ->
          if acc[key] in [nil, ""], do: Map.put(acc, key, value), else: acc
        end)

      {:noreply, assign(socket, values: values, dirty: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("upload", %{"agenda" => agenda}, socket) do
    if socket.assigns.doc do
      {:noreply, put_flash(socket, :error, "Pro další originál založte nový formulář.")}
    else
      results =
        consume_uploaded_entries(socket, :source, fn %{path: path}, entry ->
          {:ok,
           IncomingDocuments.upload(
             File.read!(path),
             entry.client_name,
             agenda,
             "header_form",
             extraction_options(socket)
           )}
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
           |> assign(dirty: false)
           |> push_patch(to: document_path(socket, doc.id))}

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

    save_current(socket, params["agenda"], false)
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
      previous = Map.take(socket.assigns, [:values, :dirty])
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

  def handle_event("send", _, socket) do
    operation(
      socket,
      fn doc ->
        if doc.current_xml do
          IncomingDocuments.send_header(
            doc.id,
            IncomingDocuments.digest(doc.current_xml),
            true
          )
        else
          {:error, "Nejprve uložte formulář"}
        end
      end,
      "Doklad byl zařazen k odeslání do ABRA."
    )
  end

  def handle_event("source-attachment-retry", _, socket) do
    operation(
      socket,
      fn doc -> SourceAttachments.enqueue(doc.id) end,
      "Podklad byl zařazen k přenosu do ABRA."
    )
  end

  def handle_event("verify", _, socket) do
    operation(
      socket,
      fn doc -> IncomingDocuments.verify(doc.id) end,
      "Ověřujeme existenci dokladu v ABRA bez opakování zápisu."
    )
  end

  def handle_event("retry", _, %{assigns: %{supplier_dirty: true}} = socket),
    do:
      {:noreply,
       put_flash(socket, :error, "Nejdřív uložte nebo znovu načtěte instrukce dodavatele.")}

  def handle_event("retry", _, socket) do
    operation(
      socket,
      fn doc ->
        IncomingDocuments.retry_extraction(doc.id, "header_form", extraction_options(socket))
      end,
      "Probíhá nové vytěžení."
    )
  end

  def handle_event("supplier-change", %{"supplier" => attrs}, socket),
    do:
      {:noreply,
       assign(socket, supplier_form: to_form(attrs, as: :supplier), supplier_dirty: true)}

  def handle_event("supplier-search", params, socket),
    do:
      {:noreply,
       assign(socket,
         supplier_query: get_in(params, ["supplier_search", "0"]) || "",
         supplier_open: true
       )}

  def handle_event("supplier-open", _, socket),
    do: {:noreply, assign(socket, supplier_open: true)}

  def handle_event("supplier-close", _, socket),
    do: {:noreply, assign(socket, supplier_open: false)}

  def handle_event("supplier-select", %{"id" => id}, socket) do
    profile = IncomingDocuments.supplier_profile(socket.assigns.doc, id)

    if profile,
      do: {:noreply, set_supplier(socket, profile, SupplierProfiles.identity(profile))},
      else: {:noreply, socket}
  end

  def handle_event("supplier-reload", _, socket) do
    profile =
      IncomingDocuments.supplier_profile(socket.assigns.doc, socket.assigns.supplier_id)

    if profile,
      do: {:noreply, set_supplier(socket, profile, SupplierProfiles.identity(profile))},
      else: {:noreply, socket}
  end

  def handle_event("supplier-new", _, socket) do
    identity =
      if socket.assigns.extraction_run, do: socket.assigns.extraction_run.identity, else: %{}

    {:noreply, set_supplier(socket, nil, identity)}
  end

  def handle_event("supplier-save", %{"supplier" => attrs} = params, socket) do
    doc = socket.assigns.doc
    retry? = params["action"] == "retry"

    if retry? && (socket.assigns.dirty || socket.assigns.accounting_dirty) do
      {:noreply,
       put_flash(socket, :error, "Nejprve uložte změny formuláře a účetního nastavení.")}
    else
      args = [
        doc.id,
        socket.assigns.supplier_id,
        attrs,
        socket.assigns.supplier_revision,
        true
      ]

      result =
        if retry?,
          do:
            apply(
              IncomingDocuments,
              :save_supplier_and_retry,
              args ++ [extraction_options(socket)]
            ),
          else: apply(IncomingDocuments, :save_supplier_instructions, args)

      case result do
        {:ok, saved} when retry? ->
          Process.send_after(self(), :refresh, 2000)

          {:noreply,
           socket
           |> assign(supplier_dirty: false)
           |> assign_document(saved)
           |> put_flash(
             :info,
             "Instrukce uloženy. Probíhá vytěžení obsahu a samostatný dotaz podle instrukcí."
           )}

        {:ok, profile} ->
          {:noreply,
           socket
           |> set_supplier(profile, SupplierProfiles.identity(profile))
           |> put_flash(:info, "Instrukce uloženy pro příště. Aktuální doklad se nezměnil.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, reason)}
      end
    end
  end

  def handle_event("content-retry", _, socket) do
    if socket.assigns.supplier_dirty do
      {:noreply, put_flash(socket, :error, "Nejprve uložte nebo znovu načtěte instrukce.")}
    else
      operation(
        socket,
        fn doc ->
          IncomingDocuments.retry_content_extraction(doc.id, extraction_options(socket))
        end,
        "Probíhá nové obsahové vytěžení s poslední uloženou revizí."
      )
    end
  end

  def handle_event("generic-extract", _, socket),
    do:
      operation(
        socket,
        fn doc ->
          IncomingDocuments.retry_content_extraction(
            doc.id,
            Keyword.put(extraction_options(socket), :without_supplier, true)
          )
        end,
        "Probíhá obecné vytěžení bez určení dodavatele."
      )

  def handle_event("restore-draft", %{"id" => id}, socket),
    do:
      operation(
        socket,
        fn doc -> IncomingDocuments.restore_draft_from_run(doc.id, id) end,
        "Pracovní návrh obnoven. Zkontrolujte a znovu uložte formulář; původní dry-run neplatí."
      )

  def handle_event("history-page", %{"page" => page}, socket) do
    page =
      case Integer.parse(page) do
        {n, ""} when n >= 0 -> n
        _ -> 0
      end

    {:noreply,
     assign(socket,
       history_page: page,
       extraction_history: IncomingDocuments.list_extraction_runs(socket.assigns.doc.id, page)
     )}
  end

  defp set_supplier(socket, profile, identity) do
    attrs =
      Map.merge(
        %{"name" => "", "ic" => "", "dic" => "", "country_code" => "CZ"},
        Map.reject(identity, fn {_, value} -> is_nil(value) end)
      )
      |> Map.merge(%{
        "profile_id" => if(profile, do: profile.id, else: ""),
        "identity_kind" => if(profile, do: profile.identity_kind, else: "ic"),
        "instructions" => if(profile, do: profile.instructions, else: "")
      })

    options =
      if profile do
        option = %{
          id: profile.id,
          name: "#{profile.name} — #{profile.ic || profile.dic}",
          hint: profile.country_code,
          search_text: "#{profile.name} #{profile.ic} #{profile.dic}"
        }

        [option | Enum.reject(socket.assigns.supplier_options, &(&1.id == profile.id))]
      else
        socket.assigns.supplier_options
      end

    assign(socket,
      supplier_options: options,
      supplier_form: to_form(attrs, as: :supplier),
      supplier_id: profile && profile.id,
      supplier_revision: profile && profile.revision,
      supplier_dirty: false,
      supplier_open: false,
      supplier_query: nil
    )
  end

  defp assign_supplier(socket, doc) do
    old_doc = socket.assigns.doc
    run = IncomingDocuments.extraction_status(doc)
    old_run = socket.assigns.extraction_run

    changed? =
      is_nil(old_doc) || old_doc.id != doc.id ||
        (old_run && old_run.id) != (run && run.id) ||
        (old_run && old_run.state) != (run && run.state) ||
        (old_run && old_run.profile_revision) != (run && run.profile_revision)

    socket = assign(socket, extraction_run: run)

    if changed? do
      options =
        IncomingDocuments.supplier_profiles(doc)
        |> Enum.map(fn p ->
          %{
            id: p.id,
            name: "#{p.name} — #{p.ic || p.dic}",
            hint: p.country_code,
            search_text: "#{p.name} #{p.ic} #{p.dic}"
          }
        end)

      socket =
        assign(socket,
          supplier_options: options,
          history_page: 0,
          extraction_history: IncomingDocuments.list_extraction_runs(doc.id)
        )

      if socket.assigns.supplier_dirty && old_doc && old_doc.id == doc.id do
        socket
      else
        profile =
          if run,
            do: IncomingDocuments.supplier_profile(doc, run.supplier_profile_id),
            else: nil

        set_supplier(socket, profile, if(run, do: run.identity, else: %{}))
      end
    else
      socket
    end
  end

  defp save_pending_supplier(%{assigns: %{supplier_dirty: false}}), do: :ok

  defp save_pending_supplier(socket) do
    case IncomingDocuments.save_supplier_instructions(
           socket.assigns.doc.id,
           socket.assigns.supplier_id,
           socket.assigns.supplier_form.params,
           socket.assigns.supplier_revision,
           true
         ) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp workflow_save(socket, send?) do
    save_current(socket, socket.assigns.agenda, send?)
  end

  defp save_current(socket, agenda, send?) do
    result =
      with {:ok, accounting} <- pending_accounting(socket) do
        if socket.assigns.doc do
          IncomingDocuments.save_form(
            socket.assigns.doc.id,
            socket.assigns.values,
            socket.assigns.hash,
            accounting,
            send?
          )
        else
          IncomingDocuments.create_header(agenda, socket.assigns.values)
        end
      end

    case result do
      {:ok, doc} ->
        if busy?(doc), do: Process.send_after(self(), :refresh, 2000)

        socket =
          socket |> assign(accounting_dirty: false, workflow_error: nil) |> assign_document(doc)

        socket =
          assign(socket,
            advance_after_send: send? && not is_nil(socket.assigns.batch)
          )

        # A manual document receives its permanent URL after the first save.
        socket =
          if socket.assigns.live_action == :new,
            do: push_patch(socket, to: document_path(socket, doc.id)),
            else: socket

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, workflow_error: reason, mobile_view: "form")}
    end
  end

  defp pending_accounting(%{assigns: %{accounting_dirty: false}}), do: {:ok, nil}

  defp pending_accounting(socket) do
    attrs = socket.assigns.accounting_form.params

    case Base.url_decode64(attrs["preset"] || "", padding: false) do
      {:ok, preset} -> {:ok, Map.put(attrs, "preset", preset)}
      :error -> {:error, "Vyberte předpis z načteného číselníku"}
    end
  end

  defp extraction_options(socket), do: [include_items: socket.assigns.include_items]

  defp editable?(nil), do: true

  defp editable?(doc),
    do:
      is_nil(doc.sent_xml) and
        (doc.state == "review" or (doc.state == "failed" and doc.error_stage == "extraction"))

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

  defp unsaved?(socket),
    do: socket.assigns.dirty || socket.assigns.accounting_dirty || socket.assigns.supplier_dirty

  defp document_path(%{assigns: %{batch: %{id: id}}}, doc_id),
    do: ~p"/admin/incoming-document-batches/#{id}/review/#{doc_id}"

  defp document_path(_, doc_id), do: ~p"/admin/incoming-document-form/#{doc_id}"

  defp navigate_review(socket, :next_pending) do
    rows = Batches.documents(socket.assigns.batch.id)
    position = Enum.find_index(rows, &(&1.id == socket.assigns.doc.id)) || 0
    {before, after_current} = Enum.split(rows, position + 1)

    next =
      Enum.find(
        after_current ++ before,
        &(&1.id != socket.assigns.doc.id && &1.state != "sent" && is_nil(&1.deferred_at))
      )

    destination = if next, do: next.id, else: :summary

    if unsaved?(socket),
      do: assign(socket, pending_navigation: destination),
      else: navigate_review(socket, destination)
  end

  defp navigate_review(socket, :defer) do
    case Batches.defer(socket.assigns.batch.id, socket.assigns.doc.id) do
      {:ok, _} ->
        navigate_review(
          assign(socket,
            dirty: false,
            accounting_dirty: false,
            supplier_dirty: false,
            pending_navigation: nil
          ),
          :next_pending
        )

      {:error, reason} ->
        put_flash(socket, :error, reason)
    end
  end

  defp navigate_review(socket, :summary),
    do: push_navigate(socket, to: ~p"/admin/incoming-document-batches/#{socket.assigns.batch.id}")

  defp navigate_review(socket, nil), do: socket

  defp navigate_review(socket, id),
    do: socket |> assign(pending_navigation: nil) |> push_patch(to: document_path(socket, id))

  defp review_rows(rows, "sent"), do: Enum.filter(rows, &(&1.state == "sent"))

  defp review_rows(rows, "errors"),
    do: Enum.filter(rows, &(&1.state in ["failed", "uncertain"] || &1.deferred_at))

  defp review_rows(rows, _),
    do: Enum.filter(rows, &(&1.state != "sent" && is_nil(&1.deferred_at)))

  defp load(socket, id),
    do: assign_document(assign(socket, workflow_error: nil), IncomingDocuments.get!(id))

  defp assign_document(socket, doc) do
    socket = assign_supplier(socket, doc)
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
          accounting_open: same? && socket.assigns.accounting_open,
          accounting_query: if(same?, do: socket.assigns.accounting_query, else: nil)
        )
      end

    {:ok, template_fields} = XML.parse(XML.template_for(doc), doc.agenda)

    assign(socket,
      doc: doc,
      batch_rows:
        Enum.map(socket.assigns.batch_rows, fn row ->
          if row.id == doc.id,
            do: Map.merge(row, %{state: doc.state, deferred_at: doc.deferred_at}),
            else: row
        end),
      agenda: doc.agenda,
      values: HeaderForm.values(doc),
      loaded_values: HeaderForm.values(doc),
      suggestion_messages: FormSuggestions.from(doc.extracted_data).messages,
      hash: IncomingDocuments.transcription_hash(doc),
      dirty: false,
      template_fields: template_fields,
      responses: [
        {"Kontrola ABRA (dry-run)", ResponseDiagnostics.for_display(doc.dry_run)},
        {"Odeslání do ABRA", ResponseDiagnostics.for_display(doc.response)}
      ]
    )
  end

  defp save_state(doc, dirty) do
    cond do
      is_nil(doc) -> "Nový doklad"
      doc.state == "sent" -> "Odesláno"
      doc.state == "sending" -> "Odesílání…"
      doc.state == "uncertain" -> "Nutno ověřit"
      doc.state in ["uploaded", "processing"] -> "Vytěžování…"
      dirty -> "Neuloženo"
      is_nil(doc.current_xml) -> "Ke kontrole"
      true -> "Uloženo"
    end
  end

  defp selected_accounting(assigns) do
    Enum.find_value(assigns.accounting_options, fn option ->
      if option.id == assigns.accounting_form[:preset].value, do: option.name
    end) || assigns.doc.accounting_settings["preset_name"] || assigns.template_fields["typUcOp"] ||
      "podle dávky"
  end

  defp extraction_phase("identify"), do: "Určujeme dodavatele originálu…"
  defp extraction_phase("content"), do: "Vytěžujeme hlavní údaje originálu…"
  defp extraction_phase("supplier_task"), do: "Samostatně zpracováváme dodavatelské instrukce…"
  defp extraction_phase(_), do: "Vytěžení dokončeno."

  defp state_label(state),
    do:
      Map.get(
        %{
          "staged" => "Připraveno před spuštěním",
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
    <Layouts.app
      flash={@flash}
      content_class="mx-auto w-full max-w-7xl space-y-6 pb-[calc(var(--incoming-actions-height,8rem)+2rem)]"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h1 class="text-3xl font-bold">
          {cond do
            @live_action == :index -> "Přijaté doklady"
            @batch -> @batch.name
            true -> "Přijatý doklad"
          end}
        </h1>
        <.link
          :if={@live_action != :index && is_nil(@batch)}
          navigate={~p"/admin/incoming-documents"}
          class="btn"
          data-confirm={
            (@dirty || @accounting_dirty || @supplier_dirty) && "Zahodit neuložené změny?"
          }
        >Přijaté doklady</.link>
      </div>
      <div :if={@live_action == :index} class="space-y-4">
        <CozyCheckoutWeb.IncomingDocumentComponents.navigation active="documents" />
        <p
          :if={@documents == []}
          class="rounded-xl border border-base-300 bg-base-100 p-6 text-base-content/60"
        >
          Zatím tu nejsou žádné doklady. Začněte nahráním dokladů nebo vytvořte doklad ručně.
        </p>
        <div
          :if={@documents != []}
          class="rounded-xl border border-base-300 bg-base-100 overflow-hidden"
        >
          <table class="table w-full table-fixed" id="incoming-list">
            <thead class="hidden md:table-header-group bg-base-200/50">
              <tr>
                <th class="w-2/5">Doklad</th><th>Kategorie</th><th>Stav</th><th>Firma ABRA</th>
              </tr>
            </thead>
            <tbody class="block md:table-row-group">
              <tr
                :for={doc <- @documents}
                class="block p-4 space-y-2 md:table-row md:p-0 md:space-y-0"
              >
                <td class="block p-0 md:table-cell md:p-4">
                  <.link
                    navigate={~p"/admin/incoming-document-form/#{doc.id}"}
                    class="link font-semibold break-words"
                  >{doc.filename}</.link>
                </td>
                <td class="block p-0 text-base-content/60 md:table-cell md:p-4">
                  {IncomingDocuments.agenda_label(doc.agenda)}
                </td>
                <td class="block p-0 md:table-cell md:p-4">
                  <span class={[
                    "badge badge-outline h-auto py-1 whitespace-normal",
                    CozyCheckoutWeb.IncomingDocumentComponents.document_state_class(doc.state)
                  ]}>{state_label(doc.state)}</span>
                </td>
                <td class="block p-0 break-words text-base-content/60 md:table-cell md:p-4">
                  <span class="md:hidden">Firma ABRA: </span>{doc.company_id}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <section :if={@batch} id="batch-review" class="space-y-3 border rounded-xl p-4">
        <p class="font-semibold">
          {Enum.find_index(@batch_rows, &(&1.id == @doc.id)) + 1} z {length(@batch_rows)} · {state_label(
            @doc.state
          )}
        </p>
        <details id="review-overview" phx-mounted={JS.ignore_attributes("open")}>
          <summary class="cursor-pointer">Přehled dávky</summary><p>
            Odesláno {Enum.count(@batch_rows, &(&1.state == "sent"))} · Zbývá {Enum.count(
              @batch_rows,
              &(&1.state != "sent")
            )}
          </p>
          <.form for={to_form(%{})} id="review-filter" phx-change="review-filter">
            <.input
              type="select"
              name="filter"
              value={@review_filter}
              label="Zobrazit"
              options={[
                {"Nevyřízené", "pending"},
                {"Chybné / odložené", "errors"},
                {"Odeslané", "sent"}
              ]}
            />
          </.form>
          <div class="flex flex-wrap gap-2">
            <button
              :for={row <- review_rows(@batch_rows, @review_filter)}
              class="btn btn-sm"
              phx-click="review-move"
              phx-value-id={row.id}
            >{row.position}. {row.filename} · {state_label(row.state)}</button>
          </div>
        </details>
        <.modal :if={@pending_navigation} id="review-unsaved" show on_cancel={JS.push("review-stay")}>
          <h2 id="review-unsaved-title" class="text-xl font-bold">Neuložené změny</h2>
          <p id="review-unsaved-description" class="my-4">Ve formuláři jsou neuložené změny.</p>
          <p :if={@workflow_error} role="alert" class="text-error">{@workflow_error}</p>
          <div class="flex flex-wrap gap-2">
            <button class="btn btn-primary" phx-click="review-save-leave">Uložit a pokračovat</button><button
              class="btn"
              phx-click="review-discard"
            >Zahodit a pokračovat</button><button class="btn" phx-click="review-stay">Zůstat</button>
          </div>
        </.modal>
      </section>
      <div :if={@live_action != :index} class="space-y-6">
        <p :if={@doc && @doc.error} class="text-error">{@doc.error}</p>
        <p :if={@doc && @doc.state in ~w(uploaded processing)} role="status">
          {if @extraction_run,
            do: extraction_phase(@extraction_run.active_step),
            else: "Probíhá vytěžování…"}
        </p>
        <p :if={@doc && @doc.extraction_metadata["identity_conflict"]} class="text-warning">
          {@doc.extraction_metadata["identity_conflict"]}
        </p>
        <p :if={@doc && @doc.extracted_data["currency"] not in [nil, "CZK"]} class="text-error">
          Měna originálu: {@doc.extracted_data["currency"]}. Formulář podporuje CZK.
        </p>
        <details
          :if={
            @suggestion_messages != [] ||
              (@doc && @doc.extracted_data["uncertainties"] not in [nil, []])
          }
          id="review-warnings"
          phx-mounted={JS.ignore_attributes("open")}
          class="text-warning"
        >
          <summary class="cursor-pointer">
            Upozornění ke kontrole ({length(@suggestion_messages) +
              length((@doc && @doc.extracted_data["uncertainties"]) || [])})
          </summary>
          <p :for={message <- @suggestion_messages}>{message}</p><p :for={
            message <- (@doc && @doc.extracted_data["uncertainties"]) || []
          }>
            {message}
          </p>
        </details>
        <div
          :if={@doc && @doc.original}
          class="flex gap-2 lg:hidden"
          role="group"
          aria-label="Zobrazení dokladu"
        >
          <button
            type="button"
            phx-click="mobile-view"
            phx-value-view="form"
            aria-pressed={to_string(@mobile_view == "form")}
            class="btn btn-sm"
          >Formulář</button>
          <button
            type="button"
            phx-click="mobile-view"
            phx-value-view="original"
            aria-pressed={to_string(@mobile_view == "original")}
            class="btn btn-sm"
          >Originál</button>
        </div>
        <div class="grid gap-6 lg:grid-cols-2">
          <.form
            for={to_form(@values, as: :document)}
            id="incoming-header-form"
            phx-change="change"
            phx-submit="save"
            class={["space-y-4 lg:block", @mobile_view == "original" && "hidden"]}
          >
            <.input
              :if={!@doc}
              type="select"
              name="agenda"
              value={@agenda}
              label="Agenda"
              options={IncomingDocuments.agendas()}
              disabled={@doc != nil}
            />
            <input :if={@doc} type="hidden" name="agenda" value={@agenda} />
            <div class="space-y-2">
              <details
                id="incoming-date-help"
                phx-mounted={JS.ignore_attributes("open")}
                class="text-sm"
              >
                <summary>Nápověda k datům</summary>

                <button type="button" phx-click="prefill-dates" class="btn btn-sm" disabled={@locked}>Doplnit prázdná data</button>
                <p>
                  Data z originálu předvyplňujeme. Chybějící datum vystavení, DUZP a splatnost navrhujeme podle dostupného vystavení či DUZP. Datum zaúčtování vychází z vystavení, uplatnění DPH z pozdějšího vystavení a DUZP. Tyto návrhy ověřte podle skutečného přijetí a účetního období.
                </p>
              </details>
            </div>
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
          </.form>
          <div class={[
            "space-y-4 lg:block lg:sticky lg:top-4 lg:self-start lg:max-h-[calc(100dvh-10rem)] lg:overflow-auto",
            @mobile_view == "form" && @doc && @doc.original && "hidden"
          ]}>
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
            <p :if={@doc && @doc.original}>
              <.link
                href={~p"/admin/incoming-documents/#{@doc.id}/original"}
                target="_blank"
                class="link"
              >Otevřít originál v plné velikosti</.link>
            </p>
            <img
              :if={@doc && @doc.original && @doc.content_type != "application/pdf"}
              src={~p"/admin/incoming-documents/#{@doc.id}/original"}
              alt="Originál dokladu"
              class="w-full rounded-lg"
            />
          </div>
        </div>
        <div :if={@doc} class={["space-y-5 lg:block", @mobile_view == "original" && "hidden"]}>
          <details
            class="bg-white rounded-xl p-4 space-y-3"
            id="incoming-accounting"
            phx-mounted={JS.ignore_attributes("open")}
          >
            <summary class="cursor-pointer">
              Předpis: {selected_accounting(assigns)} · Změnit
            </summary>
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
              phx-submit="workflow-save"
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
              </fieldset>
            </.form>
          </details>
          <p :if={@doc.state == "uncertain"} class="alert alert-warning">
            Výsledek zápisu není potvrzený. Zkontrolujte ABRA; nový zápis je zablokovaný, aby nevznikl duplicitní doklad.
          </p>

          <section
            :if={@doc.state == "sent" && @doc.original}
            id="incoming-source-attachment"
            class="space-y-2"
          >
            <h3 class="font-bold">Podklad v přílohách ABRA</h3>
            <p :if={@doc.source_attachment["state"] == "uploaded"} class="text-success">
              Obrázek / PDF je přiložený a jeho obsah byl ověřen.
            </p>
            <p :if={@doc.source_attachment["state"] in ["queued", "processing"]} role="status">
              Probíhá přiložení uloženého obrázku / PDF k dokladu v ABRA.
            </p>
            <p :if={@doc.source_attachment["error"]} class="text-error">
              {@doc.source_attachment["error"]} Účetní doklad zůstává odeslaný.
            </p>
            <button
              :if={@doc.source_attachment["state"] in [nil, "failed"]}
              class="btn"
              phx-click="source-attachment-retry"
            >Odeslat podklad do příloh ABRA</button>
          </section>
          <p :if={@doc.state == "sent"} class="alert alert-success">
            Doklad je v ABRA, ID {@doc.remote_id}.
            <a href={Client.document_url(@doc)} class="link" target="_blank" rel="noopener">Otevřít v ABRA</a>
          </p>
          <details
            id="incoming-advanced"
            phx-mounted={JS.ignore_attributes("open")}
            class="rounded-xl border p-4 space-y-4"
          >
            <summary class="cursor-pointer font-semibold">Pokročilé možnosti a nápověda</summary>
            <p>
              Vyberte agendu a vyplňte hlavičku a souhrnnou DPH. Obrázek nebo PDF může navrhnout údaje. Položky zůstanou pouze v poznámce.
            </p>
            <p class="alert alert-info">
              Pilot pro tuzemské doklady v CZK se sazbami 0 %, 12 % a 21 %. Účetní nastavení vychází ze vzoru vybrané agendy; před odesláním je zkontrolujte níže.
            </p>
            <p class="font-semibold">
              {IncomingDocuments.agenda_label(@doc.agenda)} · {state_label(@doc.state)} · Firma ABRA: {@doc.company_id}
            </p>
            <p
              :if={Extractor.strategy(@doc) != "header_form" && is_nil(@doc.sent_xml)}
              class="alert alert-info"
            >
              Tento doklad vznikl ve starším postupu. Uložením formuláře se převede na souhrnný doklad bez nákupních položek.
            </p>
            <p :if={@doc.error} class="alert alert-warning">
              {@doc.error} Údaje můžete doplnit ručně.
            </p>
            <p :if={@doc.state in ~w(uploaded processing)} role="status">
              Probíhá vytěžení originálu…
            </p>
            <p :if={@doc.extracted_data != %{}} class="alert alert-info">
              Návrhy z originálu vyžadují kontrolu. Měna v originálu: {@doc.extracted_data["currency"] ||
                "nezjištěna"}. {Enum.join(@doc.extracted_data["uncertainties"] || [], "; ")}
            </p>
            <div :if={@suggestion_messages != []} class="alert alert-warning">
              <p :for={message <- @suggestion_messages}>{message}</p>
            </div>
            <details
              :if={@doc.extracted_data != %{}}
              id="incoming-source-vat"
              phx-mounted={JS.ignore_attributes("open")}
              class="bg-base-200 rounded-lg p-4"
            >
              <summary>Rekapitulace DPH přečtená z originálu</summary>
              <button type="button" phx-click="prefill-vat" class="btn btn-sm" disabled={@locked}>Převzít rekapitulaci do polí DPH</button>
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
            <p
              :if={@doc.state in ~w(uploaded processing) && @extraction_run}
              class="alert alert-info"
              role="status"
            >
              {extraction_phase(@extraction_run.active_step)}
            </p>
            <p :if={@doc.extraction_metadata["restored_from_run"]} class="alert alert-warning">
              Zobrazený pracovní návrh byl obnoven z historie. Zkontrolujte jej proti originálu a znovu uložte.
            </p>
            <.form
              :if={@doc.original}
              for={%{}}
              id="incoming-extraction-options"
              phx-change="extraction-options"
              phx-submit="extraction-options"
              class="bg-base-200 rounded-xl p-4 space-y-2"
            >
              <.input
                type="checkbox"
                name="include_items"
                checked={@include_items}
                label="Načítat také položky (orientační přepis)"
              />
              <p>
                Volba platí pro příští vytěžení včetně opakování. Při vypnutí se OpenAI soustředí jen na hlavní údaje a rekapitulaci DPH; položky nejsou součástí zadání ani výstupního schématu.
              </p>
            </.form>
            <details
              class="bg-base-200 rounded-xl p-4 space-y-4"
              id="incoming-supplier"
              phx-mounted={JS.ignore_attributes("open")}
            >
              <summary class="font-bold">Instrukce pro vytěžování dodavatele</summary>
              <p>
                Cílová firma: {@doc.company_id}. Uložené instrukce se zpracují samostatným dotazem nad originálem.
                Jen výslovně vrácené údaje nahradí obecné čtení; nezjištěný požadovaný údaj zůstane prázdný. Účetní údaje vždy zkontrolujte.
              </p>
              <div :if={@extraction_run} class="space-y-2">
                <p>
                  Rozpoznaná identita: {@extraction_run.identity["name"]} / IČO {@extraction_run.identity[
                    "ic"
                  ]} / DIČ {@extraction_run.identity["dic"]}
                </p>
                <p>{@extraction_run.selection_reason} Přiřazení: {@extraction_run.selection}.</p>
                <p :for={message <- @extraction_run.identity_result["uncertainties"] || []}>
                  {message}
                </p>
                <p :if={@doc.state in ~w(uploaded processing)} role="status">
                  {extraction_phase(@extraction_run.active_step)}
                </p>
                <p :if={@extraction_run.profile_revision}>
                  Poslední běh použil revizi {@extraction_run.profile_revision}.
                  <span :if={@extraction_run.supplier_instructions == ""}>Známý dodavatel bez zvláštních instrukcí.</span>
                </p>
                <p
                  :if={
                    @supplier_id == @extraction_run.supplier_profile_id && @supplier_revision &&
                      @supplier_revision != @extraction_run.profile_revision
                  }
                  class="text-warning"
                >
                  Profil má novější revizi {@supplier_revision}; výsledek posledního běhu se nezměnil.
                </p>
                <details id="incoming-used-instructions" phx-mounted={JS.ignore_attributes("open")}>
                  <summary>Přesné dodavatelské instrukce posledního běhu</summary>
                  <p :if={Extractor.separate_supplier_task?(@extraction_run)}>
                    Tyto instrukce se posílají v samostatném dotazu nad originálem, bez obecného zadání a bez předchozí odpovědi.
                  </p>
                  <pre class="whitespace-pre-wrap">{@extraction_run.supplier_instructions}</pre>
                </details>
              </div>
              <details
                :if={@extraction_run && @extraction_run.supplier_task_result != %{}}
                id="incoming-supplier-task-result"
                phx-mounted={JS.ignore_attributes("open")}
              >
                <summary>Výsledek samostatného dodavatelského dotazu</summary>
                <p :for={field <- @extraction_run.supplier_task_result["fields"] || []}>
                  {field["field"]}: {field["value"] || "nezjištěno"} · Zdroj: {field["source_text"]}
                </p>
                <p :for={message <- @extraction_run.supplier_task_result["uncertainties"] || []}>
                  {message}
                </p>
                <pre
                  :if={@extraction_run.supplier_task_result["vat_summary"]}
                  class="text-xs whitespace-pre-wrap"
                >{Jason.encode!(@extraction_run.supplier_task_result["vat_summary"], pretty: true)}</pre>
              </details>
              <.form
                for={@supplier_form}
                id="supplier-instructions-form"
                phx-change="supplier-change"
                phx-submit="supplier-save"
                class="space-y-3"
              >
                <.searchable_picker
                  field={@supplier_form[:profile_id]}
                  options={@supplier_options}
                  label="Vybrat uloženého dodavatele"
                  required={false}
                  prompt="Nový profil / neznámý dodavatel"
                  search_name="supplier_search"
                  search_event="supplier-search"
                  open_event="supplier-open"
                  close_event="supplier-close"
                  select_event="supplier-select"
                  query={@supplier_query}
                  open={@supplier_open}
                />
                <button
                  type="button"
                  class="btn btn-sm"
                  phx-click="supplier-new"
                  data-confirm="Zahodit neuložené instrukce a připravit nový profil?"
                >Nový profil</button>
                <button
                  :if={@supplier_id}
                  type="button"
                  class="btn btn-sm"
                  phx-click="supplier-reload"
                  data-confirm="Zahodit neuložené instrukce a načíst aktuální revizi profilu?"
                >Načíst aktuální revizi</button>
                <p>
                  Výběr profilu nemění dodavatele v hlavičce a nespouští AI. Uložením existujícího profilu se jeho identita nemění.
                </p>
                <div class="grid gap-3 sm:grid-cols-2">
                  <.input field={@supplier_form[:name]} label="Název dodavatele" maxlength="255" />
                  <.input
                    field={@supplier_form[:country_code]}
                    label="Země (CZ apod.)"
                    maxlength="2"
                  />
                  <.input field={@supplier_form[:ic]} label="IČO dodavatele" maxlength="255" />
                  <.input field={@supplier_form[:dic]} label="DIČ dodavatele" maxlength="255" />
                </div>
                <.input
                  type="select"
                  field={@supplier_form[:identity_kind]}
                  label="Klíč profilu"
                  options={[{"České IČO", "ic"}, {"Ručně potvrzené DIČ", "dic"}]}
                />
                <.input
                  type="textarea"
                  field={@supplier_form[:instructions]}
                  label="Instrukce pro čtení originálu"
                  maxlength="8000"
                  rows="6"
                />
                <p>
                  {String.length(@supplier_form.params["instructions"] || "")} / 8 000 znaků. Aktuální revize: {@supplier_revision ||
                    "nový profil"}.
                </p>
                <p :if={@supplier_dirty} class="text-warning">
                  Instrukce mají neuložené změny. Uložení pro příště nevolá AI.
                </p>
                <button class="btn" name="action" value="save">Uložit instrukce pro příště</button>
                <button
                  :if={@doc.original && !@locked}
                  class="btn btn-primary"
                  name="action"
                  value="retry"
                  data-confirm="Uložit instrukce a nahradit ruční opravy novým vytěžením? Kontrola a dry-run se zruší."
                >Uložit instrukce a znovu vytěžit</button>
              </.form>
              <div :if={@doc.original && !@locked} class="flex flex-wrap gap-2">
                <button
                  class="btn"
                  phx-click="content-retry"
                  data-confirm="Nahradit ruční opravy obsahovým vytěžením s poslední uloženou revizí?"
                >Zopakovat obsah a dodavatelské instrukce</button>
                <button
                  class="btn"
                  phx-click="generic-extract"
                  data-confirm="Nahradit ruční opravy vytěžením bez dodavatelských instrukcí?"
                >Vytěžit bez určení dodavatele</button>
                <button
                  class="btn"
                  phx-click="retry"
                  data-confirm="Znovu určit dodavatele a vytěžit obsah? Ruční opravy a kontrola se zruší."
                >Znovu určit dodavatele</button>
              </div>
              <details id="extraction-history" phx-mounted={JS.ignore_attributes("open")}>
                <summary>Historie vytěžování</summary>
                <p class="text-sm">
                  Usage je uvedena pro každou fázi zvlášť. Bez ověřeného ceníku cenu neodhadujeme; originál se posílá znovu pro každé volání. U dodavatele s instrukcemi přibývá samostatný dotaz.
                </p>
                <div
                  :for={run <- @extraction_history}
                  id={"extraction-run-#{run.id}"}
                  class="border-t py-3 space-y-2"
                >
                  <p>
                    Běh {run.generation}: {run.mode}, {run.state}, fáze {run.active_step}; revize {run.profile_revision ||
                      "bez profilu"}.
                  </p>
                  <p>
                    {if Extractor.includes_items?(run),
                      do: "Hlavička, DPH a orientační položky",
                      else: "Pouze hlavní údaje a DPH, bez položek"}
                  </p>
                  <p :if={run.identity_conflict} class="text-warning">{run.identity_conflict}</p>
                  <div :for={
                    {label, meta} <- [
                      {"Identifikace", run.identification},
                      {"Obsah", run.content},
                      {"Samostatné dodavatelské instrukce", run.supplier_task}
                    ]
                  }>
                    <p>
                      {label}: {meta["state"] || "nevoláno"} · {meta["model"]} · HTTP {meta[
                        "http_status"
                      ]} · {meta[
                        "error"
                      ]}
                    </p>
                    <pre class="text-xs whitespace-pre-wrap">{Jason.encode!(meta["usage"] || %{})}</pre>
                  </div>
                  <details
                    id={"extraction-run-instructions-#{run.id}"}
                    phx-mounted={JS.ignore_attributes("open")}
                  >
                    <summary>Použité instrukce a otisky</summary>
                    <pre class="text-xs whitespace-pre-wrap">{run.supplier_instructions}</pre>
                    <p :for={field <- run.supplier_task_result["fields"] || []}>
                      {field["field"]}: {field["value"] || "nezjištěno"} · Zdroj: {field[
                        "source_text"
                      ]}
                    </p>
                    <p :for={message <- run.supplier_task_result["uncertainties"] || []}>{message}</p>
                    <pre
                      :if={run.supplier_task_result["vat_summary"]}
                      class="text-xs whitespace-pre-wrap"
                    >{Jason.encode!(run.supplier_task_result["vat_summary"], pretty: true)}</pre>
                    <p class="text-xs break-all">
                      Společné: {run.common_instructions_hash}; dodavatel: {run.supplier_instructions_hash}
                    </p>
                  </details>
                  <button
                    :if={!@locked && run.generation > 1}
                    class="btn btn-sm"
                    phx-click="restore-draft"
                    phx-value-id={run.id}
                    data-confirm="Obnovit návrh uložený před tímto během? Bude nutná nová kontrola a uložení."
                  >Obnovit předchozí pracovní návrh</button>
                </div>
                <button
                  :if={@history_page > 0}
                  class="btn btn-sm"
                  phx-click="history-page"
                  phx-value-page={@history_page - 1}
                >Novější běhy</button>
                <button
                  :if={length(@extraction_history) == 10}
                  class="btn btn-sm"
                  phx-click="history-page"
                  phx-value-page={@history_page + 1}
                >Starší běhy</button>
              </details>
            </details>
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
              id={"incoming-response-#{Base.url_encode64(title, padding: false)}"}
              phx-mounted={JS.ignore_attributes("open")}
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
              <details
                id={"incoming-response-details-#{Base.url_encode64(title, padding: false)}"}
                phx-mounted={JS.ignore_attributes("open")}
              >
                <summary>Technické podrobnosti odpovědi</summary><pre class="text-xs whitespace-pre-wrap break-all max-h-96 overflow-auto">{Jason.encode!(response, pretty: true)}</pre>
              </details>
            </details>
          </details>
        </div>
      </div>
      <div
        :if={@live_action != :index}
        id="incoming-actions"
        phx-hook="IncomingActionBar"
        data-unsaved={to_string(@dirty || @accounting_dirty || @supplier_dirty)}
        class="fixed bottom-0 inset-x-0 lg:left-60 z-40 border-t bg-white [&_.btn]:min-h-11 p-3 shadow-lg pb-[max(0.75rem,env(safe-area-inset-bottom))]"
      >
        <p :if={@workflow_error} class="text-error text-sm mb-2 max-h-20 overflow-auto" role="alert">
          {@workflow_error}
        </p>
        <div class="flex flex-wrap items-center gap-2">
          <div :if={@batch} class="flex items-center gap-2 w-full sm:w-auto">
            <button
              :for={{row, index} <- Enum.with_index(@batch_rows)}
              :if={abs(index - Enum.find_index(@batch_rows, &(&1.id == @doc.id))) == 1}
              class="btn btn-sm"
              phx-click="review-move"
              phx-value-id={row.id}
            >{if index < Enum.find_index(@batch_rows, &(&1.id == @doc.id)),
              do: "Předchozí",
              else: "Další"}</button>
            <span class="text-xs ml-auto sm:hidden">{save_state(@doc, @dirty || @accounting_dirty)}</span>
            <span class="text-sm ml-auto">{Enum.find_index(@batch_rows, &(&1.id == @doc.id)) + 1} / {length(
              @batch_rows
            )}</span>
          </div>
          <span class={["text-sm", @batch && "hidden sm:inline"]}>{save_state(
            @doc,
            @dirty || @accounting_dirty
          )}</span>
          <button :if={!@locked} class="btn" phx-click="workflow-save" phx-disable-with="Ukládám…">Uložit</button>
          <button :if={@doc && @doc.state == "uncertain"} class="btn btn-primary" phx-click="verify">Ověřit v ABRA</button>
          <button
            :if={@doc && !@locked}
            class="btn btn-primary grow sm:grow-0"
            phx-click="send-next"
            phx-disable-with="Odesílám…"
          >{if @batch, do: "Uložit a odeslat →", else: "Uložit a odeslat"}</button>
          <details :if={@batch} id="review-more" class="relative ml-auto">
            <summary class="btn" aria-label="Další akce">⋯</summary>
            <div class="absolute bottom-full right-0 mb-2 bg-white border rounded-lg p-2 shadow-lg min-w-48 space-y-2">
              <button
                :if={@doc.state != "sent" && !@doc.deferred_at}
                phx-click="review-defer"
                class="btn btn-sm w-full"
              >Odložit</button>
              <button :if={@doc.deferred_at} phx-click="review-return" class="btn btn-sm w-full">Vrátit mezi nevyřízené</button>
              <button phx-click="review-summary" class="btn btn-sm w-full">Souhrn dávky</button>
            </div>
          </details>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
